part of 'media_viewer_screen.dart';

/// Swipe, zoom and touch-pointer handling for the pager.
///
/// Moved out of [_MediaViewerScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _MediaViewerGestures on _MediaViewerScreenState {
  /// Asked by the swipe-to-dismiss layer whenever a finger lands. Mirrors the
  /// conditions under which item swiping is locked, plus a page change that
  /// is still settling, so a pinch, a pan of a zoomed image or a half-finished
  /// swipe is never mistaken for a dismiss.
  bool _canStartSwipeDismiss() {
    if (!mounted || _playlistController.isEmpty) return false;
    if (_isEditingLayout ||
        _multiTouchLock ||
        _zoomInteractionLock ||
        _isProgrammaticScrolling ||
        _isSwiping) {
      return false;
    }
    // Continuous mode reports "zoom ended" even while still zoomed in.
    if (_scrollMode.isContinuous && _continuousScale > 1.01) return false;
    return true;
  }

  /// Closes the viewer the way a deliberate back press does (see PopScope in
  /// build), so background playback still hands over.
  void _closeViewerFromSwipe() {
    if (!mounted) return;
    _closing = true;
    _prepareBackgroundPlaybackHandoff();
    _beginFloatingFlight(fadeChrome: false);
    Navigator.of(context).pop();
  }

  // Recomputes the shared swipe-physics notifier from the lock sources:
  // raw multi-touch (fires the instant a 2nd finger is detected), a 360 scene
  // that owns drags, zoom/interaction state reported by the active media item,
  // and horizontal swipe-to-seek gesture on videos.
  // When the playlist is vertical, swipe-to-seek is orthogonal to the page scroll
  // direction, so item-change gestures do not interfere with seek and stay enabled.
  void _updateSwipePhysics() {
    final swipeToSeekActive =
        _scrollMode == PlaylistScrollMode.horizontal &&
        _isCurrentItemSwipeToSeekEnabled;
    final shouldLock =
        _isEditingLayout ||
        _multiTouchLock ||
        (_panoramaActiveFile != null &&
            _panoramaActiveFile == _playlistController.currentFile) ||
        _zoomInteractionLock ||
        _isProgrammaticScrolling ||
        swipeToSeekActive;
    final desired = shouldLock
        ? const NeverScrollableScrollPhysics()
        : const BouncingScrollPhysics();
    if (_swipePhysicsNotifier.value.runtimeType != desired.runtimeType) {
      _swipePhysicsNotifier.value = desired;
    }
  }

  void _onZoomInteractionChanged(bool allowSwipe) {
    _zoomInteractionLock = !allowSwipe;
    _updateSwipePhysics();
  }

  /// See [CarouselGeometry.visibleCenterShift].
  double _continuousVisibleCenterShift() {
    final h = _viewportHeight;
    final controller = _continuousTransformationController;
    if (h <= 0 || controller.value.isIdentity()) return 0.0;
    return CarouselGeometry.visibleCenterShift(
      viewportHeight: h,
      sceneTop: controller.toScene(Offset.zero).dy,
      sceneBottom: controller.toScene(Offset(0, h)).dy,
    );
  }

  void _handleContinuousDoubleTap([TapDownDetails? details]) {
    final currentScale = _MediaViewerScreenState._getMatrixScale(
      _continuousTransformationController.value,
    );
    final bool isDefaultZoom = (currentScale - 1.0).abs() < 0.01;

    if (!isDefaultZoom) {
      // Zoomed in or out: smoothly animate back to default 1.0x baseline
      _animateContinuousZoomTo(Matrix4.identity(), toBaseline: true);
      return;
    }

    // At default 1.0x: smoothly animate zoom in toward tapped point
    const targetScale = 3.0;
    final vw = _viewportWidth;
    final vh = _viewportHeight;
    if (vw <= 0 || vh <= 0) return;

    final position = details?.localPosition ?? Offset(vw / 2, vh / 2);
    final x = -position.dx * (targetScale - 1.0);
    final y = -position.dy * (targetScale - 1.0);

    final scaledW = vw * targetScale;
    final scaledH = vh * targetScale;

    final clampedTx = scaledW > vw
        ? x.clamp(vw - scaledW, 0.0)
        : (vw - scaledW) / 2.0;
    final clampedTy = scaledH > vh
        ? y.clamp(vh - scaledH, 0.0)
        : (vh - scaledH) / 2.0;

    final targetMatrix = Matrix4.identity()
      ..setTranslationRaw(clampedTx, clampedTy, 0.0)
      ..scale(targetScale, targetScale, targetScale);

    _onZoomInteractionChanged(false);
    _animateContinuousZoomTo(targetMatrix, toBaseline: false);
  }

  // Called on every raw pointer down, regardless of which gesture
  // recognizer ends up winning the arena. This lets us lock out
  // swipe-to-next-item the instant a second finger touches the screen,
  // rather than waiting for InteractiveViewer's onInteractionStart (which
  // can lose the arena race to the PageView/ListView drag recognizer when
  // the two fingers of a pinch don't land in exactly the same frame).
  void _handleTouchPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || _isEditingLayout) return;
    _activeTouchPointers.add(event.pointer);
    if (_activeTouchPointers.length == 1 && !_zoomInteractionLock) {
      final toolbarConfig = ref
          .read(fileManagerToolbarSettingsProvider(null))
          .config
          .mediaViewerToolbarConfig;
      final edgeWidth =
          _viewportWidth * MediaViewerConstants.tapToNavigateEdgeFraction;
      if (toolbarConfig.tapEdgesToNavigate && edgeWidth > 0) {
        final x = event.localPosition.dx;
        final bool? next = x <= edgeWidth
            ? false
            : x >= _viewportWidth - edgeWidth
            ? true
            : null;
        if (next != null) {
          _edgeTapStartPositions[event.pointer] = event.localPosition;
          _edgeTapDirections[event.pointer] = next;
          _edgeTapStartedDuringTransition[event.pointer] =
              _isProgrammaticScrolling;
        }
      }
    }
    if (_activeTouchPointers.length == 1 &&
        _isPlaylistLoopEnabled &&
        !_zoomInteractionLock &&
        !_isProgrammaticScrolling) {
      final index = _playlistController.currentIndex;
      if (_playlistController.playlist.length > 1 &&
          (index == 0 || index == _playlistController.playlist.length - 1)) {
        _loopSwipeStartPositions[event.pointer] = event.position;
        _loopSwipeStartIndices[event.pointer] = index;
      }
    }
    if (_activeTouchPointers.length >= 2 && !_multiTouchLock) {
      _multiTouchLock = true;
      _clearEdgeTapCandidates();
      _loopSwipeStartPositions.clear();
      _loopSwipeStartIndices.clear();
      _updateSwipePhysics();
    }
  }

  void _handleTouchPointerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    final edgeStart = _edgeTapStartPositions.remove(event.pointer);
    final edgeDirection = _edgeTapDirections.remove(event.pointer);
    final startedDuringTransition =
        _edgeTapStartedDuringTransition.remove(event.pointer) ?? false;
    final start = _loopSwipeStartPositions.remove(event.pointer);
    final startIndex = _loopSwipeStartIndices.remove(event.pointer);
    _activeTouchPointers.remove(event.pointer);
    if (event is PointerUpEvent &&
        edgeStart != null &&
        edgeDirection != null &&
        _activeTouchPointers.isEmpty &&
        mounted) {
      final tolerance = startedDuringTransition
          ? math.max(MediaViewerConstants.tapToNavigateMovementTolerance, 48.0)
          : MediaViewerConstants.tapToNavigateMovementTolerance;
      if ((event.localPosition - edgeStart).distance <= tolerance) {
        if (edgeDirection) {
          _navigateToNext();
        } else {
          _navigateToPrev();
        }
      }
    }
    if (event is PointerUpEvent &&
        start != null &&
        startIndex != null &&
        _activeTouchPointers.isEmpty &&
        mounted) {
      _maybeWrapPlaylistSwipe(start, startIndex, event.position);
    }
    if (_activeTouchPointers.isEmpty && _multiTouchLock) {
      _multiTouchLock = false;
      // In continuous mode the zoom lock only covers an active pinch (the
      // list scrolls at any zoom level), so it must not outlive the fingers
      // even if the pinch never reported its end.
      if (_scrollMode.isContinuous) _zoomInteractionLock = false;
      _updateSwipePhysics();
    }
  }

  void _handleTouchPointerMove(PointerMoveEvent event) {
    final start = _edgeTapStartPositions[event.pointer];
    if (start == null) return;
    final startedDuringTransition =
        _edgeTapStartedDuringTransition[event.pointer] ?? false;
    final tolerance = startedDuringTransition
        ? math.max(MediaViewerConstants.tapToNavigateMovementTolerance, 48.0)
        : MediaViewerConstants.tapToNavigateMovementTolerance;
    if ((event.localPosition - start).distance > tolerance) {
      _clearEdgeTapCandidate(event.pointer);
    }
  }

  void _clearEdgeTapCandidate(int pointer) {
    _edgeTapStartPositions.remove(pointer);
    _edgeTapDirections.remove(pointer);
    _edgeTapStartedDuringTransition.remove(pointer);
  }

  void _clearEdgeTapCandidates() {
    _edgeTapStartPositions.clear();
    _edgeTapDirections.clear();
    _edgeTapStartedDuringTransition.clear();
  }

  /// The scroll direction of a pager that pages along [axis], as the framework
  /// resolves it (a horizontal pager runs the other way in right-to-left).
  AxisDirection _axisDirectionFor(Axis axis) {
    if (axis == Axis.vertical) return AxisDirection.down;
    return Directionality.of(context) == TextDirection.rtl
        ? AxisDirection.left
        : AxisDirection.right;
  }

  void _maybeWrapPlaylistSwipe(Offset start, int startIndex, Offset end) {
    if (!_isPlaylistLoopEnabled ||
        (_panoramaActiveFile != null &&
            _panoramaActiveFile == _playlistController.currentFile) ||
        _zoomInteractionLock ||
        _isProgrammaticScrolling) {
      return;
    }

    final count = _playlistController.playlist.length;
    if (count < 2 || _playlistController.currentIndex != startIndex) return;

    final isContinuous = _scrollMode.isContinuous;
    final axis = isContinuous ? Axis.vertical : _scrollMode.axis;
    final axisDirection = _axisDirectionFor(axis);
    final viewportExtent = axis == Axis.horizontal
        ? _viewportWidth
        : _viewportHeight;
    // Paged modes judge the swipe the same way the pager does (overall
    // movement, diagonals allowed), so swiping past the end behaves like
    // swiping between any two items. The continuous list is browsed by free
    // scrolling, where a short scroll that happens to start on the last item
    // must not jump to the first, so it keeps the stricter test.
    final direction = playlistSwipeDirection(
      end - start,
      axisDirection,
      minDistance: isContinuous
          ? math.max(48.0, viewportExtent * 0.12)
          : kPlaylistSwipeMinDistance,
      maxCrossRatio: isContinuous ? 1.0 : kPlaylistSwipeMaxCrossRatio,
    );

    if (startIndex == count - 1 && direction > 0) {
      HapticFeedback.lightImpact();
      _transitionTo(0);
    } else if (startIndex == 0 && direction < 0) {
      HapticFeedback.lightImpact();
      _transitionTo(count - 1);
    }
  }

  void _onScrollStart() {
    if (!_isSwiping) {
      _isSwiping = true;
      _lockedExtents.clear();
      _sessionController.setIsAutoAdvancing(false);
      _playbackManager.activeController?.pause();
      _cancelSlideshowTimer();
    }
  }
}
