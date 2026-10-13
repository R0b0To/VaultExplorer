import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/audio_editor/models/audio_waveform.dart';

import 'vault_audio_recorder_controller.dart';

enum _DragTarget { none, start, end, seek }

/// An interactive audio trimmer displaying the audio waveform, draggable start
/// and end trim handles, and a moving playhead.
class AudioWaveformTrimmer extends StatefulWidget {
  final int durationMs;
  final int trimStartMs;
  final int trimEndMs;
  final int currentPositionMs;
  final AudioWaveform? waveform;
  final List<double>? recordedLevels;
  final int minTrimSpanMs;
  final double height;
  final void Function(int startMs, int endMs) onTrimChanged;
  final VoidCallback? onTrimChangeStart;
  final VoidCallback? onTrimChangeEnd;
  final ValueChanged<int>? onSeek;

  const AudioWaveformTrimmer({
    super.key,
    required this.durationMs,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.currentPositionMs,
    this.waveform,
    this.recordedLevels,
    this.minTrimSpanMs = 500,
    this.height = 88.0,
    required this.onTrimChanged,
    this.onTrimChangeStart,
    this.onTrimChangeEnd,
    this.onSeek,
  });

  @override
  State<AudioWaveformTrimmer> createState() => _AudioWaveformTrimmerState();
}

class _AudioWaveformTrimmerState extends State<AudioWaveformTrimmer> {
  static const double _handleWidth = 14.0;
  static const double _hitSlack = 28.0;

  _DragTarget _activeDrag = _DragTarget.none;

  double _xForMs(int ms, double width) {
    if (widget.durationMs <= 0) return _handleWidth;
    final usableW = math.max(1.0, width - 2 * _handleWidth);
    final frac = (ms / widget.durationMs).clamp(0.0, 1.0);
    return _handleWidth + frac * usableW;
  }

  int _msForX(double x, double width) {
    if (widget.durationMs <= 0) return 0;
    final usableW = math.max(1.0, width - 2 * _handleWidth);
    final frac = ((x - _handleWidth) / usableW).clamp(0.0, 1.0);
    return (frac * widget.durationMs).round();
  }

  void _handleDragStart(Offset localPos, double width) {
    final dx = localPos.dx;
    final startX = _xForMs(widget.trimStartMs, width);
    final endX = _xForMs(widget.trimEndMs, width);

    final distToStart = (dx - (startX - _handleWidth / 2)).abs();
    final distToEnd = (dx - (endX + _handleWidth / 2)).abs();

    final minSpan = math.min(widget.minTrimSpanMs, widget.durationMs);

    if (distToStart <= _hitSlack && distToEnd <= _hitSlack) {
      _activeDrag = distToStart <= distToEnd ? _DragTarget.start : _DragTarget.end;
    } else if (distToStart <= _hitSlack) {
      _activeDrag = _DragTarget.start;
    } else if (distToEnd <= _hitSlack) {
      _activeDrag = _DragTarget.end;
    } else if (dx >= startX && dx <= endX) {
      _activeDrag = _DragTarget.seek;
      final seekMs = _msForX(dx, width).clamp(widget.trimStartMs, widget.trimEndMs).toInt();
      widget.onSeek?.call(seekMs);
    } else if (dx < startX) {
      _activeDrag = _DragTarget.start;
      final newStart = _msForX(dx, width).clamp(0, widget.trimEndMs - minSpan).toInt();
      widget.onTrimChanged(newStart, widget.trimEndMs);
      widget.onSeek?.call(newStart);
    } else {
      _activeDrag = _DragTarget.end;
      final newEnd = _msForX(dx, width).clamp(widget.trimStartMs + minSpan, widget.durationMs).toInt();
      widget.onTrimChanged(widget.trimStartMs, newEnd);
      widget.onSeek?.call(newEnd);
    }

    // Only notify trim-change-start for actual handle drags, not seeks.
    if (_activeDrag == _DragTarget.start || _activeDrag == _DragTarget.end) {
      widget.onTrimChangeStart?.call();
    }
    HapticFeedback.selectionClick();
  }

