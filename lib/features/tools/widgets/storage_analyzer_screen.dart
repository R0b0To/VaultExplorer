// Storage Analyzer: see where a vault's space goes, then do something about it.
//
// Four views over one scanned folder tree --
//   Map      the current folder as a treemap; big tiles are big files/folders
//   Folders  the same folder as a sortable list with each item's share
//   Types    usage by file type, drilling into the largest files of one type
//   Cleanup  suggestions (large, stale, temporary, empty) and the biggest files
// -- and one shared selection. Long-press (or the row menu) selects; the bar
// at the bottom deletes, copies a path, or jumps to the file browser.
//
// Deleting goes through the same background file operation the browser uses,
// after a confirmation that states how much space it frees and that it cannot
// be undone (a vault has no recycle bin).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/path_clipboard.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/features/browser/controllers/bookmark_navigation_request.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_views.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_widgets.dart';

enum _StorageTab { map, folders, types, cleanup }

class StorageAnalyzerScreen extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  /// Opens a vault in the file browser. When null (the tool was opened
  /// somewhere with no browser to go to) the "show in file browser" action is
  /// hidden.
  final ValueChanged<MountedContainer>? onOpenInBrowser;

  const StorageAnalyzerScreen({
    super.key,
    required this.mountedContainers,
    this.onOpenInBrowser,
  });

  @override
  ConsumerState<StorageAnalyzerScreen> createState() =>
      _StorageAnalyzerScreenState();
}

class _StorageAnalyzerScreenState extends ConsumerState<StorageAnalyzerScreen> {
  _StorageTab _tab = _StorageTab.map;

  /// Which cleanup suggestion is open for review (a [CleanupKind] name or
  /// [storageReviewBiggest]); null shows the list of suggestions.
  String? _review;

