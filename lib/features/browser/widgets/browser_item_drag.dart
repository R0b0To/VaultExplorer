import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_transfer_service.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_drag_session.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart'
    show CategoryEntry;
import 'package:vaultexplorer/features/browser/widgets/browser_pane_scope.dart';

export 'package:vaultexplorer/features/browser/controllers/browser_drag_session.dart'
    show BrowserDropMode;

typedef BrowserItemDropHandler =
    Future<void> Function(
      BrowserItemDragData data,
      MountedContainer destination,
      String destinationPath,
      BrowserDropMode mode,
    );

/// The tile being dragged plus the part of the selection that is in this list.
///
/// One set lookup per selected item. This used to be `List.contains`, which made
/// it (selected x listed) comparisons: with 4,700 items selected that is over
/// twenty million `RawEntry` comparisons, and it ran for every tile on every
/// rebuild.
///
/// With [aloneIfUnselected] (a mouse drag, which does not select the tile it
/// grabs), a tile that is not part of the selection is dragged on its own and
/// the selection is left out of the drag, as in a desktop file manager.
@visibleForTesting
Set<RawEntry> browserEntriesToDrag(
  RawEntry entry,
  Set<RawEntry> selected,
  List<RawEntry> visible, {
  bool aloneIfUnselected = false,
}) {
  if (selected.isEmpty) return {entry};
  if (aloneIfUnselected && !selected.contains(entry)) return {entry};
  final inList = visible.toSet();
  return {
    for (final item in selected)
      if (inList.contains(item)) item,
    entry,
  };
}

/// Converts dragged browser [entries] into native [DesktopTransferEntry] specs,
/// preserving exact paths for [CategoryEntry] items and skipping synthetic
/// source-root headers.
@visibleForTesting
List<DesktopTransferEntry> buildDesktopTransferEntries({
  required Iterable<RawEntry> entries,
  required MountedContainer fallbackContainer,
  required String sourceDirectory,
  MountedContainer Function(RawEntry entry)? containerFor,
}) {
  final out = <DesktopTransferEntry>[];
  for (final e in entries) {
    final entryContainer = containerFor?.call(e) ?? fallbackContainer;
    if (e is CategoryEntry) {
      if (e.isSourceRoot) continue;
      out.add(
        DesktopTransferEntry(
          container: entryContainer,
          vaultPath: e.path,
          name: e.baseName,
          isDir: e.isDir,
          sizeBytes: e.isDir ? 0 : e.sizeBytes,
          modifiedSecs: e.modifiedSecs,
        ),
      );
    } else {
      out.add(
        DesktopTransferEntry(
          container: entryContainer,
          vaultPath: sourceDirectory.isEmpty
              ? e.name
              : '$sourceDirectory/${e.name}',
          name: e.name,
          isDir: e.isDir,
          sizeBytes: e.isDir ? 0 : e.sizeBytes,
          modifiedSecs: e.modifiedSecs,
        ),
      );
    }
  }
  return out;
}

/// Data carried while selected browser items are being dragged.
class BrowserItemDragData {
  final MountedContainer source;
  final String sourceDirectory;
  final BrowserItemDropHandler onDrop;

  Set<RawEntry>? _entries;
  final Set<RawEntry> Function()? _resolveEntries;

  BrowserItemDragData({
    required this.source,
    required this.sourceDirectory,
    required Set<RawEntry> entries,
    required this.onDrop,
  }) : _entries = entries,
       _resolveEntries = null;

  /// Like the default constructor, but the entries are worked out the first
  /// time they are asked for. Every tile in a list builds one of these on every
  /// rebuild, and only the one that is actually dragged ever needs its
  /// entries: with thousands of items selected, computing them for every tile
  /// (as this used to) turned "select all" into a freeze.
  BrowserItemDragData.lazy({
    required this.source,
    required this.sourceDirectory,
    required Set<RawEntry> Function() entries,
    required this.onDrop,
  }) : _resolveEntries = entries;

  /// Everything the drag carries (the dragged tile plus the rest of the
  /// selection that is in the list).
  Set<RawEntry> get entries =>
      _entries ??= Set.unmodifiable(_resolveEntries!());

  String pathFor(RawEntry entry) =>
      sourceDirectory.isEmpty ? entry.name : '$sourceDirectory/${entry.name}';

