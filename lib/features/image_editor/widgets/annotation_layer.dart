import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

enum EditorTool { none, crop, draw, text, redact, tuneImage, looks }

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
  final int? selectedAnnotationIndex;

  /// `true` arms one box-creation drag, `false` disables empty-space creation,
  /// and `null` keeps the layer's standalone draw-on-empty behavior.
  final bool? isAddingRedact;
  final Color color;
  final double strokeWidthFraction;
  final ValueChanged<EditAnnotation> onAnnotationAdded;
  final void Function(int index, EditAnnotation annotation)?
  onAnnotationUpdated;
  final void Function(int index)? onAnnotationRemoved;
  final ValueChanged<int?>? onSelectedAnnotationChanged;
  final VoidCallback? onRedactAddComplete;

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
    this.selectedAnnotationIndex,
    this.isAddingRedact,
    required this.color,
    required this.strokeWidthFraction,
    required this.onAnnotationAdded,
    this.onAnnotationUpdated,
    this.onAnnotationRemoved,
    this.onSelectedAnnotationChanged,
    this.onRedactAddComplete,
    this.onAnnotationEditStart,
    required this.onTextTapped,
  });

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  late bool _isAddingRedact;
  int? _selectedAnnotationIndex;
  bool _isDraggingAnnotation = false;
  bool _isInteracting = false;
  bool _isDrawingNewRect = false;
  Offset? _lastLocalPoint;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  // Scale & rotate interaction state (matching text tool)
  Rect _startRect = Rect.zero;
  double _startRotation = 0.0;
  double _lastSnappedAngle = 0.0;
  Rect _currentRect = Rect.zero;

  // Freehand drawing state
  final List<Offset> _currentDrawingPoints = [];

  Offset? _redactStart;
  Offset? _redactCurrent;

  /// Smallest box (in on-screen pixels, per side) allowed while resizing.
  static const double _minRedactSidePx = 6.0;

  Rect? get _liveRedactRect {
    final a = _redactStart;
    final b = _redactCurrent;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

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

  @override
  void initState() {
    super.initState();
    _isAddingRedact = widget.isAddingRedact ?? false;
  }

  @override
  void didUpdateWidget(AnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAddingRedact != widget.isAddingRedact) {
      _isAddingRedact = widget.isAddingRedact ?? false;
    }
    if (oldWidget.activeTool == EditorTool.redact &&
        widget.activeTool != EditorTool.redact) {
      _selectedAnnotationIndex = null;
    } else if (widget.activeTool == EditorTool.redact &&
        (oldWidget.activeTool != EditorTool.redact ||
            oldWidget.selectedAnnotationIndex !=
                widget.selectedAnnotationIndex)) {
      _selectedAnnotationIndex = widget.selectedAnnotationIndex;
    }
    if (_selectedAnnotationIndex != null) {
      if (_selectedAnnotationIndex! >= widget.annotations.length ||
          (widget.activeTool == EditorTool.redact &&
              widget.annotations[_selectedAnnotationIndex!]
                  is! RedactAnnotation)) {
        _selectedAnnotationIndex = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSelectedAnnotationChanged?.call(null);
        });
      }
    }
  }

  void _selectAnnotation(int? index) {
    if (_selectedAnnotationIndex != index) {
      setState(() => _selectedAnnotationIndex = index);
      widget.onSelectedAnnotationChanged?.call(index);
    }
  }

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

  ({Offset point, double? guideX, double? guideY}) _snapPoint(Offset norm) {
    final sx = _snap(norm.dx, _snapTargetsX(null), widget.imageSize.width);
    final sy = _snap(norm.dy, _snapTargetsY(null), widget.imageSize.height);
    return (
      point: Offset(sx.value, sy.value),
      guideX: sx.hit ? sx.value : null,
      guideY: sy.hit ? sy.value : null,
    );
  }

  void _startRedactBox(Offset norm) {
    _selectAnnotation(null);
    final snapped = _snapPoint(norm);
    setState(() {
      _isInteracting = true;
      _isDrawingNewRect = true;
      _isDraggingAnnotation = false;
      _resizeEdges = {};
      _redactStart = snapped.point;
      _redactCurrent = snapped.point;
      _setGuides(snapped.guideX, snapped.guideY);
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _editStarted = false;
    _lastLocalPoint = details.localFocalPoint;
    final norm = _toNormalized(details.localFocalPoint);
    final hit = _hitTest(norm);

    // 0. DRAW TOOL: start freehand stroke
    if (widget.activeTool == EditorTool.draw) {
      setState(() {
        _isInteracting = true;
        _isDraggingAnnotation = false;
        _currentDrawingPoints
          ..clear()
          ..add(norm);
      });
      return;
    }

    // 1. REDACT TOOL:
    if (widget.activeTool == EditorTool.redact) {
      // 1a. Check if touching an edge of the already selected redact box (1 finger, unrotated)
      final selected = _selectedAnnotationIndex;
      if (!_isAddingRedact &&
          details.pointerCount == 1 &&
          selected != null &&
          selected < widget.annotations.length) {
        final annotation = widget.annotations[selected];
        if (annotation is RedactAnnotation &&
            annotation.rotation.abs() < 0.05) {
          final edges = _resizeEdgesAt(
            details.localFocalPoint,
            annotation.rect,
          );
          if (edges.isNotEmpty) {
            setState(() {
              _isInteracting = true;
              _resizeEdges = edges;
              _resizeRaw = annotation.rect;
              _lastLocalPoint = details.localFocalPoint;
              _isDraggingAnnotation = false;
            });
            return;
          }
        }
      }

      // Add arms the next drag anywhere on the image to create one new box.
      if (_isAddingRedact) {
        _startRedactBox(norm);
        return;
      }

      // Touching a box grabs it. A background drag moves the current box.
      final hitRedact =
          hit != null && widget.annotations[hit] is RedactAnnotation;
      final selectedForMove = hitRedact
          ? hit
          : selected != null &&
                selected < widget.annotations.length &&
                widget.annotations[selected] is RedactAnnotation
          ? selected
          : null;
      if (selectedForMove != null) {
        final ann = widget.annotations[selectedForMove] as RedactAnnotation;
        _selectAnnotation(selectedForMove);
        setState(() {
          _isInteracting = true;
          _isDraggingAnnotation = true;
          _resizeEdges = {};
          _startRect = ann.rect;
          _currentRect = ann.rect;
          _startRotation = ann.rotation;
          _lastSnappedAngle = ann.rotation;
          _lastLocalPoint = details.localFocalPoint;
        });
        return;
      }

      // Preserve the standalone layer's original draw-on-empty behavior when
      // the host does not provide an explicit Add state.
      if (widget.isAddingRedact == null) {
        _startRedactBox(norm);
        return;
      }

      _selectAnnotation(null);
      return;
    }

    // 2. TEXT TOOL: touching existing text grabs it
    if (widget.activeTool == EditorTool.text &&
        hit != null &&
        widget.annotations[hit] is TextMarkAnnotation) {
      _selectAnnotation(hit);
      setState(() {
        _isInteracting = true;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localFocalPoint;
      });
      return;
    }

    // 3. NONE TOOL: touching any annotation grabs it
    if (widget.activeTool == EditorTool.none && hit != null) {
      _selectAnnotation(hit);
      setState(() {
        _isInteracting = true;
        _isDraggingAnnotation = true;
        _lastLocalPoint = details.localFocalPoint;
      });
      return;
    }

    // Deselect when touching empty space in other tools
    if (_selectedAnnotationIndex != null) {
      _selectAnnotation(null);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final imageSize = widget.imageSize;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    // 0. Redact edge resizing (single finger)
    if (_resizeEdges.isNotEmpty) {
      if (details.pointerCount >= 2) {
        _resizeEdges = {};
      } else {
        _resizeUpdate(details.localFocalPoint);
        return;
      }
    }

    // 1. Draw tool freehand points
    if (widget.activeTool == EditorTool.draw && !_isDraggingAnnotation) {
      setState(() {
        _currentDrawingPoints.add(_toNormalized(details.localFocalPoint));
      });
      return;
    }

    // 2. Redact tool: draw the requested box after Add is armed.
    if (widget.activeTool == EditorTool.redact &&
        _isDrawingNewRect &&
        _redactStart != null) {
      final snapped = _snapPoint(_toNormalized(details.localFocalPoint));
      setState(() {
        _redactCurrent = snapped.point;
        _setGuides(snapped.guideX, snapped.guideY);
      });
      return;
    }

    // 3. Redact tool: manipulating selected box (move / pinch resize / rotate)
    if (widget.activeTool == EditorTool.redact &&
        _isDraggingAnnotation &&
        _selectedAnnotationIndex != null &&
        _selectedAnnotationIndex! < widget.annotations.length) {
      final ann = widget.annotations[_selectedAnnotationIndex!];
      if (ann is RedactAnnotation) {
        // 1. Move position (pan / translation)
        final normDelta = Offset(
          details.focalPointDelta.dx / imageSize.width,
          details.focalPointDelta.dy / imageSize.height,
        );

        var curRect = _currentRect;
        if (normDelta != Offset.zero) {
          final shifted = curRect.shift(normDelta);
          final clamped = Rect.fromLTRB(
            shifted.left.clamp(0.0, 1.0 - shifted.width),
            shifted.top.clamp(0.0, 1.0 - shifted.height),
            shifted.right.clamp(shifted.width, 1.0),
            shifted.bottom.clamp(shifted.height, 1.0),
          );
          curRect = clamped;
        }

        // 2. Pinch scale (resizing width and height around center)
        if (details.scale != 1.0) {
          final minW = _minRedactSidePx / imageSize.width;
          final minH = _minRedactSidePx / imageSize.height;
          final targetW = (_startRect.width * details.scale).clamp(minW, 1.0);
          final targetH = (_startRect.height * details.scale).clamp(minH, 1.0);
          curRect = Rect.fromCenter(
            center: curRect.center,
            width: targetW,
            height: targetH,
          );
        }
        _currentRect = curRect;

        // 3. Rotation gesture (matching TextOverlay)
        double newRotation = ann.rotation;
        if (details.rotation != 0.0 || details.pointerCount >= 2) {
          var rawAngle = _startRotation + details.rotation;

          // Magnetic snap around 0, +/-90, +/-180, +/-270 degrees within 2.5 degrees
          const snapThreshold = 2.5 * math.pi / 180.0;
          final snapPoints = [
            0.0,
            math.pi / 2,
            -math.pi / 2,
            math.pi,
            -math.pi,
            3 * math.pi / 2,
            -3 * math.pi / 2,
          ];
          for (final snap in snapPoints) {
            if ((rawAngle - snap).abs() <= snapThreshold) {
              if (_lastSnappedAngle != snap &&
                  (snap == 0.0 || snap.abs() == math.pi / 2)) {
                HapticFeedback.selectionClick();
              }
              rawAngle = snap;
              break;
            }
          }
          _lastSnappedAngle = rawAngle;
          newRotation = rawAngle;
        }

        _beginEdit();
        widget.onAnnotationUpdated?.call(
          _selectedAnnotationIndex!,
          ann.copyWith(rect: curRect, rotation: newRotation),
        );
        return;
      }
    }

    // 4. Other tools: generic annotation translation
    if (_isDraggingAnnotation &&
        _selectedAnnotationIndex != null &&
        _selectedAnnotationIndex! < widget.annotations.length) {
      final normDelta = Offset(
        details.focalPointDelta.dx / imageSize.width,
        details.focalPointDelta.dy / imageSize.height,
      );
      if (normDelta != Offset.zero) {
        final current = widget.annotations[_selectedAnnotationIndex!];
        final updated = current.translate(normDelta, imageSize);
        _beginEdit();
        widget.onAnnotationUpdated?.call(_selectedAnnotationIndex!, updated);
      }
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _editStarted = false;
    if (mounted) {
      setState(() => _isInteracting = false);
    }

    if (_resizeEdges.isNotEmpty) {
      setState(_endResize);
      return;
    }

    if (widget.activeTool == EditorTool.draw &&
        _currentDrawingPoints.isNotEmpty) {
      if (_currentDrawingPoints.length > 1) {
        widget.onAnnotationAdded(
          DrawingAnnotation(
            points: List<Offset>.from(_currentDrawingPoints),
            color: widget.color,
            strokeWidthFraction: widget.strokeWidthFraction,
          ),
        );
      }
      setState(() => _currentDrawingPoints.clear());
      return;
    }

    if (widget.activeTool == EditorTool.redact && _isDrawingNewRect) {
      _commitRedactRect();
      _isDrawingNewRect = false;
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
      final newIndex = widget.annotations.length;
      widget.onAnnotationAdded(
        RedactAnnotation(rect: rect, color: widget.color.withValues(alpha: 1)),
      );
      _selectAnnotation(newIndex);
      _isAddingRedact = false;
      widget.onRedactAddComplete?.call();
    }
    setState(() {
      _redactStart = null;
      _redactCurrent = null;
      _guideX = null;
      _guideY = null;
    });
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
    // are only created by dragging. Double-tapping an existing box deletes it.
    if (widget.activeTool == EditorTool.redact) {
      if (_isAddingRedact) return;

      final now = DateTime.now();
      final hit = _hitTest(norm);
      final isDoubleTap =
          _lastTapTime != null &&
          now.difference(_lastTapTime!) < const Duration(milliseconds: 400) &&
          _lastTapPosition != null &&
          (details.localPosition - _lastTapPosition!).distance < 35.0;

      if (isDoubleTap) {
        _lastTapTime = null;
        _lastTapPosition = null;
        final targetIndex = hit ?? _selectedAnnotationIndex;
        if (targetIndex != null &&
            targetIndex >= 0 &&
            targetIndex < widget.annotations.length &&
            widget.annotations[targetIndex] is RedactAnnotation) {
          _deleteAnnotationAt(targetIndex);
          return;
        }
      }

      _lastTapTime = now;
      _lastTapPosition = details.localPosition;

      final newIndex =
          hit != null && widget.annotations[hit] is RedactAnnotation
          ? hit
          : null;
      _selectAnnotation(newIndex);
      return;
    }

    if (widget.activeTool == EditorTool.text) {
      final hit = _hitTest(norm);
      if (hit != null && widget.annotations[hit] is TextMarkAnnotation) {
        _selectAnnotation(hit);
      } else {
        widget.onTextTapped(norm);
      }
      return;
    }

    final hit = _hitTest(norm);
    _selectAnnotation(hit);
  }

  void _deleteAnnotationAt(int index) {
    HapticFeedback.mediumImpact();
    widget.onAnnotationRemoved?.call(index);
    _selectAnnotation(null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: CustomPaint(
        size: widget.imageSize,
        painter: _AnnotationPainter(
          annotations: widget.annotations,
          selectedIndex: _selectedAnnotationIndex,
          isInteracting: _isInteracting,
          liveDrawing: _currentDrawingPoints,
          liveRedactRect: _liveRedactRect,
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
  final bool isInteracting;
  final List<Offset> liveDrawing;
  final Rect? liveRedactRect;
  final double? guideX;
  final double? guideY;
  final Color liveColor;
  final double strokeWidthFraction;

  _AnnotationPainter({
    required this.annotations,
    this.selectedIndex,
    required this.isInteracting,
    required this.liveDrawing,
    required this.liveRedactRect,
    required this.guideX,
    required this.guideY,
    required this.liveColor,
    required this.strokeWidthFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < annotations.length; i++) {
      annotations[i].paint(canvas, size);

      if (selectedIndex == i) {
        if (annotations[i] is RedactAnnotation) {
          final ann = annotations[i] as RedactAnnotation;
          final pixelRect = ann.getBounds(size);
          final center = pixelRect.center;

          canvas.save();
          canvas.translate(center.dx, center.dy);
          if (ann.rotation != 0.0) {
            canvas.rotate(ann.rotation);
          }

          final guidePaint = Paint()
            ..color = Colors.white.withValues(
              alpha: isInteracting ? 0.65 : 0.40,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;

          final halfW = pixelRect.width / 2.0 + 6.0;
          final halfH = pixelRect.height / 2.0 + 6.0;
          const extend = 18.0;

          // Vertical guide lines extending past corners
          _drawDashedLine(
            canvas,
            Offset(-halfW, -halfH - extend),
            Offset(-halfW, halfH + extend),
            guidePaint,
          );
          _drawDashedLine(
            canvas,
            Offset(halfW, -halfH - extend),
            Offset(halfW, halfH + extend),
            guidePaint,
          );

          // Horizontal guide lines extending past corners
          _drawDashedLine(
            canvas,
            Offset(-halfW - extend, -halfH),
            Offset(halfW + extend, -halfH),
            guidePaint,
          );
          _drawDashedLine(
            canvas,
            Offset(-halfW - extend, halfH),
            Offset(halfW + extend, halfH),
            guidePaint,
          );

          // Horizontal guide line passing through center
          _drawDashedLine(
            canvas,
            Offset(-halfW - extend, 0),
            Offset(halfW + extend, 0),
            guidePaint,
          );

          canvas.restore();
        } else {
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

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dash = 6,
    double gap = 4,
  }) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return;
    final unitX = dx / dist;
    final unitY = dy / dist;
    double current = 0;
    while (current < dist) {
      final end = math.min(current + dash, dist);
      canvas.drawLine(
        Offset(p1.dx + unitX * current, p1.dy + unitY * current),
        Offset(p1.dx + unitX * end, p1.dy + unitY * end),
        paint,
      );
      current += dash + gap;
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

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.isInteracting != isInteracting ||
      oldDelegate.liveDrawing != liveDrawing ||
      oldDelegate.liveRedactRect != liveRedactRect ||
      oldDelegate.guideX != guideX ||
      oldDelegate.guideY != guideY ||
      oldDelegate.liveColor != liveColor ||
      oldDelegate.strokeWidthFraction != strokeWidthFraction;
}
