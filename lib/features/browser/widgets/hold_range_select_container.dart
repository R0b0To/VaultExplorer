import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// A custom scale recognizer that prioritizes pinch-to-zoom over single-finger scrolling.
/// A custom scale recognizer that prioritizes pinch-to-zoom over single-finger scrolling
/// without leaking pointer IDs.
class _PinchScaleGestureRecognizer extends ScaleGestureRecognizer {
  _PinchScaleGestureRecognizer({super.debugOwner});

  final Set<int> _activePointers = <int>{};
  VoidCallback? onPinchEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _activePointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void stopTrackingPointer(int pointer) {
    _activePointers.remove(pointer);
    super.stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointers.clear();
    super.didStopTrackingLastPointer(pointer);
    onPinchEnd?.call();
  }

  @override
  void rejectGesture(int pointer) {
    _activePointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _activePointers.clear();
    super.dispose();
  }
}

/// The hold-to-select recognizer.
///
/// A stock [LongPressGestureRecognizer] with a shorter deadline than the
/// tiles' own (500 ms) one, and a per-pointer filter so it only takes part in
/// the gesture arena for touches that land on a real, non-placeholder item.
///
/// Living in the arena is what makes tap and hold mutually exclusive: if the
/// finger lifts before [duration], the tile's tap wins and nothing is
/// selected; once [duration] passes this recognizer accepts, which rejects the
/// tile's tap (and its own, later, long-press), so the release can never fire
/// a tap that toggles the fresh selection back off.
class _HoldSelectGestureRecognizer extends LongPressGestureRecognizer {
  _HoldSelectGestureRecognizer({super.duration, super.debugOwner});

  /// Returns whether a touch starting with [PointerDownEvent] may become a hold.
  bool Function(PointerDownEvent event)? pointerFilter;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    final filter = pointerFilter;
    if (filter != null && !filter(event)) return false;
    return super.isPointerAllowed(event);
  }
}

/// Carries the item index and [RawEntry] model in the render tree for
/// high-performance hit testing during hold range selection.
class HoldSelectMetadata {
  final int index;
  final RawEntry entry;

  const HoldSelectMetadata({
    required this.index,
    required this.entry,
  });
}

/// Wraps an individual item (file or directory cell/tile) in a zero-overhead
/// [MetaData] box so [HoldRangeSelectContainer] can locate it in $O(1)$ time during
/// hold gestures.
class HoldSelectableItem extends StatelessWidget {
  final int index;
  final RawEntry entry;
  final Widget child;