  /// Whether dropping here is the folder the items already live in.
  bool isSourceFolder(MountedContainer destination, String destinationPath) =>
      source.volId == destination.volId && sourceDirectory == destinationPath;

  /// A folder can be neither moved nor copied into itself or its descendants.
  bool _nestsFolderInItself(
    MountedContainer destination,
    String destinationPath,
  ) {
    if (source.volId != destination.volId) return false;
    for (final entry in entries) {
      if (!entry.isDir) continue;
      final sourcePath = pathFor(entry);
      if (destinationPath == sourcePath ||
          destinationPath.startsWith('$sourcePath/')) {
        return true;
      }
    }
    return false;
  }

  /// Copying is possible anywhere that does not nest a folder in itself --
  /// including the folder the items came from (the conflict sheet then offers
  /// keep-both). Moving there would be a no-op, see [canMoveInto].
  bool canCopyInto(MountedContainer destination, String destinationPath) {
    if (destination.readOnly || entries.isEmpty) return false;
    return !_nestsFolderInItself(destination, destinationPath);
  }

  bool canMoveInto(MountedContainer destination, String destinationPath) {
    if (!canCopyInto(destination, destinationPath)) return false;
    return !isSourceFolder(destination, destinationPath);
  }

  /// Whether a drop here can do anything at all (copy and/or move).
  bool canDropInto(MountedContainer destination, String destinationPath) =>
      canCopyInto(destination, destinationPath);
}

/// A release this close to where the drag began, in the folder it came from,
/// is a long-press that never became a gesture: it offers nothing to copy.
const double _kInPlaceDropSlop = 40.0;

