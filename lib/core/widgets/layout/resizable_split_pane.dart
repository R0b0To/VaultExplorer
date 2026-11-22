import 'package:material_ui/material_ui.dart';

/// Splits the available space between two children with a draggable divider.
///
/// [first] keeps the leading side of the split (left for a horizontal split,
/// top for a vertical split). A null [second] makes this a transparent
/// wrapper, which lets callers keep one tree for both split and unsplit
/// layouts.
class ResizableSplitPane extends StatefulWidget {
  final Axis axis;
  final Widget first;
  final Widget? second;
  final double initialFraction;
  final double minFirstExtent;
  final double minSecondExtent;
  final double? maxFirstExtent;
  final double dividerExtent;
  final ValueChanged<double>? onFirstExtentChanged;
  final ValueChanged<double>? onFractionChanged;
  final bool collapseSecondOnResize;
  final double collapsedSecondExtent;
  final double collapseThreshold;
  final String collapsedSecondTooltip;

  /// With [collapseSecondOnResize]: whether the second child is folded away.
  /// When non-null the owner decides (every change the user makes is reported
  /// through [onSecondCollapsedChanged], and a new value from the owner is
  /// applied); when null the pane keeps this state itself.
  final bool? secondCollapsed;
  final ValueChanged<bool>? onSecondCollapsedChanged;

  /// With [collapseSecondOnResize]: tapping the divider folds / unfolds the
  /// second child (dragging it still resizes), and the divider draws a handle
  /// with an arrow showing which way a tap moves it.
  final bool toggleSecondOnHandleTap;

  const ResizableSplitPane({
    super.key,
    required this.axis,
    required this.first,
    this.second,
    this.initialFraction = 0.5,
    this.minFirstExtent = 120,
    this.minSecondExtent = 120,
    this.maxFirstExtent,
    this.dividerExtent = 8,
    this.onFirstExtentChanged,
    this.onFractionChanged,
    this.collapseSecondOnResize = false,
    this.collapsedSecondExtent = 28,
    this.collapseThreshold = 84,
    this.collapsedSecondTooltip = 'Expand pane',
    this.secondCollapsed,
    this.onSecondCollapsedChanged,
    this.toggleSecondOnHandleTap = false,
  });

  @override
  State<ResizableSplitPane> createState() => _ResizableSplitPaneState();
}

class _ResizableSplitPaneState extends State<ResizableSplitPane> {
  late double _fraction = widget.initialFraction.clamp(0.05, 0.95).toDouble();
  late double _lastExpandedFraction = _fraction;
  late bool _secondCollapsed =
      widget.collapseSecondOnResize && (widget.secondCollapsed ?? false);

  double _availableExtent(BoxConstraints constraints) {
    final extent = widget.axis == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    return (extent - widget.dividerExtent)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  double _firstExtent(double available) {
    if (_secondCollapsed && widget.collapseSecondOnResize) {
      return (available - widget.collapsedSecondExtent)
          .clamp(0.0, available)
          .toDouble();
    }
    var min = widget.minFirstExtent;
    var max = available - widget.minSecondExtent;
    final maxFirst = widget.maxFirstExtent;
    if (maxFirst != null) max = max.clamp(0.0, maxFirst).toDouble();
    if (max < min) return available / 2;
    return (available * _fraction).clamp(min, max).toDouble();
  }

  void _resize(double delta, double available) {
    if (available <= 0) return;
    final minFirst = widget.minFirstExtent.clamp(0.0, available).toDouble();
    final secondExtentFloor = widget.collapseSecondOnResize
        ? widget.collapsedSecondExtent
        : widget.minSecondExtent;
    var maxFirstExtent = (available - secondExtentFloor)
        .clamp(minFirst, available)
        .toDouble();
    final configuredMax = widget.maxFirstExtent;
    if (configuredMax != null && configuredMax < maxFirstExtent) {
      maxFirstExtent = configuredMax.clamp(minFirst, available).toDouble();
    }
    final currentFirst = _secondCollapsed && widget.collapseSecondOnResize
        ? available - widget.collapsedSecondExtent
        : _firstExtent(available);
    final nextFirst = (currentFirst + delta)
        .clamp(minFirst, maxFirstExtent)
        .toDouble();
    final nextSecond = available - nextFirst;
    final shouldCollapse =
        widget.collapseSecondOnResize && nextSecond <= widget.collapseThreshold;
    final wasCollapsed = _secondCollapsed;
    setState(() {
      if (shouldCollapse) {
        if (!_secondCollapsed) _lastExpandedFraction = _fraction;
        _secondCollapsed = true;
        _fraction = (available - widget.collapsedSecondExtent) / available;
      } else {
        _secondCollapsed = false;
        _fraction = nextFirst / available;
        _lastExpandedFraction = _fraction;
      }
    });
    widget.onFirstExtentChanged?.call(available * _fraction);
    widget.onFractionChanged?.call(_fraction);
    if (wasCollapsed != _secondCollapsed) {
      widget.onSecondCollapsedChanged?.call(_secondCollapsed);
    }
  }

  void _collapseSecond(double available) {
    if (_secondCollapsed || !widget.collapseSecondOnResize || available <= 0) {
      return;
    }
    setState(() {
      _lastExpandedFraction = _firstExtent(available) / available;
      _secondCollapsed = true;
      _fraction = (available - widget.collapsedSecondExtent) / available;
    });
    widget.onFirstExtentChanged?.call(available * _fraction);
    widget.onFractionChanged?.call(_fraction);
    widget.onSecondCollapsedChanged?.call(true);
  }

  void _toggleSecond(double available) {
    if (_secondCollapsed) {
      _expandSecond(available);
    } else {
      _collapseSecond(available);
    }
  }

  void _expandSecond(double available) {
    if (!_secondCollapsed || available <= 0) return;
    final minFirst = widget.minFirstExtent.clamp(0.0, available).toDouble();
    final maxFirst = (available - widget.minSecondExtent)
        .clamp(minFirst, available)
        .toDouble();
    setState(() {
      _secondCollapsed = false;
      _fraction =
          (_lastExpandedFraction * available)
              .clamp(minFirst, maxFirst)
              .toDouble() /
          available;
      _lastExpandedFraction = _fraction;
    });
    widget.onFirstExtentChanged?.call(available * _fraction);
    widget.onFractionChanged?.call(_fraction);
    widget.onSecondCollapsedChanged?.call(false);
  }

  @override
  void didUpdateWidget(covariant ResizableSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFraction != widget.initialFraction) {
      _fraction = widget.initialFraction.clamp(0.05, 0.95).toDouble();
      _lastExpandedFraction = _fraction;
      _secondCollapsed = false;
    }
    // The owner folded or unfolded the second child (another pane, a restored
    // setting): follow it without reporting it back.
    final owned = widget.secondCollapsed;
    if (owned != null &&
        widget.collapseSecondOnResize &&
        owned != _secondCollapsed) {
      if (owned) _lastExpandedFraction = _fraction;
      _secondCollapsed = owned;
      if (!owned) _fraction = _lastExpandedFraction;
    }
  }

