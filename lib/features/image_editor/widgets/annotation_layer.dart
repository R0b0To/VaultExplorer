import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

enum EditorTool { none, crop, draw, text, redact }

enum _Edge { left, top, right, bottom }

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

const List<double> editorStrokeWidthFractions = [0.005, 0.010, 0.020, 0.035];

class AnnotationLayer extends StatefulWidget {
  final Size imageSize;
  final List<EditAnnotation> annotations;
  final EditorTool activeTool;
  final Color color;
  final double strokeWidthFraction;
  final ValueChanged<EditAnnotation> onAnnotationAdded;
  final void Function(int index, EditAnnotation annotation)?
  onAnnotationUpdated;
  final void Function(int index)? onAnnotationRemoved;

  /// Called once, right before the first change of a move/resize gesture, so
  /// the host can take a single undo snapshot per gesture (instead of one per
  /// frame of [onAnnotationUpdated]).
  final VoidCallback? onAnnotationEditStart;
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
    this.onAnnotationEditStart,
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

  // Redaction box state: a drag draws a rectangle between these two corners
  // (normalized). Both are null when no box is being drawn.
  Offset? _redactStart;
  Offset? _redactCurrent;

  /// Smallest box (in on-screen pixels, per side) worth keeping. Anything
  /// smaller is treated as an accidental touch.
  static const double _minRedactSidePx = 6.0;

  /// Edges/corners closer than this (px) to a drag snap onto it.
  static const double _snapPx = 10.0;

  /// Resize grab zone around a selected redaction's edges: this far outside,
  /// and up to [_edgeGrabInsidePx] (or a third of the side) inside, so a new
  /// box can still be started right beside a selected one.
  static const double _edgeGrabOutsidePx = 10.0;
  static const double _edgeGrabInsidePx = 28.0;

  // Resize state for the selected redaction.
  Set<_Edge> _resizeEdges = {};
  Rect? _resizeRaw; // normalized, un-snapped, so snapping never "sticks"

  // Snap guide lines (normalized), shown while an edge is snapped.
  double? _guideX;
  double? _guideY;

  bool _editStarted = false;

  void _beginEdit() {
    if (_editStarted) return;
    _editStarted = true;
    widget.onAnnotationEditStart?.call();
  }

  void _setGuides(double? x, double? y) {
    if ((x != null && x != _guideX) || (y != null && y != _guideY)) {
      HapticFeedback.selectionClick();
    }
    _guideX = x;
    _guideY = y;
  }

  List<double> _snapTargetsX(int? exclude) => [
    0.0,
    1.0,
    for (var i = 0; i < widget.annotations.length; i++)
      if (i != exclude && widget.annotations[i] is RedactAnnotation) ...[
        (widget.annotations[i] as RedactAnnotation).rect.left,
        (widget.annotations[i] as RedactAnnotation).rect.right,
      ],
  ];

  List<double> _snapTargetsY(int? exclude) => [
    0.0,
    1.0,
    for (var i = 0; i < widget.annotations.length; i++)
      if (i != exclude && widget.annotations[i] is RedactAnnotation) ...[
        (widget.annotations[i] as RedactAnnotation).rect.top,
        (widget.annotations[i] as RedactAnnotation).rect.bottom,
      ],
  ];

  /// Snaps [value] to the nearest of [targets] within [_snapPx] on an axis
  /// that is [axisPx] pixels long. `hit` is false when nothing was close.
  ({double value, bool hit}) _snap(
    double value,
    List<double> targets,
    double axisPx,
  ) {
    var best = value;
    var bestDistance = _snapPx / axisPx;
    var hit = false;
    for (final target in targets) {
      final distance = (target - value).abs();
      if (distance <= bestDistance) {
        best = target;
        bestDistance = distance;
        hit = true;
      }
    }
    return (value: best, hit: hit);
  }

  Set<_Edge> _resizeEdgesAt(Offset local, Rect normalizedRect) {
    final w = widget.imageSize.width;
    final h = widget.imageSize.height;
    final r = Rect.fromLTRB(
      normalizedRect.left * w,
      normalizedRect.top * h,
      normalizedRect.right * w,
      normalizedRect.bottom * h,
    );
    if (!r.inflate(_edgeGrabOutsidePx).contains(local)) return {};
    final insideX = math.min(_edgeGrabInsidePx, r.width / 3);
    final insideY = math.min(_edgeGrabInsidePx, r.height / 3);
    bool near(double distanceInside, double inside) =>
        distanceInside >= -_edgeGrabOutsidePx && distanceInside <= inside;
    return {
      if (near(local.dx - r.left, insideX)) _Edge.left,
      if (near(r.right - local.dx, insideX)) _Edge.right,
      if (near(local.dy - r.top, insideY)) _Edge.top,
      if (near(r.bottom - local.dy, insideY)) _Edge.bottom,
    };
  }

