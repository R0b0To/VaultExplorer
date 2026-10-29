import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/zoom_indicator_pill.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_to_dismiss_layer.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// Full-screen, zoomable view of an image tapped in the markdown preview.
///
/// It behaves like the media player's image page:
///  * pinch to zoom (pinch-out below 1x follows the media viewer setting),
///    double-tap zooms 3.5x on the tapped point, double-tap again resets;
///  * a zoom-level pill appears while the zoom changes, tap it to reset;
///  * one finger pans only while zoomed in;
///  * at normal zoom, drag the image away in any direction (up, down, left or
///    right) to dismiss it: the image follows the finger, the backdrop and
///    controls fade, and the image flies back to the preview.
///
/// It is handed the already-loaded encoded bytes, so opening it never touches
/// the vault again.
class MarkdownImageViewer extends ConsumerStatefulWidget {
  const MarkdownImageViewer({
    super.key,
    required this.bytes,
    required this.alt,
    required this.heroTag,
    this.pixelSize,
  });

  final Uint8List bytes;
  final String alt;

  /// Shared with the inline image so it flies into place when opened.
  final Object heroTag;

  /// Intrinsic pixel size, when known. Sizes the image box and bounds the
  /// sharp decode.
  final ui.Size? pixelSize;

  static const int _maxPreviewDecodeWidth = 4096;

  /// Decode width used for the inline preview and for the base layer here.
  /// Shared so the viewer's first frame is served from Flutter's image cache
  /// (the very bitmap the preview already decoded) instead of flashing blank
  /// while the Hero flight runs.
  static int? previewDecodeWidth(BuildContext context) {
    final px =
        MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
    if (!px.isFinite || px <= 0) return null;
    return px.round().clamp(1, _maxPreviewDecodeWidth);
  }

  static Future<void> open(
    BuildContext context, {
    required Uint8List bytes,
    required String alt,
    required Object heroTag,
    ui.Size? pixelSize,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        // Not opaque: the black backdrop fades while the image is pulled
        // away, showing the preview underneath (same as the media viewer).
        opaque: false,
        transitionDuration: MediaViewerConstants.animationDuration,
        reverseTransitionDuration: MediaViewerConstants.animationDuration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            MarkdownImageViewer(
              bytes: bytes,
              alt: alt,
              heroTag: heroTag,
              pixelSize: pixelSize,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  ConsumerState<MarkdownImageViewer> createState() =>
      _MarkdownImageViewerState();
}

class _MarkdownImageViewerState extends ConsumerState<MarkdownImageViewer>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapZoom = 3.5;

  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomController = AnimationController(
    vsync: this,
    duration: MediaViewerConstants.animationDuration,
  )..addListener(_onZoomTick);

  /// 0..1 while the image is pulled away; fades the backdrop and controls.
  final ValueNotifier<double> _dismissProgress = ValueNotifier<double>(0.0);

  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTapDetails;
  Size _viewport = Size.zero;
  bool _clamping = false;

  // Mirrors the media viewer's pinch-zoom-out setting (defaults match it).
  bool _pinchZoomOutEnabled = true;
  double _minZoomScale = 0.25;

  static double _scaleOf(Matrix4 m) => math.sqrt(
    m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1],
  );

  bool get _isZoomed => (_scaleOf(_transform.value) - 1.0).abs() > 0.01;
  bool get _isZoomedIn => _scaleOf(_transform.value) > 1.01;

  double get _effectiveMinScale => _pinchZoomOutEnabled
      ? _minZoomScale.clamp(MediaViewerConstants.minVideoZoomFloor, 1.0)
      : 1.0;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _zoomController.dispose();
    _transform.dispose();
    _dismissProgress.dispose();
    super.dispose();
  }

  // -- Matrix helpers (the image box fills the viewport, as in the player) --

  Matrix4 _centeredAt(double s) {
    final vw = _viewport.width;
    final vh = _viewport.height;
    return Matrix4.identity()
      ..translateByDouble((vw - vw * s) / 2.0, (vh - vh * s) / 2.0, 0.0, 1.0)
      ..scaleByDouble(s, s, 1.0, 1.0);
  }

  /// [m] with its pan kept inside the image (or centered when it fits).
  Matrix4 _boundedPan(Matrix4 m, double s) {
    final vw = _viewport.width;
    final vh = _viewport.height;
    final scaledW = vw * s;
    final scaledH = vh * s;
    final tx = scaledW > vw
        ? m.storage[12].clamp(vw - scaledW, 0.0)
        : (vw - scaledW) / 2.0;
    final ty = scaledH > vh
        ? m.storage[13].clamp(vh - scaledH, 0.0)
        : (vh - scaledH) / 2.0;
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..scaleByDouble(s, s, 1.0, 1.0);
  }