  @override
  void initState() {
    super.initState();
    final list = widget.mountedContainers.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(storageAnalyzerProvider.notifier);
      notifier.watchContentChanges();
      if (list.isNotEmpty) unawaited(notifier.selectTarget(list.first));
    });
    widget.mountedContainers.addListener(_onMountedChanged);
  }

  @override
  void dispose() {
    widget.mountedContainers.removeListener(_onMountedChanged);
    super.dispose();
  }

  void _onMountedChanged() {
    ref
        .read(storageAnalyzerProvider.notifier)
        .onMountedListChanged(widget.mountedContainers.value);
  }

  void _setTab(_StorageTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _review = null;
    });
  }

  // ── Interaction ────────────────────────────────────────────────────────────

  StorageActions _actions(StorageAnalyzer notifier) {
    return StorageActions(
      onTap: _onTapNode,
      onLongPress: (node) {
        if (ref.read(storageAnalyzerProvider).busy) return;
        unawaited(HapticFeedback.selectionClick());
        notifier.toggleSelected(node.path);
      },
      onMore: (node) => unawaited(_showNodeSheet(node)),
      onNavigate: notifier.openFolder,
    );
  }

  void _onTapNode(StorageNode node, bool drill) {
    final st = ref.read(storageAnalyzerProvider);
    final notifier = ref.read(storageAnalyzerProvider.notifier);
    if (st.busy) return;
    // Once something is ticked, taps keep ticking.
    if (st.hasSelection) {
      notifier.toggleSelected(node.path);
      return;
    }
    if (node.isDir && drill) {
      notifier.openFolder(node.path);
      return;
    }
    unawaited(_showNodeSheet(node));
  }

  Future<void> _showNodeSheet(StorageNode node) async {
    final st = ref.read(storageAnalyzerProvider);
    if (st.busy) return;
    final notifier = ref.read(storageAnalyzerProvider.notifier);
    final l10n = context.l10n;
    final cs = context.colors;
    final textTheme = context.typography;
    final canBrowse = widget.onOpenInBrowser != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return AppBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatBytes(node.sizeBytes)} · '
                '${l10n.storageAnalyzerFileCount(node.fileCount)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                node.path.isEmpty ? '/' : node.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (node.isDir)
                SheetOptionTile(
                  icon: Icons.folder_open_rounded,
                  title: l10n.storageAnalyzerOpenFolder,
                  onTap: () => closeThen(() {
                    notifier.openFolder(node.path);
                    // Flat lists have no folder to open into, so go where
                    // there is one.
                    if (_tab != _StorageTab.map &&
                        _tab != _StorageTab.folders) {
                      _setTab(_StorageTab.folders);
                    }
                  }),
                ),
              if (node.isDir)
                SheetOptionTile(
                  icon: Icons.refresh_rounded,
                  title: l10n.storageAnalyzerRescanFolder,
                  onTap: () => closeThen(
                    () => unawaited(notifier.refreshFolder(node.path)),
                  ),
                ),
              if (canBrowse)
                SheetOptionTile(
                  icon: Icons.drive_file_move_outline,
                  title: l10n.goToLocationAction,
                  onTap: () => closeThen(() => _showInBrowser(node)),
                ),
              SheetOptionTile(
                icon: Icons.content_copy_rounded,
                title: l10n.copyPathAction,
                onTap: () => closeThen(
                  () => unawaited(copyPathToClipboard(context, node.path)),
                ),
              ),
              SheetOptionTile(
                icon: Icons.check_circle_outline_rounded,
                title: l10n.storageAnalyzerSelectAction,
                onTap: () =>
                    closeThen(() => notifier.toggleSelected(node.path)),
              ),
              SheetOptionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: cs.error,
                title: l10n.delete,
                onTap: () =>
                    closeThen(() => unawaited(_confirmAndDelete([node]))),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Leaves the analyzer for the file browser, opened on the folder holding
  /// [node] (or on [node] itself if it is a folder).
  void _showInBrowser(StorageNode node) {
    final open = widget.onOpenInBrowser;
    final container = ref.read(storageAnalyzerProvider).selected;
    if (open == null || container == null) return;
    // Everything the hand-off needs is taken before popping: this screen's
    // ref is gone once the route closes.
    final requests = ref.read(bookmarkNavigationRequestsProvider.notifier);
    final navigator = Navigator.of(context);
    final dir = node.isDir ? node.path : node.parentPath;
    navigator.pop();
    // Same order the drawer uses: bring the vault's browser to the front
    // first, then ask it to go to the folder.
    open(container);
    requests.request(container.volId, VaultBookmark(dir, isDir: true));
  }

  Future<void> _confirmAndDelete(List<StorageNode> nodes) async {
    final st = ref.read(storageAnalyzerProvider);
    final tree = st.tree;
    if (nodes.isEmpty || tree == null || st.busy) return;
    final l10n = context.l10n;

    if (!st.canModify) {
      showAppSnackBar(
        context,
        message: l10n.readOnlyCantDelete,
        tone: AppBannerTone.warning,
      );
      return;
    }

    // Collapse nested picks exactly as the delete itself will, so the dialog
    // describes what will really happen.
    final selection = tree.resolveSelection(nodes.map((n) => n.path));
    if (selection.isEmpty) return;

    unawaited(HapticFeedback.heavyImpact());
    final message = selection.hasFolder
        ? l10n.storageAnalyzerDeleteFoldersMessage(
            '${selection.files}',
            formatBytes(selection.bytes),
          )
        : l10n.storageAnalyzerDeleteFilesMessage(formatBytes(selection.bytes));
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.deleteItemsTitle(selection.nodes.length),
      message: message,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      final result = await ref
          .read(storageAnalyzerProvider.notifier)
          .deleteNodes(selection.nodes, l10n);
      if (!mounted) return;
      _reportDelete(result);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeleteError,
        tone: AppBannerTone.error,
      );
    }
  }

  void _reportDelete(StorageDeleteResult r) {
    final l10n = context.l10n;
    if (r.readOnly) {
      showAppSnackBar(
        context,
        message: l10n.readOnlyCantDelete,
        tone: AppBannerTone.warning,
      );
    } else if (r.deleted == 0 && r.failed == 0) {
      return; // superseded by a rescan or the screen closing
    } else if (r.failed == 0) {
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeleteDone(formatBytes(r.freedBytes)),
        tone: AppBannerTone.success,
      );
    } else if (r.deleted == 0) {
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeleteNone,
        tone: AppBannerTone.error,
      );
    } else {
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeletePartial(
          '${r.deleted}',
          '${r.failed}',
          formatBytes(r.freedBytes),
        ),
        tone: AppBannerTone.warning,
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storageAnalyzerProvider);
    final notifier = ref.read(storageAnalyzerProvider.notifier);
    final l10n = context.l10n;
    final selection = st.selection;
    final showBar = st.hasSelection && !selection.isEmpty;

    return PopScope(
      // Back leaves selection mode before it leaves the screen.
      canPop: !st.hasSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) notifier.clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.toolStorageAnalyzerTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.duplicateFinderRescan,
              onPressed: st.selected == null || st.loading || st.busy
                  ? null
                  : () => unawaited(notifier.rescan()),
            ),
          ],
        ),
        bottomNavigationBar: showBar
            ? _SelectionBar(
                selection: selection,
                busy: st.busy,
                canBrowse: widget.onOpenInBrowser != null,
                onClear: notifier.clearSelection,
                onDelete: () => unawaited(_confirmAndDelete(selection.nodes)),
                onBrowse: () => _showInBrowser(selection.nodes.first),
                onCopyPath: () => unawaited(
                  copyPathToClipboard(context, selection.nodes.first.path),
                ),
              )
            : null,
        body: ValueListenableBuilder<List<MountedContainer>>(
          valueListenable: widget.mountedContainers,
          builder: (context, mountedList, _) {
            if (mountedList.isEmpty) {
              return AppEmptyState(
                icon: Icons.pie_chart_outline_rounded,
                title: l10n.storageAnalyzerNoTargetsTitle,
                message: l10n.storageAnalyzerNoTargetsMessage,
              );
            }
            return _buildBody(context, mountedList, st, notifier);
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<MountedContainer> mountedList,
    StorageAnalyzerState st,
    StorageAnalyzer notifier,
  ) {
    final l10n = context.l10n;
    final selected = st.selected;
    final actions = _actions(notifier);
    final rootLabel = selected?.displayName ?? '';

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: OptionPickerTile<int>(
            label: l10n.storageAnalyzerTargetLabel,
            value: selected?.volId ?? mountedList.first.volId,
            subtitle: selected?.displayName ?? mountedList.first.displayName,
            prefixIcon: Icons.lock_open_rounded,
            enabled: !st.busy,
            options: mountedList
                .map((c) => SelectOption(value: c.volId, label: c.displayName))
                .toList(),
            onChanged: (volId) {
              final match = mountedList.where((c) => c.volId == volId);
              if (match.isNotEmpty) {
                unawaited(notifier.selectTarget(match.first));
              }
            },
          ),
        ),
      ),
    ];

    final tree = st.tree;
    if (st.loading || (selected != null && tree == null)) {
      slivers.add(SliverToBoxAdapter(child: _ScanningPanel(st.progress)));
    } else if (selected != null && tree != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _UsageSummary(state: st),
          ),
        ),
      );
      if (st.stale) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineBanner(
                l10n.storageAnalyzerStaleNotice,
                icon: Icons.sync_problem_rounded,
                trailing: TextButton(
                  onPressed: st.busy
                      ? null
                      : () => unawaited(notifier.rescan()),
                  child: Text(l10n.duplicateFinderRescan),
                ),
              ),
            ),
          ),
        );
      }
      if (st.truncated || st.hasUnreadable) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineBanner(
                st.truncated
                    ? l10n.storageAnalyzerScanTruncatedNotice(
                        '${st.scannedCount}',
                      )
                    : l10n.storageAnalyzerPartialNotice,
                tone: AppBannerTone.warning,
              ),
            ),
          ),
        );
      }
      slivers.add(SliverToBoxAdapter(child: _buildTabs(context)));

      switch (_tab) {
        case _StorageTab.map:
          slivers.addAll(
            buildStorageMapSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
              rootLabel: rootLabel,
              onShowList: () => _setTab(_StorageTab.folders),
            ),
          );
        case _StorageTab.folders:
          slivers.addAll(
            buildStorageFoldersSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
              rootLabel: rootLabel,
            ),
          );
        case _StorageTab.types:
          slivers.addAll(
            buildStorageTypesSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
            ),
          );
        case _StorageTab.cleanup:
          slivers.addAll(
            buildStorageCleanupSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
              review: _review,
              onReview: (key) => setState(() => _review = key),
            ),
          );
      }
    }

    slivers.add(
      const SliverToBoxAdapter(
        child: SizedBox(height: AppSpacing.floatingStackClearance),
      ),
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final l10n = context.l10n;
    Widget chip(_StorageTab tab, IconData icon, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: Icon(icon, size: AppIconSize.small),
          label: Text(label),
          selected: _tab == tab,
          showCheckmark: false,
          onSelected: (_) => _setTab(tab),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          chip(
            _StorageTab.map,
            Icons.dashboard_outlined,
            l10n.storageAnalyzerTabMap,
          ),
          chip(
            _StorageTab.folders,
            Icons.folder_outlined,
            l10n.storageAnalyzerTabFolders,
          ),
          chip(
            _StorageTab.types,
            Icons.pie_chart_outline_rounded,
            l10n.storageAnalyzerTabTypes,
          ),
          chip(
            _StorageTab.cleanup,
            Icons.cleaning_services_outlined,
            l10n.storageAnalyzerTabCleanup,
          ),
        ],
      ),
    );
  }
}

