import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_seek_hud.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_to_seek_claim_recognizer.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// Wraps the audio or video preview area in the editor, providing horizontal
/// swipe-to-seek gesture recognition with an on-screen HUD, identical to the
/// video player experience.
///
/// Tapping within the area executes [onTap] (e.g. toggling playback), while
/// dragging horizontally claims the seek gesture and triggers [onSeekStart],
/// [onSeekUpdate], and [onSeekEnd] / [onSeekCancel].
class EditorSwipeToSeekArea extends ConsumerStatefulWidget {
  final Widget child;
  final Duration totalDuration;
  final Duration Function() currentPosition;
  final Duration? Function()? visibleDuration;
  final VoidCallback onTap;
  final VoidCallback onSeekStart;
  final ValueChanged<Duration> onSeekUpdate;
  final ValueChanged<Duration> onSeekEnd;
  final ValueChanged<Duration>? onSeekCancel;
  final double? seekSensitivity;
  final bool enabled;

  const EditorSwipeToSeekArea({
    super.key,
    required this.child,
    required this.totalDuration,
    required this.currentPosition,
    this.visibleDuration,
    required this.onTap,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    this.onSeekCancel,
    this.seekSensitivity,
    this.enabled = true,
  });

  @override
  ConsumerState<EditorSwipeToSeekArea> createState() =>
      _EditorSwipeToSeekAreaState();
}

class _EditorSwipeToSeekAreaState extends ConsumerState<EditorSwipeToSeekArea> {
  final Set<int> _activePointers = {};
  SwipeToSeekClaimRecognizer? _claimRecognizer;
  bool _isSwipeSeeking = false;
  bool _showSwipeSeekHud = false;
  Timer? _hudHideTimer;

  Duration _dragStartPosition = Duration.zero;
  Duration _dragTargetPosition = Duration.zero;
  Duration _dragDelta = Duration.zero;
  double _accumulatedDx = 0.0;

  double get _effectiveSensitivity {
    if (widget.seekSensitivity != null) return widget.seekSensitivity!;
    try {
      return ref
          .watch(fileManagerToolbarSettingsProvider(null))
          .config
          .mediaViewerToolbarConfig
          .seekSensitivity;
    } catch (_) {
      return 1.0;
    }
  }

