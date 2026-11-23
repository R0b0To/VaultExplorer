import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/encrypted_image_widget.dart';

/// Full-resolution image for the desktop preview pane.
///
/// [EncryptedImageWidget] shows the cached thumbnail straight away and swaps in the full-resolution
/// decode (capped to the screen size) once it has loaded, so the pane is never blank and never stays blurry.
class PreviewPaneImage extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailQuality quality;
  final ThumbnailCacheMode cacheMode;

  const PreviewPaneImage({
    super.key,
    required this.container,
    required this.filePath,
    required this.quality,
    required this.cacheMode,
  });

  @override
  Widget build(BuildContext context) => EncryptedImageWidget(
    key: ValueKey<String>('preview_img:${container.volId}:$filePath'),
    container: container,
    fileName: filePath,
    fit: BoxFit.contain,
    thumbnailQuality: quality,
    thumbnailCacheMode: cacheMode,
  );
}

/// Inline video player for the desktop preview pane.
///
/// Shows [poster] (the thumbnail) with a play button; nothing is opened until the user presses play, so
/// merely clicking through a folder of videos does not start a player for each one. Once started it plays
/// in place with a compact play/pause + seek bar, and the player is disposed when the selection changes.
class PreviewPaneVideo extends StatefulWidget {
  final MountedContainer container;
  final String filePath;
  final Widget poster;

  const PreviewPaneVideo({
    super.key,
    required this.container,
    required this.filePath,
    required this.poster,
  });

  @override
  State<PreviewPaneVideo> createState() => _PreviewPaneVideoState();
}

class _PreviewPaneVideoState extends State<PreviewPaneVideo> {
  NativeVideoController? _controller;
  bool _starting = false;
  double? _dragMs;

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onTick);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_starting || _controller != null) return;
    setState(() => _starting = true);
    // The app has a single native player; background audio lets go of it first.
    if (BackgroundPlaybackHost.instance.needsRelease) {
      await BackgroundPlaybackHost.instance.closeAndWait();
      if (!mounted) return;
    }
    final controller = NativeVideoController(
      volId: widget.container.volId,
      filePath: widget.filePath,
      autoPlay: true,
    );
    controller.addListener(_onTick);
    setState(() {
      _controller = controller;
      _starting = false;
    });
    await controller.initialize();
    if (!mounted || !identical(_controller, controller)) return;
    await controller.play();
  }

  Future<void> _togglePlay(NativeVideoController controller) async {
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _buildPoster(context);

    final value = controller.value;
    if (value.hasError) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.poster,
          Center(
            child: Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 36,
            ),
          ),
        ],
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (value.isInitialized)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _togglePlay(controller),
              child: Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: NativeVideoPlayerView(controller: controller),
                ),
              ),
            ),
          if (!value.isInitialized || value.isBuffering)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControls(context, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildPoster(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.poster,
      Center(
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _start,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _starting
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildControls(BuildContext context, NativeVideoController controller) {
    final value = controller.value;
    final durationMs = value.duration.inMilliseconds.toDouble();
    final positionMs = (_dragMs ?? value.position.inMilliseconds.toDouble())
        .clamp(0.0, durationMs > 0 ? durationMs : 1.0);
    const textStyle = TextStyle(color: Colors.white, fontSize: 11);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xB3000000)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            color: Colors.white,
            iconSize: 22,
            icon: Icon(
              value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            onPressed: value.isInitialized ? () => _togglePlay(controller) : null,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                min: 0,
                max: durationMs > 0 ? durationMs : 1.0,
                value: positionMs,
                onChanged: durationMs > 0
                    ? (v) => setState(() => _dragMs = v)
                    : null,
                onChangeEnd: (v) async {
                  setState(() => _dragMs = null);
                  await controller.seekTo(Duration(milliseconds: v.round()));
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: Text(
              '${formatClockDuration(Duration(milliseconds: positionMs.round()))} / ${formatClockDuration(value.duration)}',
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}
