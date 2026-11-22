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
  });

  @override
  State<ResizableSplitPane> createState() => _ResizableSplitPaneState();
}

class _ResizableSplitPaneState extends State<ResizableSplitPane> {
  late double _fraction = widget.initialFraction.clamp(0.05, 0.95).toDouble();
  late double _lastExpandedFraction = _fraction;
  bool _secondCollapsed = false;

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
  }

  @override
  void didUpdateWidget(covariant ResizableSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFraction != widget.initialFraction) {
      _fraction = widget.initialFraction.clamp(0.05, 0.95).toDouble();
      _lastExpandedFraction = _fraction;
      _secondCollapsed = false;
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
        final secondChild = _secondCollapsed && widget.collapseSecondOnResize
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
        final splitter = MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: horizontal
                ? (details) => _resize(details.delta.dx, available)
                : null,
            onVerticalDragUpdate: horizontal
                ? null
                : (details) => _resize(details.delta.dy, available),
            child: SizedBox(
              width: horizontal ? widget.dividerExtent : double.infinity,
              height: horizontal ? double.infinity : widget.dividerExtent,
              child: Center(
                child: Container(
                  width: horizontal ? 1 : 32,
                  height: horizontal ? 32 : 1,
                  color: cs.outlineVariant,
                ),
              ),
            ),
          ),
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