  const HoldSelectableItem({
    super.key,
    required this.index,
    required this.entry,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MetaData(
      metaData: HoldSelectMetadata(index: index, entry: entry),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}

/// How long a finger must rest on an item before hold-select fires.
///
/// Must stay *below* [kLongPressTimeout] (500 ms). Every tile also carries a
/// long-press recognizer with that deadline (an `InkWell` `onLongPress`, a
/// no-op in the browser views); the hold recognizer has to accept first, since
/// the first recognizer to accept wins the arena, and a longer delay here
/// would let the tile's no-op win and hold-select never fire.
const Duration kHoldSelectDelay = Duration(milliseconds: 400);

/// A container that coordinates hold-to-select and hold-to-range-select across
/// any layout (List, Compact, Grid, Masonry) without interfering with native scrolling.
///
/// Features:
///  • Hold an item when [isSelectionMode] is false (selects initial item and enters selection mode).
///  • Hold another item when [isSelectionMode] is true (selects all items in range between anchor and held item).
///  • Moving the finger (past the touch slop) before the hold completes hands
///    the touch to native scrolling instead.
///  • A release before the hold completes is a plain tap; a completed hold
///    selects and the release does not also fire a tap (arena-exclusive).
///  • Seamless coexistence with pinch-to-zoom (2+ fingers).
class HoldRangeSelectContainer extends StatefulWidget {
  final Widget child;
  final List<RawEntry> items;
  final Set<RawEntry> selectedItems;
  final bool isSelectionMode;
  final ValueChanged<Set<RawEntry>> onSelectionChanged;
  final void Function(RawEntry entry)? onLongPressSelect;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;
  final Duration holdDelay;

  const HoldRangeSelectContainer({
    super.key,
    required this.child,
    required this.items,
    required this.selectedItems,
    required this.isSelectionMode,
    required this.onSelectionChanged,
    this.onLongPressSelect,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.holdDelay = kHoldSelectDelay,
  });

  @override
  State<HoldRangeSelectContainer> createState() =>
      _HoldRangeSelectContainerState();
}

class _HoldRangeSelectContainerState extends State<HoldRangeSelectContainer> {
  final GlobalKey _containerKey = GlobalKey();

  Offset? _pointerDownPosition;
  HoldSelectMetadata? _pointerDownItem;
  RawEntry? _lastInteractedEntry;
  int? _lastInteractedIndex;
  bool _hasMoved = false;
  final Set<int> _downPointers = <int>{};
  final Set<int> _scrollInterruptPointers = <int>{};
  bool _scaleStarted = false;
  bool _isScrollActive = false;
  bool _scrollEndPending = false;
  bool _scrollEndResetScheduled = false;

  int? get _effectiveAnchorIndex {
    if (_lastInteractedEntry != null &&
        widget.selectedItems.contains(_lastInteractedEntry)) {
      final idx = widget.items.indexOf(_lastInteractedEntry!);
      if (idx >= 0) return idx;
    }
    if (_lastInteractedIndex != null &&
        _lastInteractedIndex! >= 0 &&
        _lastInteractedIndex! < widget.items.length &&
        widget.selectedItems.contains(widget.items[_lastInteractedIndex!])) {
      return _lastInteractedIndex;
    }
    if (widget.selectedItems.isEmpty) return null;
    final lastSelected = widget.selectedItems.last;
    final idx = widget.items.indexOf(lastSelected);
    return idx >= 0 ? idx : null;
  }

  @override
  void initState() {
    super.initState();
    assert(
      widget.holdDelay < kLongPressTimeout,
      'holdDelay must be shorter than kLongPressTimeout so the hold recognizer '
      'wins the gesture arena before the tiles\' own long-press does.',
    );
  }

  @override
  void didUpdateWidget(covariant HoldRangeSelectContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelectionMode || widget.selectedItems.isEmpty) {
      _lastInteractedIndex = null;
      _lastInteractedEntry = null;
    }
  }

  HoldSelectMetadata? _findItemAt(Offset globalPosition) {
    final renderBox =
        _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize || !renderBox.attached) {
      return null;
    }
    final localPosition = renderBox.globalToLocal(globalPosition);
    if (!renderBox.paintBounds.contains(localPosition)) return null;

    final result = BoxHitTestResult();
    renderBox.hitTest(result, position: localPosition);
    for (final hit in result.path) {
      final target = hit.target;
      if (target is RenderMetaData && target.metaData is HoldSelectMetadata) {
        return target.metaData as HoldSelectMetadata;
      }
    }
    return null;
  }

  // ── Gestures ───────────────────────────────────────────────────────────────

  /// Pointer filter for [_HoldSelectGestureRecognizer]: only touches that land
  /// on a real item may become a hold. A press that interrupts scrolling only
  /// stops the scroll; it must be released before a hold can select an item.
  bool _shouldTrackHold(PointerDownEvent event) {
    if (_isScrollActive || _scrollEndPending) {
      _scrollInterruptPointers.add(event.pointer);
      return false;
    }

    final item = _findItemAt(event.position);
    return item != null && !item.entry.isPlaceholder;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _isScrollActive = true;
      _scrollEndPending = false;
    } else if (notification is ScrollEndNotification) {
      _isScrollActive = false;
      _scrollEndPending = true;

      // A press can itself end a ballistic scroll. Keep the activity visible
      // through the current frame so that press is still treated as the one
      // that stopped scrolling, even if ScrollEnd arrives before its hold
      // recognizer checks the pointer.
      if (!_scrollEndResetScheduled) {
        _scrollEndResetScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollEndPending = false;
          _scrollEndResetScheduled = false;
        });
      }
    }

    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _downPointers.add(event.pointer);
    if (_downPointers.length > 1) return;

    _hasMoved = false;
    _pointerDownPosition = event.position;
    _pointerDownItem = _findItemAt(event.position);
  }

  /// Called by the hold recognizer once the finger has rested on the item for
  /// the full hold delay (the arena has already been won at this point).
  void _handleHoldStart(LongPressStartDetails details) {
    if (!mounted || _downPointers.length != 1) return;
    final touchedItem = _pointerDownItem;
    if (touchedItem == null || touchedItem.entry.isPlaceholder) return;

    if (!widget.isSelectionMode) {
      _lastInteractedIndex = touchedItem.index;
      _lastInteractedEntry = touchedItem.entry;
      HapticFeedback.selectionClick();
      widget.onLongPressSelect?.call(touchedItem.entry);
    } else {
      final anchorIndex = _effectiveAnchorIndex;
      if (anchorIndex != null && anchorIndex != touchedItem.index) {
        final minIndex = math.min(anchorIndex, touchedItem.index);
        final maxIndex = math.max(anchorIndex, touchedItem.index);

        final newSelection = Set<RawEntry>.from(widget.selectedItems);
        for (int i = minIndex; i <= maxIndex && i < widget.items.length; i++) {
          if (!widget.items[i].isPlaceholder) {
            newSelection.add(widget.items[i]);
          }
        }

        _lastInteractedIndex = touchedItem.index;
        _lastInteractedEntry = touchedItem.entry;
        HapticFeedback.selectionClick();
        widget.onSelectionChanged(newSelection);
      } else {
        _lastInteractedIndex = touchedItem.index;
        _lastInteractedEntry = touchedItem.entry;
        final newSelection = Set<RawEntry>.from(widget.selectedItems)
          ..add(touchedItem.entry);
        HapticFeedback.selectionClick();
        widget.onSelectionChanged(newSelection);
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_downPointers.length != 1) return;

    final startPos = _pointerDownPosition;
    if (startPos != null && (event.position - startPos).distance > 12.0) {
      _hasMoved = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _downPointers.remove(event.pointer);
    final interruptedScroll = _scrollInterruptPointers.remove(event.pointer);
    if (!interruptedScroll && !_hasMoved && _pointerDownItem != null) {
      _lastInteractedIndex = _pointerDownItem!.index;
      _lastInteractedEntry = _pointerDownItem!.entry;
    }
    _pointerDownPosition = null;
    _pointerDownItem = null;
    _hasMoved = false;
    _checkScaleFinished();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _downPointers.remove(event.pointer);
    _scrollInterruptPointers.remove(event.pointer);
    _pointerDownPosition = null;
    _pointerDownItem = null;
    _hasMoved = false;
    _checkScaleFinished();
  }

  void _checkScaleFinished() {
    if (_scaleStarted && _downPointers.length < 2) {
      _scaleStarted = false;
      widget.onScaleEnd?.call(ScaleEndDetails());
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _scaleStarted = true;
      widget.onScaleStart?.call(details);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      if (!_scaleStarted) {
        _scaleStarted = true;
        widget.onScaleStart?.call(
          ScaleStartDetails(
            focalPoint: details.focalPoint,
            localFocalPoint: details.localFocalPoint,
            pointerCount: details.pointerCount,
          ),
        );
      }
      widget.onScaleUpdate?.call(details);
    } else if (_scaleStarted && details.pointerCount < 2) {
      // One finger was lifted: immediately finish scaling so the remaining finger
      // can scroll natively without getting locked out.
      _scaleStarted = false;
      widget.onScaleEnd?.call(ScaleEndDetails(pointerCount: details.pointerCount));
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_scaleStarted) {
      _scaleStarted = false;
      widget.onScaleEnd?.call(details);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: RawGestureDetector(
        key: _containerKey,
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _HoldSelectGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_HoldSelectGestureRecognizer>(
            () => _HoldSelectGestureRecognizer(duration: widget.holdDelay),
            (_HoldSelectGestureRecognizer instance) {
              instance
                ..pointerFilter = _shouldTrackHold
                ..onLongPressStart = _handleHoldStart;
            },
          ),
          _PinchScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_PinchScaleGestureRecognizer>(
            () => _PinchScaleGestureRecognizer(),
            (_PinchScaleGestureRecognizer instance) {
              instance
                ..onStart = _handleScaleStart
                ..onUpdate = _handleScaleUpdate
                ..onEnd = _handleScaleEnd
                ..onPinchEnd = _checkScaleFinished;
            },
          ),
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: widget.child,
        ),
      ),
    );
  }
}