  void _handleDragUpdate(Offset localPos, double width) {
    if (_activeDrag == _DragTarget.none) return;
    final dx = localPos.dx;
    final minSpan = math.min(widget.minTrimSpanMs, widget.durationMs);

    switch (_activeDrag) {
      case _DragTarget.start:
        final newStart = _msForX(dx, width).clamp(
          0,
          widget.trimEndMs - minSpan,
        ).toInt();
        widget.onTrimChanged(newStart, widget.trimEndMs);
        widget.onSeek?.call(newStart);
      case _DragTarget.end:
        final newEnd = _msForX(dx, width).clamp(
          widget.trimStartMs + minSpan,
          widget.durationMs,
        ).toInt();
        widget.onTrimChanged(widget.trimStartMs, newEnd);
        widget.onSeek?.call(newEnd);
      case _DragTarget.seek:
        final seekMs = _msForX(dx, width).clamp(widget.trimStartMs, widget.trimEndMs).toInt();
        widget.onSeek?.call(seekMs);
      case _DragTarget.none:
        break;
    }
  }

  void _handleDragEnd() {
    final wasTrimDrag =
        _activeDrag == _DragTarget.start || _activeDrag == _DragTarget.end;
    _activeDrag = _DragTarget.none;
    if (wasTrimDrag) {
      widget.onTrimChangeEnd?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final selectedMs = math.max(0, widget.trimEndMs - widget.trimStartMs);
    final isTrimmed = widget.trimStartMs > 0 || widget.trimEndMs < widget.durationMs;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Time labels above waveform
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  formatAudioDuration(widget.trimStartMs),
                  style: textTheme.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    isTrimmed
                        ? 'Trimmed: ${formatAudioDuration(selectedMs)}'
                        : 'Duration: ${formatAudioDuration(selectedMs)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: isTrimmed ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: isTrimmed ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  formatAudioDuration(widget.trimEndMs),
                  style: textTheme.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Waveform & Trimmer Track
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = widget.height;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _handleDragStart(d.localPosition, w),
              onHorizontalDragUpdate: (d) => _handleDragUpdate(d.localPosition, w),
              onHorizontalDragEnd: (_) => _handleDragEnd(),
              onHorizontalDragCancel: _handleDragEnd,
              onTapUp: (d) {
                _handleDragStart(d.localPosition, w);
                _handleDragEnd();
              },
              child: SizedBox(
                width: w,
                height: h,
                child: CustomPaint(
                  painter: _WaveformTrimmerPainter(
                    durationMs: widget.durationMs,
                    trimStartMs: widget.trimStartMs,
                    trimEndMs: widget.trimEndMs,
                    currentPositionMs: widget.currentPositionMs,
                    waveform: widget.waveform,
                    recordedLevels: widget.recordedLevels,
                    handleWidth: _handleWidth,
                    activeColor: cs.primary,
                    inactiveColor: cs.outlineVariant,
                    trackColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WaveformTrimmerPainter extends CustomPainter {
  final int durationMs;
  final int trimStartMs;
  final int trimEndMs;
  final int currentPositionMs;
  final AudioWaveform? waveform;
  final List<double>? recordedLevels;
  final double handleWidth;
  final Color activeColor;
  final Color inactiveColor;
  final Color trackColor;

  _WaveformTrimmerPainter({
    required this.durationMs,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.currentPositionMs,
    required this.waveform,
    required this.recordedLevels,
    required this.handleWidth,
    required this.activeColor,
    required this.inactiveColor,
    required this.trackColor,
  });

  double _xForMs(int ms, double width) {
    if (durationMs <= 0) return handleWidth;
    final usableW = math.max(1.0, width - 2 * handleWidth);
    final frac = (ms / durationMs).clamp(0.0, 1.0);
    return handleWidth + frac * usableW;
  }

  int _msForX(double x, double width) {
    if (durationMs <= 0) return 0;
    final usableW = math.max(1.0, width - 2 * handleWidth);
    final frac = ((x - handleWidth) / usableW).clamp(0.0, 1.0);
    return (frac * durationMs).round();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(12),
    );

    // Clip to rounded track
    canvas.save();
    canvas.clipRRect(trackRRect);

    // Track background
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    final startX = _xForMs(trimStartMs, w);
    final endX = _xForMs(trimEndMs, w);

    // Draw waveform bars
    _paintWaveformBars(canvas, w, h, startX, endX);

    // Draw shaded / dimmed masks outside trim
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    if (startX > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, startX, h), maskPaint);
    }
    if (endX < w) {
      canvas.drawRect(Rect.fromLTWH(endX, 0, w - endX, h), maskPaint);
    }

    // Active selection background tint
    final activeTintPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.08);
    canvas.drawRect(Rect.fromLTWH(startX, 0, math.max(0.0, endX - startX), h), activeTintPaint);

    // Trim bounding borders: top and bottom lines
    final borderPaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(startX, 1.25), Offset(endX, 1.25), borderPaint);
    canvas.drawLine(Offset(startX, h - 1.25), Offset(endX, h - 1.25), borderPaint);

    // Left Handle
    final leftHandleRect = Rect.fromLTWH(startX - handleWidth, 0, handleWidth, h);
    final leftHandleRRect = RRect.fromRectAndCorners(
      leftHandleRect,
      topLeft: const Radius.circular(10),
      bottomLeft: const Radius.circular(10),
    );
    canvas.drawRRect(leftHandleRRect, Paint()..color = activeColor);

    // Right Handle
    final rightHandleRect = Rect.fromLTWH(endX, 0, handleWidth, h);
    final rightHandleRRect = RRect.fromRectAndCorners(
      rightHandleRect,
      topRight: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    canvas.drawRRect(rightHandleRRect, Paint()..color = activeColor);

    // Grip indicators inside handles
    final gripPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final leftCenterX = startX - handleWidth / 2;
    canvas.drawLine(Offset(leftCenterX - 1.8, h / 2 - 8), Offset(leftCenterX - 1.8, h / 2 + 8), gripPaint);
    canvas.drawLine(Offset(leftCenterX + 1.8, h / 2 - 8), Offset(leftCenterX + 1.8, h / 2 + 8), gripPaint);

    final rightCenterX = endX + handleWidth / 2;
    canvas.drawLine(Offset(rightCenterX - 1.8, h / 2 - 8), Offset(rightCenterX - 1.8, h / 2 + 8), gripPaint);
    canvas.drawLine(Offset(rightCenterX + 1.8, h / 2 - 8), Offset(rightCenterX + 1.8, h / 2 + 8), gripPaint);

    // Playhead Needle
    if (durationMs > 0 && currentPositionMs >= 0) {
      final needleX = _xForMs(currentPositionMs, w);
      final needlePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(needleX, 0), Offset(needleX, h), needlePaint);

      final pipPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(needleX, 4), 3.0, pipPaint);
      canvas.drawCircle(Offset(needleX, h - 4), 3.0, pipPaint);
    }

    canvas.restore();
  }

