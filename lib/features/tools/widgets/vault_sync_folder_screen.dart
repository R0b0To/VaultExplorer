import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/services/vault_sync_service.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_entry_actions.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_target_style.dart';

/// Which rows the folder explorer shows.
enum _ExplorerFilter { all, differences, onlyLeft, onlyRight }

/// Browses the two compared sides together, one folder at a time: every
/// file and folder from both sides, merged and labelled (only on one side,
/// newer on one side, in sync...), with sizes and full modification times.
///
/// This is how the person sees what is inside a folder -- including folders
/// that exist on only one side, and files that are already in sync (which the
/// results list leaves out). From here any item can be opened, copied across
/// or deleted, singly or several at once.
class VaultSyncFolderScreen extends ConsumerStatefulWidget {
  /// The folder to show, relative to both compared roots ('' = the root).
  final String initialPath;

  /// An entry (by relative path) to scroll to and highlight on arrival --
  /// set when the screen is opened from "Show in folder".
  final String? highlightPath;

  const VaultSyncFolderScreen({
    super.key,
    this.initialPath = '',
    this.highlightPath,
  });

  @override
  ConsumerState<VaultSyncFolderScreen> createState() =>
      _VaultSyncFolderScreenState();
}

class _VaultSyncFolderScreenState extends ConsumerState<VaultSyncFolderScreen> {
  /// Row height. Scales with the system text size so the three text lines in
  /// a row never overflow, and stays fixed per build so the list can jump
  /// straight to a highlighted row.
  double _rowExtentFor(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(62) + 30).roundToDouble();

  late String _path = widget.initialPath;
  String? _highlight;
  VaultSyncFolderListing? _listing;
  bool _loading = true;
  _ExplorerFilter _filter = _ExplorerFilter.all;
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();

  /// Bumped on every load so a slow, superseded listing can't overwrite a
  /// newer one (the person may navigate before the first one returns).
  int _loadToken = 0;

  VaultSyncService get _service =>
      VaultSyncService(ref.read(vaultFileIoApiProvider));

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _highlight = widget.highlightPath;
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = ref.read(vaultSyncProvider);
    final left = state.left;
    final right = state.right;
    if (left == null || right == null) return;

