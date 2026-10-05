import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

import '../models/edit_segment.dart';
import '../models/video_edit_math.dart';

/// One thumbnail entry in the timeline filmstrip.
typedef FilmstripEntry = ({int timeUs, ui.Image image});

enum _DragMode { none, scrub, zoom, dragStartHandle, dragEndHandle }

/// The editor's timeline: a time ruler, filmstrip, segments, keyframe ticks,
/// draggable handles, and playhead.
///
/// Painting is split into two independent layers:
/// - [_TimelineBackgroundPainter]: ruler, track, filmstrip, segments, keyframes,
///   and snapped export bars. Repaints ONLY when bounds, segments, or zoom change.
/// - [_PlayheadPainter]: playhead needle. Repaints at video playback rate without
///   touching the background or re-building ruler TextPainters.
class VideoTimeline extends StatefulWidget {
  const VideoTimeline({
    super.key,
    required this.durationUs,
    required this.segments,
    required this.selectedId,
    required this.mode,
    required this.keyframes,
    required this.snappedExportRanges,
    required this.playheadUs,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onTapAt,
    this.filmstripFrames,
    this.onHandleDragStart,
    this.onHandleDragUpdate,
    this.onHandleDragEnd,
  });

  final int durationUs;
  final List<EditSegment> segments;
  final String? selectedId;
  final VideoEditMode mode;
  final List<int> keyframes;

  /// Exactly what the cutter will export after keyframe snapping.
  /// Used to draw the thin export bars under the track (correct in all modes).
  final List<TimeRange> snappedExportRanges;
  final ValueListenable<int> playheadUs;

  final VoidCallback onScrubStart;
  final ValueChanged<int> onScrub;
  final VoidCallback onScrubEnd;
  final ValueChanged<int> onTapAt;

  final List<FilmstripEntry>? filmstripFrames;
  final VoidCallback? onHandleDragStart;
  final void Function(bool isStart, int us)? onHandleDragUpdate;
  final VoidCallback? onHandleDragEnd;

  EditSegment? get selected {
    if (selectedId == null) return null;
    final i = segments.indexWhere((s) => s.id == selectedId);
    return i < 0 ? null : segments[i];
  }

  @override
  State<VideoTimeline> createState() => VideoTimelineState();
}

class VideoTimelineState extends State<VideoTimeline> {
  static const double _rulerHeight = 20;
  static const double _trackHeight = 44;
  static const double _height = 84;
  static const int _maxZoomSpanUs = 1000000; // most zoomed-in: 1 s across the width

  late int _viewStartUs = 0;
  late int _viewSpanUs = _fullSpan;
  double _width = 1;

  // Gesture bookkeeping.
  _DragMode _dragMode = _DragMode.none;
  bool _gestureActive = false;
  bool _scrubbing = false;
  bool _multiTouch = false;
  int _gestureSpanUs = 0;
  int _focalUs = 0;
  int? _lastHapticKeyframe;

  int get _fullSpan => math.max(1, widget.durationUs);
  int get _minSpanUs => math.min(_fullSpan, _maxZoomSpanUs);

  @override
  void initState() {
    super.initState();
    widget.playheadUs.addListener(_followPlayhead);
  }

