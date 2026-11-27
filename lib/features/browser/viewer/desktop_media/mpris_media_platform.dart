import 'dart:async';
import 'dart:io' show pid;

import 'package:dbus/dbus.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_media/desktop_media_controls.dart';

const String _kTag = 'Mpris';

const String _objectPath = '/org/mpris/MediaPlayer2';
const String _rootInterface = 'org.mpris.MediaPlayer2';
const String _playerInterface = 'org.mpris.MediaPlayer2.Player';

/// MPRIS on Linux: what the desktop environment's media widget (GNOME, KDE,
/// ...), the media keys and `playerctl` talk to. The player is on the session
/// bus only while something plays, so an idle app puts nothing in the widget.
///
/// The name carries the process id, as MPRIS asks of players that can run more
/// than once.
class MprisMediaPlatform implements DesktopMediaPlatform {
  final StreamController<DesktopMediaCommandEvent> _commands =
      StreamController<DesktopMediaCommandEvent>.broadcast();
  final String _busName = 'org.mpris.MediaPlayer2.vaultexplorer.instance$pid';

  DBusClient? _client;
  _MprisObject? _object;
  bool _owning = false;
  bool _unavailable = false;
  DesktopMediaState _state = const DesktopMediaState.inactive();
  Future<void> _queue = Future<void>.value();

  @override
  Stream<DesktopMediaCommandEvent> get commands => _commands.stream;

  @override
  Future<void> update(DesktopMediaState state) {
    if (_unavailable) return Future<void>.value();
    _state = state;
    // One bus operation at a time, each applying the latest state.
    return _queue = _queue.then((_) => _apply());
  }

  Future<void> _apply() async {
    if (_unavailable) return;
    final state = _state;
    try {
      if (state.active) {
        await _ensureOwned();
        _object?.apply(state);
      } else if (_owning) {
        await _release();
      }
    } catch (e) {
      // No session bus (a headless or sandboxed run), or the bus refused us.
      VeLog.w(_kTag, 'MPRIS unavailable', e);
      _unavailable = true;
    }
  }

  Future<void> _ensureOwned() async {
    if (_owning) return;
    final client = _client ??= DBusClient.session();
    final object = _object ??= _MprisObject(_commands.add);
    await client.registerObject(object);
    await client.requestName(
      _busName,
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    _owning = true;
  }

  Future<void> _release() async {
    final client = _client;
    final object = _object;
    _owning = false;
    if (client == null || object == null) return;
    await client.releaseName(_busName);
    await client.unregisterObject(object);
  }

  @override
  Future<void> dispose() async {
    await _queue;
    try {
      if (_owning) await _release();
      await _client?.close();
    } catch (e) {
      VeLog.w(_kTag, 'Could not close the MPRIS connection', e);
    }
    _client = null;
    await _commands.close();
  }
}

/// `/org/mpris/MediaPlayer2`, with the `MediaPlayer2` and `MediaPlayer2.Player`
/// interfaces.
class _MprisObject extends DBusObject {
  _MprisObject(this._emit) : super(DBusObjectPath(_objectPath));

  final void Function(DesktopMediaCommandEvent) _emit;

  DesktopMediaState _state = const DesktopMediaState.inactive();

  /// When [_state] was reported, so that `Position` keeps counting between
  /// reports (clients read it when they want it, without a signal).
  DateTime _reportedAt = DateTime.now();

  Map<String, DBusValue> _lastPlayerProps = const {};

  void apply(DesktopMediaState state) {
    _state = state;
    _reportedAt = DateTime.now();
    final next = _playerProperties();
    final changed = <String, DBusValue>{
      for (final e in next.entries)
        // Position moves on its own; it is read, not announced.
        if (e.key != 'Position' && _lastPlayerProps[e.key] != e.value)
          e.key: e.value,
    };
    _lastPlayerProps = next;
    if (changed.isEmpty) return;
    unawaited(
      emitPropertiesChanged(_playerInterface, changedProperties: changed)
          .catchError((Object e) {
            VeLog.w(_kTag, 'Could not announce a change', e);
          }),
    );
  }

  Duration get _livePosition {
    if (!_state.playing) return _state.position;
    final elapsed = DateTime.now().difference(_reportedAt);
    final position = _state.position + elapsed;
    return _state.duration > Duration.zero && position > _state.duration
        ? _state.duration
        : position;
  }

