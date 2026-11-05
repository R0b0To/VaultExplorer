// The Storage Analyzer's map: the current folder drawn as tiles whose areas are
// proportional to size, so the heavy things are simply the big things.
//
// One level at a time, by design. Drawing every nested file at once (as desktop
// treemaps do) produces thousands of slivers that cannot be read or tapped on a
// phone. Instead each folder tile carries a thin stacked bar showing what it is
// made of, and tapping it opens it.
//
// Tiles are ordinary widgets rather than one custom painter, which gives
// ripples, hit-testing and screen-reader semantics for free.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/features/tools/models/storage_treemap_layout.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_widgets.dart';

class StorageTreemap extends StatefulWidget {
  const StorageTreemap({
    super.key,
    required this.parent,
    required this.version,
    required this.selectedPaths,
    required this.typeFilter,
    required this.onTap,
    required this.onLongPress,
    required this.onGroupTap,
  });

  /// The folder being drawn.
  final StorageNode parent;

  /// The tree's version; a change means [parent]'s contents may differ.
  final int version;
  final Set<String> selectedPaths;

  /// When set, tiles with nothing of this type fade back.
  final String? typeFilter;
  final void Function(StorageNode node) onTap;
  final void Function(StorageNode node) onLongPress;

  /// The lump of "smaller items" was tapped.
  final VoidCallback onGroupTap;

  @override
  State<StorageTreemap> createState() => _StorageTreemapState();
}

class _StorageTreemapState extends State<StorageTreemap> {
  // What each folder tile is made of, keyed by child path. Walking a subtree is
  // the only non-trivial cost here, so it is done once per (tree version,
  // folder) rather than on every selection tap.
  final Map<String, Map<String, int>> _composition = {};
  int? _compositionVersion;
  String? _compositionPath;

  Map<String, int> _compositionOf(StorageNode dir) {
    if (_compositionVersion != widget.version ||
        _compositionPath != widget.parent.path) {
      _composition.clear();
      _compositionVersion = widget.version;
      _compositionPath = widget.parent.path;
    }
    return _composition.putIfAbsent(dir.path, () {
      final totals = StorageTree.categoryTotalsOf(dir);
      return {
        for (final c in StorageCategory.all)
          if ((totals[c]?.bytes ?? 0) > 0) c: totals[c]!.bytes,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * 0.85).clamp(260.0, 420.0).toDouble();
        final entries = buildTreemapEntries(
          widget.parent.children,
          areaPx: width * height,
        );
        final tiles = squarify<TreemapEntry>(
          items: entries,
          weight: (e) => e.weightBytes.toDouble(),
          bounds: TmRect(0, 0, width, height),
        );

        final children = <Widget>[];
        for (final t in tiles) {
          final e = t.item;
          final r = t.rect;
          final Widget tile;
          if (e.isGroup) {
            tile = _TreemapTile(
              label: l10n.storageAnalyzerSmallerItems(e.grouped.length),
              sizeText: formatBytes(e.bytes),
              icon: Icons.more_horiz_rounded,
              style: storageCategoryStyle(context, ''),
              rect: r,
              selected: false,
              dimmed: false,
              composition: const <String, int>{},
              onTap: widget.onGroupTap,
              onLongPress: null,
            );
          } else {
            final node = e.node!;
            final comp = node.isDir
                ? _compositionOf(node)
                : const <String, int>{};
            final filter = widget.typeFilter;
            final matches =
                filter == null ||
                (node.isDir
                    ? (comp[filter] ?? 0) > 0
                    : node.category == filter);
            tile = _TreemapTile(
              label: node.name,
              sizeText: formatBytes(node.sizeBytes),
              icon: storageNodeIcon(node),
              style: storageCategoryStyle(
                context,
                node.isDir ? '' : node.category,
              ),
              rect: r,
              selected: widget.selectedPaths.contains(node.path),
              dimmed: !matches,
              composition: comp,
              onTap: () => widget.onTap(node),
              onLongPress: () => widget.onLongPress(node),
            );
          }
          children.add(
            Positioned(
              left: r.left,
              top: r.top,
              width: r.width,
              height: r.height,
              child: tile,
            ),
          );
        }

        return SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Stack(children: children),
          ),
        );
      },
    );
  }
}

class _TreemapTile extends StatelessWidget {
  const _TreemapTile({
    required this.label,
    required this.sizeText,
    required this.icon,
    required this.style,
    required this.rect,
    required this.selected,
    required this.dimmed,
    required this.composition,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final String sizeText;
  final IconData icon;
  final StorageCategoryStyle style;
  final TmRect rect;
  final bool selected;
  final bool dimmed;

  /// Bytes per file type inside a folder tile; empty for files.
  final Map<String, int> composition;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    final fill = dimmed ? style.fill.withValues(alpha: 0.35) : style.fill;
    final fg = dimmed ? style.onFill.withValues(alpha: 0.5) : style.onFill;

    // Text only where it can be read; tiny tiles are just colour.
    final showLabel = rect.width >= 52 && rect.height >= 32;
    final showSize = showLabel && rect.height >= 54;
    final nameLines = rect.height >= 80 ? 2 : 1;

    var compTotal = 0;
    for (final b in composition.values) {
      compTotal += b;
    }
    final showComposition =
        compTotal > 0 && rect.height >= 24 && rect.width >= 24;

    return Padding(
      padding: const EdgeInsets.all(1),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $sizeText',
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showLabel)
                  // Clipped, unbounded-height box: if a large text scale makes
                  // the label taller than the tile it is cut off rather than
                  // raising a layout overflow.
                  ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 5, 6, 9),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    icon,
                                    size: AppIconSize.inline,
                                    color: fg,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: nameLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelMedium?.copyWith(
                                      color: fg,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (showSize)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  sizeText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: fg.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (showComposition)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 4,
                    child: Row(
                      children: [
                        for (final entry in composition.entries)
                          Expanded(
                            flex: math.max(
                              1,
                              (entry.value * 1000 ~/ compTotal),
                            ),
                            child: ColoredBox(
                              color: storageCategoryStyle(
                                context,
                                entry.key,
                              ).accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.primary, width: 3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: AppIconSize.small,
                      color: cs.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
