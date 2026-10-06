import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

/// A Material-style fast scroller inspired by MaterialFiles (AndroidFastScroll).
class FastScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final List<RawEntry>? items;
  final SortBy? sortBy;
  final EdgeInsets padding;
  final double touchWidth;
  final Axis axis;

  const FastScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.items,
    this.sortBy,
    this.padding = EdgeInsets.zero,
    this.touchWidth = 28.0,
    this.axis = Axis.vertical,
  });

  @override
  State<FastScrollbar> createState() => _FastScrollbarState();
}

class _PopupBadge {
  final IconData? icon;
  final String? text;

  const _PopupBadge({this.icon, this.text});
}

class _FastScrollbarState extends State<FastScrollbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  Timer? _autoHideTimer;

  bool _isDragging = false;
  double _scrollFraction = 0.0;
  _PopupBadge? _popupBadge;
  double _dragTouchOffsetInThumb = 0.0;
  final GlobalKey _trackKey = GlobalKey();

  bool _postFrameCallbackPending = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    // FadeTransition handles animating its own opacity without needing setState rebuilds.
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(covariant FastScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    widget.controller.removeListener(_onControllerChange);
    _fadeController.dispose();
    super.dispose();
  }

  /// Safely runs [fn] and schedules a rebuild without throwing "Build scheduled during frame".
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      fn();
      if (!_postFrameCallbackPending) {
        _postFrameCallbackPending = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _postFrameCallbackPending = false;
          if (mounted) {
            setState(() {});
          }
        });
      }
    } else {
      setState(fn);
    }
  }

  bool get _canScroll {
    if (!widget.controller.hasClients) return false;
    try {
      final pos = widget.controller.position;
      return pos.axis == widget.axis &&
          pos.hasContentDimensions &&
          pos.maxScrollExtent > 0;
    } catch (_) {
      return false;
    }
  }

  void _onControllerChange() {
    if (!_isDragging && mounted && _canScroll) {
      final pos = widget.controller.position;
      if (pos.hasContentDimensions && pos.maxScrollExtent > 0) {
        final newFraction = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
        if ((newFraction - _scrollFraction).abs() > 0.0005) {
          _safeSetState(() {
            _scrollFraction = newFraction;
          });
        }
      }
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == widget.axis) {
      if (notification.metrics.maxScrollExtent <= 0) {
        return false;
      }

      if (!_isDragging) {
        final newFraction =
            (notification.metrics.pixels / notification.metrics.maxScrollExtent)
                .clamp(0.0, 1.0);

        if (notification is ScrollUpdateNotification ||
            notification is ScrollStartNotification) {
          _showThumb(autoHide: true);
        } else if (notification is ScrollEndNotification) {
          _startAutoHideTimer();
        }

        _safeSetState(() {
          _scrollFraction = newFraction;
        });
      }
    }
    return false;
  }

  void _showThumb({required bool autoHide}) {
    _autoHideTimer?.cancel();
    if (_fadeController.value < 1.0) {
      _fadeController.forward();
    }
    if (autoHide) {
      _startAutoHideTimer();
    }
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_isDragging) {
        _fadeController.reverse();
      }
    });
  }

  double _calculateThumbExtent(double trackExtent) {
    if (!_canScroll) return 48.0;
    final pos = widget.controller.position;
    final viewport = pos.viewportDimension;
    final maxScroll = pos.maxScrollExtent;
    final total = maxScroll + viewport;
    if (total <= 0) return 48.0;
    final ratio = (viewport / total).clamp(0.0, 1.0);
    return (trackExtent * ratio).clamp(44.0, trackExtent * 0.65);
  }

  String _formatPopupDate(DateTime dt) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    if (dt.year == now.year) {
      return localizations.formatShortMonthDay(dt);
    }
    return localizations.formatShortDate(dt);
  }

  _PopupBadge? _computePopupBadge(double fraction) {
    final items = widget.items;
    if (items == null || items.isEmpty) return null;

    final index = (fraction * (items.length - 1)).round().clamp(
      0,
      items.length - 1,
    );
    final entry = items[index];

    if (entry.isDir) {
      if (widget.sortBy == SortBy.name || widget.sortBy == null) {
        return _PopupBadge(
          icon: Icons.folder_rounded,
          text: entry.name.isNotEmpty
              ? entry.name.characters.first.toUpperCase()
              : null,
        );
      }
      if (widget.sortBy == SortBy.date) {
        final dt = entry.modifiedAt;
        if (dt != null) {
          return _PopupBadge(
            icon: Icons.folder_rounded,
            text: _formatPopupDate(dt),
          );
        }
      }
      return const _PopupBadge(icon: Icons.folder_rounded);
    }

    switch (widget.sortBy) {
      case SortBy.name:
      case null:
        if (entry.name.isEmpty) return null;
        return _PopupBadge(text: entry.name.characters.first.toUpperCase());
      case SortBy.extension:
        if (entry.extension.isNotEmpty) {
          return _PopupBadge(text: entry.extension.toUpperCase());
        }
        return const _PopupBadge(text: '•');
      case SortBy.size:
        return _PopupBadge(text: formatBytes(entry.sizeBytes));
      case SortBy.date:
        final dt = entry.modifiedAt;
        if (dt != null) {
          return _PopupBadge(text: _formatPopupDate(dt));
        }
        return const _PopupBadge(text: '•');
    }
  }

  void _handleDragStart(
    DragStartDetails details,
    double trackExtent,
    double leadingInset,
  ) {
    if (!_canScroll) return;

    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(details.globalPosition);
    final trackPosition =
        (widget.axis == Axis.vertical ? localPos.dy : localPos.dx) -
        leadingInset;

    final thumbExtent = _calculateThumbExtent(trackExtent);
    final travelDistance = trackExtent - thumbExtent;

    if (travelDistance <= 0) return;

    _autoHideTimer?.cancel();
    _isDragging = true;
    _fadeController.value = 1.0;

    final currentThumbTop = _scrollFraction * travelDistance;
    final isTouchingThumb =
        trackPosition >= currentThumbTop &&
        trackPosition <= currentThumbTop + thumbExtent;

    if (isTouchingThumb) {
      _dragTouchOffsetInThumb = trackPosition - currentThumbTop;
    } else {
      _dragTouchOffsetInThumb = thumbExtent / 2;
    }

    final targetThumbStart = trackPosition - _dragTouchOffsetInThumb;
    final fraction = (targetThumbStart / travelDistance).clamp(0.0, 1.0);

    _scrollFraction = fraction;
    final targetOffset = fraction * widget.controller.position.maxScrollExtent;
    widget.controller.jumpTo(targetOffset);
    _popupBadge = _computePopupBadge(fraction);

    ThumbnailConcurrency.imageLimiter.cancelTier(TaskPriority.visible);

    try {
      // Fires on every index change while dragging the scrubber, so this is
      // deliberately unlogged — haptics are also unsupported on some
      // devices, which is an expected, non-actionable failure.
      HapticFeedback.selectionClick();
    } catch (_) {
      // Haptics are unavailable on some devices; non-actionable (see above).
    }

    setState(() {});
  }

  void _handleDragUpdate(
    DragUpdateDetails details,
    double trackExtent,
    double leadingInset,
  ) {
    if (!_isDragging || !_canScroll) return;

    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(details.globalPosition);
    final trackPosition =
        (widget.axis == Axis.vertical ? localPos.dy : localPos.dx) -
        leadingInset;

    final thumbExtent = _calculateThumbExtent(trackExtent);
    final travelDistance = trackExtent - thumbExtent;

    if (travelDistance <= 0) return;

    final targetThumbStart = trackPosition - _dragTouchOffsetInThumb;
    final fraction = (targetThumbStart / travelDistance).clamp(0.0, 1.0);

    if ((fraction - _scrollFraction).abs() > 0.0001) {
      _scrollFraction = fraction;
      final targetOffset =
          fraction * widget.controller.position.maxScrollExtent;
      widget.controller.jumpTo(targetOffset);
      _popupBadge = _computePopupBadge(fraction);
      ThumbnailConcurrency.imageLimiter.cancelTier(TaskPriority.visible);
      setState(() {});
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    _popupBadge = null;
    _startAutoHideTimer();
    setState(() {});
  }

  void _handleDragCancel() {
    if (!_isDragging) return;
    _isDragging = false;
    _popupBadge = null;
    _startAutoHideTimer();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scrollbarTheme = Theme.of(context).scrollbarTheme;
    final thumbColor =
        scrollbarTheme.thumbColor?.resolve({
          if (_isDragging) WidgetState.dragged,
        }) ??
        (_isDragging ? cs.primary : cs.primary.withValues(alpha: 0.5));
    final trackColor =
        scrollbarTheme.trackColor?.resolve({
          if (_isDragging) WidgetState.dragged,
        }) ??
        cs.primary.withValues(alpha: 0.15);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isVertical = widget.axis == Axis.vertical;
                final leadingInset = isVertical
                    ? widget.padding.top
                    : widget.padding.left;
                final trailingInset = isVertical
                    ? widget.padding.bottom
                    : widget.padding.right;
                final trackExtent = isVertical
                    ? constraints.maxHeight - leadingInset - trailingInset
                    : constraints.maxWidth - leadingInset - trailingInset;

                if (trackExtent <= 0) return const SizedBox.shrink();

                final canScroll = _canScroll;
                final thumbExtent = _calculateThumbExtent(trackExtent);
                final travelDistance = trackExtent - thumbExtent;
                final thumbStart =
                    leadingInset + (_scrollFraction * travelDistance);

                final interactiveTrack = GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  dragStartBehavior: DragStartBehavior.down,
                  onVerticalDragStart: isVertical
                      ? (e) => _handleDragStart(e, trackExtent, leadingInset)
                      : null,
                  onVerticalDragUpdate: isVertical
                      ? (e) => _handleDragUpdate(e, trackExtent, leadingInset)
                      : null,
                  onHorizontalDragStart: !isVertical
                      ? (e) => _handleDragStart(e, trackExtent, leadingInset)
                      : null,
                  onHorizontalDragUpdate: !isVertical
                      ? (e) => _handleDragUpdate(e, trackExtent, leadingInset)
                      : null,
                  onVerticalDragEnd: isVertical ? _handleDragEnd : null,
                  onVerticalDragCancel: isVertical ? _handleDragCancel : null,
                  onHorizontalDragEnd: !isVertical ? _handleDragEnd : null,
                  onHorizontalDragCancel: !isVertical
                      ? _handleDragCancel
                      : null,
                  child: const SizedBox.expand(),
                );

                return Stack(
                  key: _trackKey,
                  children: [
                    // Interactive edge strip covering the full track.
                    if (canScroll)
                      isVertical
                          ? Positioned(
                              right: 0,
                              top: leadingInset,
                              height: trackExtent,
                              width: widget.touchWidth,
                              child: interactiveTrack,
                            )
                          : Positioned(
                              bottom: 0,
                              left: leadingInset,
                              width: trackExtent,
                              height: widget.touchWidth,
                              child: interactiveTrack,
                            ),

                    // Guide track line when actively dragging
                    if (_isDragging && canScroll)
                      isVertical
                          ? Positioned(
                              right: 6.0,
                              top: leadingInset,
                              height: trackExtent,
                              width: 2.0,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: trackColor,
                                    borderRadius: BorderRadius.circular(1.0),
                                  ),
                                ),
                              ),
                            )
                          : Positioned(
                              bottom: 6.0,
                              left: leadingInset,
                              width: trackExtent,
                              height: 2.0,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: trackColor,
                                    borderRadius: BorderRadius.circular(1.0),
                                  ),
                                ),
                              ),
                            ),

                    // Scrollbar thumb indicator
                    if (canScroll)
                      Positioned(
                        right: isVertical ? (_isDragging ? 2.0 : 3.0) : null,
                        bottom: isVertical ? null : (_isDragging ? 2.0 : 3.0),
                        top: isVertical ? thumbStart : null,
                        left: isVertical ? null : thumbStart,
                        child: IgnorePointer(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOut,
                              width: isVertical
                                  ? (_isDragging ? 10.0 : 4.0)
                                  : thumbExtent,
                              height: isVertical
                                  ? thumbExtent
                                  : (_isDragging ? 10.0 : 4.0),
                              decoration: BoxDecoration(
                                color: thumbColor,
                                borderRadius: BorderRadius.circular(
                                  _isDragging ? 5.0 : 2.0,
                                ),
                                boxShadow: _isDragging
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(-1, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Section popup bubble (vertical lists only)
                    if (isVertical &&
                        canScroll &&
                        _isDragging &&
                        _popupBadge != null)
                      Positioned(
                        right: widget.touchWidth + 8.0,
                        top: (thumbStart + thumbExtent / 2 - 24.0).clamp(
                          leadingInset + 8.0,
                          leadingInset + trackExtent - 48.0 - 8.0,
                        ),
                        child: IgnorePointer(
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 54,
                              minHeight: 44,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_popupBadge!.icon != null)
                                  Icon(
                                    _popupBadge!.icon,
                                    size: 22,
                                    color: cs.onPrimaryContainer,
                                  ),
                                if (_popupBadge!.icon != null &&
                                    _popupBadge!.text != null)
                                  const SizedBox(width: 6),
                                if (_popupBadge!.text != null)
                                  Text(
                                    _popupBadge!.text!,
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
