import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
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
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

const String _kTag = 'BackgroundPlayback';

/// What the media viewer hands over when it is closed while its player must
/// carry on: the live player ([playbackManager]), the playlist it was walking
/// ([playlist]) and the viewer's playback state. Either audio with "keep audio
/// playing after closing" on, video floating in the picture-in-picture window
/// ([pipWindow]), or video floating in the app's own small window
/// ([floatingPlayer]).
class BackgroundPlaybackSession {
  BackgroundPlaybackSession({
    required this.providers,
    required this.container,
    required this.playlist,
    required this.playbackManager,
    required this.playbackMode,
    required this.playbackSpeed,
    required this.isMuted,
    required this.thumbnailQuality,
    required this.thumbnailCacheMode,
    required this.startingFolder,
    required this.mediaFilter,
    required this.sortBy,
    required this.sortAscending,
    required this.pinnedPaths,
    this.pipWindow = false,
    this.floatingPlayer = false,
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

  /// True when the video is showing in the picture-in-picture window: the
  /// session then also steps through video items, and ends with the window.
  final bool pipWindow;

  /// True when the video is showing in the in-app floating player (the viewer
  /// was closed while it played). Like [pipWindow] the session steps through
  /// video items; unlike it the window is the app's own, so this session also
  /// arms the system picture-in-picture window for when the app is left.
  final bool floatingPlayer;

  // The viewer's own arguments, so it can be reopened on this playlist.
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final String? startingFolder;
  final String? mediaFilter;
  final SortBy sortBy;
  final bool sortAscending;
  final Set<String>? pinnedPaths;
}

/// A video taking off for the floating player: the viewer announces it as a
/// close that hands the video over begins, so the window can fly out of where
/// the video is on screen while the viewer is still closing (the session itself
/// is only adopted once the viewer is gone).
class FloatingPlayerEntry {
  /// The player whose video is flying; the same one the session will hold.
  final VideoPlaybackManager playbackManager;

  /// Where the video was on screen when the close began, in logical pixels of
  /// the app's view.
  final Rect from;

  const FloatingPlayerEntry({required this.playbackManager, required this.from});
}

/// Keeps media playing after the media viewer has been closed.
///
/// The viewer normally owns the player and releases it when it goes away.
/// Three cases call [adopt] instead of disposing its [VideoPlaybackManager]:
///  * audio, when "keep audio playing after closing" is on: the same native
///    player and media notification carry on with no screen of their own --
///    the notification's Previous / Next / Stop are the controls;
///  * video in a separate picture-in-picture window (the fallback of the
///    viewer's button, for when the app itself cannot enter PiP): the window
///    shows the video while the app is free to be used;
///  * video in the in-app floating player (closing the viewer while a video
///    plays, with "floating video player" on): a small draggable window over
///    the app, which becomes the system picture-in-picture window when the
///    app is left (see [PictureInPictureCoordinator]).
/// Opening that same item again hands the player back to the viewer
/// ([takeMatching]); tapping the picture-in-picture window does so through
/// [expandHandler].
///
/// Playback ends, and the player is released (and the window closed), when:
/// the notification's Stop is used, the item ends with nothing to advance to,
/// playback errors, the picture-in-picture window is dismissed, the vault it
/// plays from locks or is detached, or the app locks.
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

  /// Reopens the media viewer on the running session (the picture-in-picture
  /// window or the floating player was tapped to expand). Set by the app's
  /// root; without one, expanding just ends playback.
  void Function()? expandHandler;

  /// The video flying into the floating player while the viewer closes, or
  /// null. See [beginFloatingEntry].
  final ValueNotifier<FloatingPlayerEntry?> floatingEntry =
      ValueNotifier<FloatingPlayerEntry?>(null);
  Timer? _entryTimer;

  /// The session showing in the in-app floating player, or null. The app's
  /// root listens to this to draw the window. Updated from a microtask: the
  /// session changes from `State.dispose`, where a notifier that widgets
  /// listen to must not be touched.
  final ValueNotifier<BackgroundPlaybackSession?> floatingSession =
      ValueNotifier<BackgroundPlaybackSession?>(null);

  StreamSubscription<MediaSessionAction>? _actionSubscription;
  StreamSubscription<String>? _windowSubscription;
  bool _pipWindowOpen = false;
  ({int width, int height})? _lastWindowRatio;
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

  /// The running session, if any.
  BackgroundPlaybackSession? get session => _session;

  /// Brings the full viewer back on the running session. Without a root to do
  /// it, there is nothing to show the video in, so playback ends.
  void expand() {
    final handler = expandHandler;
    if (handler == null) {
      unawaited(closeAndWait());
    } else {
      handler();
    }
  }

  /// The viewer is closing and handing its playing video to the floating
  /// player: the window appears now, taking off from [entry]'s rectangle, and
  /// carries on as the session once the viewer has gone and [adopt]ed it.
  void beginFloatingEntry(FloatingPlayerEntry entry) {
    floatingEntry.value = entry;
    // If the viewer never gets as far as handing over, the window must not
    // stay up showing a player nobody holds.
    _entryTimer?.cancel();
    _entryTimer = Timer(const Duration(seconds: 3), endFloatingEntry);
  }

  /// The flight is over: the viewer is gone and the session has been adopted
  /// (or nothing came of it). Queued behind the session's own publication, so
  /// the window never has a frame with neither.
  void endFloatingEntry() {
    _entryTimer?.cancel();
    _entryTimer = null;
    scheduleMicrotask(() {
      if (floatingEntry.value != null) floatingEntry.value = null;
    });
  }

  void _publishFloatingSession() {
    scheduleMicrotask(() {
      final current = _session;
      final next = current != null && current.floatingPlayer ? current : null;
      if (!identical(floatingSession.value, next)) floatingSession.value = next;
    });
  }

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
    _publishFloatingSession();
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
    _publishFloatingSession();
    // The viewer shows the video again: the window has nothing left to do.
    _closePipWindow();
    return session;
  }

