part of 'media_viewer_screen.dart';

/// Resuming and saving the playback position, activating the current media and prefetching its neighbours.
///
/// Moved out of [_MediaViewerScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _MediaViewerPlayback on _MediaViewerScreenState {
  Future<String> _resumePositionKey(String fileName) async {
    final cached = _resumePositionKeys[fileName];
    if (cached != null) return cached;
    final key = await mediaResumePositionKey(
      ref.read(vaultHashApiProvider),
      widget.container.uri,
      fileName,
    );
    _resumePositionKeys[fileName] = key;
    return key;
  }

  Future<Duration?> _readResumePosition(String fileName) async {
    try {
      final key = await _resumePositionKey(fileName);
      final raw = await AppSecureStorage.instance.read(key: key);
      final milliseconds = int.tryParse(raw ?? '');
      return milliseconds == null || milliseconds <= 0
          ? null
          : Duration(milliseconds: milliseconds);
    } catch (e) {
      VeLog.w('MediaViewer', 'Could not read saved playback position', e);
      return null;
    }
  }

  Future<void> _savePlaybackPosition(
    String fileName,
    Duration position, {
    Duration? duration,
  }) async {
    if (widget._isPreviewOnly) return;
    try {
      final key = await _resumePositionKey(fileName);
      if (!isResumePositionWorthKeeping(position, duration)) {
        await AppSecureStorage.instance.delete(key: key);
        _lastSavedPlaybackPositions.remove(fileName);
      } else {
        await AppSecureStorage.instance.write(
          key: key,
          value: position.inMilliseconds.toString(),
        );
        _lastSavedPlaybackPositions[fileName] = position;
      }
    } catch (e) {
      VeLog.w('MediaViewer', 'Could not save playback position', e);
    }
  }

  Future<void> _saveActivePlaybackPosition() async {
    final fileName = _playbackManager.currentFileName;
    final value = _playbackManager.activeController?.value;
    if (fileName == null || value == null || !value.isInitialized) return;
    await _savePlaybackPosition(
      fileName,
      value.position,
      duration: value.duration,
    );
  }

  Future<void> _resolveInitialPlayback(
    NativeVideoController controller,
    String fileName,
    int flowToken,
  ) async {
    if (_resumeFlowStarted || !controller.value.isInitialized) return;
    _resumeFlowStarted = true;
    final config = await ref.read(fileManagerToolbarServiceProvider).load();
    final mode = config.mediaViewerToolbarConfig.resumePlaybackMode;
    final savedPosition = widget._isPreviewOnly
        ? null
        : await _readResumePosition(fileName);
    if (!mounted ||
        _closing ||
        flowToken != _resumeFlowToken ||
        controller != _playbackManager.activeController) {
      return;
    }

    final duration = controller.value.duration;
    final canResume =
        savedPosition != null &&
        savedPosition >= const Duration(seconds: 5) &&
        duration > Duration.zero &&
        savedPosition < duration - const Duration(seconds: 5);
    var shouldResume = canResume && mode == ResumePlaybackMode.always;
    if (!widget.startInMiniPlayer &&
        canResume &&
        mode == ResumePlaybackMode.askEveryTime) {
      if (_isAppInBackground) {
        // Nobody can answer the prompt (e.g. background playback moved on to
        // an item with a saved position): start over rather than leave the
        // playback stalled behind a dialog nobody can see.
        shouldResume = false;
      } else {
        final answer = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.resumePlaybackPromptTitle),
            content: Text(
              context.l10n.resumePlaybackPromptMessage(
                formatClockDuration(savedPosition),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.resumePlaybackStartOver),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.resumePlaybackResume),
              ),
            ],
          ),
        );
        shouldResume = answer == true;
      }
    }
    if (!mounted ||
        _closing ||
        flowToken != _resumeFlowToken ||
        controller != _playbackManager.activeController) {
      return;
    }
    if (shouldResume && savedPosition != null) {
      if ((controller.value.position - savedPosition).abs() >
          const Duration(seconds: 2)) {
        try {
          await controller.seekTo(savedPosition);
        } catch (e) {
          VeLog.w('MediaViewer', 'Could not resume playback position', e);
        }
      }
    }
    await controller.play();
    _handoffToMiniPlayerIfReady();
  }

  Future<void> _activateCurrentMedia() async {
    if (_playlistController.isEmpty) return;
    final sw = Stopwatch()..start();
    await _saveActivePlaybackPosition();
    final file = _playlistController.currentFile;
    try {
      widget.onCurrentFileChanged?.call(file);
    } catch (_) {
      // Best-effort callback into the parent widget; a bug or edge case in
      // its listener shouldn't break media activation here.
    }
    final token = ++_activateToken;
    final isVid = MediaViewerConstants.isVideo(file);
    final isAud = MediaViewerConstants.isAudio(file);
    // The app has a single native player: let go of the one still playing in
    // the background before this viewer starts one of its own.
    if ((isVid || isAud) && BackgroundPlaybackHost.instance.needsRelease) {
      await BackgroundPlaybackHost.instance.closeAndWait();
      if (!mounted || token != _activateToken) return;
    }
    final isAdopted = _adoptedFile != null && _adoptedFile == file;
    if ((isVid || isAud) && !isAdopted) {
      // An adopted player is already initialized, so nothing would ever
      // release this gate again.
      PlaybackThrottleController.setInitializing();
    }
    await PlaybackThrottleController.setActive(isVid || isAud);
    if (!mounted || token != _activateToken) return;
    _updateSwipePhysics();
    if (isVid || isAud) {
      final playbackSettings = ref
          .read(fileManagerToolbarSettingsProvider(null))
          .config
          .mediaViewerToolbarConfig;
      // Before the native player is (re)initialized for this item, so the
      // media session never advertises the previous item's neighbours.
      _syncMediaSessionNavigation();
      final mode = playbackSettings.resumePlaybackMode;
      final savedPosition = widget._isPreviewOnly
          ? null
          : (_lastSavedPlaybackPositions[file] ??
                await _readResumePosition(file));
      // The saved position was awaited above: the viewer may have been closed
      // (or the item changed) meanwhile, and a player created now would have no
      // owner left to release it.
      if (!mounted || token != _activateToken) return;
      final canResume =
          savedPosition != null && savedPosition >= const Duration(seconds: 5);
      final shouldPreSeek =
          canResume && mode == ResumePlaybackMode.always && !isAdopted;

      unawaited(
        _playbackManager.activate(
          fileName: file,
          volId: widget.container.volId,
          // Local storage has no vault session for the native player to
          // stream decrypted bytes from -- NativePlayerManager's local
          // branch instead reads this as a real, absolute path straight
          // off disk, so it needs the full path rather than one relative
          // to the container root.
          filePath: nativePlaybackPathFor(widget.container, file),
          isLocalStorage: widget.container.isLocalStorage,
          // Wait until the position preference and any resume prompt have
          // been handled before starting audio/video output.
          autoPlay: false,
          playbackSpeed: _playbackSpeed,
          looping: _videoPlaybackMode == VideoPlaybackMode.loop,
          videoDecoderMode: playbackSettings.videoDecoderMode,
          audioDecoderMode: playbackSettings.audioDecoderMode,
          volumeBoostEnabled: playbackSettings.volumeBoostEnabled,
          volumeBoostGainMb: playbackSettings.volumeBoostGainMb,
          equalizer: playbackSettings.equalizer,
          initialPosition: shouldPreSeek ? savedPosition : null,
          // Background playback + media notification / lock screen controls,
          // for vault items and plain local-storage items alike, but never
          // for the archive preview.
          mediaSession: !widget._isPreviewOnly,
        ),
      );
    } else {
      _playbackManager.pauseActive();
    }
    VeLog.d(
      'MediaViewer',
      'Activated media item index ${_playlistController.currentIndex} in ${sw.elapsedMilliseconds}ms',
    );
  }

  Uint8List? _prefetchedBytesFor(String fileName) {
    return ref
        .read(thumbnailCacheServiceProvider)
        .peekMemory(widget.container, fileName, widget.thumbnailQuality);
  }

  // See MediaPrefetchController.preloadAspectRatios: on a cold open (no
  // thumbnails decoded/cached yet), only the handful of items
  // prefetchSurrounding has actually visited have a learned aspect ratio,
  // so CarouselGeometry falls back to a fixed 16:9 guess for everything
  // else -- a guess that can be badly wrong (e.g. wide panoramas) and
  // whose error compounds across a long playlist's cumulative
  // item-height sum, worst for a jump (filmstrip tap, or just scrolling)
  // to an index the preload hasn't reached yet. Starting from
  // currentIndex rather than 0 means wherever the viewer actually opened
  // -- not necessarily the start of the playlist -- gets covered first,
  // since that's the region the person is most likely to navigate into
  // next. Kicked off once per distinct folder scope so re-entering the
  // same folder doesn't repeat the walk.
  void _kickOffAspectRatioPreload([int? startIndex]) {
    if (!_scrollMode.isContinuous) return;
    final folder = _playlistController.selectedFolder;
    final start = startIndex ?? _playlistController.currentIndex;
    if (_aspectRatioPreloadFolder == folder && startIndex == null) return;
    _aspectRatioPreloadFolder = folder;
    final playlist = _playlistController.playlist;
    unawaited(
      _prefetchController.preloadAspectRatios(
        playlist,
        startIndex: start,
        isStillWanted: () =>
            mounted &&
            _scrollMode.isContinuous &&
            _playlistController.selectedFolder == folder,
        onRatioLearned: _scheduleGeometryRebuild,
      ),
    );
  }

  double _getItemExtent(int index, double vw, double vh) {
    if (_isSwiping) {
      final locked = _lockedExtents[index];
      if (locked != null) return locked;
      final h = _geometry.itemHeight(index, vw, vh);
      _lockedExtents[index] = h;
      return h;
    }
    return _geometry.itemHeight(index, vw, vh);
  }
}
