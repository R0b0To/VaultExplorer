import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/continue_playback_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/video_playback_mode.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/media_playback_paths.dart';
import 'package:vaultexplorer/features/browser/viewer/media_session_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

const String _kTag = 'MiniPlayer';

/// Everything the media viewer hands over when it is closed while something
/// is still playing: the live player ([playbackManager]), the playlist it was
/// walking ([playlist]) and the viewer's constructor arguments, so the full
/// viewer can be reopened on exactly the same item.
class MiniPlayerSession {
  MiniPlayerSession({
    required this.providers,
    required this.container,
    required this.playlist,
    required this.playbackManager,
    required this.thumbnailQuality,
    required this.thumbnailCacheMode,
    required this.startingFolder,
    required this.mediaFilter,
    required this.sortBy,
    required this.sortAscending,
    required this.pinnedPaths,
    required this.playbackMode,
    required this.playbackSpeed,
    required this.isMuted,
  });

  /// The app's provider container. The viewer's own `ref` is gone once it is
  /// closed, so the mini player reads settings and services through this.
  final ProviderContainer providers;
  final MountedContainer container;
  final PlaylistController playlist;
  final VideoPlaybackManager playbackManager;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final String? startingFolder;
  final String? mediaFilter;
  final SortBy sortBy;
  final bool sortAscending;
  final Set<String>? pinnedPaths;
  final VideoPlaybackMode playbackMode;
  final double playbackSpeed;
  final bool isMuted;
}

/// App-wide owner of the media player once the media viewer has been closed
/// ("keep playing after closing", see [ContinuePlaybackMode]).
///
/// The viewer normally owns the player and releases it when it goes away. When
/// the person closes it with the setting on, it calls [adopt] instead of
/// disposing its [VideoPlaybackManager]: the same native player (and, for
/// background playback, the same media notification) carries on, and the
/// mini player layer (`MiniPlayerLayer`) shows a bar or a floating video window
/// for it. Opening the viewer again takes the session back with [take].
///
/// The app has a single native player, so anything else that wants it (another
/// viewer item, the video / audio editor, the capture review) must release
/// this session first: see [needsRelease] and [closeAndWait].
///
/// Plain Dart singleton rather than a provider on purpose: it is touched from
/// `State.dispose`, where provider state must not be modified.
class MiniPlayerHost {
  MiniPlayerHost._();

  static final MiniPlayerHost instance = MiniPlayerHost._();

  MiniPlayerSession? _session;
  Future<void>? _closing;

  /// The session being shown, or null. Updated asynchronously (see
  /// [_publish]) because it changes from `dispose` / `initState`, where
  /// notifying widgets is not allowed.
  final ValueNotifier<MiniPlayerSession?> sessionNotifier =
      ValueNotifier<MiniPlayerSession?>(null);

  /// True while at least one media viewer is open. The mini player stays out
  /// of the way then: the viewer has its own controls.
  final ValueNotifier<bool> viewerOpen = ValueNotifier<bool>(false);
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

  MiniPlayerSession? get session => _session;
  bool get hasSession => _session != null;

  /// True while a session exists or is still being torn down, i.e. whenever
  /// the native player may not be free yet.
  bool get needsRelease => _session != null || _closing != null;

  NativeVideoController? get activeController =>
      _session?.playbackManager.activeController;

  // --- Viewer bookkeeping ---

  void registerViewer() {
    _viewerCount++;
    _publish();
  }

  void unregisterViewer() {
    if (_viewerCount > 0) _viewerCount--;
    _publish();
  }

  /// Pushes the current state to the notifiers once the current build /
  /// unmount pass is over. Notifying listeners while the widget tree is being
  /// built or torn down throws in debug builds.
  void _publish() {
    scheduleMicrotask(() {
      if (sessionNotifier.value != _session) sessionNotifier.value = _session;
      final open = _viewerCount > 0;
      if (viewerOpen.value != open) viewerOpen.value = open;
    });
  }

  // --- Hand-off ---

  /// Takes over the player from a closing viewer. Returns false (and leaves
  /// the player to the caller, who must dispose it) when the app is locked.
  bool adopt(MiniPlayerSession session) {
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
    _publish();
    return true;
  }

  /// Gives the session back to a viewer that is opening. The player keeps
  /// playing; only this host's listeners are removed.
  MiniPlayerSession? take() {
    final session = _session;
    if (session == null) return null;
    _detach(session);
    _session = null;
    _publish();
    return session;
  }

  /// Like [take], but only when the session is playing [file] of [container]:
  /// opening that exact item from the file browser continues it instead of
  /// restarting.
  MiniPlayerSession? takeMatching(MountedContainer container, String file) {
    final session = _session;
    if (session == null) return null;
    if (session.container.uri != container.uri ||
        session.container.volId != container.volId) {
      return null;
    }
    if (session.playbackManager.currentFileName != file) return null;
    final controller = session.playbackManager.activeController;
    if (controller == null || controller.isDisposed) return null;
    return take();
  }

  /// Stops playback, releases the native player and removes the mini player.
  /// The returned future completes once the native release has finished, so
  /// the caller can safely start another player. Safe to call repeatedly.
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

