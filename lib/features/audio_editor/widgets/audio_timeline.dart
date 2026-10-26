import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/video_editor/models/edit_segment.dart';
import 'package:vaultexplorer/features/video_editor/models/video_edit_math.dart';

import '../models/audio_waveform.dart';

enum _DragMode { none, scrub, zoom, dragStartHandle, dragEndHandle }

/// The audio editor's timeline: a time ruler, the waveform, the segments,
/// draggable handles and the playhead. The video timeline's sibling -- same
/// gestures (drag to scrub, pinch to zoom, drag a selected segment's edge to
/// trim it) with the waveform in place of the filmstrip, and without keyframe
/// snapping because audio can be cut anywhere.
///
/// Painting is split into two layers so playback never repaints the waveform:
/// - [_TimelineBackgroundPainter]: ruler, waveform, segments, handles. Repaints
///   only when bounds, segments, waveform or zoom change.
/// - [_PlayheadPainter]: the playhead needle, repainted at playback rate.
class AudioTimeline extends StatefulWidget {
  const AudioTimeline({
    super.key,
    required this.durationUs,
    required this.segments,
    required this.selectedId,
    required this.mode,
    required this.playheadUs,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onTapAt,
    this.waveform,
    this.onHandleDragStart,
    this.onHandleDragUpdate,
    this.onHandleDragEnd,
  });

  final int durationUs;
  final List<EditSegment> segments;
  final String? selectedId;
  final VideoEditMode mode;
  final ValueListenable<int> playheadUs;

  /// Null until the first part of the native decode arrives; the track shows a
  /// flat centre line. While a long file is still being decoded this grows from
  /// the left (see [AudioWaveform.filledPeaks]).
  final AudioWaveform? waveform;

  final VoidCallback onScrubStart;
  final ValueChanged<int> onScrub;
  final VoidCallback onScrubEnd;
  final ValueChanged<int> onTapAt;

  final VoidCallback? onHandleDragStart;
  final void Function(bool isStart, int us)? onHandleDragUpdate;
  final VoidCallback? onHandleDragEnd;

  EditSegment? get selected {
    if (selectedId == null) return null;
    final i = segments.indexWhere((s) => s.id == selectedId);
    return i < 0 ? null : segments[i];
  }

  @override
  State<AudioTimeline> createState() => AudioTimelineState();
}

class AudioTimelineState extends State<AudioTimeline> {
  static const double _rulerHeight = 20;
  static const double _trackHeight = 96;
  static const double _height = 124;
  static const int _maxZoomSpanUs = 1000000; // most zoomed-in: 1 s across the width

  late int _viewStartUs = 0;
  late int _viewSpanUs = _fullSpan;
  double _width = 1;

  _DragMode _dragMode = _DragMode.none;
  bool _gestureActive = false;
  bool _scrubbing = false;
  int _gestureSpanUs = 0;
  int _focalUs = 0;

  int get _fullSpan => math.max(1, widget.durationUs);
  int get _minSpanUs => math.min(_fullSpan, _maxZoomSpanUs);

  @override
  void initState() {
    super.initState();
    widget.playheadUs.addListener(_followPlayhead);
  }

