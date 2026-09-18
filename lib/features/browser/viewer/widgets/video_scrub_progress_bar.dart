import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart'
    show VideoPlaybackProgress;

/// The video seekbar row (position label / slider / duration label), plus
/// a floating thumbnail that appears above the drag thumb while scrubbing.
///
/// Split out of `MediaViewerBottomControls` (which stays a
/// [StatelessWidget]) because showing that thumbnail needs state of its
/// own: a [VideoScrubPreviewController] is opened in [_beginScrub] and
/// torn down in [_endScrub], scoped to exactly one drag gesture.
class VideoScrubProgressBar extends StatefulWidget {
  final VideoPlaybackManager playbackManager;
  final ValueNotifier<VideoPlaybackProgress> videoProgressNotifier;
  final ValueChanged<bool> onShowUIChanged;
  final VoidCallback onStartHideTimer;

  const VideoScrubProgressBar({
    super.key,
    required this.playbackManager,
    required this.videoProgressNotifier,
    required this.onShowUIChanged,
    required this.onStartHideTimer,
  });

  @override
  State<VideoScrubProgressBar> createState() => _VideoScrubProgressBarState();
}

class _VideoScrubProgressBarState extends State<VideoScrubProgressBar> {
  VideoScrubPreviewController? _preview;

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final Duration abs = d.isNegative ? -d : d;
    final String minutes = abs.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = abs.inSeconds.remainder(60).toString().padLeft(2, '0');
    final String sign = d.isNegative ? '-' : '';
    if (abs.inHours > 0) {
      final String hours = abs.inHours.toString().padLeft(2, '0');
      return '$sign$hours:$minutes:$seconds';
    }
    return '$sign$minutes:$seconds';
  }

  void _beginScrub() {
    // Guards against a stray double onChangeStart (shouldn't happen, but
    // costs nothing to be defensive about a session leak).
    _preview?.dispose();
    final preview = VideoScrubPreviewController(widget.playbackManager.activeController);
    _preview = preview;
    unawaited(preview.begin().then((_) {
      // begin() completing can outlive the drag (a very quick tap-and-
      // release); rebuild only if this is still the active session and
      // the widget is still mounted, so the preview bubble can appear
      // once availability is known instead of never showing up because
      // the very first onChanged tick raced ahead of it.
      if (mounted && _preview == preview) setState(() {});
    }));
  }

  void _updateScrub(Duration position) {
    _preview?.requestFrame(position);
  }

  void _endScrub() {
    final preview = _preview;
    _preview = null;
    unawaited(preview?.end());
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SizedBox(
      height: 32,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: cs.primary,
          inactiveTrackColor: Colors.white24,
          trackHeight: 3,
          thumbColor: cs.primary,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          trackShape: const RectangularSliderTrackShape(),
        ),
        child: ValueListenableBuilder<VideoPlaybackProgress>(
          valueListenable: widget.videoProgressNotifier,
          builder: (context, progress, child) {
            final positionStr = _formatDuration(progress.position);
            final durationStr = _formatDuration(progress.duration);
            final bool hasValidDuration = progress.duration.inMilliseconds > 0;

            return Row(
              children: [
                Text(
                  positionStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final preview = _preview;
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          Slider(
                            value: progress.sliderValue.clamp(0.0, 1.0),
                            onChangeStart: hasValidDuration
                                ? (value) {
                                    widget.onShowUIChanged(true);
                                    widget.videoProgressNotifier.value =
                                        progress.copyWith(isDragging: true);
                                    _beginScrub();
                                  }
                                : null,
                            onChanged: hasValidDuration
                                ? (value) {
                                    widget.onShowUIChanged(true);
                                    final ms = progress.duration.inMilliseconds;
                                    final target = Duration(
                                      milliseconds: (value * ms).round().clamp(0, ms),
                                    );
                                    widget.videoProgressNotifier.value = progress.copyWith(
                                      isDragging: true,
                                      sliderValue: value,
                                      position: target,
                                    );
                                    _updateScrub(target);
                                  }
                                : null,
                            onChangeEnd: hasValidDuration
                                ? (value) async {
                                    final controller = widget.playbackManager.activeController;
                                    final ms = progress.duration.inMilliseconds;
                                    final targetDuration = Duration(
                                      milliseconds: (value * ms).round().clamp(0, ms),
                                    );
                                    if (controller != null && controller.value.isInitialized) {
                                      try {
                                        await controller.seekTo(targetDuration);
                                      } catch (e) {
                                        VeLog.w('VideoScrubProgressBar', 'Scrubber seekTo failed', e);
                                      }
                                    }
                                    widget.videoProgressNotifier.value = progress.copyWith(
                                      position: targetDuration,
                                      sliderValue: value.clamp(0.0, 1.0),
                                      isDragging: false,
                                    );
                                    _endScrub();
                                    widget.onStartHideTimer();
                                  }
                                : null,
                          ),
                          if (progress.isDragging &&
                              hasValidDuration &&
                              preview != null &&
                              preview.available)
                            _ScrubPreviewBubble(
                              trackWidth: constraints.maxWidth,
                              sliderValue: progress.sliderValue,
                              label: positionStr,
                              preview: preview,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Text(
                  durationStr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The floating thumbnail + timestamp shown above the slider thumb.
///
/// Positioned using the exact geometry Flutter's own [Slider] uses for
/// this widget's [RoundSliderThumbShape]/[RectangularSliderTrackShape]
/// configuration: the track (and so the thumb's travel range) is inset by
/// the thumb radius on each side, so the thumb's center sits at
/// `thumbRadius + (trackWidth - 2 * thumbRadius) * sliderValue`. [Stack]
/// clips by default, so the [VideoScrubProgressBar] above wraps this in
/// `clipBehavior: Clip.none` -- otherwise this bubble, which deliberately
/// extends above the 32px-tall seekbar row, would be cut off at its top.
class _ScrubPreviewBubble extends StatelessWidget {
  static const double _thumbRadius = 6;
  static const double _boxWidth = 144;
  static const double _boxHeight = 81;
  static const double _labelHeight = 20;
  static const double _gapAboveTrack = 12;
  static const double _rowHeight = 32;

  final double trackWidth;
  final double sliderValue;
  final String label;
  final VideoScrubPreviewController preview;

  const _ScrubPreviewBubble({
    required this.trackWidth,
    required this.sliderValue,
    required this.label,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final value = sliderValue.clamp(0.0, 1.0);
    final usableWidth = (trackWidth - _thumbRadius * 2).clamp(0.0, double.infinity);
    final thumbX = _thumbRadius + usableWidth * value;
    final maxLeft = (trackWidth - _boxWidth).clamp(0.0, double.infinity);
    final left = (thumbX - _boxWidth / 2).clamp(0.0, maxLeft);

    return Positioned(
      left: left,
      bottom: _rowHeight + _gapAboveTrack,
      child: IgnorePointer(
        child: Container(
          width: _boxWidth,
          // REMOVE THIS LINE:
          // height: _boxHeight + _labelHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _boxWidth,
                height: _boxHeight,
                child: ValueListenableBuilder<Uint8List?>(
                  valueListenable: preview.frameNotifier,
                  builder: (context, bytes, _) {
                    if (bytes == null) {
                      return const ColoredBox(color: Colors.black54);
                    }
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      width: _boxWidth,
                      height: _boxHeight,
                    );
                  },
                ),
              ),
              SizedBox(
                height: _labelHeight,
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
