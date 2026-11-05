// The four tabs of the Storage Analyzer, each as a list of slivers the screen
// drops into one scroll view. Plain functions of (state, notifier, actions):
// they own no state of their own, so the screen stays the single place that
// decides what happens when something is tapped.
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart'
    show StorageCategoryBreakdown;
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_widgets.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_treemap_view.dart';

/// [review] key for the "biggest files" list in the cleanup tab; every other
/// key is a [CleanupKind] name.
const storageReviewBiggest = 'biggest';

// ── Map ──────────────────────────────────────────────────────────────────────

List<Widget> buildStorageMapSlivers(
  BuildContext context, {
  required StorageAnalyzerState state,
  required StorageAnalyzer notifier,
  required StorageActions actions,
  required String rootLabel,
  required VoidCallback onShowList,
}) {
  final node = state.currentNode;
  if (node == null) return const [];
  final l10n = context.l10n;
  final cs = context.colors;
  final textTheme = context.typography;

  return [
    SliverToBoxAdapter(
      child: StorageBreadcrumb(
        rootLabel: rootLabel,
        path: node.path,
        onNavigate: actions.onNavigate,
      ),
    ),
    SliverToBoxAdapter(
      child: node.sizeBytes <= 0
          ? _EmptyNote(l10n.storageAnalyzerEmptyFolder)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: StorageTreemap(
                parent: node,
                version: state.treeVersion,
                selectedPaths: state.selectedPaths,
                typeFilter: state.typeFilter,
                onTap: (n) => actions.onTap(n, true),
                onLongPress: actions.onLongPress,
                onGroupTap: onShowList,
              ),
            ),
    ),
    if (state.breakdown.isNotEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final b in state.breakdown)
                    SizedBox(
                      width: itemWidth,
                      child: FilterChip(
                        avatar: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: storageCategoryStyle(
                              context,
                              b.category,
                            ).accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        labelPadding: const EdgeInsets.only(left: 2, right: 4),
                        label: Text(
                          '${storageCategoryLabel(context, b.category)} · ${formatBytes(b.sizeBytes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typography.labelSmall,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: state.typeFilter == b.category,
                        showCheckmark: false,
                        onSelected: (on) =>
                            notifier.setTypeFilter(on ? b.category : null),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Text(
          l10n.storageAnalyzerMapHint,
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    ),
  ];
}

// ── Folders ──────────────────────────────────────────────────────────────────

List<Widget> buildStorageFoldersSlivers(
  BuildContext context, {
  required StorageAnalyzerState state,
  required StorageAnalyzer notifier,
  required StorageActions actions,
  required String rootLabel,
}) {
  final node = state.currentNode;
  if (node == null) return const [];
  final l10n = context.l10n;
  final kids = [...node.children]..sort(state.sort.compare);
  final selecting = state.hasSelection;

  String sortLabel(StorageSort s) => switch (s) {
    StorageSort.size => l10n.sortFieldSize,
    StorageSort.name => l10n.sortFieldName,
    StorageSort.files => l10n.storageAnalyzerSortFiles,
    StorageSort.date => l10n.sortFieldDate,
  };

  return [
    SliverToBoxAdapter(
      child: StorageBreadcrumb(
        rootLabel: rootLabel,
        path: node.path,
        onNavigate: actions.onNavigate,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              tooltip: l10n.storageAnalyzerSelectAllHere,
              visualDensity: VisualDensity.compact,
              onPressed: kids.isEmpty
                  ? null
                  : () => notifier.addSelected(kids.map((k) => k.path)),
            ),
            PopupMenuButton<StorageSort>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: l10n.sortAction,
              initialValue: state.sort,
              onSelected: notifier.setSort,
              itemBuilder: (context) => [
                for (final s in StorageSort.values)
                  CheckedPopupMenuItem<StorageSort>(
                    value: s,
                    checked: s == state.sort,
                    child: Text(sortLabel(s)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    if (kids.isEmpty)
      SliverToBoxAdapter(child: _EmptyNote(l10n.storageAnalyzerEmptyFolder))
    else
      SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          final k = kids[i];
          return StorageNodeTile(
            key: ValueKey(k.path),
            node: k,
            parentBytes: node.sizeBytes,
            selected: state.selectedPaths.contains(k.path),
            selecting: selecting,
            drill: true,
            actions: actions,
          );
        }, childCount: kids.length),
      ),
  ];
}

// ── Types ────────────────────────────────────────────────────────────────────

List<Widget> buildStorageTypesSlivers(
  BuildContext context, {
  required StorageAnalyzerState state,
  required StorageAnalyzer notifier,
  required StorageActions actions,
}) {
  final l10n = context.l10n;
  final filter = state.typeFilter;

  if (filter == null) {
    final total = state.tree?.totalBytes ?? 0;
    return [
      SliverToBoxAdapter(
        child: SectionHeader(l10n.storageAnalyzerBreakdownHeader),
      ),
      if (state.breakdown.isEmpty)
        SliverToBoxAdapter(child: _EmptyNote(l10n.storageAnalyzerNoFilesFound))
      else
        SliverToBoxAdapter(
          child: Column(
            children: [
              for (final b in state.breakdown)
                _TypeRow(
                  breakdown: b,
                  totalBytes: total,
                  onTap: () => notifier.setTypeFilter(b.category),
                ),
            ],
          ),
        ),
    ];
  }

  final files = notifier.filesOfType(filter);
  return [
    SliverToBoxAdapter(
      child: _ListHeader(
        title: l10n.storageAnalyzerLargestOfType(
          storageCategoryLabel(context, filter),
        ),
        backLabel: l10n.storageAnalyzerAllTypes,
        onBack: () => notifier.setTypeFilter(null),
        onSelectAll: files.isEmpty
            ? null
            : () => notifier.addSelected(files.map((f) => f.path)),
      ),
    ),
    ..._flatList(state, actions, files),
  ];
}

// ── Cleanup ──────────────────────────────────────────────────────────────────

List<Widget> buildStorageCleanupSlivers(
  BuildContext context, {
  required StorageAnalyzerState state,
  required StorageAnalyzer notifier,
  required StorageActions actions,
  required String? review,
  required ValueChanged<String?> onReview,
}) {
  final l10n = context.l10n;

  if (review == null) {
    final hasFiles = (state.tree?.fileCount ?? 0) > 0;
    return [
      SliverToBoxAdapter(
        child: SectionHeader(l10n.storageAnalyzerCleanupHeader),
      ),
      if (state.cleanup.isEmpty)
        SliverToBoxAdapter(
          child: _EmptyNote(l10n.storageAnalyzerCleanupNothing),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (final s in state.cleanup)
                _CleanupCard(
                  icon: _cleanupIcon(s.kind),
                  title: _cleanupTitle(context, s.kind),
                  summary: _cleanupSummary(context, s),
                  onTap: () => onReview(s.kind.name),
                ),
              if (hasFiles)
                _CleanupCard(
                  icon: Icons.bar_chart_rounded,
                  title: l10n.storageAnalyzerBiggestFiles,
                  summary: l10n.storageAnalyzerBiggestFilesSubtitle,
                  onTap: () => onReview(storageReviewBiggest),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  final List<StorageNode> nodes;
  final String title;
  if (review == storageReviewBiggest) {
    nodes = notifier.topFiles();
    title = l10n.storageAnalyzerBiggestFiles;
  } else {
    CleanupSuggestion? found;
    for (final s in state.cleanup) {
      if (s.kind.name == review) found = s;
    }
    nodes = found?.nodes ?? const <StorageNode>[];
    title = found == null
        ? l10n.storageAnalyzerCleanupHeader
        : _cleanupTitle(context, found.kind);
  }

  return [
    SliverToBoxAdapter(
      child: _ListHeader(
        title: title,
        backLabel: l10n.storageAnalyzerAllSuggestions,
        onBack: () => onReview(null),
        onSelectAll: nodes.isEmpty
            ? null
            : () => notifier.addSelected(nodes.map((n) => n.path)),
      ),
    ),
    ..._flatList(state, actions, nodes),
  ];
}

String _cleanupTitle(BuildContext context, CleanupKind kind) {
  final l10n = context.l10n;
  return switch (kind) {
    CleanupKind.largeFiles => l10n.storageAnalyzerCleanupLarge,
    CleanupKind.staleFiles => l10n.storageAnalyzerCleanupStale,
    CleanupKind.tempFiles => l10n.storageAnalyzerCleanupTemp,
    CleanupKind.emptyFolders => l10n.storageAnalyzerCleanupEmpty,
  };
}

IconData _cleanupIcon(CleanupKind kind) => switch (kind) {
  CleanupKind.largeFiles => Icons.data_usage_rounded,
  CleanupKind.staleFiles => Icons.history_rounded,
  CleanupKind.tempFiles => Icons.cleaning_services_rounded,
  CleanupKind.emptyFolders => Icons.folder_off_outlined,
};

String _cleanupSummary(BuildContext context, CleanupSuggestion s) {
  final count = context.l10n.storageAnalyzerItemCount(s.count);
  return s.bytes > 0 ? '$count · ${formatBytes(s.bytes)}' : count;
}

// ── Shared pieces ────────────────────────────────────────────────────────────

/// A flat, lazily built list of nodes with their full paths, for views that
/// gather files from all over the volume.
List<Widget> _flatList(
  StorageAnalyzerState state,
  StorageActions actions,
  List<StorageNode> nodes,
) {
  final selecting = state.hasSelection;
  return [
    SliverList(
      delegate: SliverChildBuilderDelegate((context, i) {
        final n = nodes[i];
        return StorageNodeTile(
          key: ValueKey(n.path),
          node: n,
          parentBytes: 0,
          selected: state.selectedPaths.contains(n.path),
          selecting: selecting,
          drill: false,
          showPath: true,
          actions: actions,
        );
      }, childCount: nodes.length),
    ),
  ];
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.typography.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Heading for a drilled-in list: a back button, the title, and "select all".
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.backLabel,
    required this.onBack,
    required this.onSelectAll,
  });

  final String title;
  final String backLabel;
  final VoidCallback onBack;
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(backLabel),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onSelectAll,
                icon: const Icon(Icons.select_all_rounded, size: 18),
                label: Text(l10n.selectAll),
              ),
            ],
          ),
        ),
        SectionHeader(title),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.breakdown,
    required this.totalBytes,
    required this.onTap,
  });

  final StorageCategoryBreakdown breakdown;
  final int totalBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final style = storageCategoryStyle(context, breakdown.category);
    final double fraction = totalBytes > 0
        ? (breakdown.sizeBytes / totalBytes).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final pct = storagePercentLabel(breakdown.sizeBytes, totalBytes);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.fill,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                storageCategoryIcon(breakdown.category),
                size: AppIconSize.standard,
                color: style.onFill,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storageCategoryLabel(context, breakdown.category),
                    style: textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.storageAnalyzerFileCount(breakdown.fileCount),
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 4,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: style.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatBytes(breakdown.sizeBytes),
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (pct.isNotEmpty)
                  Text(
                    pct,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _CleanupCard extends StatelessWidget {
  const _CleanupCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    icon,
                    size: AppIconSize.standard,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onTap,
                  child: Text(context.l10n.storageAnalyzerCleanupReview),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
