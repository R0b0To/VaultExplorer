import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
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
  final void Function(int width, int height)? onSizeKnown;
  final VoidCallback? onError;
  final bool enableZoom;

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
    this.onSizeKnown,
    this.onError,
    this.enableZoom = true,
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
    _initImageDimensions();
  }

  static (int, int)? extractDimensionsFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return null;
    // JPEG SOF parser (scans markers synchronously in <0.01ms)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int i = 2;
      while (i < bytes.length - 8) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
          final h = (bytes[i + 5] << 8) | bytes[i + 6];
          final w = (bytes[i + 7] << 8) | bytes[i + 8];
          if (w > 0 && h > 0) return (w, h);
          break;
        }
        final len = (bytes[i + 2] << 8) | bytes[i + 3];
        if (len < 2) break;
        i += 2 + len;
      }
    }
    // PNG header parser
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      if (w > 0 && h > 0) return (w, h);
    }
    // GIF header parser
    if (bytes.length >= 10 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      final w = bytes[6] | (bytes[7] << 8);
      final h = bytes[8] | (bytes[9] << 8);
      if (w > 0 && h > 0) return (w, h);
    }
     // WebP (RIFF....WEBP)
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      // VP8 (lossy)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20) {
        final w = ((bytes[27] & 0x3F) << 8) | bytes[26];
        final h = ((bytes[29] & 0x3F) << 8) | bytes[28];
        if (w > 0 && h > 0) return (w, h);
      }
      // VP8L (lossless)
      if (bytes.length >= 25 &&
          bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x4C) {
        if (bytes[16] == 0x2F) {
          final w = 1 + (((bytes[18] & 0x3F) << 8) | bytes[17]);
          final h = 1 + (((bytes[20] & 0x0F) << 10) | (bytes[19] << 2) | ((bytes[18] & 0xC0) >> 6));
          if (w > 0 && h > 0) return (w, h);
        }
      }
      // VP8X (extended)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x58) {
        final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        if (w > 0 && h > 0) return (w, h);
      }
    }
    return null;
  }

  void _initImageDimensions() {
    if (widget.prefetchedBytes != null && widget.prefetchedBytes!.isNotEmpty) {
      final dims = extractDimensionsFromBytes(widget.prefetchedBytes!);
      if (dims != null && dims.$1 > 0 && dims.$2 > 0) {
        _imageSize = Size(dims.$1.toDouble(), dims.$2.toDouble());
        MediaAspectRatioCache.put(
          widget.container,
          widget.fileName,
          dims.$1,
          dims.$2,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onSizeKnown?.call(dims.$1, dims.$2);
          }
        });
      }
    }
  }

   

  @override
  void didUpdateWidget(covariant ImagePageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefetchedBytes != widget.prefetchedBytes ||
        oldWidget.fileName != widget.fileName) {
      _imageSize = null;
      _lastViewportSize = null;
      _initImageDimensions();
    }
  }

  void _centerImageInitially(BoxConstraints constraints) {
    double? ar;
    if (_imageSize != null && _imageSize!.height > 0) {
      ar = _imageSize!.width / _imageSize!.height;
    } else {
      ar = MediaAspectRatioCache.get(widget.container, widget.fileName);
    }
    if (ar == null || ar <= 0) return;

    if (widget.rotationQuarterTurns % 2 != 0) {
      ar = 1 / ar;
    }

    if (widget.imageFit == BoxFit.contain) {
      _transformationController.value = Matrix4.identity();
      _scale = 1.0;
      widget.onZoomChanged(true);
      return;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;

        double? rawAr;
        if (_imageSize != null && _imageSize!.height > 0) {
          rawAr = _imageSize!.width / _imageSize!.height;
        } else {
          rawAr = MediaAspectRatioCache.get(widget.container, widget.fileName);
        }

        double? childWidth;
        double? childHeight;
        double? canvasWidth;
        double? canvasHeight;
        bool isConstrained = true;

        if (rawAr != null && rawAr > 0 && viewportWidth > 0 && viewportHeight > 0) {
          final isRotated = widget.rotationQuarterTurns % 2 != 0;
          final ar = isRotated ? (1.0 / rawAr) : rawAr;

          if (widget.imageFit == BoxFit.fitWidth) {
            childWidth = viewportWidth;
            childHeight = viewportWidth / ar;
            isConstrained = false;
          } else if (widget.imageFit == BoxFit.fitHeight) {
            childHeight = viewportHeight;
            childWidth = viewportHeight * ar;
            isConstrained = false;
          } else {
            // BoxFit.contain: calculate exact image boundaries so Hero only wraps the actual image
            if ((viewportWidth / viewportHeight) > ar) {
              childHeight = viewportHeight;
              childWidth = viewportHeight * ar;
            } else {
              childWidth = viewportWidth;
              childHeight = viewportWidth / ar;
            }
          }

          canvasWidth = max(viewportWidth, childWidth);
          canvasHeight = max(viewportHeight, childHeight);

          final viewportSize = Size(viewportWidth, viewportHeight);
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

        Widget imageContent = Center(
          child: SizedBox(
            width: childWidth,
            height: childHeight,
            child: Hero(
              tag: 'media_hero_${widget.container.volId}_${widget.fileName}',
              createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
              child: Material(
                type: MaterialType.transparency,
                child: RotatedBox(
                  quarterTurns: widget.rotationQuarterTurns,
                  child: EncryptedImageWidget(
                    container: widget.container,
                    fileName: widget.fileName,
                    prefetchedBytes: widget.prefetchedBytes,
                    fit: BoxFit.contain,
                    onError: widget.onError,
                  ),
                ),
              ),
            ),
          ),
        );

        if (!widget.enableZoom) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => widget.onToggleUI(!widget.showUI),
            child: SizedBox.expand(
              child: imageContent,
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => widget.onToggleUI(!widget.showUI),
          onDoubleTapDown: (d) => _doubleTapDetails = d,
          onDoubleTap: () {
            final position = _doubleTapDetails?.localPosition;
            if (_scale <= 1.01) {
              _scale = 3.5;
              if (position != null) {
                final x = -position.dx * (_scale - 1);
                final y = -position.dy * (_scale - 1);
                _transformationController.value = Matrix4.identity()
                  ..translate(x, y, 0.0)
                  ..scale(_scale, _scale, 1.0);
              } else {
                _transformationController.value = Matrix4.identity()
                  ..scale(_scale, _scale, 1.0);
              }
              widget.onZoomChanged(false);
            } else {
              _scale = 1.0;
              _centerImageInitially(constraints);
              widget.onZoomChanged(true);
            }
          },
          child: SizedBox.expand(
            child: InteractiveViewer(
              transformationController: _transformationController,
              maxScale: MediaViewerConstants.maxImageZoom,
              minScale: 1.0,
              boundaryMargin: EdgeInsets.zero,
              constrained: isConstrained,
              onInteractionStart: (details) {
                if (details.pointerCount >= 2) {
                  widget.onZoomChanged(false);
                }
              },
              onInteractionUpdate: (details) {
                final s = _transformationController.value.getMaxScaleOnAxis();
                if (s != _scale) {
                  _scale = s;
                }
              },
              onInteractionEnd: (details) {
                final s = _transformationController.value.getMaxScaleOnAxis();
                final settled = s <= 1.01;
                if (settled) {
                  _scale = 1.0;
                }
                widget.onZoomChanged(settled);
              },
             child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: imageContent,
              ),
            ),
          ),
        );
      },
    );
  }
}