/// Resolves a drop onto [destination]/[destinationPath]: asks Copy / Move /
/// Cancel at the drop point (Move is left out when it would be a no-op, i.e.
/// the items were dropped into the folder they came from), then hands the
/// choice to the source viewport's handler.
Future<void> handleBrowserItemDrop(
  BuildContext context,
  DragTargetDetails<BrowserItemDragData> details,
  MountedContainer destination,
  String destinationPath,
) async {
  final data = details.data;
  if (!data.canCopyInto(destination, destinationPath)) return;
  final canMove = data.canMoveInto(destination, destinationPath);

  final scope = ProviderScope.containerOf(context, listen: false);
  final dropPosition =
      scope.read(browserDragSessionProvider.notifier).pointer.value ??
      details.offset;
  if (!canMove) {
    final start = scope.read(browserDragSessionProvider).startPosition;
    if (start != null && (dropPosition - start).distance < _kInPlaceDropSlop) {
      return;
    }
  }

  final l10n = context.l10n;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final RelativeRect menuPosition;
  if (overlay != null && overlay.hasSize) {
    final localDrop = overlay.globalToLocal(dropPosition);
    menuPosition = RelativeRect.fromRect(
      localDrop & Size.zero,
      Offset.zero & overlay.size,
    );
  } else {
    final screen = MediaQuery.sizeOf(context);
    menuPosition = RelativeRect.fromRect(
      dropPosition & Size.zero,
      Offset.zero & screen,
    );
  }
  final choice = await showMenu<BrowserDropMode>(
    context: context,
    position: menuPosition,
    items: [
      PopupMenuItem<BrowserDropMode>(
        value: BrowserDropMode.copy,
        child: _DropMenuRow(icon: Icons.copy_rounded, label: l10n.copyAction),
      ),
      if (canMove)
        PopupMenuItem<BrowserDropMode>(
          value: BrowserDropMode.move,
          child: _DropMenuRow(
            icon: Icons.drive_file_move_rounded,
            label: l10n.moveAction,
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<BrowserDropMode>(
        child: _DropMenuRow(icon: Icons.close_rounded, label: l10n.cancel),
      ),
    ],
  );
  // Dismissing the menu and choosing Cancel both come back as null.
  if (choice == null) return;
  await data.onDrop(data, destination, destinationPath, choice);
}

class _DropMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DropMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// How long a finger rests on a tile before it counts as a hold: the moment
/// that selects an unselected tile, or starts the drag of an already selected
/// one.
///
/// Must stay *below* [kLongPressTimeout] (500 ms). Every tile also carries a
/// long-press recognizer with that deadline (an `InkWell` `onLongPress`, a
/// no-op in the browser views), and whichever recognizer accepts first wins
/// the gesture arena.
const Duration kItemDragHoldDelay = Duration(milliseconds: 400);

/// How much later than the select the drag starts, when the hold that began
/// it is also the one that selected the tile. Change this one value to retime
/// it: the longer it is, the more deliberate lifting an item out of a fresh
/// selection feels.
const Duration kItemDragAfterSelectDelay = Duration(milliseconds: 600);

/// How far a pressed mouse button has to travel before it counts as a drag.
///
/// Small enough to feel immediate, large enough that the jitter of an ordinary
/// click or double-click never lifts the item.
const double kMouseDragStartSlop = 6.0;

/// What [_HoldThenDragRecognizer] asks about its tile at the moment a finger
/// lands.
///
/// The recognizer lives as long as the tile does (Flutter creates it once),
/// while the tile's selection state changes under it, so both are read live
/// rather than captured when the recognizer was made.
class _HoldDragGate {
  _HoldDragGate({
    required this.selectsFirst,
    required this.onSelect,
    required this.touchAllowed,
  });

  /// Whether a hold that starts now is the one that *selects* the tile
  /// (nothing is selected yet). False when the tile is already part of a
  /// selection: that hold goes straight to dragging. Only asked for touch and
  /// stylus: a mouse never selects by holding.
  final bool Function() selectsFirst;

  /// Selects the tile.
  final VoidCallback onSelect;

  /// Whether a touch or stylus may start a drag from this tile right now.
  /// False for an unselected tile in selection mode: that hold belongs to the
  /// range-select recognizer.
  final bool Function() touchAllowed;

  /// Kind of the pointer that last went down on the tile, i.e. the one whose
  /// drag is running or about to run.
  PointerDeviceKind lastKind = PointerDeviceKind.touch;

  bool get lastWasMouse => lastKind == PointerDeviceKind.mouse;
}

/// Per-pointer state of [_HoldThenDragRecognizer].
///
/// A mouse button drags like it does in a desktop file manager: no hold, no
/// selecting. The drag starts the moment the pointer has moved
/// [kMouseDragStartSlop] with the button down.
///
/// A touch or stylus plain hold behaves exactly like Flutter's own delayed
/// drag: the drag starts when the hold delay is up, and moving before then
/// hands the touch to scrolling.
///
/// A select-first hold has two stages. When the hold delay is up it claims
/// the touch (so the tile's own long-press, which fires at 500 ms, can't take
/// it), selects the tile, and only starts the drag after a further
/// [afterSelectDelay]. Lifting in between leaves the tile selected and starts
/// no drag; moving in between changes nothing, the drag still starts when its
/// delay is up and follows the finger from there.
class _HoldThenDragPointerState extends MultiDragPointerState {
  _HoldThenDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings, {
    required Duration holdDelay,
    required this.afterSelectDelay,
    required this.onSelect,
    required this.isDirectMouse,
  }) {
    if (!isDirectMouse) _timer = Timer(holdDelay, _holdPassed);
  }

  /// Null for a plain hold; otherwise the extra wait before the drag starts.
  final Duration? afterSelectDelay;
  final VoidCallback? onSelect;

  /// A mouse press: drags by movement alone, with no timer and no select.
  final bool isDirectMouse;

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  /// True until the hold delay is up: moving then cancels the gesture.
  bool _holding = true;

  /// Whether the drag may start as soon as the gesture is accepted.
  bool _dragReady = false;

  Offset get _currentPosition =>
      initialPosition + (pendingDelta ?? Offset.zero);

  void _holdPassed() {
    _timer = null;
    _holding = false;
    final extra = afterSelectDelay;
    if (extra == null) {
      _dragReady = true;
      final starter = _starter;
      if (starter != null) {
        _starter = null;
        starter(_currentPosition);
      } else {
        resolve(GestureDisposition.accepted);
      }
      return;
    }
    // Select first, drag a moment later.
    _timer = Timer(extra, _dragDelayPassed);
    onSelect?.call();
    if (_starter == null) resolve(GestureDisposition.accepted);
  }

  void _dragDelayPassed() {
    _timer = null;
    _dragReady = true;
    final starter = _starter;
    if (starter != null) {
      _starter = null;
      starter(_currentPosition);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_dragReady) {
      starter(_currentPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (isDirectMouse) {
      if (_dragReady || pendingDelta!.distance < kMouseDragStartSlop) return;
      _holding = false;
      _dragReady = true;
      resolve(GestureDisposition.accepted);
      return;
    }
    if (!_holding) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.rejected);
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// The drag recognizer of a browser tile. A mouse drags directly (see
/// [_HoldThenDragPointerState]); a touch or stylus is Flutter's delayed
/// (long-press) drag, except that the hold which *selects* a tile starts the
/// drag later than the select.
class _HoldThenDragRecognizer extends MultiDragGestureRecognizer {
  _HoldThenDragRecognizer({
    required this.holdDelay,
    required this.gate,
    super.allowedButtonsFilter,
  }) : super(debugOwner: null);

  final Duration holdDelay;
  final _HoldDragGate gate;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if ((event.buttons & kPrimaryMouseButton) == 0) return false;
    } else if (!gate.touchAllowed()) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    gate.lastKind = event.kind;
    final isMouse = event.kind == PointerDeviceKind.mouse;
    final selectsFirst = !isMouse && gate.selectsFirst();
    return _HoldThenDragPointerState(
      event.position,
      event.kind,
      gestureSettings,
      holdDelay: holdDelay,
      afterSelectDelay: selectsFirst ? kItemDragAfterSelectDelay : null,
      onSelect: selectsFirst ? gate.onSelect : null,
      isDirectMouse: isMouse,
    );
  }

  @override
  String get debugDescription => 'hold then drag';
}

/// A [Draggable] that asks [tryBegin] before it lets a drag start. A mouse
/// drags directly; touch and stylus long-press, and the drag of a freshly
/// selected tile starts a moment after the select (see
/// [_HoldThenDragRecognizer]).
///
/// It extends [Draggable] rather than [LongPressDraggable] because the latter
/// is tied to Flutter's single-delay recognizer; it keeps that widget's
/// [delay] and [hapticFeedbackOnStart].
///
/// Flutter gives every draggable its own recognizer, so a second finger could
/// start a second drag (even from the same tile unless `maxSimultaneousDrags`
/// is capped). The gate is checked at the moment the recognizer would start
/// the drag, which also settles two fingers that complete their long press in
/// the same frame: the first claims the slot, the other gets nothing.
class _GuardedLongPressDraggable<T extends Object> extends Draggable<T> {
  const _GuardedLongPressDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
    this.delay = kItemDragHoldDelay,
    this.hapticFeedbackOnStart = true,
    required this.gate,
    required this.tryBegin,
    required this.release,
  });

  /// How long a finger rests on the tile before the hold counts.
  final Duration delay;

  /// Whether a tick is felt when the drag starts (never for a mouse).
  final bool hapticFeedbackOnStart;

  final _HoldDragGate gate;
  final bool Function(Offset position) tryBegin;
  final VoidCallback release;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _HoldThenDragRecognizer(
      holdDelay: delay,
      gate: gate,
      allowedButtonsFilter: allowedButtonsFilter,
    )..onStart = (Offset position) {
      if (!tryBegin(position)) return null;
      final Drag? drag = onStart(position);
      if (drag == null) {
        // The draggable itself declined (its own cap): give the slot back.
        release();
        return null;
      }
      if (hapticFeedbackOnStart && !gate.lastWasMouse) {
        HapticFeedback.selectionClick();
      }
      return drag;
    };
  }
}

