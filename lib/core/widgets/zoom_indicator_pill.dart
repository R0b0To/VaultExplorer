import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The small "fit to screen · 180%" chip shown over a zoomed view. Tapping it
/// puts the view back to its normal size, which is how the image editor and
/// the media player reset a zoom without a double-tap.
class ZoomIndicatorPill extends StatelessWidget {
  final double scale;
  final VoidCallback onReset;
  final Color? backgroundColor;

  const ZoomIndicatorPill({
    super.key,
    required this.scale,
    required this.onReset,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onReset,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fit_screen_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${(scale * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [ZoomIndicatorPill] that only shows while the zoom is being changed.
///
/// It appears as soon as the scale of [transform] changes (a pinch, a
/// double-tap zoom, a reset) and fades out [hideAfter] after the last change.
/// Panning does not show it, and while hidden it ignores touches. Tapping it
/// calls [onReset].
class AutoHideZoomIndicator extends StatefulWidget {
  const AutoHideZoomIndicator({
    super.key,
    required this.transform,
    required this.onReset,
    this.hideAfter = const Duration(seconds: 2),
    this.backgroundColor,
  });

  final ValueListenable<Matrix4> transform;
  final VoidCallback onReset;
  final Duration hideAfter;
  final Color? backgroundColor;

  @override
  State<AutoHideZoomIndicator> createState() => _AutoHideZoomIndicatorState();
}

class _AutoHideZoomIndicatorState extends State<AutoHideZoomIndicator> {
  double _scale = 1.0;
  bool _visible = false;
  Timer? _hideTimer;

  static double _scaleOf(Matrix4 m) =>
      math.sqrt(m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1]);

  @override
  void initState() {
    super.initState();
    _scale = _scaleOf(widget.transform.value);
    widget.transform.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(AutoHideZoomIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) {
      oldWidget.transform.removeListener(_onTransformChanged);
      _scale = _scaleOf(widget.transform.value);
      widget.transform.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    widget.transform.removeListener(_onTransformChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _scaleOf(widget.transform.value);
    // Panning and re-centering leave the scale alone: not a zoom.
    if ((scale - _scale).abs() < 0.001) return;
    _scale = scale;
    void show() {
      if (!mounted) return;
      setState(() => _visible = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(widget.hideAfter, () {
        if (mounted) setState(() => _visible = false);
      });
    }

    // The matrix can be set while the tree is building.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !_visible,
        child: ZoomIndicatorPill(
          scale: _scale,
          onReset: widget.onReset,
          backgroundColor: widget.backgroundColor,
        ),
      ),
    );
  }
}
