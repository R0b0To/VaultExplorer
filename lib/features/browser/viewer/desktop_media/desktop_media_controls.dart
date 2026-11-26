import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/diagnostics/stall_diagnostics.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_engine_binding.dart'
    show isDesktopEngineTarget;
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_media/mpris_media_platform.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_media/windows_media_platform.dart';
import 'package:vaultexplorer/features/browser/viewer/media_session_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_info.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

const String _kTag = 'DesktopMedia';

/// What a system media surface can ask the player to do.
enum DesktopMediaCommand { play, pause, toggle, next, previous, stop, seekTo }

class DesktopMediaCommandEvent {
  final DesktopMediaCommand command;

  /// For [DesktopMediaCommand.seekTo]: where to go.
  final Duration? position;

  /// When the system reported the button press (diagnostics: how late it got
  /// here), where the platform says.
  final DateTime? pressedAt;

  const DesktopMediaCommandEvent(this.command, {this.position, this.pressedAt});
}

/// What the system media surfaces (media keys, the taskbar / lock screen
/// panel on Windows, the desktop environment's media widget on Linux) show.
@immutable
class DesktopMediaState {
  final bool active;
  final String title;
  final String artist;
  final String album;
  final bool playing;
  final Duration position;
  final Duration duration;
  final bool canNext;
  final bool canPrevious;

  const DesktopMediaState({
    required this.active,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.canNext = false,
    this.canPrevious = false,
  });

  const DesktopMediaState.inactive() : this(active: false);

  bool get canSeek => active && duration > Duration.zero;
}

/// The operating-system side of [DesktopMediaControls]: MPRIS on Linux, the
/// System Media Transport Controls on Windows.
abstract class DesktopMediaPlatform {
  /// Commands from the system (media keys, the panel's buttons, `playerctl`).
  Stream<DesktopMediaCommandEvent> get commands;

  /// Shows [state]; an inactive state removes the player from the system UI.
  /// Called about once a second while something plays, so implementations
  /// must skip work that has not changed.
  Future<void> update(DesktopMediaState state);

  Future<void> dispose();
}

/// What the system media surfaces say instead of a file name (see
/// [desktopMediaDisplayInfo]). Deliberately does not say "vault".
@visibleForTesting
const String kGenericMediaTitle = 'Playing media';

/// The title, artist and album to put on a system surface for [path].
///
/// Those surfaces are readable by other programs (the D-Bus session bus, the
/// Windows media overlay, a connected device), so decrypted names and tags go
/// out only with "show file names in media notifications" on, the same setting
/// that governs the Android notification. Without it all they get is a neutral
/// line.
@visibleForTesting
({String title, String artist, String album}) desktopMediaDisplayInfo({
  required bool showFileNames,
  required String title,
  required String artist,
  required String album,
}) => showFileNames
    ? (title: title, artist: artist, album: album)
    : (title: kGenericMediaTitle, artist: '', album: '');

/// Makes whatever the app plays in the background reachable from outside its
/// window on Linux and Windows, where there is no media notification (Android
/// has one): media keys, and the system's now-playing panel, with play / pause,
/// next, previous, stop and seeking.
///
/// It follows [BackgroundPlaybackHost.activeSession], i.e. media that a
/// session, not an open viewer, owns: music kept playing after the viewer was
/// closed, a popped-out preview, the floating video player. While a viewer is
/// open it owns playback and has its own controls, so nothing is published.
class DesktopMediaControls {
  DesktopMediaControls._();

  static final DesktopMediaControls instance = DesktopMediaControls._();

  final BackgroundPlaybackHost _host = BackgroundPlaybackHost.instance;

  DesktopMediaPlatform? _platform;
  StreamSubscription<DesktopMediaCommandEvent>? _commands;
  Timer? _timer;
  BackgroundPlaybackSession? _session;
  NativeVideoController? _controller;
  bool _started = false;