    final token = ++_loadToken;
    setState(() => _loading = true);
    final listing = await _service.listFolder(
      left: left,
      right: right,
      relDir: _path,
    );
    if (!mounted || token != _loadToken) return;
    setState(() {
      _listing = listing;
      _loading = false;
      // Forget ticks for items that are no longer here (deleted, or the
      // person moved to another folder).
      final names = {for (final e in listing.entries) e.id};
      _selected.removeWhere((id) => !names.contains(id));
    });
    _scrollToHighlight();
  }

  void _scrollToHighlight() {
    final target = _highlight;
    final listing = _listing;
    if (target == null || listing == null) return;
    final index = _visible(listing.entries).indexWhere(
      (e) => e.relativePath == target,
    );
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final offset = (index * _rowExtentFor(context) - 120).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(offset);
    });
  }

  void _goTo(String path) {
    if (path == _path) return;
    setState(() {
      _path = path;
      _highlight = null;
      _selected.clear();
    });
    unawaited(_load());
  }

  String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  /// Rows for the current filter. In "Differences", a folder present on both
  /// sides stays visible only if the last comparison found a difference
  /// somewhere inside it (or no comparison has been run).
  List<VaultDiffEntry> _visible(List<VaultDiffEntry> all) {
    if (_filter == _ExplorerFilter.all) return all;
    final scanned = ref.read(vaultSyncProvider).entries;
    final haveScan = ref.read(vaultSyncProvider).progress.stage ==
        VaultSyncScanStage.complete;
    bool hasDiffInside(VaultDiffEntry folder) =>
        !haveScan ||
        scanned.any((e) => e.relativePath.startsWith('${folder.relativePath}/'));
    return all.where((e) {
      switch (_filter) {
        case _ExplorerFilter.all:
          return true;
        case _ExplorerFilter.onlyLeft:
          return e.status == VaultDiffStatus.onlyLeft;
        case _ExplorerFilter.onlyRight:
          return e.status == VaultDiffStatus.onlyRight;
        case _ExplorerFilter.differences:
          if (e.status == VaultDiffStatus.identical) return false;
          if (e.status == VaultDiffStatus.bothFolders) {
            return hasDiffInside(e);
          }
          return true;
      }
    }).toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _onRowTap(VaultDiffEntry entry) {
    if (_selecting) {
      _toggle(entry);
      return;
    }
    // A folder on both sides, or on one side, is entered. (A file-versus-
    // folder mismatch can't be entered -- it has no single contents.)
    if (entry.isDir && !entry.typeMismatch) {
      _goTo(entry.relativePath);
      return;
    }
    _showSheet(entry);
  }

  void _toggle(VaultDiffEntry entry) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(entry.id)) _selected.add(entry.id);
    });
  }

  void _showSheet(VaultDiffEntry entry) {
    final state = ref.read(vaultSyncProvider);
    final left = state.left;
    final right = state.right;
    if (left == null || right == null) return;
    unawaited(
      showVaultSyncEntrySheet(
        context,
        ref,
        entry: entry,
        left: left,
        right: right,
        names: vaultSyncNamesOf(left, right, context.l10n),
        onOpenFolder: () => _goTo(entry.relativePath),
        // Already looking at the folder that contains it.
        onShowInFolder: null,
        onChanged: () => unawaited(_load()),
      ),
    );
  }

  List<VaultDiffEntry> get _selectedEntries {
    final all = _listing?.entries ?? const <VaultDiffEntry>[];
    return all.where((e) => _selected.contains(e.id)).toList();
  }

  Future<void> _copySelected({required bool toRight}) async {
    final entries = _selectedEntries;
    setState(_selected.clear);
    await copyVaultSyncEntriesNow(
      context,
      ref,
      entries: entries,
      toRight: toRight,
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _deleteSelected({required bool left, required bool right}) async {
    final entries = _selectedEntries;
    final changed = await confirmAndDeleteVaultSyncEntries(
      context,
      ref,
      entries: entries,
      fromLeft: left,
      fromRight: right,
    );
    if (!mounted) return;
    if (changed) setState(_selected.clear);
    unawaited(_load());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultSyncProvider);
    final left = state.left;
    final right = state.right;
    final cs = context.colors;
    final listing = _listing;
    final names = vaultSyncNamesOf(left, right, context.l10n);

    return SkinAreaScope(
      area: SkinArea.tools,
      child: PopScope(
        // Back goes up a folder (or out of selection mode) before it leaves.
        canPop: _path.isEmpty && !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selecting) {
            setState(_selected.clear);
          } else {
            _goTo(_parentOf(_path));
          }
        },
        child: Scaffold(
          appBar: _selecting ? _selectionAppBar(context) : _appBar(context),
          body: (left == null || right == null)
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    _breadcrumb(context, names),
                    _filterRow(context, names),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                    Expanded(child: _body(context, listing, names)),
                  ],
                ),
          bottomNavigationBar:
              _selecting && left != null && right != null
              ? _selectionBar(context, names)
              : null,
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) => AppBar(
    elevation: 0,
    title: Text(
      context.l10n.vaultSyncExplorerTitle,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.refresh_rounded),
        tooltip: context.l10n.vaultSyncRecompareButton,
        onPressed: _loading ? null : () => unawaited(_load()),
      ),
      const AppBarTransferButton(),
      const SizedBox(width: 4),
    ],
  );

  PreferredSizeWidget _selectionAppBar(BuildContext context) => AppBar(
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.close_rounded),
      onPressed: () => setState(_selected.clear),
    ),
    title: Text(
      context.l10n.vaultSyncSelectedCount(_selected.length),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.select_all_rounded),
        tooltip: context.l10n.selectAll,
        onPressed: () => setState(() {
          _selected
            ..clear()
            ..addAll(_visible(_listing?.entries ?? const []).map((e) => e.id));
        }),
      ),
    ],
  );

  Widget _breadcrumb(BuildContext context, VaultSyncNames names) {
    final cs = context.colors;
    final textTheme = context.typography;
    final segments = _path.isEmpty ? <String>[] : _path.split('/');
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _crumb(context, context.l10n.vaultFolderPickerRootLabel, '', last: segments.isEmpty),
          for (var i = 0; i < segments.length; i++) ...[
            Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
            _crumb(
              context,
              segments[i],
              segments.sublist(0, i + 1).join('/'),
              last: i == segments.length - 1,
            ),
          ],
          const SizedBox(width: 12),
          Center(
            child: Text(
              '${names.left}  ⇄  ${names.right}',
              style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _crumb(BuildContext context, String label, String path, {required bool last}) {
    final cs = context.colors;
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: last ? null : () => _goTo(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            label,
            style: context.typography.bodyMedium?.copyWith(
              fontWeight: last ? FontWeight.bold : FontWeight.w500,
              color: last ? cs.onSurface : cs.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterRow(BuildContext context, VaultSyncNames names) {
    String label(_ExplorerFilter f) => switch (f) {
      _ExplorerFilter.all => context.l10n.vaultSyncFilterAll,
      _ExplorerFilter.differences => context.l10n.vaultSyncFilterDifferences,
      _ExplorerFilter.onlyLeft => context.l10n.vaultSyncFilterOnlyIn(names.left),
      _ExplorerFilter.onlyRight => context.l10n.vaultSyncFilterOnlyIn(
        names.right,
      ),
    };
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final f in _ExplorerFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label(f)),
                showCheckmark: false,
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    VaultSyncFolderListing? listing,
    VaultSyncNames names,
  ) {
    if (_loading && listing == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (listing == null) return const SizedBox.shrink();
    if (listing.unreadable) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.vaultSyncExplorerLoadFailedTitle,
        message: context.l10n.vaultSyncExplorerLoadFailedMessage,
        actionLabel: context.l10n.vaultSyncRecompareButton,
        actionIcon: Icons.refresh_rounded,
        onAction: () => unawaited(_load()),
      );
    }
    final rows = _visible(listing.entries);
    if (rows.isEmpty) {
      return AppEmptyState(
        icon: Icons.folder_open_rounded,
        title: context.l10n.vaultSyncExplorerEmptyTitle,
        message: context.l10n.vaultSyncExplorerEmptyMessage,
      );
    }
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          itemExtent: _rowExtentFor(context),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: rows.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _row(context, rows[i], names),
          ),
        ),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, VaultDiffEntry e, VaultSyncNames names) {
    final cs = context.colors;
    final textTheme = context.typography;
    final selected = _selected.contains(e.id);
    final highlighted = e.relativePath == _highlight;
    final color = e.statusColor(cs);

    // One line per storage: its name, then size and full date + time.
    Widget sideLine(bool isLeft) {
      final present = isLeft ? e.existsOnLeft : e.existsOnRight;
      final size = isLeft ? e.leftSizeBytes : e.rightSizeBytes;
      final secs = isLeft ? e.leftModifiedSecs : e.rightModifiedSecs;
      final dirOnSide = e.typeMismatch
          ? (isLeft ? e.isDir : !e.isDir)
          : e.isDir;
      final detail = !present
          ? '—'
          : [
              if (!dirOnSide && size != null) formatBytes(size),
              formatEntryDateTime(secs ?? 0, context),
            ].join(' · ');
      final style = textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
      return Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              isLeft ? names.left : names.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    }

    return Material(
      color: selected
          ? cs.primaryContainer
          : highlighted
          ? cs.tertiaryContainer.withValues(alpha: 0.6)
          : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onRowTap(e),
        onLongPress: () => _toggle(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : e.isDir
                    ? Icons.folder_rounded
                    : iconForFile(e.name),
                color: selected
                    ? cs.primary
                    : e.isDir
                    ? cs.secondary
                    : colorForFile(e.name),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    sideLine(true),
                    sideLine(false),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      e.statusLabel(context.l10n, names),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!_selecting)
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => _showSheet(e),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context, VaultSyncNames names) {
    final cs = context.colors;
    final notifier = ref.read(vaultSyncProvider.notifier);
    final entries = _selectedEntries;
    bool any(EntryAction a) => entries.any((e) => notifier.canApply(e, a));

    return Material(
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: any(EntryAction.copyToRight)
                    ? () => unawaited(_copySelected(toRight: true))
                    : null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  context.l10n.vaultSyncActionCopyTo(names.right),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: any(EntryAction.copyToLeft)
                    ? () => unawaited(_copySelected(toRight: false))
                    : null,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(
                  context.l10n.vaultSyncActionCopyTo(names.left),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<(bool, bool)>(
                enabled: any(EntryAction.deleteLeft) || any(EntryAction.deleteRight),
                tooltip: context.l10n.delete,
                onSelected: (v) =>
                    unawaited(_deleteSelected(left: v.$1, right: v.$2)),
                itemBuilder: (_) => [
                  if (any(EntryAction.deleteLeft))
                    PopupMenuItem(
                      value: (true, false),
                      child: Text(
                        context.l10n.vaultSyncDeleteFromAction(names.left),
                      ),
                    ),
                  if (any(EntryAction.deleteRight))
                    PopupMenuItem(
                      value: (false, true),
                      child: Text(
                        context.l10n.vaultSyncDeleteFromAction(names.right),
                      ),
                    ),
                  if (any(EntryAction.deleteLeft) && any(EntryAction.deleteRight))
                    PopupMenuItem(
                      value: (true, true),
                      child: Text(context.l10n.vaultSyncDeleteFromBothAction),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: cs.error),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.delete,
                        style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
