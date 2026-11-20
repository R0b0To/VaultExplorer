import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';

/// Wraps a header bar (such as breadcrumbs) and a scrollable child,
/// automatically hiding the bar on vertical downward scroll and revealing it
/// on upward scroll when [enabled] is true.
class AutoHideScrollHost extends StatefulWidget {
  final bool enabled;
  final double barHeight;
  final Widget? bar;
  final Widget child;
  final Object? resetKey;

  const AutoHideScrollHost({
    super.key,
    required this.enabled,
    this.barHeight = 40.0,
    required this.bar,
    required this.child,
    this.resetKey,
  });

  @override
  State<AutoHideScrollHost> createState() => _AutoHideScrollHostState();
}

class _AutoHideScrollHostState extends State<AutoHideScrollHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _scrollbarDragging = false;
  bool _scrollbarDragEndedAtTop = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(AutoHideScrollHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      if (_controller.value != 1.0) {
        _controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (widget.resetKey != oldWidget.resetKey) {
      if (_controller.value != 1.0) {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _handleScrollbarDrag(FastScrollbarDragNotification notification) {
    if (_scrollbarDragging == notification.dragging) return false;
    _scrollbarDragging = notification.dragging;
    if (notification.dragging) {
      _scrollbarDragEndedAtTop = false;
      return false;
    }
    final atTop = _scrollbarDragEndedAtTop;
    _scrollbarDragEndedAtTop = false;
    final value = _controller.value;
    final double? target = atTop
        ? 1.0
        : (value > 0.0 && value < 1.0)
            ? (value >= 0.5 ? 1.0 : 0.0)
            : null;
    if (target != null && target != value) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    return false;
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!widget.enabled) {
      if (_controller.value != 1.0) {
        _controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return false;
    }

    if (_scrollbarDragging) {
      _scrollbarDragEndedAtTop =
          notification.metrics.maxScrollExtent > 0.0 &&
          notification.metrics.pixels <= 0.0;
      return false;
    }

    void setProgress(double value) {
      _controller.value = value.clamp(0.0, 1.0).toDouble();
    }

    final metrics = notification.metrics;
    final canScroll = metrics.maxScrollExtent > 0.0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (canScroll && metrics.pixels <= 0.0 && delta <= 0.0) {
        setProgress(1.0);
      } else if (delta != 0.0) {
        setProgress(_controller.value - (delta / widget.barHeight));
      }
    } else if (notification is OverscrollNotification) {
      if (notification.overscroll != 0.0) {
        setProgress(
          _controller.value - (notification.overscroll / widget.barHeight),
        );
      }
    } else if (notification is ScrollEndNotification) {
      if (canScroll && metrics.pixels <= 0.0) {
        _controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else if (_controller.value > 0.0 && _controller.value < 1.0) {
        _controller.animateTo(
          _controller.value >= 0.5 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bar = widget.bar;
    return NotificationListener<FastScrollbarDragNotification>(
      onNotification: _handleScrollbarDrag,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: Column(
          children: [
            if (bar != null)
              ClipRect(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Align(
                    alignment: Alignment.topCenter,
                    heightFactor: widget.enabled ? _controller.value : 1.0,
                    child: child,
                  ),
                  child: bar,
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
