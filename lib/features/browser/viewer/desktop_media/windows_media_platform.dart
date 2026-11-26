import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_media/desktop_media_controls.dart';

const String _kTag = 'WindowsMedia';

/// The System Media Transport Controls of Windows: media keys, and the media
/// overlay / lock screen panel. The native side is
/// `windows/runner/desktop_media_session.cpp`; this sends it the state and
/// receives the buttons that were pressed.
class WindowsMediaPlatform implements DesktopMediaPlatform {
  WindowsMediaPlatform({this.viewId}) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.aeidolon.vaultexplorer/desktop_media',
  );

  /// The Flutter view whose window the controls attach to.
  final int? viewId;

  final StreamController<DesktopMediaCommandEvent> _commands =
      StreamController<DesktopMediaCommandEvent>.broadcast();
  bool _unavailable = false;

  @override
  Stream<DesktopMediaCommandEvent> get commands => _commands.stream;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'command') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final name = args['command'];
    final positionMs = args['positionMs'];
    final command = switch (name) {
      'play' => DesktopMediaCommand.play,
      'pause' => DesktopMediaCommand.pause,
      'toggle' => DesktopMediaCommand.toggle,
      'next' => DesktopMediaCommand.next,
      'previous' => DesktopMediaCommand.previous,
      'stop' => DesktopMediaCommand.stop,
      'seekTo' => DesktopMediaCommand.seekTo,
      _ => null,
    };
    if (command == null) return null;
    _commands.add(
      DesktopMediaCommandEvent(
        command,
        position: positionMs is int ? Duration(milliseconds: positionMs) : null,
      ),
    );
    return null;
  }

  @override
  Future<void> update(DesktopMediaState state) async {
    if (_unavailable) return;
    try {
      await _channel.invokeMethod<void>('update', <String, Object?>{
        if (viewId != null) 'viewId': viewId,
        'active': state.active,
        'title': state.title,
        'artist': state.artist,
        'album': state.album,
        'playing': state.playing,
        'positionMs': state.position.inMilliseconds,
        'durationMs': state.duration.inMilliseconds,
        'canNext': state.canNext,
        'canPrevious': state.canPrevious,
        'canSeek': state.canSeek,
      });
    } on MissingPluginException {
      // A build without the native part (an older runner): stop trying.
      _unavailable = true;
    } on PlatformException catch (e) {
      VeLog.w(_kTag, 'System media controls unavailable', e);
      _unavailable = true;
    }
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _commands.close();
  }
}