/// Used / free at a glance. A compact ring plus text rather than the former
/// full-width gauge, so the interactive views start higher on the screen.
class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.state});

  final StorageAnalyzerState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;

    final total = state.totalBytes ?? -1;
    final free = state.freeBytes ?? -1;
    final scanned = state.tree?.totalBytes ?? 0;
    final files = state.tree?.fileCount ?? 0;
    final hasCapacity = total > 0 && free >= 0;
    final used = hasCapacity ? (total - free).clamp(0, total) : 0;
    final double fraction = hasCapacity
        ? (used / total).clamp(0.0, 1.0).toDouble()
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
                if (hasCapacity)
                  Text(
                    '${(fraction * 100).round()}%',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  Icon(Icons.folder_shared_rounded, color: cs.primary),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCapacity
                      ? l10n.storageAnalyzerUsedOfTotal(
                          formatBytes(used),
                          formatBytes(total),
                        )
                      : l10n.storageAnalyzerContentSize(formatBytes(scanned)),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasCapacity)
                  Text(
                    l10n.storageAnalyzerFreeSpace(formatBytes(free)),
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                Text(
                  hasCapacity
                      ? '${l10n.storageAnalyzerFileCount(files)} · '
                            '${formatBytes(scanned)}'
                      : l10n.storageAnalyzerFileCount(files),
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while scanning: a spinner and a live count, so a big vault reads as
/// working rather than stuck.
class _ScanningPanel extends StatelessWidget {
  const _ScanningPanel(this.progress);

  final StorageScanProgress? progress;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final p = progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.storageAnalyzerScanningMessage),
          if (p != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.storageAnalyzerScanProgress(
                '${p.files}',
                formatBytes(p.bytes),
              ),
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// The bar that appears once anything is ticked: how much, and what to do.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selection,
    required this.busy,
    required this.canBrowse,
    required this.onClear,
    required this.onDelete,
    required this.onBrowse,
    required this.onCopyPath,
  });

  final StorageSelection selection;
  final bool busy;
  final bool canBrowse;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback onBrowse;
  final VoidCallback onCopyPath;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final single = selection.nodes.length == 1;

    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: busy ? null : onClear,
              ),
              Expanded(
                child: Text(
                  l10n.storageAnalyzerSelectedSummary(
                    selection.nodes.length,
                    formatBytes(selection.bytes),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (single && canBrowse)
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outline),
                  tooltip: l10n.goToLocationAction,
                  onPressed: busy ? null : onBrowse,
                ),
              if (single)
                IconButton(
                  icon: const Icon(Icons.content_copy_rounded),
                  tooltip: l10n.copyPathAction,
                  onPressed: busy ? null : onCopyPath,
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