  /// Keeps the toolbar settings provider alive while a session runs. It is an
  /// auto-dispose provider whose every creation loads the settings from
  /// encrypted storage, and without a listener each `read` below would build
  /// (and load) a fresh one, several times a second.
  ProviderSubscription<FileManagerToolbarSettingsState>? _settings;

  /// The last state handed to the platform, to send only what changed.
  DesktopMediaState? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Starts following the host. [viewId] is the Flutter view the app draws in
  /// (the system controls attach to its window on Windows). A no-op off Linux
  /// and Windows, and when already started.
  void start({int? viewId}) {
    if (_started || !isDesktopEngineTarget) return;
    final platform = _createPlatform(viewId);
    if (platform == null) return;
    _started = true;
    unawaited(StallDiagnostics.start());
    StallDiagnostics.registerContext(
      'media',
      () =>
          'session=${_session != null} playing=${_host.playing.value} '
          'controller=${_controller != null} lastSentAgoMs='
          '${DateTime.now().difference(_lastSentAt).inMilliseconds}',
    );
    _platform = platform;
    _commands = platform.commands.listen(_onCommand);
    _host.activeSession.addListener(_onSession);
    _host.playing.addListener(_push);
    _onSession();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _host.activeSession.removeListener(_onSession);
    _host.playing.removeListener(_push);
    _unbind();
    unawaited(_commands?.cancel());
    _commands = null;
    final platform = _platform;
    _platform = null;
    if (platform != null) {
      unawaited(platform.update(const DesktopMediaState.inactive()));
      unawaited(platform.dispose());
    }
  }

  static DesktopMediaPlatform? _createPlatform(int? viewId) {
    if (Platform.isLinux) return MprisMediaPlatform();
    if (Platform.isWindows) return WindowsMediaPlatform(viewId: viewId);
    return null;
  }