  void _paintWaveformBars(Canvas canvas, double w, double h, double startX, double endX) {
    const colW = 3.5;
    const barWidth = 2.2;
    final midY = h / 2;
    final maxBarHeight = h - 16.0;
    const minBarHeight = 4.0;

    final activeBarPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final inactiveBarPaint = Paint()
      ..color = inactiveColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final wf = waveform;
    final levels = recordedLevels;

    for (var x = handleWidth; x < w - handleWidth; x += colW) {
      final barCenterX = x + colW / 2;
      final t0Ms = _msForX(x, w);
      final t1Ms = _msForX(x + colW, w);

      double level = 0.0;
      if (wf != null && wf.peaks.isNotEmpty) {
        final peak = wf.peakBetween(t0Ms * 1000, t1Ms * 1000);
        level = math.pow(peak / 255.0, 0.65).toDouble();
      } else if (levels != null && levels.isNotEmpty && durationMs > 0) {
        final n = levels.length;
        final i0 = ((t0Ms / durationMs) * n).floor().clamp(0, n - 1);
        final i1 = ((t1Ms / durationMs) * n).ceil().clamp(i0 + 1, n);
        var maxL = 0.0;
        for (var i = i0; i < i1; i++) {
          if (levels[i] > maxL) maxL = levels[i];
        }
        level = math.pow(maxL, 0.75).toDouble();
      } else {
        // Fallback default level if waveform not yet ready
        level = 0.15;
      }

      final barH = math.max(minBarHeight, level * maxBarHeight);
      final isInTrim = barCenterX >= startX && barCenterX <= endX;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(barCenterX, midY),
            width: barWidth,
            height: barH,
          ),
          const Radius.circular(barWidth / 2),
        ),
        isInTrim ? activeBarPaint : inactiveBarPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformTrimmerPainter old) =>
      old.durationMs != durationMs ||
      old.trimStartMs != trimStartMs ||
      old.trimEndMs != trimEndMs ||
      old.currentPositionMs != currentPositionMs ||
      old.waveform != waveform ||
      old.recordedLevels != recordedLevels ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.trackColor != trackColor;
}
