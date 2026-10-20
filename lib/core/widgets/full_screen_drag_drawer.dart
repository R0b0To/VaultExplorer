import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// A modal drawer that can be pulled from its content area or screen edge.
///
/// The listener observes the drag without claiming the gesture arena, allowing
/// nested vertical scrollables to keep their normal behavior. Callers can
/// limit opening to the left edge while a horizontal pager handles other swipes.
class FullScreenDragDrawer extends StatefulWidget {
  const FullScreenDragDrawer({
    super.key,
    required this.child,
    required this.drawer,
    this.canOpenFromAnywhere = true,
    this.edgeGestureTop = 0,
    this.edgeGestureTopBuilder,
    this.canStartGestureAt,
    this.backGestureInsetLeft = 24,
    this.onDrawerChanged,
    this.onEdgeGestureChanged,
  });

  final Widget child;
  final Widget? drawer;
  final bool canOpenFromAnywhere;
  final double edgeGestureTop;
  final double Function()? edgeGestureTopBuilder;
  final bool Function(Offset position)? canStartGestureAt;
  final double backGestureInsetLeft;
  final ValueChanged<bool>? onDrawerChanged;
  final ValueChanged<bool>? onEdgeGestureChanged;

  @override
  State<FullScreenDragDrawer> createState() => _FullScreenDragDrawerState();
}

