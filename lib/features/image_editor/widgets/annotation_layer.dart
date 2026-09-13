import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

enum EditorTool { none, crop, draw, text, redact }

const List<Color> editorColorPalette = [
  Color(0xFFEF4444), // Red
  Color(0xFFF97316), // Orange
  Color(0xFFFBBF24), // Yellow
  Color(0xFF22C55E), // Green
  Color(0xFF06B6D4), // Cyan
  Color(0xFF3B82F6), // Blue
  Color(0xFFA855F7), // Purple
  Color(0xFFEC4899), // Pink
  Color(0xFFFFFFFF), // White
  Color(0xFF000000), // Black
];

const List<double> editorStrokeWidthFractions = [
  0.005,
  0.010,
  0.020,
  0.035,
];

class AnnotationLayer extends StatefulWidget {
  final Size imageSize;
  final List<EditAnnotation> annotations;
  final EditorTool activeTool;
  final Color color;
  final double strokeWidthFraction;
  final ValueChanged<EditAnnotation> onAnnotationAdded;
  final void Function(int index, EditAnnotation annotation)? onAnnotationUpdated;
  final void Function(int index)? onAnnotationRemoved;
  final ValueChanged<Offset> onTextTapped;

  const AnnotationLayer({
    super.key,
    required this.imageSize,
    required this.annotations,
    required this.activeTool,
    required this.color,
    required this.strokeWidthFraction,
    required this.onAnnotationAdded,
    this.onAnnotationUpdated,
    this.onAnnotationRemoved,
    required this.onTextTapped,
  });

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  int? _selectedAnnotationIndex;
  bool _isDraggingAnnotation = false;
  Offset? _lastLocalPoint;

  // Freehand drawing state
  final List<Offset> _currentDrawingPoints = [];

  // Redaction box state
  Offset? _redactStartNormalized;
  Offset? _redactCurrentNormalized;

  Offset _toNormalized(Offset local) => Offset(
        (local.dx / widget.imageSize.width).clamp(0.0, 1.0),
        (local.dy / widget.imageSize.height).clamp(0.0, 1.0),
      );

  int? _hitTest(Offset normalized) {
    for (int i = widget.annotations.length - 1; i >= 0; i--) {
      if (widget.annotations[i].contains(normalized, widget.imageSize)) {
        return i;
      }
    }
    return null;
  }

  void _onPanDown(DragDownDetails details) {
    final norm = _toNormalized(details.localPosition);
    final hit = _hitTest(norm);

    // 1. IN REDACT TOOL: Touching an existing redact box grabs and moves it
    if (widget.activeTool == EditorTool.redact && hit != null && widget.annotations[hit] is RedactAnnotation) {
      setState(() {
        _selectedAnnotationIndex = hit;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localPosition;
      });
      return;
    }

    // 2. IN TEXT TOOL: Touching existing text grabs and moves it
    if (widget.activeTool == EditorTool.text && hit != null && widget.annotations[hit] is TextMarkAnnotation) {
      setState(() {
        _selectedAnnotationIndex = hit;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localPosition;
      });
      return;
    }

    // 3. IN NONE TOOL: Touching any annotation grabs and moves it
    if (widget.activeTool == EditorTool.none && hit != null) {
      setState(() {
        _selectedAnnotationIndex = hit;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localPosition;
      });
      return;
    }

    // Deselect when touching elsewhere
    if (_selectedAnnotationIndex != null) {
      setState(() => _selectedAnnotationIndex = null);
    }

    // 4. DRAW TOOL: Always draws freely, even over redact boxes
    if (widget.activeTool == EditorTool.draw) {
      setState(() {
        _currentDrawingPoints
          ..clear()
          ..add(norm);
      });
      return;
    }

    // 5. REDACT TOOL: Dragging on empty space creates a new redact box
    if (widget.activeTool == EditorTool.redact) {
      setState(() {
        _redactStartNormalized = norm;
        _redactCurrentNormalized = norm;
      });
      return;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.activeTool == EditorTool.draw) {
      setState(() {
        _currentDrawingPoints.add(_toNormalized(details.localPosition));
      });
      return;
    }

    if (widget.activeTool == EditorTool.redact && _redactStartNormalized != null) {
      setState(() {
        _redactCurrentNormalized = _toNormalized(details.localPosition);
      });
      return;
    }

    if (_isDraggingAnnotation &&
        _selectedAnnotationIndex != null &&
        _lastLocalPoint != null) {
      final delta = Offset(
        (details.localPosition.dx - _lastLocalPoint!.dx) / widget.imageSize.width,
        (details.localPosition.dy - _lastLocalPoint!.dy) / widget.imageSize.height,
      );
      _lastLocalPoint = details.localPosition;

      final current = widget.annotations[_selectedAnnotationIndex!];
      final updated = current.translate(delta, widget.imageSize);
      widget.onAnnotationUpdated?.call(_selectedAnnotationIndex!, updated);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.activeTool == EditorTool.draw && _currentDrawingPoints.isNotEmpty) {
      widget.onAnnotationAdded(
        DrawingAnnotation(
          points: List<Offset>.from(_currentDrawingPoints),
          color: widget.color,
          strokeWidthFraction: widget.strokeWidthFraction,
        ),
      );
      setState(() => _currentDrawingPoints.clear());
      return;
    }

    if (widget.activeTool == EditorTool.redact &&
        _redactStartNormalized != null &&
        _redactCurrentNormalized != null) {
      final rect = Rect.fromPoints(_redactStartNormalized!, _redactCurrentNormalized!);
      if (rect.width > 0.01 && rect.height > 0.01) {
        widget.onAnnotationAdded(
          RedactAnnotation(rect: rect, color: widget.color),
        );
      }
      setState(() {
        _redactStartNormalized = null;
        _redactCurrentNormalized = null;
      });
      return;
    }

    if (_isDraggingAnnotation) {
      setState(() {
        _isDraggingAnnotation = false;
        _lastLocalPoint = null;
      });
    }
  }