  void _resizeUpdate(Offset local) {
    final index = _selectedAnnotationIndex;
    final raw = _resizeRaw;
    final last = _lastLocalPoint;
    if (index == null ||
        raw == null ||
        last == null ||
        index >= widget.annotations.length) {
      return;
    }
    final annotation = widget.annotations[index];
    if (annotation is! RedactAnnotation) return;

    final w = widget.imageSize.width;
    final h = widget.imageSize.height;
    final dx = (local.dx - last.dx) / w;
    final dy = (local.dy - last.dy) / h;
    _lastLocalPoint = local;

    final minW = _minRedactSidePx / w;
    final minH = _minRedactSidePx / h;
    double clampTo(double v, double lo, double hi) =>
        v.clamp(lo, math.max(lo, hi)).toDouble();

    var l = raw.left;
    var t = raw.top;
    var r = raw.right;
    var b = raw.bottom;
    if (_resizeEdges.contains(_Edge.left)) l = clampTo(l + dx, 0, r - minW);
    if (_resizeEdges.contains(_Edge.right)) r = clampTo(r + dx, l + minW, 1);
    if (_resizeEdges.contains(_Edge.top)) t = clampTo(t + dy, 0, b - minH);
    if (_resizeEdges.contains(_Edge.bottom)) b = clampTo(b + dy, t + minH, 1);
    _resizeRaw = Rect.fromLTRB(l, t, r, b);

    // Snap only the edges being dragged, to the other redactions.
    final xs = _snapTargetsX(index);
    final ys = _snapTargetsY(index);
    var sl = l, sr = r, st = t, sb = b;
    double? guideX;
    double? guideY;
    if (_resizeEdges.contains(_Edge.left)) {
      final snapped = _snap(l, xs, w);
      sl = clampTo(snapped.value, 0, sr - minW);
      if (snapped.hit) guideX = sl;
    }
    if (_resizeEdges.contains(_Edge.right)) {
      final snapped = _snap(r, xs, w);
      sr = clampTo(snapped.value, sl + minW, 1);
      if (snapped.hit) guideX = sr;
    }
    if (_resizeEdges.contains(_Edge.top)) {
      final snapped = _snap(t, ys, h);
      st = clampTo(snapped.value, 0, sb - minH);
      if (snapped.hit) guideY = st;
    }
    if (_resizeEdges.contains(_Edge.bottom)) {
      final snapped = _snap(b, ys, h);
      sb = clampTo(snapped.value, st + minH, 1);
      if (snapped.hit) guideY = sb;
    }

    setState(() => _setGuides(guideX, guideY));
    _beginEdit();
    widget.onAnnotationUpdated?.call(
      index,
      annotation.copyWith(rect: Rect.fromLTRB(sl, st, sr, sb)),
    );
  }

  void _endResize() {
    _resizeEdges = {};
    _resizeRaw = null;
    _guideX = null;
    _guideY = null;
    _lastLocalPoint = null;
  }