  @override
  void didUpdateWidget(VideoTimeline old) {
    super.didUpdateWidget(old);
    if (old.playheadUs != widget.playheadUs) {
      old.playheadUs.removeListener(_followPlayhead);
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
    final visible = playhead >= _viewStartUs && playhead <= _viewStartUs + _viewSpanUs;
    final anchorUs = visible ? playhead : _viewStartUs + _viewSpanUs ~/ 2;
    final frac = (anchorUs - _viewStartUs) / _viewSpanUs;
    final span = (_viewSpanUs / factor).round().clamp(_minSpanUs, _fullSpan).toInt();
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
    _multiTouch = d.pointerCount > 1;
    _gestureSpanUs = _viewSpanUs;
    _focalUs = _xToUs(d.localFocalPoint.dx);
    _lastHapticKeyframe = null;

    if (_multiTouch) {
      _dragMode = _DragMode.zoom;
      return;
    }

    // Check if user grabbed a handle of the selected segment
    final selected = widget.selected;
    if (selected != null) {
      const handleHitSlop = 24.0;
      final x0 = (selected.startUs - _viewStartUs) / _viewSpanUs * _width;
      final x1 = (selected.endUs - _viewStartUs) / _viewSpanUs * _width;
      final touchX = d.localFocalPoint.dx;
      final touchY = d.localFocalPoint.dy;
      const trackTop = _rulerHeight + 4;
      final inTrackY = touchY >= trackTop - 12 && touchY <= trackTop + _trackHeight + 12;

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
      _multiTouch = true;
      final scale = d.horizontalScale <= 0 ? 1.0 : d.horizontalScale;
      final span = (_gestureSpanUs / scale).round().clamp(_minSpanUs, _fullSpan).toInt();
      final start = (_focalUs - (d.localFocalPoint.dx / _width) * span).round();
      setState(() {
        _viewSpanUs = span;
        _viewStartUs = _clampStart(start, span);
      });
      return;
    }

    if (_dragMode == _DragMode.dragStartHandle || _dragMode == _DragMode.dragEndHandle) {
      final isStart = _dragMode == _DragMode.dragStartHandle;
      final rawUs = _clampUs(_xToUs(d.localFocalPoint.dx));
      var snappedUs = rawUs;
      if (widget.keyframes.isNotEmpty) {
        final kf = nearestKeyframe(widget.keyframes, rawUs);
        if (kf != null) {
          final kfX = (kf - _viewStartUs) / _viewSpanUs * _width;
          if ((d.localFocalPoint.dx - kfX).abs() <= 16.0) {
            snappedUs = kf;
          }
        }
      }
      if (snappedUs != _lastHapticKeyframe && widget.keyframes.contains(snappedUs)) {
        _lastHapticKeyframe = snappedUs;
        HapticFeedback.selectionClick();
      }
      widget.onHandleDragUpdate?.call(isStart, snappedUs);
      widget.onScrub(snappedUs);
      return;
    }

    if (_scrubbing) {
      widget.onScrub(_clampUs(_xToUs(d.localFocalPoint.dx)));
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragMode == _DragMode.dragStartHandle || _dragMode == _DragMode.dragEndHandle) {
      widget.onHandleDragEnd?.call();
    } else if (_scrubbing) {
      _scrubbing = false;
      widget.onScrubEnd();
    }
    _dragMode = _DragMode.none;
    _multiTouch = false;
    _gestureActive = false;
    _lastHapticKeyframe = null;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final segmentColor = widget.mode == VideoEditMode.keep ? cs.primary : cs.error;
    final style = context.typography.labelSmall?.copyWith(color: cs.onSurfaceVariant) ??
        TextStyle(fontSize: 10, color: cs.onSurfaceVariant);

    return Semantics(
      label: context.l10n.videoEditorTimelineLabel,
      value: '${formatTimecode(widget.playheadUs.value)} / ${formatTimecode(widget.durationUs)}',
      onIncrease: () => widget.onScrub(_clampUs(widget.playheadUs.value + 1000000)),
      onDecrease: () => widget.onScrub(_clampUs(widget.playheadUs.value - 1000000)),
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
                // Layer 1: Background, filmstrip, track, segments, handles, keyframes, ruler, export bars
                CustomPaint(
                  size: Size(_width, _height),
                  painter: _TimelineBackgroundPainter(
                    durationUs: widget.durationUs,
                    viewStartUs: _viewStartUs,
                    viewSpanUs: _viewSpanUs,
                    segments: widget.segments,
                    selectedId: widget.selectedId,
                    mode: widget.mode,
                    keyframes: widget.keyframes,
                    snappedExportRanges: widget.snappedExportRanges,
                    filmstripFrames: widget.filmstripFrames,
                    trackColor: cs.surfaceContainerHighest,
                    segmentColor: segmentColor,
                    snapColor: cs.tertiary,
                    tickColor: cs.outline,
                    labelStyle: style,
                  ),
                ),
                // Layer 2: Fast playhead needle (only repaints playhead)
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

/// Static / background layer of the timeline.
/// Does NOT depend on playheadUs, so it is never re-rendered during playback.
class _TimelineBackgroundPainter extends CustomPainter {
  _TimelineBackgroundPainter({
    required this.durationUs,
    required this.viewStartUs,
    required this.viewSpanUs,
    required this.segments,
    required this.selectedId,
    required this.mode,
    required this.keyframes,
    required this.snappedExportRanges,
    required this.filmstripFrames,
    required this.trackColor,
    required this.segmentColor,
    required this.snapColor,
    required this.tickColor,
    required this.labelStyle,
  });

  final int durationUs;
  final int viewStartUs;
  final int viewSpanUs;
  final List<EditSegment> segments;
  final String? selectedId;
  final VideoEditMode mode;
  final List<int> keyframes;
  final List<TimeRange> snappedExportRanges;
  final List<FilmstripEntry>? filmstripFrames;
  final Color trackColor;
  final Color segmentColor;
  final Color snapColor;
  final Color tickColor;
  final TextStyle labelStyle;

  static const List<int> _stepsUs = [
    100000, 200000, 500000, 1000000, 2000000, 5000000, 10000000, 15000000,
    30000000, 60000000, 120000000, 300000000, 600000000, 900000000,
    1800000000, 3600000000, 7200000000,
  ];

  double _x(int us, double width) => (us - viewStartUs) / viewSpanUs * width;

  int _lowerBound(int t) {
    var lo = 0;
    var hi = keyframes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (keyframes[mid] < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const rulerH = VideoTimelineState._rulerHeight;
    const trackH = VideoTimelineState._trackHeight;
    const trackTop = rulerH + 4;
    final w = size.width;

    _paintRuler(canvas, w);

    // Track rounded rect & filmstrip clipping
    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackTop, w, trackH),
      const Radius.circular(8),
    );

    canvas.save();
    canvas.clipRRect(trackRRect);

    // Base track
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    // Filmstrip frames — cover-fit: each thumbnail keeps its natural aspect
    // ratio (cropped to fill the track height) so zooming in reveals more of
    // the frame instead of stretching it.
    if (filmstripFrames != null && filmstripFrames!.isNotEmpty) {
      final frames = filmstripFrames!;
      final paint = Paint()..filterQuality = FilterQuality.low;
      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final nextUs = (i < frames.length - 1) ? frames[i + 1].timeUs : durationUs;
        final xStart = _x(frame.timeUs, w);
        final xEnd = _x(nextUs, w);
        if (xEnd < 0 || xStart > w) continue;
        final dstW = math.max(xEnd - xStart, 1.0);

        final imgW = frame.image.width.toDouble();
        final imgH = frame.image.height.toDouble();
        // The natural width the thumbnail would occupy at trackH height.
        final fitW = imgW * (trackH / imgH);

        if (dstW <= fitW) {
          // Destination is narrower than (or equal to) the natural fit:
          // centre-crop the source horizontally.
          final srcCropW = imgW * (dstW / fitW);
          final srcX = (imgW - srcCropW) / 2;
          final src = Rect.fromLTWH(srcX, 0, srcCropW, imgH);
          final dst = Rect.fromLTRB(xStart, trackTop, xStart + dstW, trackTop + trackH);
          canvas.drawImageRect(frame.image, src, dst, paint);
        } else {
          // Zoomed so far that this frame's span is wider than the natural
          // fit: tile the same cover-fitted thumbnail across the span.
          final src = Rect.fromLTWH(0, 0, imgW, imgH);
          var tileX = xStart;
          while (tileX < xEnd) {
            final tileEnd = math.min(tileX + fitW, xEnd);
            final tileW = tileEnd - tileX;
            final srcCropW = imgW * (tileW / fitW);
            final tileSrc = Rect.fromLTWH(0, 0, srcCropW, imgH);
            final tileDst = Rect.fromLTRB(tileX, trackTop, tileEnd, trackTop + trackH);
            canvas.drawImageRect(frame.image, tileSrc, tileDst, paint);
            tileX += fitW;
          }
        }
      }
    }

    // Shading for removed sections / gaps
    _paintRemovedSections(canvas, w, trackTop, trackH);

    // Kept segments overlay (tinted)
    for (final s in segments) {
      final x0 = _x(s.startUs, w);
      final x1 = _x(s.endUs, w);
      if (x1 < 0 || x0 > w) continue;
      final isSelected = s.id == selectedId;
      final rect = Rect.fromLTRB(math.max(x0, 0.0), trackTop, math.min(x1, w), trackTop + trackH);
      canvas.drawRect(
        rect,
        Paint()..color = segmentColor.withValues(alpha: isSelected ? 0.35 : 0.18),
      );
    }

    canvas.restore();

    // Selected segment borders and draggable handles (outside clip so handles can slightly extend)
    for (final s in segments) {
      final x0 = _x(s.startUs, w);
      final x1 = _x(s.endUs, w);
      if (x1 < 0 || x0 > w) continue;
      final isSelected = s.id == selectedId;

      if (isSelected) {
        final rect = Rect.fromLTRB(math.max(x0, 0.0), trackTop, math.min(x1, w), trackTop + trackH);
        canvas.drawRect(
          rect.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = segmentColor,
        );

        // Start handle (pill with grip line)
        if (x0 >= 0 && x0 <= w) {
          final handleRect = Rect.fromLTWH(x0 - 5, trackTop - 3, 10, trackH + 6);
          canvas.drawRRect(
            RRect.fromRectAndRadius(handleRect, const Radius.circular(3)),
            Paint()..color = segmentColor,
          );
          final grip = Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = 1.2;
          canvas.drawLine(Offset(x0, trackTop + 8), Offset(x0, trackTop + trackH - 8), grip);
        }

        // End handle (pill with grip line)
        if (x1 >= 0 && x1 <= w) {
          final handleRect = Rect.fromLTWH(x1 - 5, trackTop - 3, 10, trackH + 6);
          canvas.drawRRect(
            RRect.fromRectAndRadius(handleRect, const Radius.circular(3)),
            Paint()..color = segmentColor,
          );
          final grip = Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = 1.2;
          canvas.drawLine(Offset(x1, trackTop + 8), Offset(x1, trackTop + trackH - 8), grip);
        }
      }
    }

    // Keyframe ticks
    if (keyframes.isNotEmpty) {
      final lo = _lowerBound(viewStartUs);
      final hi = _lowerBound(viewStartUs + viewSpanUs + 1);
      final count = hi - lo;
      if (count > 0 && w / count >= 4) {
        final tick = Paint()
          ..color = tickColor.withValues(alpha: 0.8)
          ..strokeWidth = 1;
        for (var i = lo; i < hi; i++) {
          final x = _x(keyframes[i], w);
          canvas.drawLine(
            Offset(x, trackTop + trackH - 9),
            Offset(x, trackTop + trackH),
            tick,
          );
        }
      }
    }

    // What will really be exported (snapped to keyframes), as thin bars under the track.
    // Uses snappedExportRanges directly so it is 100% correct in both Keep and Cut-out modes!
    if (keyframes.isNotEmpty && snappedExportRanges.isNotEmpty) {
      final snapPaint = Paint()..color = snapColor;
      for (final r in snappedExportRanges) {
        final x0 = math.max(_x(r.startUs, w), 0.0);
        final x1 = math.min(_x(r.endUs, w), w);
        if (x1 <= x0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x0, trackTop + trackH + 3, x1, trackTop + trackH + 6),
            const Radius.circular(1.5),
          ),
          snapPaint,
        );
      }
    }
  }