  Map<String, DBusValue> _rootProperties() => <String, DBusValue>{
    'CanQuit': const DBusBoolean(false),
    'CanRaise': const DBusBoolean(false),
    'HasTrackList': const DBusBoolean(false),
    'Identity': const DBusString('VaultExplorer'),
    'SupportedUriSchemes': DBusArray.string(const <String>[]),
    'SupportedMimeTypes': DBusArray.string(const <String>[]),
  };

  Map<String, DBusValue> _playerProperties() {
    final s = _state;
    return <String, DBusValue>{
      'PlaybackStatus': DBusString(
        !s.active ? 'Stopped' : (s.playing ? 'Playing' : 'Paused'),
      ),
      'Rate': const DBusDouble(1),
      'MinimumRate': const DBusDouble(1),
      'MaximumRate': const DBusDouble(1),
      'Volume': const DBusDouble(1),
      'Position': DBusInt64(_livePosition.inMicroseconds),
      'Metadata': _metadata(),
      'CanGoNext': DBusBoolean(s.active && s.canNext),
      'CanGoPrevious': DBusBoolean(s.active && s.canPrevious),
      'CanPlay': DBusBoolean(s.active),
      'CanPause': DBusBoolean(s.active),
      'CanSeek': DBusBoolean(s.canSeek),
      'CanControl': DBusBoolean(s.active),
    };
  }

  DBusValue _metadata() {
    final s = _state;
    if (!s.active) return DBusDict.stringVariant(const <String, DBusValue>{});
    return DBusDict.stringVariant(<String, DBusValue>{
      'mpris:trackid': DBusObjectPath('/org/vaultexplorer/track/current'),
      if (s.duration > Duration.zero)
        'mpris:length': DBusInt64(s.duration.inMicroseconds),
      'xesam:title': DBusString(s.title),
      if (s.artist.isNotEmpty) 'xesam:artist': DBusArray.string([s.artist]),
      if (s.album.isNotEmpty) 'xesam:album': DBusString(s.album),
    });
  }

  Map<String, DBusValue>? _propertiesOf(String interface) => switch (interface) {
    _rootInterface => _rootProperties(),
    _playerInterface => _playerProperties(),
    _ => null,
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = _propertiesOf(interface)?[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(_propertiesOf(interface) ?? const {});

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == _rootInterface) {
      switch (methodCall.name) {
        case 'Raise':
        case 'Quit':
          return DBusMethodSuccessResponse();
      }
    } else if (methodCall.interface == _playerInterface) {
      switch (methodCall.name) {
        case 'Play':
          _emit(const DesktopMediaCommandEvent(DesktopMediaCommand.play));
          return DBusMethodSuccessResponse();
        case 'Pause':
          _emit(const DesktopMediaCommandEvent(DesktopMediaCommand.pause));
          return DBusMethodSuccessResponse();
        case 'PlayPause':
          _emit(const DesktopMediaCommandEvent(DesktopMediaCommand.toggle));
          return DBusMethodSuccessResponse();
        case 'Stop':
          _emit(const DesktopMediaCommandEvent(DesktopMediaCommand.stop));
          return DBusMethodSuccessResponse();
        case 'Next':
          _emit(const DesktopMediaCommandEvent(DesktopMediaCommand.next));
          return DBusMethodSuccessResponse();
        case 'Previous':
          _emit(const DesktopMediaCommandEvent(DesktopMediaCommand.previous));
          return DBusMethodSuccessResponse();
        case 'Seek':
          // Relative, in microseconds.
          final offset = methodCall.values.isNotEmpty
              ? methodCall.values[0].asInt64()
              : 0;
          _seek(_livePosition + Duration(microseconds: offset));
          return DBusMethodSuccessResponse();
        case 'SetPosition':
          // (track id, absolute position in microseconds)
          if (methodCall.values.length >= 2) {
            _seek(Duration(microseconds: methodCall.values[1].asInt64()));
          }
          return DBusMethodSuccessResponse();
        case 'OpenUri':
          return DBusMethodSuccessResponse();
      }
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  void _seek(Duration target) {
    var position = target < Duration.zero ? Duration.zero : target;
    if (_state.duration > Duration.zero && position > _state.duration) {
      position = _state.duration;
    }
    _emit(
      DesktopMediaCommandEvent(DesktopMediaCommand.seekTo, position: position),
    );
  }
}