  @override
  void didUpdateWidget(AudioTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playheadUs != widget.playheadUs) {
      oldWidget.playheadUs.removeListener(_followPlayhead);
      widget.playheadUs.addListener(_followPlayhead);
    }
  }

  @override
  void dispose() {
    widget.playheadUs.removeListener(_followPlayhead);
    super.dispose();
  }

  // ── Zoom window ────────────────────────────────────────────────────────

  int _clampStart(int start, int span) =>
      start.clamp(0, math.max(0, _fullSpan - span)).toInt();

  int _clampUs(int us) => us.clamp(0, widget.durationUs).toInt();

  int _xToUs(double x) => (_viewStartUs + (x / _width) * _viewSpanUs).round();

  /// Zooms by [factor] (>1 zooms in) around the playhead, or the window
  /// centre when the playhead is off-screen.
  void zoomBy(double factor) {
    final playhead = widget.playheadUs.value;
    final visible =
        playhead >= _viewStartUs && playhead <= _viewStartUs + _viewSpanUs;
    final anchorUs = visible ? playhead : _viewStartUs + _viewSpanUs ~/ 2;
    final frac = (anchorUs - _viewStartUs) / _viewSpanUs;
    final span =
        (_viewSpanUs / factor).round().clamp(_minSpanUs, _fullSpan).toInt();
    setState(() {
      _viewSpanUs = span;
      _viewStartUs = _clampStart((anchorUs - frac * span).round(), span);
    });
  }

  void resetZoom() => setState(() {
    _viewStartUs = 0;
    _viewSpanUs = _fullSpan;
  });

  bool get isZoomed => _viewSpanUs < _fullSpan;
  int get viewStartUs => _viewStartUs;
  int get viewSpanUs => _viewSpanUs;
  Duration get visibleDuration => Duration(microseconds: _viewSpanUs);

  /// Keeps the playhead on screen during playback and after seeks made with
  /// the buttons (not while the user's finger is on the timeline).
  void _followPlayhead() {
    if (_gestureActive || !isZoomed || !mounted) return;
    final p = widget.playheadUs.value;
    if (p >= _viewStartUs && p <= _viewStartUs + _viewSpanUs) return;
    setState(() {
      _viewStartUs = _clampStart(p - (_viewSpanUs * 0.1).round(), _viewSpanUs);
    });
  }

  // ── Gestures ───────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _gestureActive = true;
    _gestureSpanUs = _viewSpanUs;
    _focalUs = _xToUs(d.localFocalPoint.dx);

    if (d.pointerCount > 1) {
      _dragMode = _DragMode.zoom;
      return;
    }

    // Did the finger land on a handle of the selected segment?
    final selected = widget.selected;
    if (selected != null) {
      const handleHitSlop = 24.0;
      final x0 = (selected.startUs - _viewStartUs) / _viewSpanUs * _width;
      final x1 = (selected.endUs - _viewStartUs) / _viewSpanUs * _width;
      final touchX = d.localFocalPoint.dx;
      final touchY = d.localFocalPoint.dy;
      const trackTop = _rulerHeight + 4;
      final inTrackY =
          touchY >= trackTop - 12 && touchY <= trackTop + _trackHeight + 12;

      if (inTrackY && (touchX - x0).abs() <= handleHitSlop) {
        _dragMode = _DragMode.dragStartHandle;
        widget.onHandleDragStart?.call();
        HapticFeedback.selectionClick();
        return;
      } else if (inTrackY && (touchX - x1).abs() <= handleHitSlop) {
        _dragMode = _DragMode.dragEndHandle;
        widget.onHandleDragStart?.call();
        HapticFeedback.selectionClick();
        return;
      }
    }

    _dragMode = _DragMode.scrub;
    _scrubbing = true;
    widget.onScrubStart();
    widget.onScrub(_clampUs(_focalUs));
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) {
      if (_scrubbing) {
        _scrubbing = false;
        widget.onScrubEnd();
      }
      _dragMode = _DragMode.zoom;
      final scale = d.scale <= 0 ? 1.0 : d.scale;
      final span =
          (_gestureSpanUs / scale).round().clamp(_minSpanUs, _fullSpan).toInt();
      final start = (_focalUs - (d.localFocalPoint.dx / _width) * span).round();
      setState(() {
        _viewSpanUs = span;
        _viewStartUs = _clampStart(start, span);
      });
      return;
    }

    if (_dragMode == _DragMode.dragStartHandle ||
        _dragMode == _DragMode.dragEndHandle) {
      final isStart = _dragMode == _DragMode.dragStartHandle;
      final us = _clampUs(_xToUs(d.localFocalPoint.dx));
      widget.onHandleDragUpdate?.call(isStart, us);
      // Scrubbing the player to the edge lets the person hear where they cut.
      widget.onScrub(us);
      return;
    }

    if (_scrubbing) {
      widget.onScrub(_clampUs(_xToUs(d.localFocalPoint.dx)));
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragMode == _DragMode.dragStartHandle ||
        _dragMode == _DragMode.dragEndHandle) {
      widget.onHandleDragEnd?.call();
    } else if (_scrubbing) {
      _scrubbing = false;
      widget.onScrubEnd();
    }
    _dragMode = _DragMode.none;
    _gestureActive = false;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final segmentColor =
        widget.mode == VideoEditMode.keep ? cs.primary : cs.error;
    final style =
        context.typography.labelSmall?.copyWith(color: cs.onSurfaceVariant) ??
        TextStyle(fontSize: 10, color: cs.onSurfaceVariant);

    return Semantics(
      label: context.l10n.audioEditorTimelineLabel,
      value:
          '${formatTimecode(widget.playheadUs.value)} / ${formatTimecode(widget.durationUs)}',
      onIncrease: () =>
          widget.onScrub(_clampUs(widget.playheadUs.value + 1000000)),
      onDecrease: () =>
          widget.onScrub(_clampUs(widget.playheadUs.value - 1000000)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = math.max(1, constraints.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onTapAt(_clampUs(_xToUs(d.localPosition.dx))),
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              children: [
                // Layer 1: ruler, waveform, segments, handles.
                CustomPaint(
                  size: Size(_width, _height),
                  painter: _TimelineBackgroundPainter(
                    durationUs: widget.durationUs,
                    viewStartUs: _viewStartUs,
                    viewSpanUs: _viewSpanUs,
                    segments: widget.segments,
                    selectedId: widget.selectedId,
                    mode: widget.mode,
                    waveform: widget.waveform,
                    trackColor: cs.surfaceContainerHighest,
                    waveColor: cs.onSurfaceVariant,
                    segmentColor: segmentColor,
                    tickColor: cs.outline,
                    labelStyle: style,
                  ),
                ),
                // Layer 2: the playhead only.
                ValueListenableBuilder<int>(
                  valueListenable: widget.playheadUs,
                  builder: (context, playhead, _) => CustomPaint(
                    size: Size(_width, _height),
                    painter: _PlayheadPainter(
                      viewStartUs: _viewStartUs,
                      viewSpanUs: _viewSpanUs,
                      playheadUs: playhead,
                      playheadColor: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Everything except the playhead. Never depends on the playhead position, so
/// it isn't re-rendered during playback.
class _TimelineBackgroundPainter extends CustomPainter {
  _TimelineBackgroundPainter({
    required this.durationUs,
    required this.viewStartUs,
    required this.viewSpanUs,
    required this.segments,
    required this.selectedId,
    required this.mode,
    required this.waveform,
    required this.trackColor,
    required this.waveColor,
    required this.segmentColor,
    required this.tickColor,
    required this.labelStyle,
  });

  final int durationUs;
  final int viewStartUs;
  final int viewSpanUs;
  final List<EditSegment> segments;
  final String? selectedId;
  final VideoEditMode mode;
  final AudioWaveform? waveform;
  final Color trackColor;
  final Color waveColor;
  final Color segmentColor;
  final Color tickColor;
  final TextStyle labelStyle;

  static const List<int> _stepsUs = [
    100000, 200000, 500000, 1000000, 2000000, 5000000, 10000000, 15000000,
    30000000, 60000000, 120000000, 300000000, 600000000, 900000000,
    1800000000, 3600000000, 7200000000,
  ];

  double _x(int us, double width) => (us - viewStartUs) / viewSpanUs * width;

  @override
  void paint(Canvas canvas, Size size) {
    const rulerH = AudioTimelineState._rulerHeight;
    const trackH = AudioTimelineState._trackHeight;
    const trackTop = rulerH + 4;
    final w = size.width;

    _paintRuler(canvas, w);

    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackTop, w, trackH),
      const Radius.circular(8),
    );

    canvas.save();
    canvas.clipRRect(trackRRect);
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    _paintWaveform(canvas, w, trackTop, trackH);
    _paintRemovedSections(canvas, w, trackTop, trackH);

    // Segment tint.
    for (final s in segments) {
      final x0 = _x(s.startUs, w);
      final x1 = _x(s.endUs, w);
      if (x1 < 0 || x0 > w) continue;
      final isSelected = s.id == selectedId;
      final rect = Rect.fromLTRB(
        math.max(x0, 0.0),
        trackTop,
        math.min(x1, w),
        trackTop + trackH,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = segmentColor.withValues(alpha: isSelected ? 0.25 : 0.12),
      );
    }
    canvas.restore();

    // Selected segment border and handles (outside the clip so they can overhang).
    for (final s in segments) {
      if (s.id != selectedId) continue;
      final x0 = _x(s.startUs, w);
      final x1 = _x(s.endUs, w);
      if (x1 < 0 || x0 > w) continue;
      final rect = Rect.fromLTRB(
        math.max(x0, 0.0),
        trackTop,
        math.min(x1, w),
        trackTop + trackH,
      );
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = segmentColor,
      );
      for (final x in [x0, x1]) {
        if (x < 0 || x > w) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 5, trackTop - 3, 10, trackH + 6),
            const Radius.circular(3),
          ),
          Paint()..color = segmentColor,
        );
        canvas.drawLine(
          Offset(x, trackTop + 8),
          Offset(x, trackTop + trackH - 8),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = 1.2,
        );
      }
    }
  }

  void _paintWaveform(Canvas canvas, double w, double trackTop, double trackH) {
    final mid = trackTop + trackH / 2;
    final wf = waveform;
    final line = Paint()
      ..color = waveColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    if (wf == null || wf.peaks.isEmpty) {
      canvas.drawLine(Offset(0, mid), Offset(w, mid), line);
      return;
    }

    // One bar per 2 px column: the loudest peak under that column, mirrored
    // around the centre line. Quiet passages are lifted by a power curve so
    // they stay visible next to loud ones.
    const colW = 2.0;
    final half = trackH / 2 - 4;
    final bar = Paint()
      ..color = waveColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final usPerPx = viewSpanUs / w;
    for (var x = 0.0; x < w; x += colW) {
      final t0 = (viewStartUs + x * usPerPx).round();
      final t1 = (viewStartUs + (x + colW) * usPerPx).round();
      if (t0 >= durationUs) break;
      // Not decoded yet: leave the flat centre line, don't paint bars of silence over it.
      if (!wf.complete && t0 >= wf.coveredUs) break;
      final peak = wf.peakBetween(t0, t1);
      final h = math.max(1.0, math.pow(peak / 255.0, 0.6).toDouble() * half);
      canvas.drawLine(Offset(x + 1, mid - h), Offset(x + 1, mid + h), bar);
    }
    canvas.drawLine(Offset(0, mid), Offset(w, mid), line);

    // Part of the file the native decode hasn't reached (yet, or ever if it stalled).
    if (!wf.complete) {
      final x = _x(wf.coveredUs, w);
      if (x < w) {
        canvas.drawRect(
          Rect.fromLTRB(math.max(x, 0.0), trackTop, w, trackTop + trackH),
          Paint()..color = trackColor.withValues(alpha: 0.6),
        );
      }
    }
  }

  void _paintRemovedSections(
    Canvas canvas,
    double w,
    double trackTop,
    double trackH,
  ) {
    final removedRanges = mode == VideoEditMode.keep
        ? invertRanges(
            mergeOverlapping([for (final s in segments) s.range]),
            durationUs,
          )
        : mergeOverlapping([for (final s in segments) s.range]);

    final removedPaint = Paint()..color = Colors.black.withValues(alpha: 0.52);
    final hatchPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    for (final gap in removedRanges) {
      final gx0 = _x(gap.startUs, w);
      final gx1 = _x(gap.endUs, w);
      if (gx1 < 0 || gx0 > w) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          math.max(gx0, 0.0),
          trackTop,
          math.min(gx1, w),
          trackTop + trackH,
        ),
        removedPaint,
      );

      // Diagonal hatching across the removed region.
      const step = 14.0;
      var hx = gx0 - trackH;
      while (hx < gx1 + trackH) {
        final p0 = Offset(math.max(gx0, hx), trackTop + trackH);
        final p1 = Offset(math.min(gx1, hx + trackH), trackTop);
        if (p0.dx <= p1.dx) canvas.drawLine(p0, p1, hatchPaint);
        hx += step;
      }
    }
  }

  void _paintRuler(Canvas canvas, double w) {
    final pxPerUs = w / viewSpanUs;
    var step = _stepsUs.last;
    for (final s in _stepsUs) {
      if (s * pxPerUs >= 70) {
        step = s;
        break;
      }
    }
    final tick = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    final first = (viewStartUs / step).ceil() * step;
    for (var t = first; t <= viewStartUs + viewSpanUs; t += step) {
      if (t > durationUs) break;
      final x = _x(t, w);
      canvas.drawLine(Offset(x, 12), Offset(x, 19), tick);
      final tp = TextPainter(
        text: TextSpan(
          text: formatTimecode(t, millis: step < 1000000),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (x + 3 + tp.width <= w) tp.paint(canvas, Offset(x + 3, 0));
    }
  }

  @override
  bool shouldRepaint(_TimelineBackgroundPainter old) =>
      old.viewStartUs != viewStartUs ||
      old.viewSpanUs != viewSpanUs ||
      old.selectedId != selectedId ||
      old.mode != mode ||
      old.segmentColor != segmentColor ||
      old.waveColor != waveColor ||
      !identical(old.segments, segments) ||
      !identical(old.waveform, waveform);
}

/// Lightweight top layer that only draws the playhead needle and circle.
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.viewStartUs,
    required this.viewSpanUs,
    required this.playheadUs,
    required this.playheadColor,
  });

  final int viewStartUs;
  final int viewSpanUs;
  final int playheadUs;
  final Color playheadColor;

  double _x(int us, double width) => (us - viewStartUs) / viewSpanUs * width;

  @override
  void paint(Canvas canvas, Size size) {
    const rulerH = AudioTimelineState._rulerHeight;
    const trackH = AudioTimelineState._trackHeight;
    const trackTop = rulerH + 4;
    final w = size.width;

    final px = _x(playheadUs, w);
    if (px >= -3 && px <= w + 3) {
      final paint = Paint()
        ..color = playheadColor
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(px, rulerH - 2),
        Offset(px, trackTop + trackH + 8),
        paint,
      );
      canvas.drawCircle(Offset(px, rulerH - 2), 5, paint);
    }
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.playheadUs != playheadUs ||
      old.viewStartUs != viewStartUs ||
      old.viewSpanUs != viewSpanUs ||
      old.playheadColor != playheadColor;
}