/// Tile id used when a tile is built outside any directory viewport.
const TabId _kUnscopedTab = TabId(-1);

/// Adds dragging and, for folders, a highlighted drop target around one
/// file-manager tile.
///
/// With a mouse, pressing any tile and moving drags it straight away, without
/// selecting it or holding first: a tile that is part of the selection takes
/// the whole selection along, any other tile goes alone (see
/// [browserEntriesToDrag]).
///
/// With touch or stylus the selection recognizer remains responsible for
/// range-selecting unselected rows; a selected row can be held to drag the
/// complete selection. Holding a tile while nothing is selected selects it at
/// the hold delay
/// ([kItemDragHoldDelay]) and, if the finger stays down, lifts it into a drag
/// [kItemDragAfterSelectDelay] later. Lifting and holding again on an already
/// selected tile starts the drag at the plain hold delay.
///
/// Also draws the flash on tiles a finished drop just created (see
/// [BrowserPaneScope.revealNames]) and freezes the tile while the viewport is
/// locked by a drag that started in another one.
class BrowserItemDragItem extends StatefulWidget {
  final Widget child;
  final RawEntry entry;
  final MountedContainer? container;
  final MountedContainer Function(RawEntry entry)? containerFor;
  final String currentDirectory;
  final List<RawEntry> visibleItems;
  final Set<RawEntry> selectedItems;
  final bool isSelectionMode;
  final bool enabled;
  final ValueChanged<RawEntry> onItemLongPress;
  final BrowserItemDropHandler? onDrop;

