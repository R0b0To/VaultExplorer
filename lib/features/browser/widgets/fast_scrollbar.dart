import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/scroll_speed_tracker.dart';
import 'package:vaultexplorer/core/widgets/scroll_speed_scope.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

/// Sent up the tree when a [FastScrollbar] handle is grabbed or released.
///
/// Lets an ancestor that reacts to scroll direction (the file manager's
/// auto-hiding app bar) ignore the stream of `jumpTo` calls the handle makes
/// without every list, grid and masonry view having to forward a callback.
class FastScrollbarDragNotification extends Notification {
  const FastScrollbarDragNotification({required this.dragging});

  final bool dragging;
}

/// A gallery section shown on the fast-scroll timeline.
class FastScrollSection {
  const FastScrollSection({required this.offset, required this.label});

  /// Scroll offset where this section starts.
  final double offset;
  final String label;
}

/// A Material-style fast scroller inspired by MaterialFiles (AndroidFastScroll).
class FastScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final List<RawEntry>? items;
  final SortBy? sortBy;

  /// Builds timeline markers from the current gallery layout when dragging
  /// starts. Offsets are in the scrollable's content coordinates.
  final List<FastScrollSection> Function()? sectionsBuilder;
  final EdgeInsets padding;
  final double touchWidth;
  final Axis axis;

  /// Default width of the draggable edge strip. Views that sit under the
  /// scroller use it to keep their own pointer handling (drag-selection) out
  /// of that strip.
  static const double defaultTouchWidth = 28.0;

  /// Called with `true` when the handle is grabbed and `false` when it is
  /// released (or the drag is cancelled).
  ///
  /// Dragging the handle scrolls with repeated `jumpTo` calls, which look
  /// like fast user scrolling to any ancestor listening to scroll
  /// notifications. Owners that react to scroll direction (auto-hiding bars,
  /// for instance) can use this to ignore those jumps.
  final ValueChanged<bool>? onDragStateChanged;

  /// Becomes true while the content is moving too fast to read (a fling, or
  /// the handle being dragged across the list), and false again as soon as it
  /// slows down. The list below gets the same answer through
  /// [ScrollSpeedScope] (thumbnails wait on it); pass one to be told too.
  final ValueNotifier<bool>? scrollSpeed;

  const FastScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.items,
    this.sortBy,
    this.sectionsBuilder,
    this.padding = EdgeInsets.zero,
    this.touchWidth = defaultTouchWidth,
    this.axis = Axis.vertical,
    this.onDragStateChanged,
    this.scrollSpeed,
  });

  @override
  State<FastScrollbar> createState() => _FastScrollbarState();
}

class _PopupBadge {
  final IconData? icon;
  final String? text;

  const _PopupBadge({this.icon, this.text});
}

class _VisibleSectionMarker {
  const _VisibleSectionMarker({required this.section, required this.centerY});

  final FastScrollSection section;
  final double centerY;
}

