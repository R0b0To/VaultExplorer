import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/video_playback_mode.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/media_playback_paths.dart';
import 'package:vaultexplorer/features/browser/viewer/media_session_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

const String _kTag = 'BackgroundPlayback';

/// What the media viewer hands over when it is closed while audio is playing
/// and "keep audio playing after closing" is on: the live player
/// ([playbackManager]), the playlist it was walking ([playlist]) and the
/// viewer's playback state.
class BackgroundPlaybackSession {
  BackgroundPlaybackSession({
    required this.providers,
    required this.container,
    required this.playlist,
    required this.playbackManager,
    required this.playbackMode,
    required this.playbackSpeed,
    required this.isMuted,
  });

  /// The app's provider container. The viewer's own `ref` is gone once it is
  /// closed, so settings and services are read through this.
  final ProviderContainer providers;
  final MountedContainer container;
  final PlaylistController playlist;
  final VideoPlaybackManager playbackManager;
  final VideoPlaybackMode playbackMode;
  final double playbackSpeed;
  final bool isMuted;
}

/// Keeps audio playing after the media viewer has been closed.
///
/// The viewer normally owns the player and releases it when it goes away.
/// When the person closes it with audio playing and the setting on, it calls
/// [adopt] instead of disposing its [VideoPlaybackManager]: the same native
/// player and media notification carry on, with no screen of their own -- the
/// notification's Previous / Next / Stop are the controls. Opening that same
/// item again hands the player back to the viewer ([takeMatching]).
///
/// The audio ends, and the player is released, when: the notification's Stop
/// is used, the track ends with nothing to advance to, playback errors, the
/// vault it plays from locks or is detached, or the app locks.
///
/// The app has a single native player, so anything else that wants it (another
/// viewer item, the video / audio editor, the capture review) must release
/// this session first: see [needsRelease] and [closeAndWait].
///
/// Plain Dart singleton rather than a provider on purpose: it is touched from
/// `State.dispose`, where provider state must not be modified.
class BackgroundPlaybackHost {
  BackgroundPlaybackHost._();

  static final BackgroundPlaybackHost instance = BackgroundPlaybackHost._();

  BackgroundPlaybackSession? _session;
  Future<void>? _closing;
  int _viewerCount = 0;

  StreamSubscription<MediaSessionAction>? _actionSubscription;
  void Function(int volId)? _lockedListener;
  void Function(int volId)? _detachedListener;
  NativeVideoController? _tickController;
  Timer? _advanceTimer;
  bool _advancing = false;
  bool? _reportedPlaying;
  String? _lastSavedFile;
  Duration _lastSavedPosition = Duration.zero;

  /// True while a session exists or is still being torn down, i.e. whenever
  /// the native player may not be free yet.
  bool get needsRelease => _session != null || _closing != null;

  /// Viewers tell the host they are open: a viewer answers the notification's
  /// Previous / Next for its own playlist, so the host must not as well.
  void registerViewer() => _viewerCount++;

  void unregisterViewer() {
    if (_viewerCount > 0) _viewerCount--;
  }

  // --- Hand-off ---

  /// Takes over the player from a closing viewer. Returns false (and leaves
  /// the player to the caller, who must dispose it) when the app is locked.
  bool adopt(BackgroundPlaybackSession session) {
    final lockController = session.providers.read(
      sessionLockControllerProvider,
    );
    if (lockController.isAppLocked) return false;

    final previous = _session;
    if (previous != null && !identical(previous, session)) {
      // The viewer releases any earlier session before it plays something of
      // its own, so this should not happen. If it does, the single native
      // player has already been replaced; disposing the old Dart controller
      // now would release the *new* player, so only let go of the listeners.
      _detach(previous);
    }
    _session = session;
    _attach(session);
    return true;
  }

  /// Gives the session back to a viewer that is opening on the very item it
  /// plays, so the audio carries on instead of restarting. The player keeps
  /// playing; only this host's listeners are removed.
  BackgroundPlaybackSession? takeMatching(
    MountedContainer container,
    String file,
  ) {
    final session = _session;
    if (session == null) return null;
    if (session.container.uri != container.uri ||
        session.container.volId != container.volId) {
      return null;
    }
    if (session.playbackManager.currentFileName != file) return null;
    final controller = session.playbackManager.activeController;
    if (controller == null || controller.isDisposed) return null;
    _detach(session);
    _session = null;
    return session;
  }

  /// Stops playback, releases the native player and the notification. The
  /// returned future completes once the native release has finished, so the
  /// caller can safely start another player. Safe to call repeatedly.
  Future<void> closeAndWait() {
    final pending = _closing;
    if (pending != null) return pending;
    final session = _session;
    if (session == null) return Future<void>.value();
    late final Future<void> future;
    future = _teardown(session).whenComplete(() {
      if (identical(_closing, future)) _closing = null;
    });
    _closing = future;
    return future;
  }