  const BrowserItemDragItem({
    super.key,
    required this.child,
    required this.entry,
    required this.container,
    this.containerFor,
    required this.currentDirectory,
    required this.visibleItems,
    required this.selectedItems,
    required this.isSelectionMode,
    required this.enabled,
    required this.onItemLongPress,
    required this.onDrop,
  });

  @override
  State<BrowserItemDragItem> createState() => _BrowserItemDragItemState();
}

class _BrowserItemDragItemState extends State<BrowserItemDragItem> {
  int? _activePointerId;
  PointerDeviceKind? _activePointerKind;
  bool _isPrimaryMouseDown = false;
  bool _handedOffToOsDrag = false;

  late final _HoldDragGate _gate = _HoldDragGate(
    selectsFirst: () => !widget.isSelectionMode,
    onSelect: _selectOnHold,
    // An unselected tile in selection mode is left to the range-select hold
    // for touch; a mouse can always grab it.
    touchAllowed: () =>
        !widget.isSelectionMode || widget.selectedItems.contains(widget.entry),
  );

  /// The first stage of a select-first hold (see [_HoldThenDragPointerState]).
  void _selectOnHold() {
    if (!mounted) return;
    // Another finger is already dragging items: this one only competes for
    // the same slot, it must not select anything.
    final session = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(browserDragSessionProvider);
    if (session.isActive) return;
    widget.onItemLongPress(widget.entry);
  }

