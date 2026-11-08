import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/audio_editor/audio_edit_providers.dart';
import 'package:vaultexplorer/features/browser/viewer/models/ab_loop_state.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart'
    show VideoPlaybackProgress;
import 'package:vaultexplorer/features/library/waveform/waveform_bars.dart';

/// The seek bar for music: the track's waveform, with the played part
/// highlighted, which can be tapped or dragged to seek.
///
/// It uses the same envelope extractor as the audio editor, asked for the file
/// the player has open. Until that is ready, and for a file that is too long to
/// be worth decoding while it plays (an audiobook), or one that cannot be
/// decoded, [fallback] (the ordinary slider) is shown instead, so seeking always
/// works. Seeking follows the slider's contract exactly: the progress notifier
/// is updated while dragging and the player is told to seek on release, and an
/// A-B loop clamps the position.
class AudioWaveformSeekBar extends ConsumerStatefulWidget {
  final VideoPlaybackManager playbackManager;
  final ValueNotifier<VideoPlaybackProgress> videoProgressNotifier;
  final ValueListenable<AbLoopState> abLoopNotifier;
  final ValueChanged<bool> onShowUIChanged;
  final VoidCallback onStartHideTimer;

  /// Shown whenever there is no waveform to draw.
  final Widget fallback;

  /// Colour of the elapsed and total time. White suits the viewer's dark
  /// background; the music player panel passes its own theme colours.
  final Color timeColor;

  /// Colour of the part of the waveform that has not played yet.
  final Color restColor;

  const AudioWaveformSeekBar({
    super.key,
    required this.playbackManager,
    required this.videoProgressNotifier,
    required this.abLoopNotifier,
    required this.onShowUIChanged,
    required this.onStartHideTimer,
    required this.fallback,
    this.timeColor = Colors.white,
    this.restColor = Colors.white24,
  });

  /// Longer files keep the plain slider: decoding them would compete with
  /// playback for minutes.
  static const Duration maxDecodeDuration = Duration(minutes: 25);

  @override
  ConsumerState<AudioWaveformSeekBar> createState() => _AudioWaveformSeekBarState();
}

class _AudioWaveformSeekBarState extends ConsumerState<AudioWaveformSeekBar> {
  /// Finished waveforms, so a track played again (or stepped back to) draws at
  /// once. Bars are tiny; the cap is only about not growing without bound.
  static final LinkedHashMap<String, List<double>> _cache = LinkedHashMap();
  static const int _cacheLimit = 32;

  /// Operation ids for the extractor: kept well above the audio editor's own so
  /// the two can never be confused in progress events.
  static int _nextOpId = 0x40000000;

  List<double>? _bars;
  String? _loadedKey;
  int? _runningOp;

  @override
  void initState() {
    super.initState();
    widget.playbackManager.activeControllerNotifier.addListener(_maybeLoad);
    widget.videoProgressNotifier.addListener(_maybeLoad);
    _maybeLoad();
  }

  @override
  void dispose() {
    widget.playbackManager.activeControllerNotifier.removeListener(_maybeLoad);
    widget.videoProgressNotifier.removeListener(_maybeLoad);
    _cancelRunning();
    super.dispose();
  }

  String? _keyFor() {
    final c = widget.playbackManager.activeController;
    if (c == null) return null;
    return '${c.volId}|${c.filePath}|${c.isLocalStorage}';
  }

  void _cancelRunning() {
    final op = _runningOp;
    _runningOp = null;
    if (op != null) {
      unawaited(ref.read(vaultAudioEditApiProvider).cancel(op).catchError((_) {}));
    }
  }

  /// Starts loading when the playing file changes (or its length becomes
  /// known), and does nothing otherwise. Called on every progress tick, so the
  /// early exits matter.
  void _maybeLoad() {
    if (!mounted) return;
    final key = _keyFor();
    if (key == null) return;
    if (key == _loadedKey) return;

    final controller = widget.playbackManager.activeController!;
    final duration = widget.videoProgressNotifier.value.duration;
    // Length not known yet: try again on a later tick rather than decode blind.
    if (duration <= Duration.zero) return;

    _cancelRunning();
    _loadedKey = key;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      setState(() => _bars = cached);
      return;
    }
    setState(() => _bars = null);
    if (duration > AudioWaveformSeekBar.maxDecodeDuration) return;

