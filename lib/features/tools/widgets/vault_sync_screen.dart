// File: lib/features/tools/widgets/vault_sync_screen.dart

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/services/vault_sync_service.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_location_picker_sheet.dart';

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
    _initDefaultSides();
  }

  void _initDefaultSides() {
    final containers = widget.mountedContainers.value;
    if (containers.isNotEmpty) {
      _left = VaultSyncSide(container: containers.first, relativePath: '');
      if (containers.length > 1) {
        _right = VaultSyncSide(container: containers[1], relativePath: '');
      }
    }
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
          isLeft: isLeft,
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
      setState(() => _isSyncing = false);
      return;
    }
    _watchOpsForCompletion(ops);
  }

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
        elevation: 0,
        title: Text(
          context.l10n.toolVaultSyncTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          AppBarTransferButton(),
          SizedBox(width: 4),
        ],
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
          return _buildMainList(context);
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
    final isLandscape = context.screen.useWideLayout;

    return ListView.builder(
      padding: isLandscape
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
          : AppSpacing.pagePadding,
      itemCount: 1 + filtered.length + (noSearchMatches ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidePickers(context, isLandscape),
              const SizedBox(height: 10),
              if (_isComparing)
                _buildComparingCard(context)
              else if (_progress.stage == VaultSyncScanStage.idle ||
                  _progress.stage == VaultSyncScanStage.cancelled)
                _buildIdleCard(context)
              else if (_entries.isEmpty)
                _buildInSyncCard(context)
              else ...[
                _buildSummaryCard(context, isLandscape),
                const SizedBox(height: 10),
                _buildSearchBar(context),
                const SizedBox(height: 10),
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
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildDiffTile(context, filtered[index - 1], isLandscape),
        );
      },
    );
  }

  // ── SIDE PICKERS ───────────────────────────────────────────────────────────

  Widget _buildSidePickers(BuildContext context, bool isLandscape) {
    final sameLocationWarning = (_left != null && _right != null && _left == _right)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              context.l10n.vaultSyncSameLocationWarning,
              style: context.typography.bodySmall?.copyWith(color: context.colors.error),
            ),
          )
        : null;

    if (isLandscape) {
      return Container(
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildSideTile(
                    context,
                    isLeft: true,
                    side: _left,
                    label: context.l10n.vaultSyncLeftLabel,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  tooltip: context.l10n.vaultSyncSwapTooltip,
                  onPressed: (_left == null && _right == null) || _isComparing || _isSyncing
                      ? null
                      : _swapSides,
                ),
                Expanded(
                  child: _buildSideTile(
                    context,
                    isLeft: false,
                    side: _right,
                    label: context.l10n.vaultSyncRightLabel,
                  ),
                ),
              ],
            ),
            if (sameLocationWarning != null) sameLocationWarning,
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          _buildSideTile(
            context,
            isLeft: true,
            side: _left,
            label: context.l10n.vaultSyncLeftLabel,
          ),
          Center(
            child: IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: context.l10n.vaultSyncSwapTooltip,
              onPressed: (_left == null && _right == null) || _isComparing || _isSyncing
                  ? null
                  : _swapSides,
            ),
          ),
          _buildSideTile(
            context,
            isLeft: false,
            side: _right,
            label: context.l10n.vaultSyncRightLabel,
          ),
          if (sameLocationWarning != null) sameLocationWarning,
        ],
      ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(
          isLeft ? Icons.looks_one_rounded : Icons.looks_two_rounded,
          color: cs.primary,
          size: AppIconSize.small,
        ),
      ),
      title: Row(
        children: [
          Text(label, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                    Icon(Icons.lock_outline_rounded, size: 11, color: cs.onErrorContainer),
                    const SizedBox(width: 3),
                    Text(
                      context.l10n.vaultSyncReadOnlyBadge,
                      style: textTheme.labelSmall?.copyWith(color: cs.onErrorContainer, fontSize: 10),
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
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 18),
      onTap: (_isComparing || _isSyncing) ? null : () => _pickSide(isLeft: isLeft),
    );
  }

  // ── IDLE / PROGRESS / IN-SYNC CARDS ────────────────────────────────────────

  Widget _buildIdleCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.compare_arrows_rounded,
                  color: cs.onPrimaryContainer,
                  size: AppIconSize.small,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.vaultSyncIntroTitle,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_canCompare && !_isSyncing) ? _startCompare : null,
              icon: const Icon(Icons.compare_arrows_rounded, size: 18),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              label: Text(
                context.l10n.vaultSyncCompareButton,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparingCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.vaultSyncComparingLabel,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            context.l10n.vaultSyncCompareStatsLabel(
              _progress.dirsScanned,
              _progress.entriesCompared,
            ),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _cancelCompare,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(context.l10n.vaultSyncCancelCompareButton),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
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

  // ── SUMMARY & CONTROLS ─────────────────────────────────────────────────────

  Widget _buildSummaryCard(BuildContext context, bool isLandscape) {
    final cs = context.colors;
    final textTheme = context.typography;

    final onlyLeft = _entries.where((e) => e.status == VaultDiffStatus.onlyLeft).length;
    final onlyRight = _entries.where((e) => e.status == VaultDiffStatus.onlyRight).length;
    final leftNewer = _entries.where((e) => e.status == VaultDiffStatus.leftNewer).length;
    final rightNewer = _entries.where((e) => e.status == VaultDiffStatus.rightNewer).length;
    final conflicts = _entries.where((e) => e.status == VaultDiffStatus.conflicted).length;

    return Container(
      padding: EdgeInsets.all(isLandscape ? 12 : 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.difference_rounded, color: cs.onPrimaryContainer, size: AppIconSize.small),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.vaultSyncDifferencesFoundLabel(_entries.length),
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      context.l10n.vaultSyncInSyncCountLabel(_identicalCount),
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: context.l10n.vaultSyncRecompareButton,
                visualDensity: VisualDensity.compact,
                onPressed: _isSyncing ? null : _startCompare,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (onlyLeft > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeOnlyLeft(onlyLeft), cs.primary),
              if (onlyRight > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeOnlyRight(onlyRight), cs.secondary),
              if (leftNewer > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeLeftNewer(leftNewer), cs.tertiary),
              if (rightNewer > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeRightNewer(rightNewer), cs.tertiary),
              if (conflicts > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeConflicts(conflicts), cs.error),
            ],
          ),
          const SizedBox(height: 10),
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
    );
  }

  Widget _buildTagBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: context.typography.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = context.colors;
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: context.l10n.vaultSyncSearchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () => _searchController.clear(),
              )
            : null,
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  // ── DIFF TILES ─────────────────────────────────────────────────────────────

  Widget _buildDiffTile(BuildContext context, VaultDiffEntry entry, bool isLandscape) {
    if (isLandscape) {
      return _buildDiffTileWide(context, entry);
    }
    return _buildDiffTilePortrait(context, entry);
  }

  Widget _buildDiffTilePortrait(BuildContext context, VaultDiffEntry entry) {
    final cs = context.colors;
    final textTheme = context.typography;
    final action = _actionFor(entry);

    final statusColor = _statusColor(context, entry.status);
    final statusLabel = _statusLabel(context, entry);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
            spacing: 6,
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

  Widget _buildDiffTileWide(BuildContext context, VaultDiffEntry entry) {
    final cs = context.colors;
    final textTheme = context.typography;
    final action = _actionFor(entry);
    final statusColor = _statusColor(context, entry.status);
    final statusLabel = _statusLabel(context, entry);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  entry.isDir ? Icons.folder_rounded : iconForFile(entry.name),
                  size: 18,
                  color: entry.isDir ? cs.secondary : colorForFile(entry.name),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                _buildTagBadge(context, statusLabel, statusColor),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSideDetail(context, entry, isLeftSide: true),
                ),
                SizedBox(
                  width: 44,
                  child: Center(child: _buildActionMenu(context, entry, action)),
                ),
                Expanded(
                  child: _buildSideDetail(context, entry, isLeftSide: false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideDetail(
    BuildContext context,
    VaultDiffEntry entry, {
    required bool isLeftSide,
  }) {
    final style = context.typography.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    final absentHere = isLeftSide
        ? entry.status == VaultDiffStatus.onlyRight
        : entry.status == VaultDiffStatus.onlyLeft;
    if (absentHere) {
      return Text('—', style: style, textAlign: isLeftSide ? TextAlign.left : TextAlign.right);
    }

    final sizeBytes = isLeftSide ? entry.leftSizeBytes : entry.rightSizeBytes;
    final modifiedSecs = isLeftSide ? entry.leftModifiedSecs : entry.rightModifiedSecs;
    final onlyOnThisSide = isLeftSide
        ? entry.status == VaultDiffStatus.onlyLeft
        : entry.status == VaultDiffStatus.onlyRight;

    final String text;
    if (entry.isDir && onlyOnThisSide) {
      final sizeText = sizeBytes != null && sizeBytes > 0 ? '${formatBytes(sizeBytes)} · ' : '';
      final folderDetail = isLeftSide
          ? context.l10n.vaultSyncFolderOnlyLeftDetail
          : context.l10n.vaultSyncFolderOnlyRightDetail;
      text = '$sizeText$folderDetail';
    } else {
      text = '${formatBytes(sizeBytes ?? 0)} · ${formatEntryDate(modifiedSecs ?? 0)}';
    }

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: isLeftSide ? TextAlign.left : TextAlign.right,
      style: style,
    );
  }

  Widget _buildDiffDetailText(BuildContext context, VaultDiffEntry entry) {
    final style = context.typography.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    switch (entry.status) {
      case VaultDiffStatus.onlyLeft:
        final sizeText = entry.leftSizeBytes != null && entry.leftSizeBytes! > 0
            ? '${formatBytes(entry.leftSizeBytes!)} · '
            : '';
        return Text(
          entry.isDir
              ? '$sizeText${context.l10n.vaultSyncFolderOnlyLeftDetail}'
              : '${formatBytes(entry.leftSizeBytes ?? 0)} · ${formatEntryDate(entry.leftModifiedSecs ?? 0)}',
          style: style,
        );
      case VaultDiffStatus.onlyRight:
        final sizeText = entry.rightSizeBytes != null && entry.rightSizeBytes! > 0
            ? '${formatBytes(entry.rightSizeBytes!)} · '
            : '';
        return Text(
          entry.isDir
              ? '$sizeText${context.l10n.vaultSyncFolderOnlyRightDetail}'
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

  Color _statusColor(BuildContext context, VaultDiffStatus status) {
    final cs = context.colors;
    return switch (status) {
      VaultDiffStatus.onlyLeft => cs.primary,
      VaultDiffStatus.onlyRight => cs.secondary,
      VaultDiffStatus.leftNewer => cs.tertiary,
      VaultDiffStatus.rightNewer => cs.tertiary,
      VaultDiffStatus.conflicted => cs.error,
    };
  }

  String _statusLabel(BuildContext context, VaultDiffEntry entry) {
    return switch (entry.status) {
      VaultDiffStatus.onlyLeft => context.l10n.vaultSyncStatusOnlyLeft,
      VaultDiffStatus.onlyRight => context.l10n.vaultSyncStatusOnlyRight,
      VaultDiffStatus.leftNewer => context.l10n.vaultSyncStatusLeftNewer,
      VaultDiffStatus.rightNewer => context.l10n.vaultSyncStatusRightNewer,
      VaultDiffStatus.conflicted => entry.typeMismatch
          ? context.l10n.vaultSyncStatusTypeMismatch
          : context.l10n.vaultSyncStatusConflict,
    };
  }

  Widget _buildActionMenu(BuildContext context, VaultDiffEntry entry, EntryAction action) {
    final cs = context.colors;

    if (entry.typeMismatch) {
      return Tooltip(
        message: context.l10n.vaultSyncTypeMismatchTooltip,
        child: Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
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
      return Icon(icon, color: color.withValues(alpha: 0.5), size: 20);
    }

    return PopupMenuButton<EntryAction>(
      icon: Icon(icon, color: color, size: 20),
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

  // ── BOTTOM ACTION BAR ──────────────────────────────────────────────────────

  Widget _buildBottomActionBar(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
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
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                shape: const StadiumBorder(),
              ),
              onPressed: _isSyncing ? null : _confirmAndSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                _isSyncing
                    ? context.l10n.vaultSyncSyncingButton
                    : context.l10n.vaultSyncSyncNowButton,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}