class _FullScreenDragDrawerState extends State<FullScreenDragDrawer>
    with SingleTickerProviderStateMixin {
  static const double _defaultDrawerWidth = 304.0;
  static const double _drawerEdgeWidth = 24.0;
  static const double _dragSlop = 8.0;
  static const double _flingVelocity = 650.0;
  static const Duration _settleDuration = Duration(milliseconds: 220);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _settleDuration,
  );

  LocalHistoryEntry? _historyEntry;
  _DrawerPointerDrag? _pointerDrag;
  bool _reportedOpen = false;
  bool _edgeGestureActive = false;

  @override
  void dispose() {
    _pointerDrag = null;
    _historyEntry?.remove();
    _historyEntry = null;
    _controller.dispose();
    super.dispose();
  }

  void openDrawer() {
    if (widget.drawer == null) return;
    _ensureHistoryEntry();
    _setReportedOpen(true);
    _animateTo(1.0);
  }

  void _ensureHistoryEntry() {
    if (_historyEntry != null) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    _historyEntry = LocalHistoryEntry(
      impliesAppBarDismissal: false,
      onRemove: _handleHistoryEntryRemoved,
    );
    route.addLocalHistoryEntry(_historyEntry!);
  }

  void _handleHistoryEntryRemoved() {
    _historyEntry = null;
    _setReportedOpen(false);
    if (mounted) _animateTo(0.0);
  }

  void _closeDrawer() {
    final entry = _historyEntry;
    if (entry != null) {
      entry.remove();
    } else {
      _setReportedOpen(false);
      _animateTo(0.0);
    }
  }

  void _animateTo(double value) {
    if (!mounted) return;
    final remaining = (value - _controller.value).abs();
    if (remaining <= 0.001) return;
    final durationMs = (_settleDuration.inMilliseconds * remaining)
        .round()
        .clamp(60, _settleDuration.inMilliseconds);
    _controller.animateTo(
      value,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutCubic,
    );
  }

  void _setReportedOpen(bool open) {
    if (_reportedOpen == open) return;
    _reportedOpen = open;
    widget.onDrawerChanged?.call(open);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointerDrag != null) {
      _pointerDrag = null;
      _setEdgeGestureActive(false);
      if (_controller.value < 0.5) {
        _closeDrawer();
      } else {
        _setReportedOpen(true);
        _animateTo(1.0);
      }
      return;
    }
    if (widget.drawer == null) return;

    // Leave the OS back-gesture strip to the platform. In particular, a
    // canceled predictive-back gesture must not briefly animate this drawer.
    if (event.position.dx <= widget.backGestureInsetLeft) return;

    final startValue = _controller.value;
    if (startValue <= 0.001 &&
        widget.canStartGestureAt?.call(event.position) == false) {
      return;
    }
    final edgeGestureTop =
        widget.edgeGestureTopBuilder?.call() ?? widget.edgeGestureTop;
    final startsAtOpenEdge =
        event.position.dx <= widget.backGestureInsetLeft + _drawerEdgeWidth &&
        event.position.dy >= edgeGestureTop;
    if (startValue <= 0.001 &&
        !widget.canOpenFromAnywhere &&
        !startsAtOpenEdge) {
      return;
    }
    if (startValue <= 0.001 &&
        !widget.canOpenFromAnywhere &&
        startsAtOpenEdge) {
      _setEdgeGestureActive(true);
    }

    final velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _pointerDrag = _DrawerPointerDrag(
      pointer: event.pointer,
      startPosition: event.position,
      startValue: startValue,
      velocityTracker: velocityTracker,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final drag = _pointerDrag;
    if (drag == null || drag.pointer != event.pointer) return;
    drag.velocityTracker.addPosition(event.timeStamp, event.position);

    final delta = event.position - drag.startPosition;
    if (!drag.isDragging) {
      if (delta.distance < _dragSlop) return;
      if (delta.dx.abs() <= delta.dy.abs()) {
        _pointerDrag = null;
        _setEdgeGestureActive(false);
        return;
      }
      // A closed drawer only opens on a rightward swipe. When it is already
      // visible, either direction can adjust the drawer and cancel its motion.
      if (drag.startValue <= 0.001 && delta.dx <= 0.0) {
        _pointerDrag = null;
        _setEdgeGestureActive(false);
        return;
      }
      drag.isDragging = true;
      _controller.stop();
      _ensureHistoryEntry();
      _setReportedOpen(true);
    }

    final width = math.min(
      _defaultDrawerWidth,
      MediaQuery.sizeOf(context).width,
    );
    _controller.value = (drag.startValue + delta.dx / width)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _handlePointerUp(PointerEvent event, {bool cancelled = false}) {
    final drag = _pointerDrag;
    if (drag == null || drag.pointer != event.pointer) return;
    if (!cancelled) {
      drag.velocityTracker.addPosition(event.timeStamp, event.position);
    }
    _pointerDrag = null;
    if (!drag.isDragging) {
      _setEdgeGestureActive(false);
      return;
    }

    final velocity = cancelled
        ? 0.0
        : drag.velocityTracker.getVelocity().pixelsPerSecond.dx;
    final shouldOpen = cancelled
        ? drag.startValue >= 0.5
        : velocity > _flingVelocity
        ? true
        : velocity < -_flingVelocity
        ? false
        : _controller.value >= 0.5;

    if (shouldOpen) {
      _ensureHistoryEntry();
      _setReportedOpen(true);
      _animateTo(1.0);
    } else {
      _closeDrawer();
    }
    _setEdgeGestureActive(false);
  }

  void _setEdgeGestureActive(bool active) {
    if (_edgeGestureActive == active) return;
    _edgeGestureActive = active;
    widget.onEdgeGestureChanged?.call(active);
  }

  @override
  Widget build(BuildContext context) {
    final listener = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (event) => _handlePointerUp(event, cancelled: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final drawerWidth = math.min(
            _defaultDrawerWidth,
            constraints.maxWidth,
          );
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (widget.drawer != null)
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final progress = _controller.value;
                      if (progress <= 0.001) return const SizedBox.shrink();
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _closeDrawer,
                              child: ColoredBox(
                                color: Colors.black.withValues(
                                  alpha: 0.54 * progress,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: -drawerWidth * (1.0 - progress),
                            top: 0,
                            bottom: 0,
                            width: drawerWidth,
                            child: widget.drawer!,
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (widget.drawer == null) return listener;
    return FullScreenDragDrawerScope(openDrawer: openDrawer, child: listener);
  }
}

class _DrawerPointerDrag {
  _DrawerPointerDrag({
    required this.pointer,
    required this.startPosition,
    required this.startValue,
    required this.velocityTracker,
  });

  final int pointer;
  final Offset startPosition;
  final double startValue;
  final VelocityTracker velocityTracker;
  bool isDragging = false;
}

class FullScreenDragDrawerScope extends InheritedWidget {
  const FullScreenDragDrawerScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  final VoidCallback openDrawer;

  static FullScreenDragDrawerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FullScreenDragDrawerScope>();

  @override
  bool updateShouldNotify(FullScreenDragDrawerScope oldWidget) =>
      openDrawer != oldWidget.openDrawer;
}