  Future<void> _teardown(BackgroundPlaybackSession session) async {
    _detach(session);
    if (identical(_session, session)) _session = null;
    try {
      session.providers.read(sessionLockControllerProvider).setMediaPlaying(
        false,
      );
    } catch (e) {
      VeLog.w(_kTag, 'Could not clear the media-playing flag', e);
    }
    unawaited(PlaybackThrottleController.setActive(false));
    final manager = session.playbackManager;
    final file = manager.currentFileName;
    final value = manager.activeController?.value;
    if (file != null && value != null && value.isInitialized) {
      await _savePosition(session, file, value.position, value.duration);
    }
    try {
      manager.pauseActive();
      await manager.invalidateActive();
    } catch (e) {
      VeLog.w(_kTag, 'Releasing the player failed', e);
    }
    manager.dispose();
  }

  // --- Wiring ---

  void _attach(BackgroundPlaybackSession session) {
    final events = session.providers.read(vaultEngineEventsProvider);
    void onVolumeGone(int volId) {
      if (volId == session.container.volId && identical(_session, session)) {
        VeLog.i(_kTag, 'Container went away; ending background playback');
        unawaited(closeAndWait());
      }
    }

    _lockedListener = onVolumeGone;
    _detachedListener = onVolumeGone;
    events.addContainerLockedListener(onVolumeGone);
    events.addUsbContainerDetachedListener(onVolumeGone);

    _actionSubscription = MediaSessionBridge.actions.listen(_onSessionAction);
    session.playbackManager.activeControllerNotifier.addListener(
      _onActiveControllerChanged,
    );

    _advancing = false;
    _reportedPlaying = null;
    _lastSavedFile = null;
    _lastSavedPosition = Duration.zero;
    unawaited(PlaybackThrottleController.setActive(true));
    _bindController(session);
    _syncNavigation(session);
  }

  void _detach(BackgroundPlaybackSession session) {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _advancing = false;
    unawaited(_actionSubscription?.cancel());
    _actionSubscription = null;
    final tick = _tickController;
    if (tick != null) {
      try {
        tick.removeListener(_onTick);
      } catch (_) {
        // The controller may already be disposed; the reference is dropped
        // either way.
      }
    }
    _tickController = null;
    try {
      session.playbackManager.activeControllerNotifier.removeListener(
        _onActiveControllerChanged,
      );
    } catch (_) {
      // Notifier already disposed along with its manager.
    }
    final events = session.providers.read(vaultEngineEventsProvider);
    final locked = _lockedListener;
    final detached = _detachedListener;
    if (locked != null) events.removeContainerLockedListener(locked);
    if (detached != null) events.removeUsbContainerDetachedListener(detached);
    _lockedListener = null;
    _detachedListener = null;
  }

  void _onActiveControllerChanged() {
    final session = _session;
    if (session == null) return;
    _bindController(session);
  }

  void _bindController(BackgroundPlaybackSession session) {
    final previous = _tickController;
    if (previous != null) {
      try {
        previous.removeListener(_onTick);
      } catch (_) {
        // Disposed with its manager; nothing to unhook.
      }
    }
    final controller = session.playbackManager.activeController;
    _tickController = controller;
    _advancing = false;
    _reportedPlaying = null;
    if (controller == null || controller.isDisposed) return;
    controller.addListener(_onTick);
    // Every item gets its own native controller, which starts at the default
    // volume: re-apply the mute choice, as the viewer does.
    unawaited(controller.setVolume(session.isMuted ? 0 : 100));
    _reportPlaying(session, controller.value.isPlaying);
  }

  MediaViewerToolbarConfig _config(BackgroundPlaybackSession session) => session
      .providers
      .read(fileManagerToolbarSettingsProvider(null))
      .config
      .mediaViewerToolbarConfig;

  void _reportPlaying(BackgroundPlaybackSession session, bool isPlaying) {
    if (_reportedPlaying == isPlaying) return;
    _reportedPlaying = isPlaying;
    // Same signal the viewer's player widget gives: inactivity timers are
    // held off while media plays.
    session.providers.read(sessionLockControllerProvider).setMediaPlaying(
      isPlaying,
    );
  }

