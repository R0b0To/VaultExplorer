import 'dart:async';
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
  final Set<int> _downPointers = <int>{};
  Timer? _holdTimer;
  bool _scaleStarted = false;

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
    _downPointers.add(event.pointer);
    if (_downPointers.length > 1) {
      _cancelHoldTimer();
      return;
    }

    _hasMoved = false;
    _pointerDownPosition = event.position;
    _pointerDownItem = _findItemAt(event.position);

    if (_pointerDownItem != null && !_pointerDownItem!.entry.isPlaceholder) {
      _cancelHoldTimer();
      _holdTimer = Timer(widget.holdDelay, () {
        if (!mounted || _downPointers.length != 1 || _pointerDownItem == null) return;
        final touchedItem = _pointerDownItem!;
        if (touchedItem.entry.isPlaceholder) return;

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
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_downPointers.length != 1) {
      _cancelHoldTimer();
      return;
    }

    final startPos = _pointerDownPosition;
    if (startPos != null && (event.position - startPos).distance > 12.0) {
      _hasMoved = true;
      _cancelHoldTimer();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _downPointers.remove(event.pointer);
    _cancelHoldTimer();
    if (!_hasMoved && _pointerDownItem != null) {
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
    _cancelHoldTimer();
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
      _cancelHoldTimer();
      widget.onScaleStart?.call(details);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      _cancelHoldTimer();
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
        child: widget.child,
      ),
    );
  }
}