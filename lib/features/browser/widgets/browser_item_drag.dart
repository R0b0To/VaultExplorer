import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

typedef BrowserItemDropHandler =
    Future<void> Function(
      BrowserItemDragData data,
      MountedContainer destination,
      String destinationPath,
    );

/// Data carried while selected browser items are being moved.
class BrowserItemDragData {
  final MountedContainer source;
  final String sourceDirectory;
  final Set<RawEntry> entries;
  final BrowserItemDropHandler onDrop;

  const BrowserItemDragData({
    required this.source,
    required this.sourceDirectory,
    required this.entries,
    required this.onDrop,
  });

  String pathFor(RawEntry entry) =>
      sourceDirectory.isEmpty ? entry.name : '$sourceDirectory/${entry.name}';

  bool canDropInto(MountedContainer destination, String destinationPath) {
    if (entries.isEmpty) return false;
    if (source.volId == destination.volId &&
        sourceDirectory == destinationPath) {
      return false;
    }

    for (final entry in entries) {
      if (!entry.isDir) continue;
      final sourcePath = pathFor(entry);
      if (destinationPath == sourcePath ||
          destinationPath.startsWith('$sourcePath/')) {
        return false;
      }
    }
    return true;
  }
}

/// Adds long-press dragging and, for folders, a highlighted move drop target
/// around one file-manager tile. The selection recognizer remains responsible
/// for range-selecting unselected rows; a selected row can be held to drag the
/// complete selection.
class BrowserItemDragItem extends StatelessWidget {
  final Widget child;
  final RawEntry entry;
  final MountedContainer? container;
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
    required this.currentDirectory,
    required this.visibleItems,
    required this.selectedItems,
    required this.isSelectionMode,
    required this.enabled,
    required this.onItemLongPress,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    final drawerScope = FullScreenDragDrawerScope.maybeOf(context);
    final source = container;
    if (!enabled || source == null || entry.isPlaceholder || onDrop == null) {
      return child;
    }

    final dragEntries =
        selectedItems
            .where((selected) => visibleItems.contains(selected))
            .toSet()
          ..add(entry);
    final data = BrowserItemDragData(
      source: source,
      sourceDirectory: currentDirectory,
      entries: Set.unmodifiable(dragEntries),
      onDrop: onDrop!,
    );

    Widget dragChild = child;
    if (entry.isDir) {
      final targetPath = currentDirectory.isEmpty
          ? entry.name
          : '$currentDirectory/${entry.name}';
      dragChild = DragTarget<BrowserItemDragData>(
        onWillAcceptWithDetails: (details) =>
            details.data.canDropInto(source, targetPath),
        onAcceptWithDetails: (details) =>
            unawaited(details.data.onDrop(details.data, source, targetPath)),
        builder: (context, candidates, rejected) => Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            if (candidates.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // In selection mode, unselected rows belong to the range-select hold
    // recognizer. They become draggable after selection and a fresh hold.
    if (isSelectionMode && !selectedItems.contains(entry)) return dragChild;

    return LongPressDraggable<BrowserItemDragData>(
      data: data,
      delay: const Duration(milliseconds: 400),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        drawerScope?.setDrawerDragBlocked(true);
        onItemLongPress(entry);
      },
      onDragEnd: (_) => drawerScope?.setDrawerDragBlocked(false),
      // Keep the overlay independent from the live tile. File tiles can own
      // stateful thumbnail and PiP subtrees that must not be laid out twice.
      feedback: Opacity(
        opacity: 0.62,
        child: _DragFeedback(entry: entry, count: data.entries.length),
      ),
      childWhenDragging: dragChild,
      child: dragChild,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final RawEntry entry;
  final int count;

  const _DragFeedback({required this.entry, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = colors.primary;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        height: 56,
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
