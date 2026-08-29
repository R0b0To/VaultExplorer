import 'package:material_ui/material_ui.dart';

import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

/// Which markup tool is currently active in the image editor. Crop is
/// handled by a separate overlay ([CropOverlay]) since it needs its own
/// apply/cancel step rather than drawing directly.
enum EditorTool { none, crop, draw, text, redact }

/// Renders every already-committed [annotations] and captures new ones
/// for whichever [activeTool] is selected.
///
/// Like [CropOverlay], this widget is sized to exactly match the
/// displayed image; gesture coordinates are local pixels within that box,
/// converted to the model's normalized [0,1] coordinates on commit (see
/// [EditAnnotation]).
class AnnotationLayer extends StatefulWidget {
  final Size imageSize;
  final List<EditAnnotation> annotations;
  final EditorTool activeTool;
  final Color color;
  final double strokeWidthFraction;

  /// Called with a freshly-completed stroke/redaction box.
  final ValueChanged<EditAnnotation> onAnnotationAdded;

  /// Called with a normalized [0,1] tap position while the text tool is
  /// active; the screen owns the actual text-entry dialog and, if
  /// confirmed, adds the resulting [TextMarkAnnotation] itself.
  final ValueChanged<Offset> onTextTapped;

  const AnnotationLayer({
    super.key,
    required this.imageSize,
    required this.annotations,
    required this.activeTool,
    required this.color,
    required this.strokeWidthFraction,
    required this.onAnnotationAdded,
    required this.onTextTapped,
  });

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  final List<Offset> _liveStrokePoints = [];
  Rect? _liveRedactRect;
  Offset? _redactDragStart;

  Offset _normalize(Offset local) => Offset(
        (local.dx / widget.imageSize.width).clamp(0.0, 1.0).toDouble(),
        (local.dy / widget.imageSize.height).clamp(0.0, 1.0).toDouble(),
      );

  Offset _clampLocal(Offset local) => Offset(
        local.dx.clamp(0.0, widget.imageSize.width).toDouble(),
        local.dy.clamp(0.0, widget.imageSize.height).toDouble(),
      );

  void _handlePanStart(DragStartDetails details) {
    final local = _clampLocal(details.localPosition);
    switch (widget.activeTool) {
      case EditorTool.draw:
        setState(() => _liveStrokePoints
          ..clear()
          ..add(local));
        break;
      case EditorTool.redact:
        setState(() {
          _redactDragStart = local;
          _liveRedactRect = Rect.fromPoints(local, local);
        });
        break;
      case EditorTool.none:
      case EditorTool.crop:
      case EditorTool.text:
        break;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final local = _clampLocal(details.localPosition);
    switch (widget.activeTool) {
      case EditorTool.draw:
        if (_liveStrokePoints.isEmpty) return;
        setState(() => _liveStrokePoints.add(local));
        break;
      case EditorTool.redact:
        if (_redactDragStart == null) return;
        setState(() => _liveRedactRect = Rect.fromPoints(_redactDragStart!, local));
        break;
      case EditorTool.none:
      case EditorTool.crop:
      case EditorTool.text:
        break;
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    switch (widget.activeTool) {
      case EditorTool.draw:
        if (_liveStrokePoints.isNotEmpty) {
          widget.onAnnotationAdded(
            FreehandStrokeAnnotation(
              points: _liveStrokePoints.map(_normalize).toList(growable: false),
              color: widget.color,
              strokeWidthFraction: widget.strokeWidthFraction,
            ),
          );
        }
        setState(() => _liveStrokePoints.clear());
        break;
      case EditorTool.redact:
        final rect = _liveRedactRect;
        if (rect != null && rect.width > 8 && rect.height > 8) {
          widget.onAnnotationAdded(
            RedactAnnotation(
              rect: Rect.fromLTRB(
                _normalize(rect.topLeft).dx,
                _normalize(rect.topLeft).dy,
                _normalize(rect.bottomRight).dx,
                _normalize(rect.bottomRight).dy,
              ),
              color: widget.color,
            ),
          );
        }
        setState(() {
          _liveRedactRect = null;
          _redactDragStart = null;
        });
        break;
      case EditorTool.none:
      case EditorTool.crop:
      case EditorTool.text:
        break;
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.activeTool != EditorTool.text) return;
    widget.onTextTapped(_normalize(_clampLocal(details.localPosition)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      onTapUp: _handleTapUp,
      child: CustomPaint(
        size: widget.imageSize,
        painter: _AnnotationPainter(
          annotations: widget.annotations,
          liveStroke: widget.activeTool == EditorTool.draw && _liveStrokePoints.length > 1
              ? FreehandStrokeAnnotation(
                  points: _liveStrokePoints.map(_normalize).toList(growable: false),
                  color: widget.color,
                  strokeWidthFraction: widget.strokeWidthFraction,
                )
              : null,
          liveRedactRect: _liveRedactRect,
          liveRedactColor: widget.color,
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<EditAnnotation> annotations;
  final EditAnnotation? liveStroke;
  final Rect? liveRedactRect;
  final Color liveRedactColor;

  _AnnotationPainter({
    required this.annotations,
    required this.liveStroke,
    required this.liveRedactRect,
    required this.liveRedactColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      annotation.paint(canvas, size);
    }
    liveStroke?.paint(canvas, size);
    final liveRect = liveRedactRect;
    if (liveRect != null) {
      canvas.drawRect(liveRect, Paint()..color = liveRedactColor.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations ||
      oldDelegate.liveStroke != liveStroke ||
      oldDelegate.liveRedactRect != liveRedactRect;
}