  void _handoffToOsDrag(
    int viewId,
    BrowserItemDragData data,
    BrowserDragSession session,
    FullScreenDragDrawerScope? drawerScope,
  ) {
    final resolved = data.entries;
    if (resolved.isEmpty) return;

    final transferItems = buildDesktopTransferEntries(
      entries: resolved,
      fallbackContainer: data.source,
      sourceDirectory: data.sourceDirectory,
      containerFor: widget.containerFor,
    );
    if (transferItems.isEmpty) return;

    _handedOffToOsDrag = true;
    final pointer = _activePointerId;
    if (pointer != null) {
      scheduleMicrotask(() => GestureBinding.instance.cancelPointer(pointer));
    }
    session.end();
    drawerScope?.setDrawerDragBlocked(false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isPrimaryMouseDown) {
        _handedOffToOsDrag = false;
        return;
      }
      unawaited(
        DesktopTransferService.instance
            .startOutboundDrag(viewId: viewId, items: transferItems)
            .whenComplete(() {
              _handedOffToOsDrag = false;
              _isPrimaryMouseDown = false;
              _activePointerId = null;
            }),
      );
    });
  }

  /// The tile with its overlays. The tile is always the first child of the
  /// same [Stack], so toggling a highlight or the lock never re-parents it
  /// (file tiles own stateful thumbnail and PiP subtrees).
  Widget _withOverlays(
    BuildContext context, {
    required bool locked,
    required bool revealed,
    int revealToken = 0,
    bool dropHover = false,
  }) {
    final child = widget.child;
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        IgnorePointer(ignoring: locked, child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: dropHover ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: primary, width: 3),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: _DropRevealPulse(
              active: revealed,
              token: revealToken,
              color: primary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final container = widget.container;
    final currentDirectory = widget.currentDirectory;
    final visibleItems = widget.visibleItems;
    final selectedItems = widget.selectedItems;
    final isSelectionMode = widget.isSelectionMode;
    final onDrop = widget.onDrop;
    final scope = BrowserPaneScope.maybeOf(context);
    final locked = scope?.interactionLocked ?? false;
    final revealed = scope?.revealNames.contains(entry.name) ?? false;
    final revealToken = scope?.revealToken ?? 0;

    final drawerScope = FullScreenDragDrawerScope.maybeOf(context);
    final source = container;
    if (!widget.enabled ||
        source == null ||
        entry.isPlaceholder ||
        onDrop == null) {
      return _withOverlays(
        context,
        locked: locked,
        revealed: revealed,
        revealToken: revealToken,
      );
    }

    final session = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(browserDragSessionProvider.notifier);

    final data = BrowserItemDragData.lazy(
      source: source,
      sourceDirectory: currentDirectory,
      entries: () => browserEntriesToDrag(
        entry,
        selectedItems,
        visibleItems,
        // A mouse grabs the tile without selecting it, so an unselected tile
        // moves alone instead of joining the selection.
        aloneIfUnselected: _gate.lastWasMouse,
      ),
      onDrop: onDrop,
    );

    Widget dragChild;
    if (entry.isDir) {
      final targetPath = currentDirectory.isEmpty
          ? entry.name
          : '$currentDirectory/${entry.name}';
      dragChild = DragTarget<BrowserItemDragData>(
        onWillAcceptWithDetails: (details) =>
            details.data.canDropInto(source, targetPath),
        onAcceptWithDetails: (details) => unawaited(
          handleBrowserItemDrop(context, details, source, targetPath),
        ),
        builder: (context, candidates, rejected) => _withOverlays(
          context,
          locked: locked,
          revealed: revealed,
          revealToken: revealToken,
          dropHover: candidates.isNotEmpty,
        ),
      );
    } else {
      dragChild = _withOverlays(
        context,
        locked: locked,
        revealed: revealed,
        revealToken: revealToken,
      );
    }

    final tabId = scope?.tabId ?? _kUnscopedTab;
    final draggable = _GuardedLongPressDraggable<BrowserItemDragData>(
      data: data,
      delay: kItemDragHoldDelay,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      gate: _gate,
      tryBegin: (position) => session.tryBegin(tabId, position),
      release: session.end,
      onDragStarted: () {
        drawerScope?.setDrawerDragBlocked(true);
        // A mouse drags without selecting. Otherwise the tile is normally
        // already selected by the hold (see _selectOnHold); a no-op then.
        if (!_gate.lastWasMouse) widget.onItemLongPress(entry);
      },
      onDragUpdate: (details) {
        session.updatePointer(details.globalPosition);
        if (!PlatformFeatures.isDesktop ||
            _handedOffToOsDrag ||
            !_isPrimaryMouseDown ||
            _activePointerKind != PointerDeviceKind.mouse) {
          return;
        }
        final view = View.maybeOf(context);
        if (view == null) return;
        final dpr = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1.0;
        final size = view.physicalSize / dpr;
        if (size.width <= 0 || size.height <= 0) return;
        final pos = details.globalPosition;
        const edgeMargin = 4.0;
        if (pos.dx <= edgeMargin ||
            pos.dy <= edgeMargin ||
            pos.dx >= size.width - edgeMargin ||
            pos.dy >= size.height - edgeMargin) {
          _handoffToOsDrag(view.viewId, data, session, drawerScope);
        }
      },
      onDragEnd: (_) {
        session.end();
        drawerScope?.setDrawerDragBlocked(false);
      },
      // Keep the overlay independent from the live tile. File tiles can own
      // stateful thumbnail and PiP subtrees that must not be laid out twice.
      feedback: _DragFeedback(
        entry: entry,
        data: data,
        pointer: session.pointer,
        isMouse: () => _gate.lastWasMouse,
      ),
      childWhenDragging: dragChild,
      child: dragChild,
    );
    if (!PlatformFeatures.isDesktop) return draggable;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _activePointerId = event.pointer;
        _activePointerKind = event.kind;
        _handedOffToOsDrag = false;
        _isPrimaryMouseDown =
            event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kPrimaryMouseButton) != 0;
      },
      onPointerMove: (event) {
        if (event.pointer == _activePointerId && !_handedOffToOsDrag) {
          session.updateActivePointer(event.position);
        }
      },
      onPointerUp: (event) {
        if (event.pointer == _activePointerId) {
          if (!_handedOffToOsDrag) {
            session.updateActivePointer(event.position);
          }
          _isPrimaryMouseDown = false;
          _activePointerId = null;
        }
      },
      onPointerCancel: (event) {
        if (event.pointer == _activePointerId) {
          if (!_handedOffToOsDrag) {
            _isPrimaryMouseDown = false;
          }
          _activePointerId = null;
        }
      },
      child: draggable,
    );
  }
}

/// How long the flash on freshly dropped items lasts, start to finish. Short
/// on purpose: it is a pulse that says "these just arrived", not a highlight
/// that has to be waited out. Change this one value to retime it.
const Duration kDropRevealPulseDuration = Duration(milliseconds: 600);

/// Strongest the flash gets, as the alpha of the primary colour. A little
/// firmer than a held highlight would be, since it is only there for a moment.
const double _kDropRevealPulsePeakAlpha = 0.28;

