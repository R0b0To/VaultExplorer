import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_playback_paths.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/encrypted_image_widget.dart';
import 'package:vaultexplorer/features/browser/widgets/preview_pane_handoff.dart';

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
///
/// The pop-out button hands the live player to [BackgroundPlaybackHost] as a floating-player session
/// (the app's in-app mini video player), so the video keeps playing, from where it is, after the
/// selection moves on. The pane then goes back to its poster.
class PreviewPaneVideo extends StatefulWidget {
  final MountedContainer container;
  final String filePath;
  final Widget poster;

  /// The folder the file was selected in, and the thumbnail settings: carried into the floating
  /// player's session so that expanding it into the full viewer behaves as if it had been opened here.
  final String? startingFolder;
  final ThumbnailQuality quality;
  final ThumbnailCacheMode cacheMode;

  const PreviewPaneVideo({
    super.key,
    required this.container,
    required this.filePath,
    required this.poster,
    required this.quality,
    required this.cacheMode,
    this.startingFolder,
  });

  @override
  State<PreviewPaneVideo> createState() => _PreviewPaneVideoState();
}

class _PreviewPaneVideoState extends State<PreviewPaneVideo> {
  VideoPlaybackManager? _manager;
  NativeVideoController? _controller;
  bool _starting = false;
  double? _dragMs;

  /// True once the player belongs to [BackgroundPlaybackHost]: this pane must
  /// then neither dispose nor drive it any more.
  bool _handedOff = false;

  /// The player's creation, which is asynchronous: a manager must not be
  /// disposed under it.
  Future<void>? _activation;

  @override
  void dispose() {
    if (!_handedOff) {
      _controller?.removeListener(_onTick);
      final manager = _manager;
      if (manager != null) {
        final pending = _activation;
        if (pending != null && _controller == null) {
          unawaited(
            pending.then<void>((_) {}, onError: (_) {}).whenComplete(
              manager.dispose,
            ),
          );
        } else {
          manager.dispose();
        }
      }
    }
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_starting || _manager != null) return;
    setState(() => _starting = true);
    // The app has a single native player; background playback lets go of it first.
    if (BackgroundPlaybackHost.instance.needsRelease) {
      await BackgroundPlaybackHost.instance.closeAndWait();
      if (!mounted) return;
    }
    // Played through a manager, like the viewer does, so the running player can be
    // handed over as it is (see _popOut).
    final manager = VideoPlaybackManager();
    _handedOff = false;
    _manager = manager;
    final activation = manager.activate(
      fileName: widget.filePath,
      volId: widget.container.volId,
      filePath: nativePlaybackPathFor(widget.container, widget.filePath),
      isLocalStorage: widget.container.isLocalStorage,
      autoPlay: true,
      playbackSpeed: 1,
    );
    _activation = activation;
    try {
      await activation;
    } catch (_) {
      if (mounted) {
        setState(() {
          _manager = null;
          _starting = false;
        });
        manager.dispose();
      }
      return;
    }
    // Disposed while the player was being created: dispose() took care of it.
    if (!mounted) return;
    final controller = manager.activeController;
    if (controller == null || controller.isDisposed) {
      setState(() => _starting = false);
      return;
    }
    controller.addListener(_onTick);
    setState(() {
      _controller = controller;
      _starting = false;
    });
  }

  /// The pop-out button: the playing video moves to the in-app floating player
  /// and carries on there, so it survives the selection changing.
  void _popOut() {
    final manager = _manager;
    final controller = _controller;
    if (_handedOff || manager == null || controller == null) return;
    final handedOff = handOffPreviewPlayback(
      context: context,
      container: widget.container,
      filePath: widget.filePath,
      manager: manager,
      controller: controller,
      quality: widget.quality,
      cacheMode: widget.cacheMode,
      startingFolder: widget.startingFolder,
      floating: true,
    );
    if (!handedOff) return;
    controller.removeListener(_onTick);
    setState(() {
      _handedOff = true;
      _manager = null;
      _controller = null;
    });
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
          if (value.isInitialized)
            Positioned(top: 4, right: 4, child: _buildPopOutButton(context)),
        ],
      ),
    );
  }

  Widget _buildPopOutButton(BuildContext context) => Material(
    color: Colors.black54,
    shape: const CircleBorder(),
    child: IconButton(
      visualDensity: VisualDensity.compact,
      color: Colors.white,
      iconSize: 18,
      tooltip: context.l10n.floatingPlayerTitle,
      icon: const Icon(Icons.picture_in_picture_alt_rounded),
      onPressed: _popOut,
    ),
  );

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
