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

  const FastScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.items,
    this.sortBy,
    this.padding = EdgeInsets.zero,
    this.touchWidth = 28.0,
  });

  @override
  State<FastScrollbar> createState() => _FastScrollbarState();
}

class _PopupBadge {
  final IconData? icon;
  final String? text;

  const _PopupBadge({this.icon, this.text});
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

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

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
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
      return pos.hasContentDimensions && pos.maxScrollExtent > 0;
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
    if (notification.depth == 0) {
      if (notification.metrics.maxScrollExtent <= 0) {
        return false;
      }

      if (!_isDragging) {
        final newFraction = (notification.metrics.pixels /
                notification.metrics.maxScrollExtent)
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

  double _calculateThumbHeight(double trackHeight) {
    if (!_canScroll) return 48.0;
    final pos = widget.controller.position;
    final viewport = pos.viewportDimension;
    final maxScroll = pos.maxScrollExtent;
    final total = maxScroll + viewport;
    if (total <= 0) return 48.0;
    final ratio = (viewport / total).clamp(0.0, 1.0);
    return (trackHeight * ratio).clamp(44.0, trackHeight * 0.65);
  }

  String _formatPopupDate(DateTime dt) {
    final now = DateTime.now();
    final monthText = _monthNames[dt.month - 1];
    if (dt.year == now.year) {
      return '${dt.day} $monthText';
    }
    return '${dt.day} $monthText ${dt.year}';
  }

  _PopupBadge? _computePopupBadge(double fraction) {
    final items = widget.items;
    if (items == null || items.isEmpty) return null;

    final index =
        (fraction * (items.length - 1)).round().clamp(0, items.length - 1);
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
    double trackHeight,
    double topInset,
  ) {
    if (!_canScroll) return;

    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(details.globalPosition);
    final trackY = localPos.dy - topInset;

    final thumbHeight = _calculateThumbHeight(trackHeight);
    final travelDistance = trackHeight - thumbHeight;

    if (travelDistance <= 0) return;

    _autoHideTimer?.cancel();
    _isDragging = true;
    _fadeController.value = 1.0;

    final currentThumbTop = _scrollFraction * travelDistance;
    final isTouchingThumb = trackY >= currentThumbTop &&
        trackY <= currentThumbTop + thumbHeight;

    if (isTouchingThumb) {
      _dragTouchOffsetInThumb = trackY - currentThumbTop;
    } else {
      _dragTouchOffsetInThumb = thumbHeight / 2;
    }

    final targetThumbTop = trackY - _dragTouchOffsetInThumb;
    final fraction = (targetThumbTop / travelDistance).clamp(0.0, 1.0);

    _scrollFraction = fraction;
    final targetOffset = fraction * widget.controller.position.maxScrollExtent;
    widget.controller.jumpTo(targetOffset);
    _popupBadge = _computePopupBadge(fraction);

    ThumbnailConcurrency.imageLimiter.cancelTier(TaskPriority.visible);

    try {
      HapticFeedback.selectionClick();
    } catch (_) {}

    setState(() {});
  }

  void _handleDragUpdate(
    DragUpdateDetails details,
    double trackHeight,
    double topInset,
  ) {
    if (!_isDragging || !_canScroll) return;

    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(details.globalPosition);
    final trackY = localPos.dy - topInset;

    final thumbHeight = _calculateThumbHeight(trackHeight);
    final travelDistance = trackHeight - thumbHeight;

    if (travelDistance <= 0) return;

    final targetThumbTop = trackY - _dragTouchOffsetInThumb;
    final fraction = (targetThumbTop / travelDistance).clamp(0.0, 1.0);

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
    final thumbColor = scrollbarTheme.thumbColor?.resolve({
          if (_isDragging) WidgetState.dragged,
        }) ??
        (_isDragging ? cs.primary : cs.primary.withValues(alpha: 0.5));
    final trackColor = scrollbarTheme.trackColor?.resolve({
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
                final topInset = widget.padding.top;
                final bottomInset = widget.padding.bottom;
                final trackHeight =
                    constraints.maxHeight - topInset - bottomInset;

                if (trackHeight <= 0) return const SizedBox.shrink();

                final canScroll = _canScroll;
                final thumbHeight = _calculateThumbHeight(trackHeight);
                final travelDistance = trackHeight - thumbHeight;
                final thumbTop =
                    topInset + (_scrollFraction * travelDistance);

                return Stack(
                  key: _trackKey,
                  children: [
                    // Interactive edge strip covering the full track.
                    if (canScroll)
                      Positioned(
                        right: 0,
                        top: topInset,
                        height: trackHeight,
                        width: widget.touchWidth,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          dragStartBehavior: DragStartBehavior.down,
                          onVerticalDragStart: (e) =>
                              _handleDragStart(e, trackHeight, topInset),
                          onVerticalDragUpdate: (e) =>
                              _handleDragUpdate(e, trackHeight, topInset),
                          onVerticalDragEnd: _handleDragEnd,
                          onVerticalDragCancel: _handleDragCancel,
                          child: const SizedBox.expand(),
                        ),
                      ),

                    // Guide track line when actively dragging
                    if (_isDragging && canScroll)
                      Positioned(
                        right: 6.0,
                        top: topInset,
                        height: trackHeight,
                        width: 2.0,
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
                        right: _isDragging ? 2.0 : 3.0,
                        top: thumbTop,
                        child: IgnorePointer(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOut,
                              width: _isDragging ? 10.0 : 4.0,
                              height: thumbHeight,
                              decoration: BoxDecoration(
                                color: thumbColor,
                                borderRadius: BorderRadius.circular(
                                    _isDragging ? 5.0 : 2.0),
                                boxShadow: _isDragging
                                    ? [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.25),
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

                    // Section popup bubble
                    if (canScroll && _isDragging && _popupBadge != null)
                      Positioned(
                        right: widget.touchWidth + 8.0,
                        top: (thumbTop + thumbHeight / 2 - 24.0).clamp(
                          topInset + 8.0,
                          topInset + trackHeight - 48.0 - 8.0,
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