/// One quick pulse over a tile: a fast rise, then a softer fade away.
///
/// It plays when [active] turns on, and again for every new [token] (a second
/// drop that lands on the same names). Turning [active] off does not cut it
/// short -- the pulse always finishes -- so the viewport only has to leave the
/// names announced for as long as it takes tiles to be built.
class _DropRevealPulse extends StatefulWidget {
  final bool active;
  final int token;
  final Color color;

  const _DropRevealPulse({
    required this.active,
    required this.token,
    required this.color,
  });

  @override
  State<_DropRevealPulse> createState() => _DropRevealPulseState();
}

class _DropRevealPulseState extends State<_DropRevealPulse>
    with SingleTickerProviderStateMixin {
  /// 0 -> 1 -> 0 over the pulse: the first quarter rises, the rest fades.
  static final Animatable<double> _envelope = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 75,
    ),
  ]);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kDropRevealPulseDuration,
  );
  late final Animation<double> _strength = _controller.drive(_envelope);

  @override
  void initState() {
    super.initState();
    // A tile built while its name is being announced (scrolled into view by
    // the reveal, say) pulses as it appears.
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _DropRevealPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active || widget.token != oldWidget.token)) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Almost every tile is at rest almost all the time: paint nothing.
        if (_controller.isDismissed) return const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: _kDropRevealPulsePeakAlpha * _strength.value,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
        );
      },
    );
  }
}

/// The card that follows the finger. The overlay places its origin at the
/// touch point, so the card is shifted to sit above the fingertip -- or to the
/// side when there is no room above -- instead of underneath the hand.
class _DragFeedback extends StatelessWidget {
  static const double _width = 220;
  static const double _height = 56;

  /// Clear space between the fingertip and the card.
  static const double _gap = 44;

  /// Clear space between a mouse cursor and the card.
  static const double _cursorGap = 14;
  static const double _margin = 8;

  final RawEntry entry;
  final BrowserItemDragData data;
  final ValueListenable<Offset?> pointer;

  /// Whether the drag is driven by a mouse: the card then trails the cursor
  /// (below and to its right) instead of floating above a fingertip.
  final bool Function() isMouse;

  const _DragFeedback({
    required this.entry,
    required this.data,
    required this.pointer,
    required this.isMouse,
  });

  /// How many items are being dragged. Only worked out once the feedback is
  /// actually shown (see [BrowserItemDragData.lazy]).
  int get count => data.entries.length;

  Offset _shiftFor(BuildContext context, Offset finger) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final minTop = media.padding.top + _margin;

    if (isMouse()) {
      var left = finger.dx + _cursorGap;
      var top = finger.dy + _cursorGap;
      if (left + _width > size.width - _margin) {
        left = finger.dx - _cursorGap - _width;
      }
      if (top + _height > size.height - _margin) {
        top = finger.dy - _cursorGap - _height;
      }
      left = left
          .clamp(_margin, math.max(_margin, size.width - _width - _margin))
          .toDouble();
      top = top
          .clamp(minTop, math.max(minTop, size.height - _height - _margin))
          .toDouble();
      return Offset(left - finger.dx, top - finger.dy);
    }

    var left = finger.dx - _width / 2;
    var top = finger.dy - _height - _gap;
    if (top < minTop) {
      // Not enough room above: sit beside the finger, on the roomier side.
      top = finger.dy - _height / 2;
      final roomRight = size.width - finger.dx;
      left = roomRight >= _width + _gap + _margin
          ? finger.dx + _gap
          : finger.dx - _gap - _width;
    }
    left = left
        .clamp(_margin, math.max(_margin, size.width - _width - _margin))
        .toDouble();
    top = top
        .clamp(minTop, math.max(minTop, size.height - _height - _margin))
        .toDouble();
    return Offset(left - finger.dx, top - finger.dy);
  }

  @override
  Widget build(BuildContext context) {
    final card = Opacity(opacity: 0.82, child: _buildCard(context));
    return ValueListenableBuilder<Offset?>(
      valueListenable: pointer,
      child: card,
      builder: (context, finger, card) {
        if (finger == null) return card!;
        return Transform.translate(
          offset: _shiftFor(context, finger),
          child: card,
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = colors.primary;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _width,
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              entry.isDir
                  ? Icons.folder_rounded
                  : Icons.insert_drive_file_rounded,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (count > 1) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