class _FastScrollbarState extends State<FastScrollbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  Timer? _autoHideTimer;

  bool _isDragging = false;
  double _scrollFraction = 0.0;
  _PopupBadge? _popupBadge;
  List<FastScrollSection> _dragSections = const [];
  double _dragTouchOffsetInThumb = 0.0;
  final GlobalKey _trackKey = GlobalKey();

  /// `maxScrollExtent` captured when the current drag began. Only used to
  /// keep the thumb's length constant while it is held.
  double? _dragMaxExtent;

  /// Low-pass filtered `maxScrollExtent` for the current drag (see
  /// [_dragTargetOffset]).
  double? _dragSmoothedExtent;

  /// How far the filtered extent moves toward the live one per drag event.
  static const double _kExtentSmoothing = 0.15;

  bool _postFrameCallbackPending = false;
  final ValueNotifier<int> _overlayTick = ValueNotifier<int>(0);

  late final bool _ownsSpeedNotifier = widget.scrollSpeed == null;
  late final ValueNotifier<bool> _speedNotifier =
      widget.scrollSpeed ?? ValueNotifier<bool>(false);
  late final ScrollSpeedTracker _speedTracker = ScrollSpeedTracker(
    onFastChanged: _setFast,
  );
  final Stopwatch _clock = Stopwatch()..start();
  bool? _pendingFast;

  /// Publishes the speed verdict. It can arrive in the middle of a frame (a
  /// `jumpTo` made while the viewport is laying out), when tiles must not be
  /// told to rebuild: then it waits for the end of the frame.
  void _setFast(bool fast) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      final alreadyPending = _pendingFast != null;
      _pendingFast = fast;
      if (alreadyPending) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final value = _pendingFast;
        _pendingFast = null;
        if (mounted && value != null) _speedNotifier.value = value;
      });
      return;
    }
    _speedNotifier.value = fast;
  }

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
    _speedTracker.dispose();
    if (_isDragging) {
      // Never leave an owner thinking the handle is still held.
      _isDragging = false;
      _dragMaxExtent = null;
      _dragSmoothedExtent = null;
      widget.onDragStateChanged?.call(false);
    }
     _fadeController.dispose();
    _overlayTick.dispose();
    if (_ownsSpeedNotifier) _speedNotifier.dispose();
    super.dispose();
  }

  /// Safely updates scrollbar overlay state without rebuilding the wrapped scrollable.
  void _notifyOverlay([VoidCallback? fn]) {
    fn?.call();
    if (!mounted) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_postFrameCallbackPending) {
        _postFrameCallbackPending = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _postFrameCallbackPending = false;
          if (mounted) {
            _overlayTick.value++;
          }
        });
      }
    } else {
      _overlayTick.value++;
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
    if (!mounted) return;
    final position = widget.controller.hasClients
        ? widget.controller.position
        : null;
    if (position != null && position.hasPixels && position.hasViewportDimension) {
      // Every change of the offset counts, whoever made it: a finger, a fling,
      // or this handle's own jumpTo.
      _speedTracker.sample(
        position.pixels,
        position.viewportDimension,
        _clock.elapsed,
      );
    }
    if (!_canScroll) return;
    if (_isDragging && _scrollFraction >= 0.999) {
      if (widget.controller.position.pixels < widget.controller.position.maxScrollExtent) {
        widget.controller.jumpTo(widget.controller.position.maxScrollExtent);
      }
      return;
    }
    if (!_isDragging) {
      final pos = widget.controller.position;
      if (pos.hasContentDimensions && pos.maxScrollExtent > 0) {
        final newFraction = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
        if ((newFraction - _scrollFraction).abs() > 0.0005) {
          _notifyOverlay(() {
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

        if ((newFraction - _scrollFraction).abs() > 0.0005) {
          _notifyOverlay(() {
            _scrollFraction = newFraction;
          });
        }
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
    // Frozen while dragging so the thumb does not change size as the list
    // refines its own extent estimate.
    final maxScroll =
        (_isDragging ? _dragMaxExtent : null) ?? pos.maxScrollExtent;
    final total = maxScroll + viewport;
    if (total <= 0) return 48.0;
    final ratio = (viewport / total).clamp(0.0, 1.0);
    final maxThumbExtent = trackExtent * 0.65;
    final minThumbExtent = maxThumbExtent < 44.0 ? maxThumbExtent : 44.0;
    return (trackExtent * ratio).clamp(minThumbExtent, maxThumbExtent);
  }

  String _formatPopupDate(DateTime dt) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    if (dt.year == now.year) {
      return localizations.formatShortMonthDay(dt);
    }
    return localizations.formatShortDate(dt);
  }

  FastScrollSection? _sectionAt(double fraction) {
    if (_dragSections.isEmpty) return null;
    final position = widget.controller.hasClients
        ? widget.controller.position
        : null;
    final extent = _dragMaxExtent ?? position?.maxScrollExtent ?? 0.0;
    if (extent <= 0) return _dragSections.first;
    final offset =
        fraction * extent + (position?.viewportDimension ?? 0.0) / 2;
    var active = _dragSections.first;
    for (final section in _dragSections) {
      if (section.offset > offset) break;
      active = section;
    }
    return active;
  }

  _PopupBadge? _computePopupBadge(double fraction) {
    final section = _sectionAt(fraction);
    if (section != null) return _PopupBadge(text: section.label);

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
    _dragMaxExtent = widget.controller.position.maxScrollExtent;
    _dragSmoothedExtent = _dragMaxExtent;
    try {
      _dragSections = widget.sectionsBuilder?.call() ?? const [];
    } catch (_) {
      _dragSections = const [];
    }
    _isDragging = true;
    _notifyDragState(true);
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

    final previousFraction = _scrollFraction;
    _scrollFraction = fraction;
    widget.controller.jumpTo(_dragTargetOffset(fraction, previousFraction));
    _popupBadge = _computePopupBadge(fraction);

    ThumbnailConcurrency.imageLimiter.cancelTier(TaskPriority.visible);
    ThumbnailConcurrency.imageLimiter.cancelTier(TaskPriority.adjacent);
    ThumbnailConcurrency.videoLimiter.cancelTier(TaskPriority.visible);
    ThumbnailConcurrency.videoLimiter.cancelTier(TaskPriority.adjacent);

     try {
      // Fires on every index change while dragging the scrubber, so this is
      // deliberately unlogged — haptics are also unsupported on some
      // devices, which is an expected, non-actionable failure.
      HapticFeedback.selectionClick();
    } catch (_) {
      // Haptics are unavailable on some devices; non-actionable (see above).
    }

    _notifyOverlay();
  }

  void _notifyDragState(bool dragging) {
    widget.onDragStateChanged?.call(dragging);
    if (mounted) {
      FastScrollbarDragNotification(dragging: dragging).dispatch(context);
    }
  }

  /// Scroll offset for the thumb moving from [previousFraction] to
  /// [fraction] (both 0..1) during a drag.
  ///
  /// A list whose children differ in height (the markdown preview) only
  /// *estimates* its extent, from the children laid out around the viewport,
  /// and the estimate changes with every jump the handle makes. Reading
  /// `fraction * maxScrollExtent` therefore moved the content up and down
  /// even while the finger moved steadily.
  ///
  /// Instead the content moves *relative to where it is now*: the part of the
  /// track still ahead of the thumb is spread over the part of the content
  /// still ahead of the viewport (and the same behind it when dragging
  /// back). An error in the estimate then only changes how fast the content
  /// moves, never where it is, so nothing jumps, and the content can only
  /// reach its end when the thumb reaches the end of the track (exactly 0 and
  /// the live extent at the two ends). The extent is low-pass filtered so the
  /// speed does not flicker either. When the extent is exact (a plain list)
  /// this equals `fraction * maxScrollExtent`.
  double _dragTargetOffset(double fraction, double previousFraction) {
    final position = widget.controller.position;
    final live = position.maxScrollExtent;
    if (fraction >= 0.999) return live;
    if (fraction <= 0.0) return 0.0;

    final smoothed = _dragSmoothedExtent ?? live;
    final filtered = smoothed + (live - smoothed) * _kExtentSmoothing;
    _dragSmoothedExtent = filtered;
    // Never plan beyond what the list says exists, or the content would
    // reach its end before the thumb does.
    final extent = filtered < live ? filtered : live;

    final anchor = position.pixels.clamp(0.0, live);
    final double target;
    if (fraction > previousFraction) {
      // Share of the remaining track covered by this move.
      final share = (fraction - previousFraction) / (1 - previousFraction);
      final ahead = extent > anchor ? extent - anchor : 0.0;
      target = anchor + share * ahead;
    } else if (fraction < previousFraction) {
      final share = (previousFraction - fraction) / previousFraction;
      target = anchor - share * anchor;
    } else {
      target = anchor;
    }
    return target.clamp(0.0, live);
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

   if ((fraction - _scrollFraction).abs() > 0.0001 || fraction >= 0.999) {
      final previousFraction = _scrollFraction;
      _scrollFraction = fraction;
      widget.controller.jumpTo(_dragTargetOffset(fraction, previousFraction));
      _popupBadge = _computePopupBadge(fraction);
      _notifyOverlay();
    }
  }

  List<_VisibleSectionMarker> _visibleSectionMarkers({
    required double leadingInset,
    required double trackExtent,
    required double thumbStart,
    required double thumbExtent,
  }) {
    final maxScrollExtent = _dragMaxExtent;
    if (maxScrollExtent == null ||
        maxScrollExtent <= 0 ||
        _dragSections.length < 2 ||
        trackExtent < 120.0) {
      return const [];
    }

    final contentExtent =
        maxScrollExtent + widget.controller.position.viewportDimension;
    if (contentExtent <= 0) return const [];

    final minGap = (trackExtent / 14).clamp(28.0, 64.0).toDouble();
    final thumbCenter = thumbStart + thumbExtent / 2;
    final markers = <_VisibleSectionMarker>[];
    var lastCenterY = double.negativeInfinity;
    for (final section in _dragSections) {
      final fraction = (section.offset / contentExtent)
          .clamp(0.0, 1.0)
          .toDouble();
      final centerY = leadingInset + fraction * trackExtent;
      if ((centerY - thumbCenter).abs() < 36.0 ||
          centerY - lastCenterY < minGap) {
        continue;
      }
      markers.add(_VisibleSectionMarker(section: section, centerY: centerY));
      lastCenterY = centerY;
    }
    return markers;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    _dragMaxExtent = null;
    _dragSmoothedExtent = null;
    _notifyDragState(false);
    _popupBadge = null;
    _dragSections = const [];
    _startAutoHideTimer();
    _notifyOverlay();
  }

  void _handleDragCancel() {
    if (!_isDragging) return;
    _isDragging = false;
    _dragMaxExtent = null;
    _dragSmoothedExtent = null;
    _notifyDragState(false);
    _popupBadge = null;
    _dragSections = const [];
    _startAutoHideTimer();
    _notifyOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // This widget draws its own handle. On desktop the framework adds
          // a second, platform scrollbar to every scroll view, which showed
          // up as two handles side by side.
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ScrollSpeedScope(fast: _speedNotifier, child: widget.child),
          ),
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

                return ValueListenableBuilder<int>(
                  valueListenable: _overlayTick,
                  child: interactiveTrack,
                  builder: (context, _, cachedTrack) {
                    final cs = Theme.of(context).colorScheme;
                    final scrollbarTheme = Theme.of(context).scrollbarTheme;
                    final thumbColor =
                        scrollbarTheme.thumbColor?.resolve({
                          if (_isDragging) WidgetState.dragged,
                        }) ??
                        (_isDragging
                            ? cs.primary
                            : cs.primary.withValues(alpha: 0.5));
                    final trackColor =
                        scrollbarTheme.trackColor?.resolve({
                          if (_isDragging) WidgetState.dragged,
                        }) ??
                        cs.primary.withValues(alpha: 0.15);

                    final canScroll = _canScroll;
                    final thumbExtent = _calculateThumbExtent(trackExtent);
                    final travelDistance = trackExtent - thumbExtent;
                    final thumbStart =
                        leadingInset + (_scrollFraction * travelDistance);
                    final sectionMarkers =
                        isVertical && _isDragging && trackExtent >= 120.0
                        ? _visibleSectionMarkers(
                            leadingInset: leadingInset,
                            trackExtent: trackExtent,
                            thumbStart: thumbStart,
                            thumbExtent: thumbExtent,
                          )
                        : const <_VisibleSectionMarker>[];

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
                                  child: cachedTrack!,
                                )
                              : Positioned(
                                  bottom: 0,
                                  left: leadingInset,
                                  width: trackExtent,
                                  height: widget.touchWidth,
                                  child: cachedTrack!,
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

                    // Group locations along the track while the handle is held.
                    for (final marker in sectionMarkers)
                      Positioned(
                        right: widget.touchWidth + 8.0,
                        top: (marker.centerY - 11.0)
                            .clamp(leadingInset, leadingInset + trackExtent - 22.0)
                            .toDouble(),
                        child: IgnorePointer(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 128.0),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9.0,
                              vertical: 3.0,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surface.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(14.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 4.0,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              marker.section.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ),

                    // Section popup bubble (vertical lists only)
                    if (isVertical &&
                        canScroll &&
                        _isDragging &&
                        _popupBadge != null &&
                        trackExtent >= 64.0)
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
                              maxWidth: 220,
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
                                  Flexible(
                                    child: Text(
                                      _popupBadge!.text!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: cs.onPrimaryContainer,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