  // ── HOLD TO MOVE (Long Press grabs any shape in any tool) ─────────────────

  void _onLongPressStart(LongPressStartDetails details) {
    final norm = _toNormalized(details.localPosition);
    final hit = _hitTest(norm);
    if (hit != null) {
      setState(() {
        _selectedAnnotationIndex = hit;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localPosition;
        _currentDrawingPoints.clear();
        _redactStartNormalized = null;
        _redactCurrentNormalized = null;
      });
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_isDraggingAnnotation &&
        _selectedAnnotationIndex != null &&
        _lastLocalPoint != null) {
      final delta = Offset(
        (details.localPosition.dx - _lastLocalPoint!.dx) / widget.imageSize.width,
        (details.localPosition.dy - _lastLocalPoint!.dy) / widget.imageSize.height,
      );
      _lastLocalPoint = details.localPosition;

      final current = widget.annotations[_selectedAnnotationIndex!];
      final updated = current.translate(delta, widget.imageSize);
      widget.onAnnotationUpdated?.call(_selectedAnnotationIndex!, updated);
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_isDraggingAnnotation) {
      setState(() {
        _isDraggingAnnotation = false;
        _lastLocalPoint = null;
      });
    }
  }

  void _onTapUp(TapUpDetails details) {
    final norm = _toNormalized(details.localPosition);

    // Single-tap in draw mode adds a dot
    if (widget.activeTool == EditorTool.draw) {
      widget.onAnnotationAdded(
        DrawingAnnotation(
          points: [norm],
          color: widget.color,
          strokeWidthFraction: widget.strokeWidthFraction,
        ),
      );
      return;
    }

    if (widget.activeTool == EditorTool.text) {
      final hit = _hitTest(norm);
      if (hit != null && widget.annotations[hit] is TextMarkAnnotation) {
        setState(() => _selectedAnnotationIndex = hit);
      } else {
        widget.onTextTapped(norm);
      }
      return;
    }

    final hit = _hitTest(norm);
    setState(() => _selectedAnnotationIndex = hit);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: _onPanDown,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onTapUp: _onTapUp,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: CustomPaint(
        size: widget.imageSize,
        painter: _AnnotationPainter(
          annotations: widget.annotations,
          selectedIndex: _selectedAnnotationIndex,
          liveDrawing: _currentDrawingPoints,
          liveRedact: (_redactStartNormalized != null && _redactCurrentNormalized != null)
              ? Rect.fromPoints(_redactStartNormalized!, _redactCurrentNormalized!)
              : null,
          liveColor: widget.color,
          strokeWidthFraction: widget.strokeWidthFraction,
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<EditAnnotation> annotations;
  final int? selectedIndex;
  final List<Offset> liveDrawing;
  final Rect? liveRedact;
  final Color liveColor;
  final double strokeWidthFraction;

  _AnnotationPainter({
    required this.annotations,
    this.selectedIndex,
    required this.liveDrawing,
    this.liveRedact,
    required this.liveColor,
    required this.strokeWidthFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < annotations.length; i++) {
      annotations[i].paint(canvas, size);

      // Clean selection frame (no misleading corner resize dots)
      if (selectedIndex == i) {
        final bounds = annotations[i].getBounds(size);
        if (bounds != null) {
          final borderPaint = Paint()
            ..color = const Color(0xFF3B82F6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;

          final fillPaint = Paint()
            ..color = const Color(0xFF3B82F6).withValues(alpha: 0.12)
            ..style = PaintingStyle.fill;

          final rrect = RRect.fromRectAndRadius(
            bounds.inflate(6.0),
            const Radius.circular(6.0),
          );
          canvas.drawRRect(rrect, fillPaint);
          canvas.drawRRect(rrect, borderPaint);
        }
      }
    }

    if (liveDrawing.isNotEmpty) {
      final strokeWidth = size.height * strokeWidthFraction;
      final paint = Paint()
        ..color = liveColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (liveDrawing.length == 1) {
        final p = Offset(liveDrawing.first.dx * size.width, liveDrawing.first.dy * size.height);
        canvas.drawCircle(p, strokeWidth / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path();
        final first = Offset(liveDrawing.first.dx * size.width, liveDrawing.first.dy * size.height);
        path.moveTo(first.dx, first.dy);

        for (int i = 1; i < liveDrawing.length; i++) {
          final pt = Offset(liveDrawing[i].dx * size.width, liveDrawing[i].dy * size.height);
          path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    if (liveRedact != null) {
      final pixelRect = Rect.fromLTRB(
        liveRedact!.left * size.width,
        liveRedact!.top * size.height,
        liveRedact!.right * size.width,
        liveRedact!.bottom * size.height,
      );
      canvas.drawRect(pixelRect, Paint()..color = liveColor);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}