  void _onSession() {
    final session = _host.activeSession.value;
    if (identical(session, _session)) return;
    _unbind();
    _session = session;
    StallDiagnostics.log(
      'media',
      session == null
          ? 'session ended'
          : 'session started (library=${session.libraryPlayback}, '
                'floating=${session.floatingPlayer}, '
                'items=${session.playlist.playlist.length})',
    );
    if (session != null) {
      final manager = session.playbackManager;
      manager.activeControllerNotifier.addListener(_onController);
      manager.currentFileNotifier.addListener(_push);
      _bindController(manager.activeController);
      _settings = session.providers.listen(
        fileManagerToolbarSettingsProvider(null),
        (previous, next) {},
      );
      // Position changes are not worth a push each; a second is what the
      // system panels can show (they carry on counting by themselves).
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _push(fromTimer: true),
      );
    }
    _push();
  }

  void _onController() {
    final session = _session;
    if (session == null) return;
    _bindController(session.playbackManager.activeController);
    _push();
  }

  void _bindController(NativeVideoController? controller) {
    if (identical(controller, _controller)) return;
    _safeRemove(_controller, _push);
    _controller = controller;
    controller?.addListener(_push);
  }

  void _unbind() {
    _timer?.cancel();
    _timer = null;
    _safeRemove(_controller, _push);
    _controller = null;
    _settings?.close();
    _settings = null;
    _lastSent = null;
    final session = _session;
    _session = null;
    if (session != null) {
      final manager = session.playbackManager;
      try {
        manager.activeControllerNotifier.removeListener(_onController);
        manager.currentFileNotifier.removeListener(_push);
      } catch (_) {
        // The session's player is released (and its notifiers disposed) before
        // the host announces that it is gone; nothing is left to detach from.
      }
    }
  }

  static void _safeRemove(NativeVideoController? controller, VoidCallback l) {
    if (controller == null) return;
    try {
      controller.removeListener(l);
    } catch (_) {
      // Already disposed with its player; the reference is dropped either way.
    }
  }

  /// What the system surfaces show, apart from the position they extrapolate.
  static bool _sameShown(DesktopMediaState a, DesktopMediaState b) =>
      a.active == b.active &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.album == b.album &&
      a.playing == b.playing &&
      a.duration == b.duration &&
      a.canNext == b.canNext &&
      a.canPrevious == b.canPrevious;

  /// Sends the current state when it changed. The player reports its position
  /// several times a second; those reports alone only reach the platform from
  /// the one-second timer ([fromTimer]).
  void _push({bool fromTimer = false}) {
    final platform = _platform;
    if (platform == null) return;
    StallDiagnostics.bump('media.push');
    final state = StallDiagnostics.time('media.state', _currentState, warnMs: 5);
    final last = _lastSent;
    if (last != null && _sameShown(last, state)) {
      if (!fromTimer) return;
      if (!state.playing && state.position == last.position) return;
      if (DateTime.now().difference(_lastSentAt) <
          const Duration(milliseconds: 900)) {
        return;
      }
    }
    _lastSent = state;
    _lastSentAt = DateTime.now();
    StallDiagnostics.bump('media.sent');
    unawaited(platform.update(state));
  }

  DesktopMediaState _currentState() {
    final session = _session;
    if (session == null) return const DesktopMediaState.inactive();
    final controller = _controller;
    if (controller != null && controller.isDisposed) {
      return const DesktopMediaState.inactive();
    }
    final value = controller?.value;
    final path = session.playlist.currentFile.isNotEmpty
        ? session.playlist.currentFile
        : (session.playbackManager.currentFileName ?? '');

    final showNames =
        _settings
            ?.read()
            .config
            .mediaViewerToolbarConfig
            .showFileNamesInMediaNotification ??
        false;
    var title = '';
    var artist = '';
    var album = '';
    if (showNames && path.isNotEmpty) {
      // Tags from the library when the file is in it, else the file name.
      final info = NowPlayingInfo.resolve(
        session.providers.read(musicLibraryProvider).hub,
        session,
        path,
      );
      title = info.title;
      artist = info.artist;
      album = info.album;
    }
    final shown = desktopMediaDisplayInfo(
      showFileNames: showNames,
      title: title,
      artist: artist,
      album: album,
    );
    return DesktopMediaState(
      active: true,
      title: shown.title,
      artist: shown.artist,
      album: shown.album,
      playing: value?.isPlaying ?? false,
      position: value?.position ?? Duration.zero,
      duration: value?.duration ?? Duration.zero,
      canNext: _host.canStepNext,
      canPrevious: _host.canStepPrevious,
    );
  }

  /// Logs when [work] (a command's effect) is done and how long it took.
  void _track(String what, Future<void> work) {
    final watch = Stopwatch()..start();
    unawaited(
      work.whenComplete(() {
        StallDiagnostics.log(
          'media',
          '$what done in ${watch.elapsedMilliseconds}ms',
        );
      }),
    );
  }

  void _onCommand(DesktopMediaCommandEvent event) {
    final pressedAt = event.pressedAt;
    final delay = pressedAt == null
        ? 'unknown'
        : '${DateTime.now().difference(pressedAt).inMilliseconds}ms';
    StallDiagnostics.log(
      'media',
      'command ${event.command.name} reached Dart $delay after the press '
          '(session: ${_session != null})',
    );
    if (_session == null) return;
    switch (event.command) {
      case DesktopMediaCommand.play:
        if (!_host.playing.value) _track('play', _host.togglePlayback());
      case DesktopMediaCommand.pause:
        if (_host.playing.value) _track('pause', _host.togglePlayback());
      case DesktopMediaCommand.toggle:
        _track('toggle', _host.togglePlayback());
      case DesktopMediaCommand.next:
        MediaSessionBridge.dispatch('next');
      case DesktopMediaCommand.previous:
        MediaSessionBridge.dispatch('previous');
      case DesktopMediaCommand.stop:
        _track('stop', _host.closeAndWait());
      case DesktopMediaCommand.seekTo:
        final target = event.position;
        final controller = _controller;
        if (target == null || controller == null || controller.isDisposed) {
          return;
        }
        _track(
          'seek',
          controller.seekTo(target).catchError((Object e) {
            VeLog.w(_kTag, 'Could not seek', e);
          }),
        );
    }
  }
}