    final op = _nextOpId++;
    _runningOp = op;
    final api = ref.read(vaultAudioEditApiProvider);
    unawaited(() async {
      try {
        final result = await api.waveform(
          volId: controller.volId,
          filePath: controller.filePath,
          isLocalStorage: controller.isLocalStorage,
          opId: op,
        );
        if (!mounted || _runningOp != op) return;
        _runningOp = null;
        final bars = WaveformBars.fromPeaks(result.peaks);
        if (bars.isEmpty) return;
        _cache[key] = bars;
        while (_cache.length > _cacheLimit) {
          _cache.remove(_cache.keys.first);
        }
        setState(() => _bars = bars);
      } catch (e) {
        // A file that cannot be decoded just keeps the ordinary slider.
        if (_runningOp == op) _runningOp = null;
        VeLog.w('AudioWaveformSeekBar', 'Waveform unavailable', e);
      }
    }());
  }

  // ── Seeking (same contract as the ordinary slider) ───────────────────────

  double _clampToLoop(double value, Duration duration) {
    final loop = widget.abLoopNotifier.value;
    final a = loop.a;
    if (a == null || duration <= Duration.zero) return value;
    final ms = duration.inMilliseconds;
    final lower = a.inMilliseconds / ms;
    final b = loop.b;
    final upper = b == null ? 1.0 : b.inMilliseconds / ms;
    return math.min(math.max(value, lower), upper);
  }

  void _begin() {
    widget.onShowUIChanged(true);
    final p = widget.videoProgressNotifier.value;
    widget.videoProgressNotifier.value = p.copyWith(isDragging: true);
  }

  void _update(double dx, double width) {
    final p = widget.videoProgressNotifier.value;
    if (p.duration.inMilliseconds <= 0 || width <= 0) return;
    final value = _clampToLoop((dx / width).clamp(0.0, 1.0), p.duration);
    final ms = p.duration.inMilliseconds;
    widget.onShowUIChanged(true);
    widget.videoProgressNotifier.value = p.copyWith(
      isDragging: true,
      sliderValue: value,
      position: Duration(milliseconds: (value * ms).round().clamp(0, ms)),
    );
  }

  Future<void> _end() async {
    final p = widget.videoProgressNotifier.value;
    final value = p.sliderValue.clamp(0.0, 1.0);
    final ms = p.duration.inMilliseconds;
    final target = Duration(milliseconds: (value * ms).round().clamp(0, ms));
    final controller = widget.playbackManager.activeController;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.seekTo(target);
      } catch (e) {
        VeLog.w('AudioWaveformSeekBar', 'seekTo failed', e);
      }
    }
    widget.videoProgressNotifier.value = widget.videoProgressNotifier.value.copyWith(
      position: target,
      sliderValue: value,
      isDragging: false,
    );
    widget.onStartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars;
    if (bars == null) return widget.fallback;

    final cs = context.colors;
    return SizedBox(
      height: 52,
      child: ValueListenableBuilder<VideoPlaybackProgress>(
        valueListenable: widget.videoProgressNotifier,
        builder: (context, progress, _) {
          final hasDuration = progress.duration.inMilliseconds > 0;
          return Row(
            children: [
              Text(
                formatClockDuration(progress.position),
                style: TextStyle(
                  color: widget.timeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: hasDuration
                          ? (d) {
                              _begin();
                              _update(d.localPosition.dx, width);
                            }
                          : null,
                      onTapUp: hasDuration ? (_) => unawaited(_end()) : null,
                      onTapCancel: hasDuration ? () => unawaited(_end()) : null,
                      onHorizontalDragStart: hasDuration ? (_) => _begin() : null,
                      onHorizontalDragUpdate: hasDuration
                          ? (d) => _update(d.localPosition.dx, width)
                          : null,
                      onHorizontalDragEnd: hasDuration ? (_) => unawaited(_end()) : null,
                      onHorizontalDragCancel: hasDuration ? () => unawaited(_end()) : null,
                      child: ValueListenableBuilder<AbLoopState>(
                        valueListenable: widget.abLoopNotifier,
                        builder: (context, loop, _) => CustomPaint(
                          size: Size(width, 52),
                          painter: _WaveformPainter(
                            bars: bars,
                            progress: progress.sliderValue.clamp(0.0, 1.0),
                            playedColor: cs.primary,
                            restColor: widget.restColor,
                            loop: loop,
                            duration: progress.duration,
                            loopColor: cs.tertiary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatClockDuration(progress.duration),
                style: TextStyle(
                  color: widget.timeColor.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color playedColor;
  final Color restColor;
  final AbLoopState loop;
  final Duration duration;
  final Color loopColor;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.playedColor,
    required this.restColor,
    required this.loop,
    required this.duration,
    required this.loopColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;
    final n = bars.length;
    final slot = size.width / n;
    final barWidth = math.max(1.5, slot * 0.62);
    final midY = size.height / 2;

    // The A-B section sits behind the bars.
    final a = loop.a;
    if (a != null && duration > Duration.zero) {
      final ms = duration.inMilliseconds;
      final from = (a.inMilliseconds / ms).clamp(0.0, 1.0) * size.width;
      final b = loop.b;
      final to = b == null ? size.width : (b.inMilliseconds / ms).clamp(0.0, 1.0) * size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(from, 0, math.max(from + 2, to), size.height),
          const Radius.circular(4),
        ),
        Paint()..color = loopColor.withValues(alpha: 0.22),
      );
    }

    final played = Paint()..color = playedColor;
    final rest = Paint()..color = restColor;
    final playedBars = WaveformBars.playedBars(progress, n);
    for (var i = 0; i < n; i++) {
      final h = math.max(2.0, size.height * 0.92 * bars[i]);
      final cx = slot * i + slot / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, midY), width: barWidth, height: h),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, (i + 0.5) <= playedBars ? played : rest);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      !identical(old.bars, bars) ||
      old.playedColor != playedColor ||
      old.restColor != restColor ||
      old.loop.a != loop.a ||
      old.loop.b != loop.b ||
      old.duration != duration;
}
