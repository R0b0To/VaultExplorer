import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

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

/// A container that coordinates hold-to-select and hold-to-range-select across
/// any layout (List, Compact, Grid, Masonry) without interfering with native scrolling.
///
/// Features:
///  • Hold an item when [isSelectionMode] is false (selects initial item and enters selection mode).
///  • Hold another item when [isSelectionMode] is true (selects all items in range between anchor and held item).
///  • Moving the finger cancels the hold timer, allowing fluid native scrolling.
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
    this.holdDelay = const Duration(milliseconds: 280),
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
  int _activePointers = 0;
  Timer? _holdTimer;

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
  void didUpdateWidget(covariant HoldRangeSelectContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelectionMode || widget.selectedItems.isEmpty) {
      _lastInteractedIndex = null;
      _lastInteractedEntry = null;
    }
  }

  @override
  void dispose() {
    _cancelHoldTimer();
    super.dispose();
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
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

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers > 1) {
      _cancelHoldTimer();
      return;
    }

    _hasMoved = false;
    _pointerDownPosition = event.position;
    _pointerDownItem = _findItemAt(event.position);

    if (_pointerDownItem != null && !_pointerDownItem!.entry.isPlaceholder) {
      _cancelHoldTimer();
      _holdTimer = Timer(widget.holdDelay, () {
        if (!mounted || _activePointers != 1 || _pointerDownItem == null) return;
        final touchedItem = _pointerDownItem!;
        if (touchedItem.entry.isPlaceholder) return;

        if (!widget.isSelectionMode) {
          _lastInteractedIndex = touchedItem.index;
          _lastInteractedEntry = touchedItem.entry;
          HapticFeedback.selectionClick();
          widget.onLongPressSelect?.call(touchedItem.entry);
        } else {
          // Already in selection mode: select all items between last anchor and touched item!
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
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointers != 1) {
      _cancelHoldTimer();
      return;
    }

    final startPos = _pointerDownPosition;
    // If the user moves their finger beyond threshold, cancel hold timer and mark as scrolling
    if (startPos != null && (event.position - startPos).distance > 12.0) {
      _hasMoved = true;
      _cancelHoldTimer();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    _cancelHoldTimer();
    // Only register interaction if finger did not move (i.e. a discrete tap, not a scroll)
    if (!_hasMoved && _pointerDownItem != null) {
      _lastInteractedIndex = _pointerDownItem!.index;
      _lastInteractedEntry = _pointerDownItem!.entry;
    }
    _pointerDownPosition = null;
    _pointerDownItem = null;
    _hasMoved = false;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    _cancelHoldTimer();
    _pointerDownPosition = null;
    _pointerDownItem = null;
    _hasMoved = false;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _cancelHoldTimer();
      widget.onScaleStart?.call(details);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      _cancelHoldTimer();
      widget.onScaleUpdate?.call(details);
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    widget.onScaleEnd?.call(details);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        key: _containerKey,
        behavior: HitTestBehavior.translucent,
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        onScaleEnd: _handleScaleEnd,
        child: widget.child,
      ),
    );
  }
}