  void _closePipWindow() {
    if (!_pipWindowOpen) return;
    _pipWindowOpen = false;
    unawaited(PictureInPictureBridge.closeWindow());
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
    _publishFloatingSession();
    try {
      session.providers.read(sessionLockControllerProvider).setMediaPlaying(
        false,
      );
    } catch (e) {
      VeLog.w(_kTag, 'Could not clear the media-playing flag', e);
    }
    unawaited(PlaybackThrottleController.setActive(false));
    _closePipWindow();
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
    if (session.pipWindow) {
      _pipWindowOpen = true;
      _windowSubscription = PictureInPictureBridge.windowEvents.listen(
        _onWindowEvent,
      );
    }

    _advancing = false;
    _reportedPlaying = null;
    _lastWindowRatio = null;
    _lastSavedFile = null;
    _lastSavedPosition = Duration.zero;
    unawaited(PlaybackThrottleController.setActive(true));
    _bindController(session);
    _syncNavigation(session);
  }

  void _detach(BackgroundPlaybackSession session) {
    // A no-op unless this host is the one arming picture-in-picture.
    PictureInPictureCoordinator.instance.detach(this);
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _advancing = false;
    unawaited(_actionSubscription?.cancel());
    _actionSubscription = null;
    unawaited(_windowSubscription?.cancel());
    _windowSubscription = null;
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
    if (controller == null || controller.isDisposed) {
      if (session.floatingPlayer) {
        PictureInPictureCoordinator.instance.detach(this);
      }
      return;
    }
    controller.addListener(_onTick);
    // Every item gets its own native controller, which starts at the default
    // volume: re-apply the mute choice, as the viewer does.
    unawaited(controller.setVolume(session.isMuted ? 0 : 100));
    _reportPlaying(session, controller.value.isPlaying);
    if (session.floatingPlayer) {
      // Leaving the app (home, recents, another app) while the floating player
      // plays turns the app into the picture-in-picture window. This does not
      // depend on the viewer's "automatic picture-in-picture" setting: having
      // the floating player on is the person asking for exactly that.
      PictureInPictureCoordinator.instance.attach(
        this,
        controller,
        autoEnter: true,
      );
    }
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

    if (session.pipWindow && _pipWindowOpen) {
      // The window keeps the shape of what it shows (the next item may differ).
      final ratio = pictureInPictureRatio(value.aspectRatio);
      if (ratio != _lastWindowRatio) {
        _lastWindowRatio = ratio;
        unawaited(
          PictureInPictureBridge.setWindowRatio(
            width: ratio.width,
            height: ratio.height,
          ),
        );
      }
    }

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

  // --- Picture-in-picture window ---

  void _onWindowEvent(String event) {
    switch (event) {
      case 'closed':
        // Dismissed by the person: the video does not carry on without it.
        _pipWindowOpen = false;
        unawaited(closeAndWait());
      case 'expanded':
        // Tapped to go back to the app: reopen the viewer on this session.
        _pipWindowOpen = false;
        expand();
      case 'audioOnly':
        // The window's "audio only" button: the window has closed itself and
        // the sound carries on from the media notification, whose Previous /
        // Next / Stop now steer the session. Nothing is stopped here.
        _pipWindowOpen = false;
    }
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

  /// Index of the closest item this session can play in [direction], wrapping
  /// around only when "loop playlist" is on; null when there is none. Audio
  /// sessions play audio only; a picture-in-picture window and the floating
  /// player play video only (audio and images have nothing to show in them).
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
      final file = playlist.playlist[index];
      final playable = session.pipWindow || session.floatingPlayer
          ? MediaViewerConstants.isVideo(file)
          : MediaViewerConstants.isAudio(file);
      if (playable) return index;
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
