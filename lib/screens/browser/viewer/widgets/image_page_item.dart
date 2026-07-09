import 'dart:typed_data';
import 'package:flutter/material.dart';
import '/../../models/mounted_container.dart';
import '../media_viewer_constants.dart';
import 'encrypted_image_widget.dart';

class ImagePageItem extends StatefulWidget {
  final String fileName;
  final Uint8List? prefetchedBytes;
  final MountedContainer container;
  final BoxFit imageFit;
  final int rotationQuarterTurns;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final ValueChanged<bool> onZoomChanged;

  const ImagePageItem({
    Key? key,
    required this.fileName,
    required this.prefetchedBytes,
    required this.container,
    required this.imageFit,
    required this.rotationQuarterTurns,
    required this.showUI,
    required this.onToggleUI,
    required this.onZoomChanged,
  }) : super(key: key);

  @override
  State<ImagePageItem> createState() => _ImagePageItemState();
}

class _ImagePageItemState extends State<ImagePageItem> {
  late final TransformationController _transformationController;
  double _scale = 1.0;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.onToggleUI(!widget.showUI),
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: () {
        final position = _doubleTapDetails?.localPosition;
        if (_scale == 1.0) {
          _scale = 2.5;
          if (position != null) {
            final x = -position.dx * (_scale - 1);
            final y = -position.dy * (_scale - 1);
            _transformationController.value = Matrix4.identity()
              ..translate(x, y)
              ..scale(_scale);
          } else {
            _transformationController.value = Matrix4.identity()..scale(_scale);
          }
          widget.onZoomChanged(false);
        } else {
          _scale = 1.0;
          _transformationController.value = Matrix4.identity();
          widget.onZoomChanged(true);
        }
      },
      child: SizedBox.expand(
        child: InteractiveViewer(
          transformationController: _transformationController,
          maxScale: MediaViewerConstants.maxImageZoom,
          minScale: 0.5,
          boundaryMargin: EdgeInsets.zero,
          onInteractionUpdate: (details) {
            final s = _transformationController.value.getMaxScaleOnAxis();
            if (s != _scale) {
              _scale = s;
              widget.onZoomChanged(s <= 1.01);
            }
          },
          onInteractionEnd: (details) {
            final s = _transformationController.value.getMaxScaleOnAxis();
            if (s <= 1.01) {
              widget.onZoomChanged(true);
            }
          },
          child: Center(
            child: RotatedBox(
              quarterTurns: widget.rotationQuarterTurns,
              child: EncryptedImageWidget(
                container: widget.container,
                fileName: widget.fileName,
                prefetchedBytes: widget.prefetchedBytes,
                fit: widget.imageFit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}