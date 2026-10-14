import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';


class ArchiveFileViewer extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;

  const ArchiveFileViewer({super.key, required this.bytes, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final isImage = MediaViewerConstants.isImage(fileName);
    final isText = const {'txt', 'md', 'csv', 'json', 'xml'}.contains(ext);

    return Scaffold(
      // Pictures sit on black, like in the media viewer.
      backgroundColor: isImage ? Colors.black : null,
      appBar: AppBar(
        title: Text(fileName),
        elevation: 0,
        backgroundColor: isImage ? Colors.black : null,
        foregroundColor: isImage ? Colors.white : null,
      ),
      // The picture fills the body so its zoom can use the whole screen; the
      // other previews are small and stay centred.
      body: isImage
          ? _ZoomableArchiveImage(bytes: bytes)
          : Center(child: _buildContent(context, isText)),
    );
  }

  Widget _buildContent(BuildContext context, bool isText) {
    if (isText) {
      String? text;
      Object? error;
      try {
        text = utf8.decode(bytes);
      } catch (e) {
        error = e;
      }

      if (error != null) {
        return Text(context.l10n.archiveErrorReadingFile('$error'));
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: SelectableText(
            text ?? '',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.insert_drive_file_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          context.l10n.archivePreviewNotAvailableMessage,
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }
}

/// A picture that pinch- and double-tap-zooms across the whole screen, the way
/// the media viewer's pictures do.
///
/// A bare [InteractiveViewer] around an [Image] inside a [Center] sizes itself
/// to the picture and clips the zoom to that rectangle, so the picture grows
/// inside a fixed box instead of getting bigger on screen. Here the viewer is
/// the size of the screen and the picture is contained inside it.
class _ZoomableArchiveImage extends StatefulWidget {
  const _ZoomableArchiveImage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ZoomableArchiveImage> createState() => _ZoomableArchiveImageState();
}

class _ZoomableArchiveImageState extends State<_ZoomableArchiveImage>
    with SingleTickerProviderStateMixin {
  /// Same target scale the media viewer's double-tap zooms to.
  static const double _doubleTapScale = 3.5;

  final TransformationController _controller = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: MediaViewerConstants.animationDuration,
    )..addListener(() {
        final animation = _animation;
        if (animation != null) _controller.value = animation.value;
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animationController.forward(from: 0.0);
  }

  void _onDoubleTap(Size viewport) {
    // Zoomed in: a double tap puts the picture back, wherever you tap.
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _animateTo(Matrix4.identity());
      return;
    }
    const scale = _doubleTapScale;
    final position = _doubleTapPosition ?? viewport.center(Offset.zero);
    // Keep the point that was tapped under the finger, without scrolling past
    // the picture's edges.
    final tx = (-position.dx * (scale - 1)).clamp(
      viewport.width * (1 - scale),
      0.0,
    );
    final ty = (-position.dy * (scale - 1)).clamp(
      viewport.height * (1 - scale),
      0.0,
    );
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(tx, ty, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: () => _onDoubleTap(viewport),
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 1.0,
            maxScale: MediaViewerConstants.maxImageZoom,
            onInteractionStart: (_) => _animationController.stop(),
            child: SizedBox.expand(
              child: Image.memory(
                widget.bytes,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    context.l10n.invalidOrCorruptedImageMessage,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
