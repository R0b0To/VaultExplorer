import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/services/vault_sync_service.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_location_picker_sheet.dart';

/// Vault-to-Vault Synchronizer / Diff tool.
///
/// Lets the user pick a Left and Right vault (or two folders in the same
/// vault), compares them with [VaultSyncService.scanDiff], and applies a
/// 1-click two-way or one-way sync using [VaultSyncService.executeSync] --
/// which reuses the same [FileOperationService] batch copy engine as a
/// normal multi-select copy in the file browser.
class VaultSyncScreen extends StatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const VaultSyncScreen({super.key, required this.mountedContainers});

  @override
  State<VaultSyncScreen> createState() => _VaultSyncScreenState();
}

class _VaultSyncScreenState extends State<VaultSyncScreen> {
  final VaultSyncService _service = VaultSyncService();
  final TextEditingController _searchController = TextEditingController();

  VaultSyncSide? _left;
  VaultSyncSide? _right;

  bool _isComparing = false;
  VaultSyncScanProgress _progress = const VaultSyncScanProgress(
    stage: VaultSyncScanStage.idle,
  );
  List<VaultDiffEntry> _entries = const [];
  int _identicalCount = 0;
  VaultSyncCancellationToken? _cancelToken;

  SyncDirection _direction = SyncDirection.twoWay;
  final Map<String, EntryAction> _overrides = {};

  bool _isSyncing = false;

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canCompare {
    final left = _left;
    final right = _right;
    if (left == null || right == null) return false;
    return left != right;
  }

