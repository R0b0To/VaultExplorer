import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart'
    show VideoPlaybackProgress;

/// The video seekbar row (position label / slider / duration label), plus
/// a preview of the frame under the thumb while scrubbing.
///
/// What that preview looks like depends on [previewStyle]:
///  - [ScrubPreviewStyle.miniBox]: a small thumbnail floating above the
///    thumb, drawn right here by [_ScrubPreviewBubble].
///  - [ScrubPreviewStyle.fullscreen]: the frame covers the whole video
///    area. That can't be drawn from inside this 32px-tall row, so the
///    active [VideoScrubPreviewController] is published to [previewHost]
///    and `VideoScrubFullscreenLayer` (in the viewer's top-level stack)
///    does the drawing.
///
/// Split out of `MediaViewerBottomControls` (which stays a
/// [StatelessWidget]) because showing either preview needs state of its
/// own: a [VideoScrubPreviewController] is opened in [_beginScrub] and
/// torn down in [_endScrub], scoped to exactly one drag gesture.
class VideoScrubProgressBar extends StatefulWidget {
  final VideoPlaybackManager playbackManager;
  final ValueNotifier<VideoPlaybackProgress> videoProgressNotifier;
  final ValueChanged<bool> onShowUIChanged;
  final VoidCallback onStartHideTimer;
  final ScrubPreviewStyle previewStyle;
  final VideoScrubPreviewHost previewHost;

  const VideoScrubProgressBar({
    super.key,
    required this.playbackManager,
    required this.videoProgressNotifier,
    required this.onShowUIChanged,
    required this.onStartHideTimer,
    required this.previewStyle,
    required this.previewHost,
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

  bool get _isFullscreen => widget.previewStyle == ScrubPreviewStyle.fullscreen;

  /// Width / height of the frame being previewed. Uses the player's own
  /// video size, which Media3 reports already turned upright on API 21+,
  /// the same orientation the native scrub frames are decoded in. Falls
  /// back to 16:9 (the old fixed box) while the size is still unknown.
  double _previewAspectRatio() {
    final size = widget.playbackManager.activeController?.value.size;
    if (size == null || size.width <= 0 || size.height <= 0) return 16 / 9;
    return size.width / size.height;
  }

  void _beginScrub() {
    // Guards against a stray double onChangeStart (shouldn't happen, but
    // costs nothing to be defensive about a session leak).
    final stale = _preview;
    if (stale != null) {
      stale.dispose();
      _releaseFromHost(stale);
    }
    final preview = VideoScrubPreviewController.forStyle(
      widget.playbackManager.activeController,
      widget.previewStyle,
    );
    _preview = preview;
    unawaited(preview.begin().then((_) {
      // begin() completing can outlive the drag (a very quick tap-and-
      // release); act only if this is still the active session and the
      // widget is still mounted, so the preview can appear once
      // availability is known instead of never showing up because the
      // very first onChanged tick raced ahead of it.
      if (!mounted || _preview != preview) return;
      // Fullscreen: hand the session to the layer, but only once the
      // native side has confirmed it can decode this video. Done here, in
      // an async callback, rather than in build()/dispose() -- notifying
      // the layer while the framework has the widget tree locked would
      // assert.
      if (_isFullscreen && preview.available) {
        widget.previewHost.value = preview;
      }
      setState(() {});
    }));
  }

  void _updateScrub(Duration position) {
    _preview?.requestFrame(position);
  }

  void _endScrub() {
    final preview = _preview;
    _preview = null;
    if (preview == null) return;
    unawaited(preview.end());
    // onChangeEnd resolves after awaiting a seek, so this bar (and the
    // screen that owns the host) may already be gone by now.
    if (mounted) _releaseFromHost(preview);
  }

  void _releaseFromHost(VideoScrubPreviewController preview) {
    if (widget.previewHost.value == preview) widget.previewHost.value = null;
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
            final positionStr = formatClockDuration(progress.position);
            final durationStr = formatClockDuration(progress.duration);
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
                          if (!_isFullscreen &&
                              progress.isDragging &&
                              hasValidDuration &&
                              preview != null &&
                              preview.available)
                            _ScrubPreviewBubble(
                              trackWidth: constraints.maxWidth,
                              sliderValue: progress.sliderValue,
                              label: positionStr,
                              preview: preview,
                              aspectRatio: _previewAspectRatio(),
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

/// Size of the mini-box thumbnail for frames of [aspectRatio] (width / height).
///
/// Fits the frame inside a 144x144 square so nothing is cropped: a 16:9 video
/// gets the original 144x81 box, a 9:16 one gets 81x144. Extreme ratios are
/// clamped to 1:2 .. 5:2 so the box never gets so narrow the timestamp label
/// doesn't fit; those (rare) frames are cropped slightly instead.
Size scrubMiniBoxSize(double aspectRatio) {
  const maxEdge = 144.0;
  final ratio = aspectRatio.isFinite && aspectRatio > 0
      ? aspectRatio.clamp(0.5, 2.5).toDouble()
      : 16 / 9;
  return ratio >= 1 ? Size(maxEdge, maxEdge / ratio) : Size(maxEdge * ratio, maxEdge);
}

/// The floating thumbnail + timestamp shown above the slider thumb.
///
/// The box takes the shape of the video ([scrubMiniBoxSize]) rather than
/// being a fixed 16:9, so portrait clips aren't cropped to a thin band.
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
  static const double _labelHeight = 20;
  static const double _gapAboveTrack = 12;
  static const double _rowHeight = 32;

  final double trackWidth;
  final double sliderValue;
  final String label;
  final VideoScrubPreviewController preview;

  /// Width / height of the frames being previewed.
  final double aspectRatio;

  const _ScrubPreviewBubble({
    required this.trackWidth,
    required this.sliderValue,
    required this.label,
    required this.preview,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final value = sliderValue.clamp(0.0, 1.0);
    final usableWidth = (trackWidth - _thumbRadius * 2).clamp(0.0, double.infinity);
    final thumbX = _thumbRadius + usableWidth * value;
    final box = scrubMiniBoxSize(aspectRatio);
    final maxLeft = (trackWidth - box.width).clamp(0.0, double.infinity);
    final left = (thumbX - box.width / 2).clamp(0.0, maxLeft);

    return Positioned(
      left: left,
      bottom: _rowHeight + _gapAboveTrack,
      child: IgnorePointer(
        child: Container(
          width: box.width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: box.width,
                height: box.height,
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
                      width: box.width,
                      height: box.height,
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
