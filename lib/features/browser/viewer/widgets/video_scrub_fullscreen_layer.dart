import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart'
    show VideoPlaybackProgress;

/// The [ScrubPreviewStyle.fullscreen] scrub preview: while the seekbar is
/// being dragged, the frame under the thumb fills the video area, with a
/// timestamp pill above the controls.
///
/// Lives in the viewer's top-level stack, *between* the media pages and the
/// top/bottom chrome. That z-order is the point: the frame covers the
/// video, but the seekbar the user's finger is on stays visible above it.
/// (The seekbar itself is a 32px row inside the bottom controls and can't
/// paint outside its own box, hence a separate layer fed through
/// [previewHost].)
///
/// Purely visual: it never takes pointer events, so the drag keeps going to
/// the slider.
class VideoScrubFullscreenLayer extends StatelessWidget {
  const VideoScrubFullscreenLayer({
    super.key,
    required this.previewHost,
    required this.progress,
    this.rotationQuarterTurns = 0,
  });

  /// Holds the active drag's preview session, or null between drags.
  final VideoScrubPreviewHost previewHost;

  /// Same notifier the seekbar drives; supplies "is a drag in progress" and
  /// the position/duration for the timestamp.
  final ValueListenable<VideoPlaybackProgress> progress;

  /// The viewer's manual "rotate" setting for the current video, in the same
  /// unit the video itself is given, so the frame turns with it.
  final int rotationQuarterTurns;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([previewHost, progress]),
        builder: (context, _) {
          final preview = previewHost.value;
          final p = progress.value;

          // isDisposed guards a session whose seekbar was unmounted
          // mid-drag: it can't clear the host from dispose() (notifying
          // during teardown would assert), so a stale entry is possible
          // and must not be built against.
          final Widget child;
          if (preview != null &&
              !preview.isDisposed &&
              p.isDragging &&
              p.duration > Duration.zero) {
            child = _FullscreenFrame(
              key: ObjectKey(preview),
              preview: preview,
              position: p.position,
              duration: p.duration,
              rotationQuarterTurns: rotationQuarterTurns,
            );
          } else {
            child = const SizedBox.shrink();
          }

          // Also what keeps the last frame on screen while it fades out
          // after the drag ends, covering the moment before the seek
          // underneath has rendered its new frame.
          return AnimatedSwitcher(duration: AppMotion.short2, child: child);
        },
      ),
    );
  }
}

class _FullscreenFrame extends StatelessWidget {
  const _FullscreenFrame({
    super.key,
    required this.preview,
    required this.position,
    required this.duration,
    required this.rotationQuarterTurns,
  });

  final VideoScrubPreviewController preview;
  final Duration position;
  final Duration duration;
  final int rotationQuarterTurns;

  /// Distance from the bottom safe-area edge to the pill: clears the bottom
  /// controls (seekbar row + transport dock) that sit above this layer.
  static const double _pillBottomOffset = 148;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: preview.frameNotifier,
      builder: (context, bytes, _) {
        // Until the first frame lands this stays fully transparent, so the
        // live video remains visible instead of blinking to black and back.
        return AnimatedOpacity(
          opacity: bytes == null ? 0 : 1,
          duration: AppMotion.short2,
          child: bytes == null
              ? const SizedBox.expand()
              : ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RotatedBox(
                        quarterTurns: rotationQuarterTurns,
                        child: _ScrubFrameImage(bytes: bytes),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: bottomInset + _pillBottomOffset,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ScrubTimePill(
                              position: position,
                              duration: duration,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// One decoded scrub frame, shown letterboxed.
///
/// Wraps [Image.memory] only to evict each frame from Flutter's shared
/// [ImageCache] once it has been replaced (or the layer goes away).
/// Fullscreen frames decode to several MB apiece; left alone, a long drag
/// would fill the cache's 100 MB budget with frames nobody will look at
/// again and push out everything the viewer and browser actually want kept.
class _ScrubFrameImage extends StatefulWidget {
  const _ScrubFrameImage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ScrubFrameImage> createState() => _ScrubFrameImageState();
}

class _ScrubFrameImageState extends State<_ScrubFrameImage> {
  static void _evict(Uint8List bytes) {
    // MemoryImage's identity is the bytes object itself, so this targets
    // exactly the entry Image.memory created for this frame.
    unawaited(MemoryImage(bytes).evict());
  }

  @override
  void didUpdateWidget(_ScrubFrameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _evict(oldWidget.bytes);
  }

  @override
  void dispose() {
    _evict(widget.bytes);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      widget.bytes,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      // Keep showing the previous frame while the next one decodes, rather
      // than flashing empty on every position change.
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
    );
  }
}

class _ScrubTimePill extends StatelessWidget {
  const _ScrubTimePill({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '${formatClockDuration(position)} / ${formatClockDuration(duration)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          // Fixed-width digits so the pill doesn't jitter as the time ticks.
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