  Future<void> _pickSide({required bool isLeft}) async {
    final containers = widget.mountedContainers.value;
    if (containers.isEmpty) return;
    final result = await Navigator.push<VaultSyncSide>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultSyncLocationPickerSheet(
          mountedContainers: containers,
          sideLabel: isLeft
              ? context.l10n.vaultSyncLeftLabel
              : context.l10n.vaultSyncRightLabel,
          initialSide: isLeft ? _left : _right,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isLeft) {
        _left = result;
      } else {
        _right = result;
      }
      _resetResults();
    });
  }

  void _swapSides() {
    setState(() {
      final tmp = _left;
      _left = _right;
      _right = tmp;
      _resetResults();
    });
  }

  void _resetResults() {
    _cancelToken?.cancel();
    _isComparing = false;
    _entries = const [];
    _identicalCount = 0;
    _overrides.clear();
    _progress = const VaultSyncScanProgress(stage: VaultSyncScanStage.idle);
  }

  Future<void> _startCompare() async {
    final left = _left;
    final right = _right;
    if (left == null || right == null || left == right) return;

    _cancelToken?.cancel();
    final token = VaultSyncCancellationToken();
    _cancelToken = token;

    setState(() {
      _isComparing = true;
      _entries = const [];
      _identicalCount = 0;
      _overrides.clear();
      _progress = const VaultSyncScanProgress(stage: VaultSyncScanStage.comparing);
    });

    await for (final update in _service.scanDiff(
      left: left,
      right: right,
      cancelToken: token,
    )) {
      if (!mounted) return;
      setState(() {
        _progress = update.progress;
        _entries = update.entries;
        _identicalCount = update.identicalCount;
        if (update.progress.stage == VaultSyncScanStage.complete ||
            update.progress.stage == VaultSyncScanStage.cancelled) {
          _isComparing = false;
        }
      });
    }
  }

  void _cancelCompare() {
    _cancelToken?.cancel();
  }

  EntryAction _actionFor(VaultDiffEntry e) {
    final override = _overrides[e.id];
    var action = override ?? _service.defaultAction(e, _direction);
    if (action == EntryAction.copyToRight && (_right?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    if (action == EntryAction.copyToLeft && (_left?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    return action;
  }

  void _setOverride(VaultDiffEntry e, EntryAction action) {
    setState(() => _overrides[e.id] = action);
  }

  List<VaultDiffEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    return _entries
        .where((e) => e.relativePath.toLowerCase().contains(_searchQuery))
        .toList();
  }

  int get _pendingCopyToRightCount =>
      _entries.where((e) => _actionFor(e) == EntryAction.copyToRight).length;

  int get _pendingCopyToLeftCount =>
      _entries.where((e) => _actionFor(e) == EntryAction.copyToLeft).length;

  int get _pendingTotal => _pendingCopyToRightCount + _pendingCopyToLeftCount;

  int get _pendingBytesToRight {
    var total = 0;
    for (final e in _entries) {
      if (_actionFor(e) == EntryAction.copyToRight) total += e.leftSizeBytes ?? 0;
    }
    return total;
  }

  int get _pendingBytesToLeft {
    var total = 0;
    for (final e in _entries) {
      if (_actionFor(e) == EntryAction.copyToLeft) total += e.rightSizeBytes ?? 0;
    }
    return total;
  }

  int get _pendingBytes => _pendingBytesToRight + _pendingBytesToLeft;

  Future<void> _confirmAndSync() async {
    if (_isSyncing) return;
    final left = _left;
    final right = _right;
    if (left == null || right == null || _pendingTotal == 0) return;

    final pendingTotal = _pendingTotal;
    final pendingBytes = _pendingBytes;
    final bytesToRight = _pendingBytesToRight;
    final bytesToLeft = _pendingBytesToLeft;

    // Set this synchronously, before the first `await`, so a rapid second
    // tap can't slip through while the space check or confirm dialog is
    // still in flight -- not just once copying actually starts.
    setState(() => _isSyncing = true);

    final hasSpace = await _checkAvailableSpace(
      left: left,
      right: right,
      bytesToLeft: bytesToLeft,
      bytesToRight: bytesToRight,
    );
    if (!hasSpace || !mounted) {
      if (mounted) setState(() => _isSyncing = false);
      return;
    }

    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.vaultSyncConfirmTitle,
      message: context.l10n.vaultSyncConfirmMessage(pendingTotal, formatBytes(pendingBytes)),
      confirmLabel: context.l10n.vaultSyncSyncNowButton,
    );
    if (!confirmed || !mounted) {
      if (mounted) setState(() => _isSyncing = false);
      return;
    }

    final plan = <String, EntryAction>{
      for (final e in _entries) e.id: _actionFor(e),
    };

    final ops = _service.executeSync(
      left: left,
      right: right,
      entries: _entries,
      plan: plan,
      l10n: context.l10n,
    );
    if (ops.isEmpty) {
      // Shouldn't happen given the _pendingTotal > 0 guard above, but don't
      // get stuck showing "Syncing…" forever if it somehow does.
      setState(() => _isSyncing = false);
      return;
    }
    _watchOpsForCompletion(ops);

    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.vaultSyncStartedMessage(pendingTotal),
        tone: AppBannerTone.success,
      );
    }
  }

  /// Queries live free space on whichever side(s) [bytesToLeft]/
  /// [bytesToRight] would actually write to, and blocks with an
  /// explanatory dialog if either is short. Uses the same 95%-of-free
  /// safety margin as [FileOperationService]'s own pre-flight check, so
  /// this agrees with whether the copy engine would go on to accept or
  /// reject the batch.
  Future<bool> _checkAvailableSpace({
    required VaultSyncSide left,
    required VaultSyncSide right,
    required int bytesToLeft,
    required int bytesToRight,
  }) async {
    final problems = <String>[];

    if (bytesToRight > 0) {
      final free = await _service.freeSpaceBytes(right.container);
      if (!mounted) return false;
      if (free != null && bytesToRight > (free * 0.95).floor()) {
        problems.add(
          context.l10n.vaultSyncNotEnoughSpaceMessage(
            right.displayLabel,
            formatBytes(bytesToRight),
            formatBytes(free),
          ),
        );
      }
    }
    if (bytesToLeft > 0) {
      final free = await _service.freeSpaceBytes(left.container);
      if (!mounted) return false;
      if (free != null && bytesToLeft > (free * 0.95).floor()) {
        problems.add(
          context.l10n.vaultSyncNotEnoughSpaceMessage(
            left.displayLabel,
            formatBytes(bytesToLeft),
            formatBytes(free),
          ),
        );
      }
    }

    if (problems.isEmpty) return true;
    if (!mounted) return false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.vaultSyncNotEnoughSpaceTitle),
        content: Text(problems.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.close),
          ),
        ],
      ),
    );
    return false;
  }

  /// Once every enqueued copy batch has left the pending/running state,
  /// clears the syncing flag and automatically re-runs the comparison so
  /// the diff list reflects what just got copied.
  void _watchOpsForCompletion(List<FileOperation> ops) {
    if (ops.isEmpty) return;
    var remaining = ops.length;
    for (final op in ops) {
      late final VoidCallback listener;
      listener = () {
        final done =
            op.status != FileOperationStatus.pending &&
            op.status != FileOperationStatus.running;
        if (!done) return;
        op.removeListener(listener);
        remaining--;
        if (remaining <= 0 && mounted) {
          setState(() => _isSyncing = false);
          _startCompare();
        }
      };
      op.addListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.surfaceContainerHigh,
        title: Text(
          context.l10n.toolVaultSyncTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ValueListenableBuilder<List<MountedContainer>>(
        valueListenable: widget.mountedContainers,
        builder: (context, containers, _) {
          if (containers.isEmpty) {
            return AppEmptyState(
              icon: Icons.sync_disabled_rounded,
              title: context.l10n.vaultSyncNoVaultsTitle,
              message: context.l10n.vaultSyncNoVaultsMessage,
            );
          }
          return Stack(
            children: [
              _buildMainList(context),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Align(
                  alignment: Alignment.center,
                  child: FloatingActivityStack(),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: (!_isComparing && _pendingTotal > 0)
          ? _buildBottomActionBar(context)
          : null,
    );
  }

  Widget _buildMainList(BuildContext context) {
    final showResults =
        !_isComparing &&
        _progress.stage != VaultSyncScanStage.idle &&
        _progress.stage != VaultSyncScanStage.cancelled &&
        _entries.isNotEmpty;
    final filtered = showResults ? _filteredEntries : const <VaultDiffEntry>[];
    final noSearchMatches = showResults && _searchQuery.isNotEmpty && filtered.isEmpty;

    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: 1 + filtered.length + (noSearchMatches ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidePickers(context),
              const SizedBox(height: AppSpacing.md),
              if (_isComparing)
                _buildComparingCard(context)
              else if (_progress.stage == VaultSyncScanStage.idle ||
                  _progress.stage == VaultSyncScanStage.cancelled)
                _buildIdleCard(context)
              else if (_entries.isEmpty)
                _buildInSyncCard(context)
              else ...[
                _buildSummaryCard(context),
                const SizedBox(height: AppSpacing.md),
                _buildSearchBar(context),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }
        if (noSearchMatches && index == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: context.l10n.noResultsTitle,
              message: context.l10n.noResultsForQueryMessage(_searchController.text.trim()),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _buildDiffTile(context, filtered[index - 1]),
        );
      },
    );
  }

  Widget _buildSidePickers(BuildContext context) {
    return SectionCard(
      children: [
        _buildSideTile(
          context,
          isLeft: true,
          side: _left,
          label: context.l10n.vaultSyncLeftLabel,
        ),
        _buildSwapRow(context),
        _buildSideTile(
          context,
          isLeft: false,
          side: _right,
          label: context.l10n.vaultSyncRightLabel,
        ),
        if (_left != null && _right != null && _left == _right)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              context.l10n.vaultSyncSameLocationWarning,
              style: context.typography.bodySmall?.copyWith(color: context.colors.error),
            ),
          ),
      ],
    );
  }

  Widget _buildSideTile(
    BuildContext context, {
    required bool isLeft,
    required VaultSyncSide? side,
    required String label,
  }) {
    final cs = context.colors;
    final textTheme = context.typography;
    final isReadOnly = side?.container.readOnly ?? false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        isLeft ? Icons.looks_one_rounded : Icons.looks_two_rounded,
        color: cs.primary,
      ),
      title: Row(
        children: [
          Text(label, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (isReadOnly) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: context.l10n.vaultSyncReadOnlyTooltip,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 12, color: cs.onErrorContainer),
                    const SizedBox(width: 3),
                    Text(
                      context.l10n.vaultSyncReadOnlyBadge,
                      style: textTheme.labelSmall?.copyWith(color: cs.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        side == null
            ? context.l10n.vaultSyncTapToSelect
            : '${side.container.displayName} / ${side.relativePath.isEmpty ? context.l10n.vaultFolderPickerRootLabel : side.relativePath}',
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: (_isComparing || _isSyncing) ? null : () => _pickSide(isLeft: isLeft),
    );
  }

  Widget _buildSwapRow(BuildContext context) {
    return Center(
      child: IconButton(
        icon: const Icon(Icons.swap_vert_rounded),
        tooltip: context.l10n.vaultSyncSwapTooltip,
        onPressed: (_left == null && _right == null) || _isComparing || _isSyncing
            ? null
            : _swapSides,
      ),
    );
  }

  Widget _buildIdleCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      Icons.compare_arrows_rounded,
                      color: cs.onPrimaryContainer,
                      size: AppIconSize.action,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.vaultSyncIntroTitle,
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          context.l10n.vaultSyncIntroSubtitle,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_canCompare && !_isSyncing) ? _startCompare : null,
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: Text(context.l10n.vaultSyncCompareButton),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparingCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.vaultSyncComparingLabel,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                context.l10n.vaultSyncCompareStatsLabel(
                  _progress.dirsScanned,
                  _progress.entriesCompared,
                ),
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _cancelCompare,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(context.l10n.vaultSyncCancelCompareButton),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInSyncCard(BuildContext context) {
    return Column(
      children: [
        AppEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: context.l10n.vaultSyncInSyncTitle,
          message: context.l10n.vaultSyncInSyncMessage(_identicalCount),
          actionLabel: context.l10n.vaultSyncRecompareButton,
          actionIcon: Icons.refresh_rounded,
          onAction: _startCompare,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    final onlyLeft = _entries.where((e) => e.status == VaultDiffStatus.onlyLeft).length;
    final onlyRight = _entries.where((e) => e.status == VaultDiffStatus.onlyRight).length;
    final leftNewer = _entries.where((e) => e.status == VaultDiffStatus.leftNewer).length;
    final rightNewer = _entries.where((e) => e.status == VaultDiffStatus.rightNewer).length;
    final conflicts = _entries.where((e) => e.status == VaultDiffStatus.conflicted).length;

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      Icons.difference_rounded,
                      color: cs.onPrimaryContainer,
                      size: AppIconSize.action,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.vaultSyncDifferencesFoundLabel(_entries.length),
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          context.l10n.vaultSyncInSyncCountLabel(_identicalCount),
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: context.l10n.vaultSyncRecompareButton,
                    onPressed: _isSyncing ? null : _startCompare,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onlyLeft > 0)
                    _buildTagBadge(context, context.l10n.vaultSyncBadgeOnlyLeft(onlyLeft), cs.primary),
                  if (onlyRight > 0)
                    _buildTagBadge(
                      context,
                      context.l10n.vaultSyncBadgeOnlyRight(onlyRight),
                      cs.secondary,
                    ),
                  if (leftNewer > 0)
                    _buildTagBadge(
                      context,
                      context.l10n.vaultSyncBadgeLeftNewer(leftNewer),
                      cs.tertiary,
                    ),
                  if (rightNewer > 0)
                    _buildTagBadge(
                      context,
                      context.l10n.vaultSyncBadgeRightNewer(rightNewer),
                      cs.tertiary,
                    ),
                  if (conflicts > 0)
                    _buildTagBadge(
                      context,
                      context.l10n.vaultSyncBadgeConflicts(conflicts),
                      cs.error,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              OptionPickerTile<SyncDirection>(
                label: context.l10n.vaultSyncDirectionLabel,
                value: _direction,
                prefixIcon: Icons.sync_alt_rounded,
                enabled: !_isSyncing,
                options: [
                  SelectOption(
                    value: SyncDirection.twoWay,
                    label: context.l10n.vaultSyncDirectionTwoWay,
                    subtitle: context.l10n.vaultSyncDirectionTwoWaySubtitle,
                  ),
                  SelectOption(
                    value: SyncDirection.leftToRight,
                    label: context.l10n.vaultSyncDirectionLeftToRight,
                    subtitle: context.l10n.vaultSyncDirectionLeftToRightSubtitle,
                  ),
                  SelectOption(
                    value: SyncDirection.rightToLeft,
                    label: context.l10n.vaultSyncDirectionRightToLeft,
                    subtitle: context.l10n.vaultSyncDirectionRightToLeftSubtitle,
                  ),
                ],
                onChanged: (dir) => setState(() {
                  _direction = dir;
                  _overrides.clear();
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: context.typography.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = context.colors;
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: context.l10n.vaultSyncSearchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () => _searchController.clear(),
              )
            : null,
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildDiffTile(BuildContext context, VaultDiffEntry entry) {
    final cs = context.colors;
    final textTheme = context.typography;
    final action = _actionFor(entry);

    final Color statusColor = switch (entry.status) {
      VaultDiffStatus.onlyLeft => cs.primary,
      VaultDiffStatus.onlyRight => cs.secondary,
      VaultDiffStatus.leftNewer => cs.tertiary,
      VaultDiffStatus.rightNewer => cs.tertiary,
      VaultDiffStatus.conflicted => cs.error,
    };
    final String statusLabel = switch (entry.status) {
      VaultDiffStatus.onlyLeft => context.l10n.vaultSyncStatusOnlyLeft,
      VaultDiffStatus.onlyRight => context.l10n.vaultSyncStatusOnlyRight,
      VaultDiffStatus.leftNewer => context.l10n.vaultSyncStatusLeftNewer,
      VaultDiffStatus.rightNewer => context.l10n.vaultSyncStatusRightNewer,
      VaultDiffStatus.conflicted => entry.typeMismatch
          ? context.l10n.vaultSyncStatusTypeMismatch
          : context.l10n.vaultSyncStatusConflict,
    };

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          entry.isDir ? Icons.folder_rounded : iconForFile(entry.name),
          color: entry.isDir ? cs.secondary : colorForFile(entry.name),
        ),
        title: Text(
          entry.relativePath,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildTagBadge(context, statusLabel, statusColor),
              _buildDiffDetailText(context, entry),
            ],
          ),
        ),
        trailing: _buildActionMenu(context, entry, action),
      ),
    );
  }

  Widget _buildDiffDetailText(BuildContext context, VaultDiffEntry entry) {
    final style = context.typography.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    switch (entry.status) {
      case VaultDiffStatus.onlyLeft:
        return Text(
          entry.isDir
              ? context.l10n.vaultSyncFolderOnlyLeftDetail
              : '${formatBytes(entry.leftSizeBytes ?? 0)} · ${formatEntryDate(entry.leftModifiedSecs ?? 0)}',
          style: style,
        );
      case VaultDiffStatus.onlyRight:
        return Text(
          entry.isDir
              ? context.l10n.vaultSyncFolderOnlyRightDetail
              : '${formatBytes(entry.rightSizeBytes ?? 0)} · ${formatEntryDate(entry.rightModifiedSecs ?? 0)}',
          style: style,
        );
      case VaultDiffStatus.leftNewer:
      case VaultDiffStatus.rightNewer:
      case VaultDiffStatus.conflicted:
        return Text(
          context.l10n.vaultSyncBothSidesDetail(
            formatBytes(entry.leftSizeBytes ?? 0),
            formatEntryDate(entry.leftModifiedSecs ?? 0),
            formatBytes(entry.rightSizeBytes ?? 0),
            formatEntryDate(entry.rightModifiedSecs ?? 0),
          ),
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _buildActionMenu(BuildContext context, VaultDiffEntry entry, EntryAction action) {
    final cs = context.colors;

    if (entry.typeMismatch) {
      return Tooltip(
        message: context.l10n.vaultSyncTypeMismatchTooltip,
        child: Icon(Icons.error_outline_rounded, color: cs.error),
      );
    }

    final canCopyToRight =
        entry.status != VaultDiffStatus.onlyRight && !(_right?.container.readOnly ?? false);
    final canCopyToLeft =
        entry.status != VaultDiffStatus.onlyLeft && !(_left?.container.readOnly ?? false);

    final (IconData icon, Color color) = switch (action) {
      EntryAction.copyToRight => (Icons.arrow_forward_rounded, cs.primary),
      EntryAction.copyToLeft => (Icons.arrow_back_rounded, cs.secondary),
      EntryAction.skip => (Icons.remove_circle_outline_rounded, cs.onSurfaceVariant),
    };

    if (_isSyncing) {
      // The plan was already snapshotted when the sync started -- avoid
      // implying further taps here would change anything about the run
      // that's currently in flight.
      return Icon(icon, color: color.withValues(alpha: 0.5));
    }

    return PopupMenuButton<EntryAction>(
      icon: Icon(icon, color: color),
      tooltip: context.l10n.vaultSyncChangeActionTooltip,
      onSelected: (a) => _setOverride(entry, a),
      itemBuilder: (ctx) => [
        if (canCopyToRight)
          PopupMenuItem(
            value: EntryAction.copyToRight,
            child: Text(context.l10n.vaultSyncActionCopyToRight),
          ),
        if (canCopyToLeft)
          PopupMenuItem(
            value: EntryAction.copyToLeft,
            child: Text(context.l10n.vaultSyncActionCopyToLeft),
          ),
        PopupMenuItem(
          value: EntryAction.skip,
          child: Text(context.l10n.vaultSyncActionSkip),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.vaultSyncChangesQueuedLabel(_pendingTotal),
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    formatBytes(_pendingBytes),
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _isSyncing ? null : _confirmAndSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(
                _isSyncing
                    ? context.l10n.vaultSyncSyncingButton
                    : context.l10n.vaultSyncSyncNowButton,
              ),
            ),
          ],
        ),
      ),
    );
  }
}