  Rect? get _liveRedactRect {
    final a = _redactStart;
    final b = _redactCurrent;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

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
    _editStarted = false;
    final norm = _toNormalized(details.localPosition);
    final hit = _hitTest(norm);

    // 0. IN REDACT TOOL: grabbing an edge/corner of the selected redaction
    // resizes it.
    final selected = _selectedAnnotationIndex;
    if (widget.activeTool == EditorTool.redact &&
        selected != null &&
        selected < widget.annotations.length) {
      final annotation = widget.annotations[selected];
      if (annotation is RedactAnnotation) {
        final edges = _resizeEdgesAt(details.localPosition, annotation.rect);
        if (edges.isNotEmpty) {
          setState(() {
            _resizeEdges = edges;
            _resizeRaw = annotation.rect;
            _lastLocalPoint = details.localPosition;
          });
          return;
        }
      }
    }

    // 1. IN REDACT TOOL: Touching an existing redaction grabs and moves it.
    if (widget.activeTool == EditorTool.redact &&
        hit != null &&
        widget.annotations[hit] is RedactAnnotation) {
      setState(() {
        _selectedAnnotationIndex = hit;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localPosition;
      });
      return;
    }

    // 2. IN TEXT TOOL: Touching existing text grabs and moves it
    if (widget.activeTool == EditorTool.text &&
        hit != null &&
        widget.annotations[hit] is TextMarkAnnotation) {
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

    // 4. DRAW TOOL: start a freehand stroke.
    if (widget.activeTool == EditorTool.draw) {
      setState(() {
        _currentDrawingPoints
          ..clear()
          ..add(norm);
      });
      return;
    }

    // 5. REDACT TOOL: start a rectangle; dragging stretches it.
    if (widget.activeTool == EditorTool.redact) {
      final snapped = _snapPoint(norm);
      setState(() {
        _redactStart = snapped.point;
        _redactCurrent = snapped.point;
        _setGuides(snapped.guideX, snapped.guideY);
      });
      return;
    }
  }

  ({Offset point, double? guideX, double? guideY}) _snapPoint(Offset norm) {
    final sx = _snap(norm.dx, _snapTargetsX(null), widget.imageSize.width);
    final sy = _snap(norm.dy, _snapTargetsY(null), widget.imageSize.height);
    return (
      point: Offset(sx.value, sy.value),
      guideX: sx.hit ? sx.value : null,
      guideY: sy.hit ? sy.value : null,
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_resizeEdges.isNotEmpty) {
      _resizeUpdate(details.localPosition);
      return;
    }

    if (widget.activeTool == EditorTool.draw && !_isDraggingAnnotation) {
      setState(() {
        _currentDrawingPoints.add(_toNormalized(details.localPosition));
      });
      return;
    }

    if (widget.activeTool == EditorTool.redact &&
        !_isDraggingAnnotation &&
        _redactStart != null) {
      final snapped = _snapPoint(_toNormalized(details.localPosition));
      setState(() {
        _redactCurrent = snapped.point;
        _setGuides(snapped.guideX, snapped.guideY);
      });
      return;
    }

    if (_isDraggingAnnotation &&
        _selectedAnnotationIndex != null &&
        _lastLocalPoint != null) {
      final delta = Offset(
        (details.localPosition.dx - _lastLocalPoint!.dx) /
            widget.imageSize.width,
        (details.localPosition.dy - _lastLocalPoint!.dy) /
            widget.imageSize.height,
      );
      _lastLocalPoint = details.localPosition;

      final current = widget.annotations[_selectedAnnotationIndex!];
      final updated = current.translate(delta, widget.imageSize);
      _beginEdit();
      widget.onAnnotationUpdated?.call(_selectedAnnotationIndex!, updated);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_resizeEdges.isNotEmpty) {
      setState(_endResize);
      _editStarted = false;
      return;
    }

    if (!_isDraggingAnnotation &&
        widget.activeTool == EditorTool.draw &&
        _currentDrawingPoints.isNotEmpty) {
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

    if (!_isDraggingAnnotation &&
        widget.activeTool == EditorTool.redact &&
        _redactStart != null) {
      _commitRedactRect();
      return;
    }

    if (_isDraggingAnnotation) {
      setState(() {
        _isDraggingAnnotation = false;
        _lastLocalPoint = null;
      });
    }
  }

  void _commitRedactRect() {
    final rect = _liveRedactRect;
    final size = widget.imageSize;
    if (rect != null &&
        rect.width * size.width >= _minRedactSidePx &&
        rect.height * size.height >= _minRedactSidePx) {
      // The new box goes on top of the list, so it is the one to select.
      final newIndex = widget.annotations.length;
      widget.onAnnotationAdded(
        RedactAnnotation(rect: rect, color: widget.color.withValues(alpha: 1)),
      );
      setState(() => _selectedAnnotationIndex = newIndex);
    }
    setState(() {
      _redactStart = null;
      _redactCurrent = null;
      _guideX = null;
      _guideY = null;
    });
  }

  void _onPanCancel() {
    setState(() {
      _currentDrawingPoints.clear();
      _redactStart = null;
      _redactCurrent = null;
      _guideX = null;
      _guideY = null;
      _resizeEdges = {};
      _resizeRaw = null;
      _isDraggingAnnotation = false;
      _lastLocalPoint = null;
    });
  }

  // ── HOLD TO MOVE (Long Press grabs any shape in any tool) ─────────────────

  void _onLongPressStart(LongPressStartDetails details) {
    final norm = _toNormalized(details.localPosition);
    final hit = _hitTest(norm);
    if (hit != null) {
      _editStarted = false;
      setState(() {
        _selectedAnnotationIndex = hit;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localPosition;
        _currentDrawingPoints.clear();
        _redactStart = null;
        _redactCurrent = null;
      });
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_isDraggingAnnotation &&
        _selectedAnnotationIndex != null &&
        _lastLocalPoint != null) {
      final delta = Offset(
        (details.localPosition.dx - _lastLocalPoint!.dx) /
            widget.imageSize.width,
        (details.localPosition.dy - _lastLocalPoint!.dy) /
            widget.imageSize.height,
      );
      _lastLocalPoint = details.localPosition;

      final current = widget.annotations[_selectedAnnotationIndex!];
      final updated = current.translate(delta, widget.imageSize);
      _beginEdit();
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

    // A tap in the redact tool selects an existing box (or deselects); boxes
    // are only created by dragging.
    if (widget.activeTool == EditorTool.redact) {
      final hit = _hitTest(norm);
      setState(
        () => _selectedAnnotationIndex =
            hit != null && widget.annotations[hit] is RedactAnnotation
            ? hit
            : null,
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
      onPanCancel: _onPanCancel,
      onTapUp: _onTapUp,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      // No onLongPressCancel on purpose: the long-press recognizer is rejected
      // (and reports "cancel") every time a drag wins the gesture arena, which
      // used to wipe the in-progress stroke/box mid-drag. A long press that was
      // actually accepted always ends via onLongPressEnd.
      child: CustomPaint(
        size: widget.imageSize,
        painter: _AnnotationPainter(
          annotations: widget.annotations,
          selectedIndex: _selectedAnnotationIndex,
          liveDrawing: _currentDrawingPoints,
          liveRedactRect: _liveRedactRect,
          showResizeHandles: widget.activeTool == EditorTool.redact,
          guideX: _guideX,
          guideY: _guideY,
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
  final Rect? liveRedactRect;
  final bool showResizeHandles;
  final double? guideX;
  final double? guideY;
  final Color liveColor;
  final double strokeWidthFraction;

  _AnnotationPainter({
    required this.annotations,
    this.selectedIndex,
    required this.liveDrawing,
    required this.liveRedactRect,
    required this.showResizeHandles,
    required this.guideX,
    required this.guideY,
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

          if (showResizeHandles && annotations[i] is RedactAnnotation) {
            _paintHandles(canvas, bounds);
          }
        }
      }
    }

    final liveRect = liveRedactRect;
    if (liveRect != null) {
      final pixelRect = Rect.fromLTRB(
        liveRect.left * size.width,
        liveRect.top * size.height,
        liveRect.right * size.width,
        liveRect.bottom * size.height,
      );
      canvas.drawRect(
        pixelRect,
        Paint()
          ..color = liveColor.withValues(alpha: 1)
          ..style = PaintingStyle.fill,
      );
      // Thin light outline so the box stays visible over similarly coloured
      // parts of the image while it is being drawn.
      canvas.drawRect(
        pixelRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    _paintGuides(canvas, size);

    if (liveDrawing.isNotEmpty) {
      final strokeWidth = size.height * strokeWidthFraction;
      final paint = Paint()
        ..color = liveColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (liveDrawing.length == 1) {
        final p = Offset(
          liveDrawing.first.dx * size.width,
          liveDrawing.first.dy * size.height,
        );
        canvas.drawCircle(
          p,
          strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        final path = Path();
        final first = Offset(
          liveDrawing.first.dx * size.width,
          liveDrawing.first.dy * size.height,
        );
        path.moveTo(first.dx, first.dy);

        for (int i = 1; i < liveDrawing.length; i++) {
          final pt = Offset(
            liveDrawing[i].dx * size.width,
            liveDrawing[i].dy * size.height,
          );
          path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  void _paintGuides(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = const Color(0xFF22D3EE)
      ..strokeWidth = 1.0;
    final gx = guideX;
    final gy = guideY;
    if (gx != null) {
      canvas.drawLine(
        Offset(gx * size.width, 0),
        Offset(gx * size.width, size.height),
        guide,
      );
    }
    if (gy != null) {
      canvas.drawLine(
        Offset(0, gy * size.height),
        Offset(size.width, gy * size.height),
        guide,
      );
    }
  }

  void _paintHandles(Canvas canvas, Rect bounds) {
    final fill = Paint()..color = Colors.white;
    final border = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    void handle(Offset center) {
      canvas.drawCircle(center, 7, fill);
      canvas.drawCircle(center, 7, border);
    }

    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      handle(corner);
    }
    // Edge-midpoint handles only when the side is long enough not to overlap
    // the corner handles.
    if (bounds.width >= 48) {
      handle(Offset(bounds.center.dx, bounds.top));
      handle(Offset(bounds.center.dx, bounds.bottom));
    }
    if (bounds.height >= 48) {
      handle(Offset(bounds.left, bounds.center.dy));
      handle(Offset(bounds.right, bounds.center.dy));
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