  void _setMatrix(Matrix4 m) {
    _clamping = true;
    _transform.value = m;
    _clamping = false;
  }

  /// Keeps the matrix legal while the person pinches or pans.
  void _onTransformChanged() {
    if (_clamping || !mounted) return;
    if (_viewport.width <= 0 || _viewport.height <= 0) return;
    final matrix = _transform.value;
    final s = _scaleOf(matrix);
    if (s <= 0) return;

    if (s < _effectiveMinScale) {
      _setMatrix(_centeredAt(_effectiveMinScale));
      return;
    }
    if (s >= 1.0) {
      final bounded = _boundedPan(matrix, s);
      if ((bounded.storage[12] - matrix.storage[12]).abs() > 0.001 ||
          (bounded.storage[13] - matrix.storage[13]).abs() > 0.001) {
        _setMatrix(bounded);
      }
    }
  }

  void _onZoomTick() {
    final animation = _zoomAnimation;
    if (animation != null) _setMatrix(animation.value);
  }

  void _animateZoomTo(Matrix4 target) {
    _zoomController.stop();
    _zoomAnimation = _zoomController
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Matrix4Tween(begin: _transform.value, end: target));
    _zoomController.forward(from: 0.0).then((_) {
      // Pan is only enabled while zoomed in, so refresh once settled.
      if (mounted) setState(() {});
    });
  }

  /// Size of the picture itself at normal zoom (BoxFit.contain in the view).
  Size _imageBox(Size viewport) {
    final size = widget.pixelSize;
    if (size == null ||
        size.width <= 0 ||
        size.height <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return viewport;
    }
    final scale = math.min(
      viewport.width / size.width,
      viewport.height / size.height,
    );
    return Size(size.width * scale, size.height * scale);
  }

  void _onDoubleTap() {
    // Anywhere on a zoomed (or zoomed-out) image, double-tap goes back to 1x.
    if (_isZoomed) {
      _animateZoomTo(Matrix4.identity());
      return;
    }

    final position = _doubleTapDetails?.localPosition;
    final box = _imageBox(_viewport);
    if (position != null && _viewport.width > 0 && _viewport.height > 0) {
      final imageRect = Rect.fromLTWH(
        (_viewport.width - box.width) / 2,
        (_viewport.height - box.height) / 2,
        box.width,
        box.height,
      );
      // In the black margin at 1x: nothing to zoom into.
      if (!imageRect.contains(position)) return;
    }

    const t = _doubleTapZoom;
    final target = Matrix4.identity();
    if (position != null) {
      target.translateByDouble(
        -position.dx * (t - 1),
        -position.dy * (t - 1),
        0.0,
        1.0,
      );
    }
    target.scaleByDouble(t, t, 1.0, 1.0);
    _animateZoomTo(_boundedPan(target, _scaleOf(target)));
  }

  /// Asked whenever a finger lands. Dismiss only works at normal zoom: a
  /// zoomed image is panned instead, and a zoom animation must finish first.
  bool _canStartDismiss() =>
      mounted && !_isZoomed && !_zoomController.isAnimating;

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  Widget _fadeDuringDismiss(Widget child) {
    return ValueListenableBuilder<double>(
      valueListenable: _dismissProgress,
      child: child,
      builder: (context, progress, child) => IgnorePointer(
        ignoring: progress >= 0.99,
        child: Opacity(
          opacity: (1.0 - progress).clamp(0.0, 1.0).toDouble(),
          child: child,
        ),
      ),
    );
  }

  /// Width to decode the sharp layer at: a few screens wide, but never more
  /// than the app's decoded-bitmap budget or the image's own width.
  int? _detailDecodeWidth(double viewportPx) {
    if (!viewportPx.isFinite || viewportPx <= 0) return null;
    var width = viewportPx * MediaViewerConstants.fullResDecodeZoomHeadroom;
    final size = widget.pixelSize;
    if (size != null && size.width > 0 && size.height > 0) {
      final aspect = size.width / size.height;
      width = math.min(
        width,
        math.sqrt(MediaViewerConstants.maxImageDecodePixels * aspect),
      );
      width = math.min(width, size.width);
    } else {
      width = math.min(width, 4096);
    }
    return math.max(1, width.round());
  }

  @override
  Widget build(BuildContext context) {
    // Follow the media viewer's pinch-zoom-out setting.
    _pinchZoomOutEnabled = ref.watch(
      fileManagerToolbarSettingsProvider(null).select(
        (s) => s.config.mediaViewerToolbarConfig.pinchZoomOutEnabled,
      ),
    );
    _minZoomScale = ref.watch(
      fileManagerToolbarSettingsProvider(null).select(
        (s) => s.config.mediaViewerToolbarConfig.minVideoZoomScale,
      ),
    );

    final viewportPx =
        MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
    final baseWidth = MarkdownImageViewer.previewDecodeWidth(context);
    final detailWidth = _detailDecodeWidth(viewportPx);
    final showDetail =
        detailWidth != null && (baseWidth == null || detailWidth > baseWidth);

    // Two layers: the preview-resolution bitmap (already cached, so the first
    // frame and the Hero flight are instant) with a sharper decode appearing
    // on top for zooming. Both use BoxFit.contain so they line up exactly.
    final image = Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: baseWidth,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
          ),
        ),
        if (showDetail)
          Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth: detailWidth,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return const SizedBox.shrink();
            },
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
      ],
    );

    final alt = widget.alt.trim();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUI.transparentDark,
      // The black behind the viewer fades out while a swipe-to-dismiss drag
      // pulls the image away, showing the preview underneath.
      child: ValueListenableBuilder<double>(
        valueListenable: _dismissProgress,
        builder: (context, progress, scaffold) {
          final fades = ModalRoute.of(context)?.opaque == false;
          return ColoredBox(
            color: fades
                ? Colors.black.withValues(alpha: 1.0 - progress)
                : Colors.black,
            child: scaffold,
          );
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              _viewport = viewport;
              final box = _imageBox(viewport);

              final imageContent = Center(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: Hero(
                    tag: widget.heroTag,
                    createRectTween: (begin, end) =>
                        MaterialRectArcTween(begin: begin, end: end),
                    child: image,
                  ),
                ),
              );

              // Swipe-to-dismiss in any direction. The shared dismiss layer
              // handles one axis, so two are nested: the outer one listens
              // for up/down, the inner one for left/right. Each target must
              // sit under the layer it belongs to (a target binds to the
              // nearest layer above it), hence the vertical target wraps the
              // horizontal layer. Targets live inside the InteractiveViewer
              // so their recognizers beat its scale recognizer.
              final zoomable = GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: _onDoubleTap,
                child: SizedBox.expand(
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: _effectiveMinScale,
                    maxScale: MediaViewerConstants.maxImageZoom,
                    interactionEndFrictionCoefficient: 0.0005,
                    boundaryMargin: _pinchZoomOutEnabled
                        ? const EdgeInsets.all(double.infinity)
                        : EdgeInsets.zero,
                    // One finger moves the image only while zoomed in; at 1x
                    // it is free for the swipe-to-dismiss drag.
                    panEnabled: _isZoomedIn,
                    onInteractionStart: (details) {
                      if (details.pointerCount >= 2) _zoomController.stop();
                    },
                    onInteractionEnd: (details) {
                      final s = _scaleOf(_transform.value);
                      final clampedS = s.clamp(
                        _effectiveMinScale,
                        MediaViewerConstants.maxImageZoom,
                      );
                      if (clampedS < 1.0 &&
                          viewport.width > 0 &&
                          viewport.height > 0) {
                        _setMatrix(_centeredAt(clampedS));
                      }
                      setState(() {});
                    },
                    child: SizedBox(
                      width: viewport.width,
                      height: viewport.height,
                      child: MediaSwipeDismissTarget(
                        child: MediaSwipeDismissLayer(
                          enabled: true,
                          axis: Axis.horizontal,
                          bothDirections: true,
                          canStart: _canStartDismiss,
                          onDismiss: _close,
                          progress: _dismissProgress,
                          transformChild: false,
                          child: MediaSwipeDismissTarget(child: imageContent),
                        ),
                      ),
                    ),
                  ),
                ),
              );

              return MediaSwipeDismissLayer(
                enabled: true,
                axis: Axis.vertical,
                bothDirections: true,
                canStart: _canStartDismiss,
                onDismiss: _close,
                progress: _dismissProgress,
                transformChild: false,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    zoomable,
                    if (alt.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _fadeDuringDismiss(
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                              child: SafeArea(
                                top: false,
                                child: Padding(
                                  // Right padding keeps it clear of the zoom
                                  // pill.
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    32,
                                    100,
                                    12,
                                  ),
                                  child: Text(
                                    alt,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: _fadeDuringDismiss(
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: IconButton(
                              tooltip: context.l10n.close,
                              icon: const Icon(Icons.close_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Last, so nothing can cover it.
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _fadeDuringDismiss(
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                            child: AutoHideZoomIndicator(
                              transform: _transform,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              onReset: () =>
                                  _animateZoomTo(Matrix4.identity()),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
