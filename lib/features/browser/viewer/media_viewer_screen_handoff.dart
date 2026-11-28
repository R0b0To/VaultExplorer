part of 'media_viewer_screen.dart';

/// Hand-off to the mini player and picture-in-picture, and the expand/floating flights.
///
/// Moved out of [_MediaViewerScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _MediaViewerHandoff on _MediaViewerScreenState {
  /// Previous / Next on the media notification and lock screen act on the
  /// playlist, so the native media session is told whether either exists.
  void _syncMediaSessionNavigation() {
    if (widget._isPreviewOnly) return;
    final index = _playlistController.currentIndex;
    final count = _playlistController.playlist.length;
    final loop = _isPlaylistLoopEnabled;
    unawaited(
      MediaSessionBridge.setNavigation(
        hasPrevious: count > 1 && (index > 0 || loop),
        hasNext: count > 1 && (index < count - 1 || loop),
        currentPosition: count > 1 ? index + 1 : 0,
        totalItems: count > 1 ? count : 0,
      ),
    );
  }

  /// Stop on the media notification / lock screen / a headset: playback and
  /// the notification are already ended natively, so close the viewer too
  /// rather than leaving a dead player to come back to. Disposing it is the
  /// normal exit (saves the position, releases the player). The archive
  /// preview never has a media session, so it ignores this.
  void _closeFromMediaSession() {
    if (widget._isPreviewOnly) return;
    _backgroundPlaybackHandoff = null;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    // Dismiss anything opened on top of the viewer (a sheet, a dialog) first.
    navigator.popUntil((r) => identical(r, route));
    if (!route.isFirst) navigator.pop();
  }

  /// Called when the person closes the viewer (back button or gesture) --
  /// never for closes the app forces (app lock, locked or detached container,
  /// the media notification's Stop), which must always end playback. When
  /// "keep audio playing after closing" is on and audio is playing, prepares
  /// the hand-off that [dispose] completes: the live player goes to
  /// [BackgroundPlaybackHost] instead of being released. The same goes for a
  /// playing video when the floating video player is on: it carries on in a
  /// small window over the app (and in the picture-in-picture window once the
  /// app is left). A video can also be sent to the system's window right away
  /// with the picture-in-picture button, see [_enterPictureInPictureWindow].
  /// Nothing that is paused is kept.
  void _prepareBackgroundPlaybackHandoff({bool forceFloating = false}) {
    _backgroundPlaybackHandoff = null;
    _floatingClose.value = _FloatingClose.none;
    if (widget._isPreviewOnly || _playlistController.isEmpty) return;
    if (ref.read(mediaViewerLockProvider(widget.container.volId))) return;
    final file = _playbackManager.currentFileName;
    final controller = _playbackManager.activeController;
    if (file == null || controller == null || controller.isDisposed) return;
    // Mid-transition: the player isn't on the item the playlist points at.
    if (file != _playlistController.currentFile) return;
    final isAudio = MediaViewerConstants.isAudio(file);
    final isVideo = MediaViewerConstants.isVideo(file);
    if (!isAudio && !isVideo) return;
    final value = controller.value;
    // Playing, or about to be. The player is opened with auto-play off and
    // started only after it is initialized and the saved position has been
    // looked up, so for the first moments of a video it is not "playing" yet;
    // going back then used to drop the video instead of floating it. A video
    // the person paused, one that has finished and one that failed are still
    // let go.
    if (value.hasError) return;
    final finished =
        value.duration > Duration.zero && value.position >= value.duration;
    // A paused video is let go with the viewer, except when the person asked
    // for the floating window itself: then it floats paused, as it is.
    if (!forceFloating &&
        (finished || !(value.isPlaying || !controller.pauseRequested))) {
      return;
    }
    final config = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    if (isAudio) {
      if (!(widget.keepAudioPlayingOnClose ??
          config.keepAudioPlayingAfterClose)) {
        return;
      }
      _backgroundPlaybackHandoff = _newBackgroundPlaybackSession(
        pipWindow: false,
      );
    } else {
      // [forceFloating]: the person asked for it with the PiP button, so the
      // "floating video player on close" setting does not apply.
      if (!config.floatingPlayerEnabled && !forceFloating) return;
      _backgroundPlaybackHandoff = _newBackgroundPlaybackSession(
        pipWindow: false,
        floatingPlayer: true,
      );
    }
    final handoff = _backgroundPlaybackHandoff;
    if (handoff?.libraryPlayback == true) {
      BackgroundPlaybackHost.instance.previewMiniPlayerTransition(handoff!);
    }
    if (_backgroundPlaybackHandoff != null &&
        !value.isPlaying &&
        !(forceFloating && controller.pauseRequested)) {
      // It was about to start, and the code that would have started it (this
      // viewer's) is going away: whoever takes the player over must see that
      // it plays.
      unawaited(controller.playWhenReady());
    }
  }

  /// A back press. Closes the viewer, handing the video to the floating
  /// player (or the audio to the background) when there is one to hand over.
  /// If the player does not exist yet, because the video was only just opened,
  /// it waits for it, briefly: going back straight after opening a video
  /// should still float it, not drop it.
  Future<void> _closeFromBackPress({bool forceFloating = false}) async {
    if (_closingFromBackPress) return;
    _closingFromBackPress = true;
    _closing = true;
    try {
      await _waitForPlayerToExist();
      if (!mounted) return;
      _prepareBackgroundPlaybackHandoff(forceFloating: forceFloating);
      _beginFloatingFlight();
      Navigator.of(context).pop();
    } finally {
      _closingFromBackPress = false;
    }
  }

  void _handoffToMiniPlayerIfReady() {
    if (!widget.startInMiniPlayer ||
        !mounted ||
        _closing ||
        _closingFromBackPress) {
      return;
    }
    final controller = _playbackManager.activeController;
    if (controller == null ||
        controller.isDisposed ||
        !controller.value.isPlaying) {
      return;
    }
    unawaited(_closeFromBackPress());
  }

  void _dismissMiniPlayerBootstrapAfterError() {
    if (!widget.startInMiniPlayer || _miniPlayerBootstrapDismissScheduled) {
      return;
    }
    _miniPlayerBootstrapDismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _miniPlayerBootstrapDismissScheduled = false;
      if (!mounted || !widget.startInMiniPlayer) return;
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  /// Returns once the player for the item on screen exists (or after a
  /// moment, whichever is first). Only waits when there would be something to
  /// hand over: a video with the floating player on, or an audio file with
  /// "keep audio playing after closing" on.
  Future<void> _waitForPlayerToExist() async {
    if (widget._isPreviewOnly || _playlistController.isEmpty) return;
    final file = _playlistController.currentFile;
    final isVideo = MediaViewerConstants.isVideo(file);
    final isAudio = MediaViewerConstants.isAudio(file);
    if (!isVideo && !isAudio) return;
    final config = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    final wouldHandOver = isVideo
        ? config.floatingPlayerEnabled
        : (widget.keepAudioPlayingOnClose ?? config.keepAudioPlayingAfterClose);
    if (!wouldHandOver) return;
    bool exists() {
      final controller = _playbackManager.activeController;
      return controller != null &&
          !controller.isDisposed &&
          _playbackManager.currentFileName == file;
    }

    if (exists()) return;
    final done = Completer<void>();
    void check() {
      if (!done.isCompleted && exists()) done.complete();
    }

    _playbackManager.activeControllerNotifier.addListener(check);
    try {
      await done.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () {},
      );
    } finally {
      _playbackManager.activeControllerNotifier.removeListener(check);
    }
  }

  /// The viewer's video growing out of the floating window it was opened
  /// from, the reverse of [_beginFloatingFlight]. The window stays up, still
  /// showing the video, while this finds out where the viewer's own video is;
  /// then the viewer draws its copy at the window's rectangle (under the window,
  /// so nothing shows), the window goes, and the copy grows into place as the
  /// backdrop and the controls fade in.
  Future<void> _runExpandFlight(Rect from) async {
    // The video widget needs a few frames to come up on the adopted player.
    Rect? dest;
    for (var frame = 0; frame < 30 && dest == null; frame++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      dest = _videoProbe.measure();
    }
    final layer = _expandLayerContext;
    final layerBox = layer != null && layer.mounted
        ? layer.findRenderObject()
        : null;
    if (dest == null || layerBox is! RenderBox || !layerBox.attached) {
      // Could not tell where the video lands: no flight, it simply shows.
      _finishExpandFlight();
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandController?.dispose();
    _expandController = controller;
    controller.addListener(() {
      _openReveal.value = Curves.easeOut.transform(controller.value);
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finishExpandFlight();
    });
    _expandFlight.value = _ExpandFlight(
      from: from,
      dest: dest,
      origin: layerBox.localToGlobal(Offset.zero),
      animation: controller,
    );
    unawaited(controller.forward());
    // After the frame that first draws the viewer's copy over the window's
    // spot, the window can go: the one frame in which both are drawn is not
    // seen, they are the same picture in the same place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackgroundPlaybackHost.instance.endFloatingExit();
    });
  }

  void _finishExpandFlight() {
    BackgroundPlaybackHost.instance.endFloatingExit();
    if (!mounted) return;
    _expandFlight.value = null;
    _openReveal.value = 1.0;
  }

  /// The media layer of the item on screen during [_runExpandFlight]: hidden
  /// while its place is measured, then scaled and moved so the video starts
  /// exactly where the floating window had it, clipped to the window's rounded
  /// shape and growing into its own.
  Widget _expandFlightLayer(Widget media) {
    return ValueListenableBuilder<_ExpandFlight?>(
      valueListenable: _expandFlight,
      child: media,
      builder: (context, flight, child) {
        if (flight == null) return child!;
        final dest = flight.dest;
        final animation = flight.animation;
        if (dest == null || animation == null) {
          _expandLayerContext = context;
          return Opacity(opacity: 0.0, child: child);
        }
        final destLocal = dest.shift(-flight.origin);
        final fromLocal = flight.from.shift(-flight.origin);
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final e = Curves.easeInOutCubic.transform(animation.value);
            final startScale = fromLocal.width / destLocal.width;
            final scale = startScale + (1.0 - startScale) * e;
            final center = Offset.lerp(fromLocal.center, destLocal.center, e)!;
            final matrix = Matrix4.identity()
              ..translate(
                center.dx - scale * destLocal.center.dx,
                center.dy - scale * destLocal.center.dy,
              )
              ..scale(scale, scale, 1.0);
            // On screen the corners go from the window's 14 to square.
            final radius = 14.0 * (1.0 - e) / scale;
            return Transform(
              transform: matrix,
              child: ClipRRect(
                clipper: _RRectClipper(destLocal, radius),
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  /// Called as a close that hands the playing video to the floating player
  /// begins, right before the route pops. Together, in the same frame (so
  /// nothing flickers):
  ///  * the floating window appears over the video, where it is *now* (a swipe
  ///    may have moved it since it was last reported), and flies into its
  ///    corner;
  ///  * the viewer stops drawing its own copy of the video;
  ///  * the viewer's Hero flight back to the file manager's thumbnail is off:
  ///    the video is going to the floating player, not back to where it was
  ///    opened from.
  ///
  /// [fadeChrome]: a swipe already fades the backdrop and the controls as it
  /// goes; a back press does not, so this does it, quickly, to keep the
  /// window's flight from happening over a black screen that lingers.
  void _beginFloatingFlight({bool fadeChrome = true}) {
    if (_backgroundPlaybackHandoff?.floatingPlayer != true) return;
    // The floating player is a native window of its own on desktop: there is
    // no in-app panel to fly the video into.
    final flies =
        !DesktopPipWindowController.isAvailable && _videoProbe.measure() != null;
    final from = flies ? _videoProbe.measure() : null;
    if (from != null) {
      BackgroundPlaybackHost.instance.beginFloatingEntry(
        FloatingPlayerEntry(playbackManager: _playbackManager, from: from),
      );
    }
    _floatingClose.value = from != null
        ? _FloatingClose.flying
        : _FloatingClose.withoutFlight;

    final start = _swipeDismissProgress.value;
    if (fadeChrome && start < 0.99) {
      _closeFade?.dispose();
      final fade = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
      );
      _closeFade = fade;
      fade.addListener(() {
        _swipeDismissProgress.value =
            start + (1.0 - start) * Curves.easeOut.transform(fade.value);
      });
      unawaited(fade.forward());
    }

    // The route normally goes in a moment. If the pop is swallowed, the viewer
    // must not stay half-faded with its own video hidden.
    _floatingCloseGuard?.cancel();
    _floatingCloseGuard = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _closeFade?.stop();
      _floatingClose.value = _FloatingClose.none;
      _swipeDismissProgress.value = 0.0;
      BackgroundPlaybackHost.instance.endFloatingEntry();
    });
  }

  BackgroundPlaybackSession _newBackgroundPlaybackSession({
    required bool pipWindow,
    bool floatingPlayer = false,
  }) => BackgroundPlaybackSession(
    providers: ProviderScope.containerOf(context, listen: false),
    container: widget.container,
    playlist: _playlistController,
    playbackManager: _playbackManager,
    playbackMode: _videoPlaybackMode,
    playbackSpeed: _playbackSpeed,
    isMuted: _isMuted,
    thumbnailQuality: widget.thumbnailQuality,
    thumbnailCacheMode: widget.thumbnailCacheMode,
    startingFolder: widget.startingFolder,
    mediaFilter: widget.mediaFilter,
    sortBy: widget.sortBy,
    sortAscending: widget.sortAscending,
    pinnedPaths: widget.pinnedPaths,
    libraryPlayback: widget.isLibraryPlayback,
    pipWindow: pipWindow,
    floatingPlayer: floatingPlayer,
  );

  /// The viewer's picture-in-picture button on desktop, where there is no
  /// system PiP window: the viewer closes and the video carries on in the
  /// app's own small floating window, which can be dragged to any corner and
  /// opened back up into the viewer. Same as closing the viewer with the
  /// floating video player on, but asked for explicitly, so it does not depend
  /// on that setting.
  Future<void> _floatVideoOnDesktop() async {
    if (widget._isPreviewOnly || _closing || _playlistController.isEmpty) {
      return;
    }
    final file = _playbackManager.currentFileName;
    final controller = _playbackManager.activeController;
    if (file == null ||
        file != _playlistController.currentFile ||
        !MediaViewerConstants.isVideo(file) ||
        controller == null ||
        controller.isDisposed) {
      return;
    }
    final value = controller.value;
    if (!value.isInitialized || value.hasError) return;
    if (ref.read(mediaViewerLockProvider(widget.container.volId))) return;
    await _closeFromBackPress(forceFloating: true);
  }

  /// The viewer's picture-in-picture button: the app itself becomes Android's
  /// PiP window around the video that is playing, with the viewer left open
  /// underneath (tapping the window brings the app back to it; dismissing it
  /// pauses the video). Nothing is handed to another window, which is what
  /// keeps the transition continuous.
  ///
  /// Only if the system refuses that does it fall back to the older way: a
  /// separate window activity takes the video, the viewer closes, and the live
  /// player goes to [BackgroundPlaybackHost], which keeps it going and answers
  /// the window being tapped (reopen the viewer) or dismissed (stop).
  Future<void> _enterPictureInPictureWindow() async {
    if (widget._isPreviewOnly ||
        _enteringPictureInPicture ||
        _playlistController.isEmpty) {
      return;
    }
    final file = _playbackManager.currentFileName;
    final controller = _playbackManager.activeController;
    if (file == null ||
        file != _playlistController.currentFile ||
        !MediaViewerConstants.isVideo(file) ||
        controller == null ||
        controller.isDisposed) {
      return;
    }
    final value = controller.value;
    if (!value.isInitialized || value.hasError) return;
    if (ref.read(mediaViewerLockProvider(widget.container.volId))) return;

    _enteringPictureInPicture = true;
    // First choice: the app itself becomes the window. It is the activity that
    // is already playing this video, so nothing is handed over and the video
    // carries on without a hitch (that is what looks like one continuous
    // movement into the corner, as in YouTube). The viewer stays open
    // underneath; tapping the window brings the app back to it.
    if (await PictureInPictureCoordinator.instance.enterNow(this)) {
      _enteringPictureInPicture = false;
      return;
    }
    // Fallback, if the system would not do that: a separate window activity.
    final ratio = pictureInPictureRatio(value.aspectRatio);
    final lockController = ref.read(sessionLockControllerProvider);
    bool entered = false;
    try {
      // The app is covered by the window's activity for a moment: that must
      // not count as leaving it (lock timers, return to the decoy).
      entered = await lockController.withLockSuppression(
        () => PictureInPictureBridge.startWindow(
          width: ratio.width,
          height: ratio.height,
        ),
      );
    } finally {
      _enteringPictureInPicture = false;
    }
    if (!entered) return;
    if (!mounted) {
      unawaited(PictureInPictureBridge.closeWindow());
      return;
    }
    // The video may have changed while the window came up.
    final stillPlaying = _playbackManager.activeController;
    if (stillPlaying == null ||
        stillPlaying.isDisposed ||
        _playbackManager.currentFileName != _playlistController.currentFile) {
      unawaited(PictureInPictureBridge.closeWindow());
      return;
    }
    _backgroundPlaybackHandoff = _newBackgroundPlaybackSession(pipWindow: true);
    Navigator.of(context).pop();
  }
}