  void _onTick() {
    final session = _session;
    final controller = _tickController;
    if (session == null || controller == null || controller.isDisposed) return;
    final value = controller.value;
    if (value.hasError) {
      VeLog.w(_kTag, 'Playback error; ending background playback');
      unawaited(closeAndWait());
      return;
    }
    _reportPlaying(session, value.isPlaying);
    if (!value.isInitialized) return;

    final position = value.position;
    final duration = value.duration;
    final file = session.playbackManager.currentFileName;
    if (file != null && duration > Duration.zero) {
      if (_lastSavedFile != file) {
        _lastSavedFile = file;
        _lastSavedPosition = Duration.zero;
      }
      if (position.inSeconds - _lastSavedPosition.inSeconds >= 5) {
        _lastSavedPosition = position;
        unawaited(_savePosition(session, file, position, duration));
      }
    }
    if (duration <= Duration.zero) return;

    if (session.playbackMode == VideoPlaybackMode.loop) {
      if (value.isPlaying && position >= duration) {
        unawaited(controller.seekTo(Duration.zero));
        unawaited(controller.play());
      }
      return;
    }
    if (_advancing || position < duration) return;
    _advancing = true;
    unawaited(controller.pause());
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 300), () {
      _advanceTimer = null;
      unawaited(_onItemEnded(session));
    });
  }

  /// The item ran to its end: on to the next one in play-and-advance mode,
  /// otherwise there is nothing left to keep alive.
  Future<void> _onItemEnded(BackgroundPlaybackSession session) async {
    if (!identical(_session, session)) return;
    if (session.playbackMode == VideoPlaybackMode.playAndAdvance) {
      final target = _neighbour(1);
      if (target != null) {
        await _playIndex(session, target);
        return;
      }
    }
    await closeAndWait();
  }

  // --- Navigation ---

  void _onSessionAction(MediaSessionAction action) {
    // While a viewer is open it handles Previous / Next for its own playlist;
    // answering too would move two playlists at once. Stop always applies: the
    // native side has already ended playback.
    if (action != MediaSessionAction.stop && _viewerCount > 0) return;
    switch (action) {
      case MediaSessionAction.next:
        unawaited(_step(1));
      case MediaSessionAction.previous:
        unawaited(_step(-1));
      case MediaSessionAction.stop:
        unawaited(closeAndWait());
    }
  }

  bool get _hasNext => _neighbour(1) != null;
  bool get _hasPrevious => _neighbour(-1) != null;

  /// Index of the closest audio item in [direction], wrapping around only when
  /// "loop playlist" is on; null when there is none. Videos and images have
  /// no place to play in the background, so they are skipped.
  int? _neighbour(int direction) {
    final session = _session;
    if (session == null) return null;
    final playlist = session.playlist;
    final count = playlist.playlist.length;
    if (count <= 1) return null;
    final loop = _config(session).loopPlaylist;
    var index = playlist.currentIndex;
    for (var i = 0; i < count - 1; i++) {
      var candidate = index + direction;
      if (candidate < 0 || candidate >= count) {
        if (!loop) return null;
        candidate = (candidate + count) % count;
      }
      index = candidate;
      if (MediaViewerConstants.isAudio(playlist.playlist[index])) return index;
    }
    return null;
  }

  Future<void> _step(int direction) async {
    final session = _session;
    if (session == null) return;
    final target = _neighbour(direction);
    if (target == null) {
      _advancing = false;
      return;
    }
    await _playIndex(session, target);
  }

  Future<void> _playIndex(BackgroundPlaybackSession session, int index) async {
    final manager = session.playbackManager;
    final previousFile = manager.currentFileName;
    final previousValue = manager.activeController?.value;
    if (previousFile != null &&
        previousValue != null &&
        previousValue.isInitialized) {
      unawaited(
        _savePosition(
          session,
          previousFile,
          previousValue.position,
          previousValue.duration,
        ),
      );
    }
    session.playlist.updateIndex(index);
    final file = session.playlist.currentFile;
    final config = _config(session);
    try {
      await manager.activate(
        fileName: file,
        volId: session.container.volId,
        filePath: nativePlaybackPathFor(session.container, file),
        isLocalStorage: session.container.isLocalStorage,
        autoPlay: true,
        playbackSpeed: session.playbackSpeed,
        looping: session.playbackMode == VideoPlaybackMode.loop,
        videoDecoderMode: config.videoDecoderMode,
        audioDecoderMode: config.audioDecoderMode,
        volumeBoostEnabled: config.volumeBoostEnabled,
        volumeBoostGainMb: config.volumeBoostGainMb,
        equalizer: config.equalizer,
        mediaSession: true,
      );
    } catch (e) {
      VeLog.w(_kTag, 'Could not switch item; ending background playback', e);
      unawaited(closeAndWait());
      return;
    }
    _advancing = false;
    if (identical(_session, session)) _syncNavigation(session);
  }

  /// Tells the media notification whether Previous / Next can act, like the
  /// viewer does for its own playlist.
  void _syncNavigation(BackgroundPlaybackSession session) {
    final count = session.playlist.playlist.length;
    unawaited(
      MediaSessionBridge.setNavigation(
        hasPrevious: _hasPrevious,
        hasNext: _hasNext,
        currentPosition: count > 1 ? session.playlist.currentIndex + 1 : 0,
        totalItems: count > 1 ? count : 0,
      ),
    );
  }

  // --- Resume position ---

  Future<void> _savePosition(
    BackgroundPlaybackSession session,
    String file,
    Duration position,
    Duration? duration,
  ) async {
    try {
      final key = await mediaResumePositionKey(
        session.providers.read(vaultHashApiProvider),
        session.container.uri,
        file,
      );
      if (isResumePositionWorthKeeping(position, duration)) {
        await AppSecureStorage.instance.write(
          key: key,
          value: position.inMilliseconds.toString(),
        );
      } else {
        await AppSecureStorage.instance.delete(key: key);
      }
    } catch (e) {
      VeLog.w(_kTag, 'Could not save playback position', e);
    }
  }
}