  Future<void> _teardown(MiniPlayerSession session) async {
    _detach(session);
    if (identical(_session, session)) _session = null;
    sessionNotifier.value = null;
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

  void _attach(MiniPlayerSession session) {
    final events = session.providers.read(vaultEngineEventsProvider);
    void onVolumeGone(int volId) {
      if (volId == session.container.volId && identical(_session, session)) {
        VeLog.i(_kTag, 'Container went away; closing the mini player');
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
    session.playbackManager.currentFileNotifier.addListener(
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

  void _detach(MiniPlayerSession session) {
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
      session.playbackManager.currentFileNotifier.removeListener(
        _onActiveControllerChanged,
      );
    } catch (_) {
      // Notifier already disposed along with its manager.
    }
    PictureInPictureCoordinator.instance.detach(this);
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

  void _bindController(MiniPlayerSession session) {
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
    _syncPictureInPicture(session);
    if (controller == null || controller.isDisposed) return;
    controller.addListener(_onTick);
    // Every item gets its own native controller, which starts at the default
    // volume: re-apply the mute choice, as the viewer does.
    unawaited(controller.setVolume(session.isMuted ? 0 : 100));
    _reportPlaying(session, controller.value.isPlaying);
  }

  /// Offers the mini player's video to Android's picture-in-picture window
  /// (when the setting is on), or withdraws it for audio.
  void _syncPictureInPicture(MiniPlayerSession session) {
    final coordinator = PictureInPictureCoordinator.instance;
    final file = session.playbackManager.currentFileName;
    final controller = session.playbackManager.activeController;
    if (file == null ||
        controller == null ||
        controller.isDisposed ||
        !MediaViewerConstants.isVideo(file)) {
      coordinator.detach(this);
      return;
    }
    coordinator.attach(
      this,
      controller,
      enabled: _config(session).pictureInPictureEnabled,
    );
  }

  MediaViewerToolbarConfig _config(MiniPlayerSession session) => session
      .providers
      .read(fileManagerToolbarSettingsProvider(null))
      .config
      .mediaViewerToolbarConfig;

  void _reportPlaying(MiniPlayerSession session, bool isPlaying) {
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
      VeLog.w(_kTag, 'Playback error; closing the mini player');
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
    if (_advancing) return;
    if (session.playbackMode == VideoPlaybackMode.playAndAdvance &&
        position >= duration) {
      _advancing = true;
      unawaited(controller.pause());
      _advanceTimer?.cancel();
      _advanceTimer = Timer(const Duration(milliseconds: 300), () {
        _advanceTimer = null;
        unawaited(_step(1));
      });
    }
  }

  // --- Navigation ---

  void _onSessionAction(MediaSessionAction action) {
    // While a viewer is open it handles Previous / Next for its own playlist;
    // answering too would move two playlists at once. Stop always applies: the
    // native side has already ended playback.
    if (action != MediaSessionAction.stop && viewerOpen.value) return;
    switch (action) {
      case MediaSessionAction.next:
        unawaited(next());
      case MediaSessionAction.previous:
        unawaited(previous());
      case MediaSessionAction.stop:
        unawaited(closeAndWait());
    }
  }

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  bool get hasNext => _neighbour(1) != null;
  bool get hasPrevious => _neighbour(-1) != null;

  /// Index of the closest playable item in [direction], wrapping around only
  /// when "loop playlist" is on; null when there is none.
  int? _neighbour(int direction) {
    final session = _session;
    if (session == null) return null;
    final playlist = session.playlist;
    final count = playlist.playlist.length;
    if (count <= 1) return null;
    final config = _config(session);
    var index = playlist.currentIndex;
    for (var i = 0; i < count - 1; i++) {
      var candidate = index + direction;
      if (candidate < 0 || candidate >= count) {
        if (!config.loopPlaylist) return null;
        candidate = (candidate + count) % count;
      }
      index = candidate;
      final file = playlist.playlist[index];
      final isVideo = MediaViewerConstants.isVideo(file);
      final isAudio = MediaViewerConstants.isAudio(file);
      final allowed =
          isAudio ||
          (isVideo &&
              config.continuePlaybackMode != ContinuePlaybackMode.audioOnly);
      if (allowed) return index;
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

  Future<void> _playIndex(MiniPlayerSession session, int index) async {
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
      VeLog.w(_kTag, 'Could not switch item; closing the mini player', e);
      unawaited(closeAndWait());
      return;
    }
    _advancing = false;
    if (identical(_session, session)) _syncNavigation(session);
  }

  /// Tells the media notification whether Previous / Next can act, like the
  /// viewer does for its own playlist.
  void _syncNavigation(MiniPlayerSession session) {
    final count = session.playlist.playlist.length;
    unawaited(
      MediaSessionBridge.setNavigation(
        hasPrevious: hasPrevious,
        hasNext: hasNext,
        currentPosition: count > 1 ? session.playlist.currentIndex + 1 : 0,
        totalItems: count > 1 ? count : 0,
      ),
    );
  }

  // --- Transport ---

  void togglePlayPause() {
    final controller = activeController;
    if (controller == null || controller.isDisposed) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  void seekTo(Duration position) {
    final controller = activeController;
    if (controller == null || controller.isDisposed) return;
    unawaited(controller.seekTo(position));
  }

  // --- Resume position ---

  Future<void> _savePosition(
    MiniPlayerSession session,
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