  @override
  Widget build(BuildContext context) {
    final second = widget.second;
    if (second == null) return widget.first;

    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = _availableExtent(constraints);
        final firstExtent = _firstExtent(available);
        final horizontal = widget.axis == Axis.horizontal;
        final collapsed = _secondCollapsed && widget.collapseSecondOnResize;
        final toggleOnTap =
            widget.collapseSecondOnResize && widget.toggleSecondOnHandleTap;
        final secondChild = collapsed && widget.collapsedSecondExtent <= 0
            // Nothing is left of it but the divider, which unfolds it again.
            ? const SizedBox.shrink()
            : collapsed
            ? Tooltip(
                message: widget.collapsedSecondTooltip,
                child: Material(
                  color: cs.surfaceContainerLow,
                  child: InkWell(
                    onTap: () => _expandSecond(available),
                    child: SizedBox.expand(
                      child: Center(
                        child: Icon(
                          horizontal
                              ? Icons.chevron_left_rounded
                              : Icons.expand_less_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : second;
        final splitter = _SplitHandle(
          horizontal: horizontal,
          extent: widget.dividerExtent,
          showToggle: toggleOnTap,
          collapsed: collapsed,
          tooltip: widget.collapsedSecondTooltip,
          onDelta: (delta) => _resize(delta, available),
          onTap: toggleOnTap ? () => _toggleSecond(available) : null,
        );

        if (horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: firstExtent, child: widget.first),
              splitter,
              Expanded(child: secondChild),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: firstExtent, child: widget.first),
            splitter,
            Expanded(child: secondChild),
          ],
        );
      },
    );
  }
}

/// The draggable divider. It tints while the pointer is over it or it is being
/// dragged. With [showToggle] it also draws a small handle with an arrow (the
/// direction a tap moves the second child: away when it is shown, back when
/// it is folded), and a tap reports through [onTap].
class _SplitHandle extends StatefulWidget {
  const _SplitHandle({
    required this.horizontal,
    required this.extent,
    required this.showToggle,
    required this.collapsed,
    required this.tooltip,
    required this.onDelta,
    required this.onTap,
  });

  final bool horizontal;
  final double extent;
  final bool showToggle;
  final bool collapsed;
  final String tooltip;
  final ValueChanged<double> onDelta;
  final VoidCallback? onTap;

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  bool _hovering = false;
  bool _dragging = false;

  void _setDragging(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
  }

  IconData get _arrow {
    // The second child is below (vertical split) or to the right (horizontal
    // split) of the divider: folding moves it that way.
    if (widget.horizontal) {
      return widget.collapsed
          ? Icons.keyboard_arrow_left_rounded
          : Icons.keyboard_arrow_right_rounded;
    }
    return widget.collapsed
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final horizontal = widget.horizontal;
    final active = _hovering || _dragging;

    final Widget mark;
    if (widget.showToggle) {
      mark = Container(
        width: horizontal ? 10 : 36,
        height: horizontal ? 36 : 10,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.22)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          _arrow,
          size: 10,
          color: active ? cs.primary : cs.onSurfaceVariant,
        ),
      );
    } else {
      mark = Container(
        width: horizontal ? 1 : 32,
        height: horizontal ? 32 : 1,
        color: active ? cs.primary : cs.outlineVariant,
      );
    }

    Widget handle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onHorizontalDragStart: horizontal ? (_) => _setDragging(true) : null,
      onHorizontalDragUpdate: horizontal
          ? (details) => widget.onDelta(details.delta.dx)
          : null,
      onHorizontalDragEnd: horizontal ? (_) => _setDragging(false) : null,
      onHorizontalDragCancel: horizontal ? () => _setDragging(false) : null,
      onVerticalDragStart: horizontal ? null : (_) => _setDragging(true),
      onVerticalDragUpdate: horizontal
          ? null
          : (details) => widget.onDelta(details.delta.dy),
      onVerticalDragEnd: horizontal ? null : (_) => _setDragging(false),
      onVerticalDragCancel: horizontal ? null : () => _setDragging(false),
      child: Container(
        width: horizontal ? widget.extent : double.infinity,
        height: horizontal ? double.infinity : widget.extent,
        color: active ? cs.primary.withValues(alpha: 0.08) : null,
        alignment: Alignment.center,
        child: mark,
      ),
    );
    if (widget.showToggle) {
      handle = Tooltip(message: widget.tooltip, child: handle);
    }
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: handle,
    );
  }
}