  @override
  void dispose() {
    _hudHideTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_isSwipeSeeking && _activePointers.length > 1) {
      _abortSwipeSeek();
    }
  }

  void _onPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
  }

  bool _canClaim() {
    if (!widget.enabled) return false;
    if (_activePointers.length > 1) return false;
    if (widget.totalDuration <= Duration.zero) return false;
    return true;
  }

  void _handleDragStart(DragStartDetails details) {
    if (!_canClaim()) return;

    _isSwipeSeeking = true;
    _dragStartPosition = widget.currentPosition();
    _dragTargetPosition = _dragStartPosition;
    _dragDelta = Duration.zero;
    _accumulatedDx = 0.0;
    _hudHideTimer?.cancel();

    unawaited(HapticFeedback.selectionClick());
    widget.onSeekStart();

    setState(() => _showSwipeSeekHud = true);
  }

  void _handleDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (!_isSwipeSeeking) return;
    if (_activePointers.length > 1) {
      _abortSwipeSeek();
      return;
    }

    final dx = details.primaryDelta ?? details.delta.dx;
    _accumulatedDx += dx;

    final width = screenWidth > 0 ? screenWidth : 360.0;
    final totalSec = widget.totalDuration.inMilliseconds / 1000.0;
    final visible = widget.visibleDuration?.call();
    final visibleSec = visible != null
        ? (visible.inMilliseconds / 1000.0).clamp(0.1, totalSec)
        : totalSec;

    double seekRangeSeconds;
    if (visibleSec < totalSec) {
      // If the timeline is zoomed in, decrease sensitivity proportionally so
      // that seeking across the preview scales with the visible time window.
      // E.g. in a 2-second visible range, full-width swipe spans 2 seconds (or less),
      // allowing smooth millisecond-level precision without jumping seconds.
      if (visibleSec <= 60) {
        seekRangeSeconds = visibleSec;
      } else if (visibleSec <= 300) {
        seekRangeSeconds = math.min(visibleSec, 90.0);
      } else if (visibleSec <= 1800) {
        seekRangeSeconds = math.min(visibleSec, 180.0);
      } else {
        seekRangeSeconds = math.min(
          visibleSec,
          (visibleSec * 0.1).clamp(180.0, 600.0),
        );
      }
    } else {
      if (totalSec <= 60) {
        seekRangeSeconds = totalSec;
      } else if (totalSec <= 300) {
        seekRangeSeconds = 90.0;
      } else if (totalSec <= 1800) {
        seekRangeSeconds = 180.0;
      } else {
        seekRangeSeconds = (totalSec * 0.1).clamp(180.0, 600.0);
      }
    }

    final dragFraction = _accumulatedDx / width;
    final deltaSeconds =
        dragFraction * seekRangeSeconds * _effectiveSensitivity;
    final deltaMs = (deltaSeconds * 1000).round();

    final startMs = _dragStartPosition.inMilliseconds;
    final totalMs = widget.totalDuration.inMilliseconds;
    final targetMs = (startMs + deltaMs).clamp(0, totalMs);
    final targetPosition = Duration(milliseconds: targetMs);
    final delta = targetPosition - _dragStartPosition;

    _dragTargetPosition = targetPosition;
    _dragDelta = delta;

    widget.onSeekUpdate(targetPosition);
    setState(() {});
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isSwipeSeeking) return;
    _isSwipeSeeking = false;

    widget.onSeekEnd(_dragTargetPosition);
    unawaited(HapticFeedback.lightImpact());

    _hideHudSoon();
  }

  void _handleDragCancel() {
    if (!_isSwipeSeeking) return;
    _isSwipeSeeking = false;

    if (widget.onSeekCancel != null) {
      widget.onSeekCancel!(_dragStartPosition);
    } else {
      widget.onSeekEnd(_dragStartPosition);
    }

    _hideHudSoon();
  }

  void _abortSwipeSeek() {
    _claimRecognizer?.abort();
    _handleDragCancel();
  }

  void _hideHudSoon() {
    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(MediaViewerConstants.edgeSwipeHudHideDelay, () {
      if (mounted) setState(() => _showSwipeSeekHud = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final edgeInset = math.min(
          MediaViewerConstants.swipeToSeekEdgeInset,
          constraints.maxWidth * 0.2,
        );

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_isSwipeSeeking || _showSwipeSeekHud) return;
                  widget.onTap();
                },
                child: widget.child,
              ),
              Positioned(
                left: edgeInset,
                right: edgeInset,
                top: 0,
                bottom: 0,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: <Type, GestureRecognizerFactory>{
                    SwipeToSeekClaimRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          SwipeToSeekClaimRecognizer
                        >(
                          () {
                            final recognizer = SwipeToSeekClaimRecognizer(
                              canClaim: _canClaim,
                            );
                            _claimRecognizer = recognizer;
                            return recognizer;
                          },
                          (recognizer) {
                            recognizer.onStart = _handleDragStart;
                            recognizer.onUpdate = (d) =>
                                _handleDragUpdate(d, constraints.maxWidth);
                            recognizer.onEnd = _handleDragEnd;
                            recognizer.onCancel = _handleDragCancel;
                          },
                        ),
                  },
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (_showSwipeSeekHud)
                SwipeSeekHud(
                  targetPosition: _dragTargetPosition,
                  totalDuration: widget.totalDuration,
                  delta: _dragDelta,
                  showMilliseconds:
                      (widget.visibleDuration?.call() ?? widget.totalDuration)
                          .inSeconds <
                      10,
                ),
            ],
          ),
        );
      },
    );
  }
}