  void _paintRemovedSections(Canvas canvas, double w, double trackTop, double trackH) {
    final removedRanges = mode == VideoEditMode.keep
        ? invertRanges(mergeOverlapping([for (final s in segments) s.range]), durationUs)
        : mergeOverlapping([for (final s in segments) s.range]);

    final removedPaint = Paint()..color = Colors.black.withValues(alpha: 0.52);
    final hatchPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    for (final gap in removedRanges) {
      final gx0 = _x(gap.startUs, w);
      final gx1 = _x(gap.endUs, w);
      if (gx1 < 0 || gx0 > w) continue;
      final gapRect = Rect.fromLTRB(math.max(gx0, 0.0), trackTop, math.min(gx1, w), trackTop + trackH);
      canvas.drawRect(gapRect, removedPaint);

      // Diagonal hatch lines across removed region
      const step = 14.0;
      var hx = gx0 - trackH;
      while (hx < gx1 + trackH) {
        final p0 = Offset(math.max(gx0, hx), trackTop + trackH);
        final p1 = Offset(math.min(gx1, hx + trackH), trackTop);
        if (p0.dx <= p1.dx) {
          canvas.drawLine(p0, p1, hatchPaint);
        }
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
      !identical(old.segments, segments) ||
      !identical(old.snappedExportRanges, snappedExportRanges) ||
      !identical(old.filmstripFrames, filmstripFrames) ||
      !identical(old.keyframes, keyframes);
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
    const rulerH = VideoTimelineState._rulerHeight;
    const trackH = VideoTimelineState._trackHeight;
    const trackTop = rulerH + 4;
    final w = size.width;

    final px = _x(playheadUs, w);
    if (px >= -3 && px <= w + 3) {
      final paint = Paint()
        ..color = playheadColor
        ..strokeWidth = 2;
      canvas.drawLine(Offset(px, rulerH - 2), Offset(px, trackTop + trackH + 8), paint);
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
