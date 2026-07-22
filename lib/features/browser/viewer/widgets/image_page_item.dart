import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/encrypted_image_widget.dart';

class ImagePageItem extends StatefulWidget {
  final String fileName;
  final Uint8List? prefetchedBytes;
  final MountedContainer container;
  final BoxFit imageFit;
  final int rotationQuarterTurns;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback? onError;

  const ImagePageItem({
    super.key,
    required this.fileName,
    required this.prefetchedBytes,
    required this.container,
    required this.imageFit,
    required this.rotationQuarterTurns,
    required this.showUI,
    required this.onToggleUI,
    required this.onZoomChanged,
    this.onError,
  });

  @override
  State<ImagePageItem> createState() => _ImagePageItemState();
}

class _ImagePageItemState extends State<ImagePageItem> {
  late final TransformationController _transformationController;
  double _scale = 1.0;
  TapDownDetails? _doubleTapDetails;
  Size? _imageSize;

  BoxFit? _lastFit;
  int? _lastRotation;
  Size? _lastViewportSize;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _loadImageSize();
  }

  void _loadImageSize() {
    if (widget.prefetchedBytes != null && widget.prefetchedBytes!.isNotEmpty) {
      decodeImageFromList(widget.prefetchedBytes!).then((image) {
        if (mounted) {
          setState(() {
            _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ImagePageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefetchedBytes != widget.prefetchedBytes ||
        oldWidget.fileName != widget.fileName) {
      _imageSize = null;
      _lastViewportSize = null; 
      _loadImageSize();
    }
  }

  void _centerImageInitially(BoxConstraints constraints) {
    if (_imageSize == null) return;

    double ar = _imageSize!.width / _imageSize!.height;
    if (widget.rotationQuarterTurns % 2 != 0) {
      ar = 1 / ar;
    }

    double? childWidth;
    double? childHeight;

    if (widget.imageFit == BoxFit.fitWidth) {
      childWidth = constraints.maxWidth;
      childHeight = constraints.maxWidth / ar;
    } else if (widget.imageFit == BoxFit.fitHeight) {
      childHeight = constraints.maxHeight;
      childWidth = constraints.maxHeight * ar;
    }

    if (childWidth != null && childHeight != null) {
      final canvasWidth = max(constraints.maxWidth, childWidth);
      final canvasHeight = max(constraints.maxHeight, childHeight);

      double x = 0.0;
      double y = 0.0;

      if (canvasWidth > constraints.maxWidth) {
        x = -(canvasWidth - constraints.maxWidth) / 2;
      }
      if (canvasHeight > constraints.maxHeight) {
        y = -(canvasHeight - constraints.maxHeight) / 2;
      }

      _transformationController.value = Matrix4.translationValues(x, y, 0.0);
      _scale = 1.0;
    }
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
              ..translateByDouble(x, y, 0.0, 1.0)
              ..scaleByDouble(_scale, _scale, _scale, 1.0);
          } else {
            _transformationController.value = Matrix4.identity()
            ..scaleByDouble(_scale, _scale, _scale, 1.0);
          }
          widget.onZoomChanged(false);
        } else {
          _scale = 1.0;
          _transformationController.value = Matrix4.identity();
          widget.onZoomChanged(true);
        }
      },
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double? childWidth;
            double? childHeight;
            double? canvasWidth;
            double? canvasHeight;
            bool isConstrained = true;

            if (_imageSize != null) {
              double ar = _imageSize!.width / _imageSize!.height;
              if (widget.rotationQuarterTurns % 2 != 0) {
                ar = 1 / ar;
              }

              if (widget.imageFit == BoxFit.fitWidth) {
                childWidth = constraints.maxWidth;
                childHeight = constraints.maxWidth / ar;
                isConstrained = false;
              } else if (widget.imageFit == BoxFit.fitHeight) {
                childHeight = constraints.maxHeight;
                childWidth = constraints.maxHeight * ar;
                isConstrained = false;
              }

              if (childWidth != null && childHeight != null) {
                canvasWidth = max(constraints.maxWidth, childWidth);
                canvasHeight = max(constraints.maxHeight, childHeight);
              }

              final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
              if (_lastFit != widget.imageFit ||
                  _lastRotation != widget.rotationQuarterTurns ||
                  _lastViewportSize != viewportSize) {
                _lastFit = widget.imageFit;
                _lastRotation = widget.rotationQuarterTurns;
                _lastViewportSize = viewportSize;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _centerImageInitially(constraints);
                  }
                });
              }
            }

            return InteractiveViewer(
              transformationController: _transformationController,
              maxScale: MediaViewerConstants.maxImageZoom,
              minScale: 0.5,
              boundaryMargin: EdgeInsets.zero,
              constrained: isConstrained,
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
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Center(
                  child: SizedBox(
                    width: childWidth,
                    height: childHeight,
                    child: RotatedBox(
                      quarterTurns: widget.rotationQuarterTurns,
                      child: EncryptedImageWidget(
                        container: widget.container,
                        fileName: widget.fileName,
                        prefetchedBytes: widget.prefetchedBytes,
                        fit: widget.imageFit,
                        onError: widget.onError,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
