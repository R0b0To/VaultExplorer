import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_entry_actions.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_folder_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_location_picker_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_target_style.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

enum _SyncDirectionMode { twoWay, oneWay, mirror }

String _middleEllipsis(String value) {
  const maxCodePoints = 18;
  const prefixCodePoints = 8;
  final codePoints = value.runes.toList();
  if (codePoints.length <= maxCodePoints) return value;
  const suffixCodePoints = maxCodePoints - prefixCodePoints - 1;
  return '${String.fromCharCodes(codePoints.take(prefixCodePoints))}…'
      '${String.fromCharCodes(codePoints.skip(codePoints.length - suffixCodePoints))}';
}

class VaultSyncScreen extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const VaultSyncScreen({super.key, required this.mountedContainers});

  @override
  ConsumerState<VaultSyncScreen> createState() => _VaultSyncScreenState();
}

class _VaultSyncScreenState extends ConsumerState<VaultSyncScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(vaultSyncProvider.notifier)
          .initDefaultSides(widget.mountedContainers.value);
    });
  }

  Future<void> _pickSide(VaultSyncState state, {required bool isLeft}) async {
    final containers = widget.mountedContainers.value;
    final result = await Navigator.push<VaultSyncSide>(
      context,
      MaterialPageRoute(
        builder: (_) => SkinAreaScope(area: SkinArea.tools, child: VaultSyncLocationPickerSheet(
          mountedContainers: containers,
          showStorageChooser: true,
          initialSide: isLeft ? state.left : state.right,
          isLeft: isLeft,
        )),
      ),
    );
    if (result == null || !mounted) return;
    ref
        .read(vaultSyncProvider.notifier)
        .setSide(isLeft: isLeft, side: result);
  }

  int _pendingBytesToRight(VaultSyncState state) {
    var total = 0;
    for (final e in state.entries) {
      if (ref.read(vaultSyncProvider.notifier).actionFor(e) == EntryAction.copyToRight) {
        total += e.leftSizeBytes ?? 0;
      }
    }
    return total;
  }

  int _pendingBytesToLeft(VaultSyncState state) {
    var total = 0;
    for (final e in state.entries) {
      if (ref.read(vaultSyncProvider.notifier).actionFor(e) == EntryAction.copyToLeft) {
        total += e.rightSizeBytes ?? 0;
      }
    }
    return total;
  }

  Future<void> _confirmAndSync(VaultSyncState state) async {
    if (state.isSyncing) return;
    final left = state.left;
    final right = state.right;
    if (left == null || right == null) return;

    final bytesToRight = _pendingBytesToRight(state);
    final bytesToLeft = _pendingBytesToLeft(state);
    final pendingBytes = bytesToRight + bytesToLeft;

    final pendingTotal = state.entries
        .where((e) => ref.read(vaultSyncProvider.notifier).actionFor(e) != EntryAction.skip)
        .length;

    if (pendingTotal == 0) return;

    final problems = await ref.read(vaultSyncProvider.notifier).checkAvailableSpace(
          bytesToLeft: bytesToLeft,
          bytesToRight: bytesToRight,
          l10n: context.l10n,
        );

    if (!mounted) return;
    if (problems.isNotEmpty) {
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
      return;
    }

    // Copying out of a vault leaves plain files on the other side -- say so.
    final plaintextTargets =
        ref.read(vaultSyncProvider.notifier).plaintextExportTargets();
    var confirmMessage =
        context.l10n.vaultSyncConfirmMessage(pendingTotal, formatBytes(pendingBytes));
    if (plaintextTargets.isNotEmpty) {
      confirmMessage =
          '$confirmMessage\n\n${context.l10n.vaultSyncPlaintextWarning(plaintextTargets.join(', '))}';
    }
    // Deleting can't be undone, so say exactly how much will go.
    final deleteCount = ref.read(vaultSyncProvider.notifier).pendingDeleteCount();
    if (deleteCount > 0) {
      confirmMessage =
          '$confirmMessage\n\n${context.l10n.vaultSyncConfirmDeletionsMessage(deleteCount)}';
    }

    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.vaultSyncConfirmTitle,
      message: confirmMessage,
      confirmLabel: context.l10n.vaultSyncSyncNowButton,
      isDestructive: deleteCount > 0,
    );
    if (!confirmed || !mounted) return;

    ref.read(vaultSyncProvider.notifier).executeSync(context.l10n);
  }

  List<VaultDiffEntry> _filteredEntries() =>
      ref.read(vaultSyncProvider.notifier).visibleEntries();

  String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  /// Opens the folder explorer: both sides merged, one folder at a time.
  void _openExplorer({String path = '', String? highlight}) {
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VaultSyncFolderScreen(
            initialPath: path,
            highlightPath: highlight,
          ),
        ),
      ),
    );
  }

  List<VaultDiffEntry> _selectedEntries(VaultSyncState state) => state.entries
      .where((e) => state.selectedIds.contains(e.id))
      .toList();

  void _onEntryTap(VaultSyncState state, VaultDiffEntry entry) {
    final notifier = ref.read(vaultSyncProvider.notifier);
    if (state.selectedIds.isNotEmpty) {
      notifier.toggleSelected(entry.id);
      return;
    }
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
        onOpenFolder: () => _openExplorer(path: entry.relativePath),
        onShowInFolder: () => _openExplorer(
          path: _parentOf(entry.relativePath),
          highlight: entry.relativePath,
        ),
      ),
    );
  }

  void _onEntryLongPress(VaultDiffEntry entry) {
    HapticFeedback.selectionClick();
    ref.read(vaultSyncProvider.notifier).toggleSelected(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultSyncProvider);
    final pendingTotal = state.entries
        .where((e) => ref.read(vaultSyncProvider.notifier).actionFor(e) != EntryAction.skip)
        .length;

    final selecting = state.selectedIds.isNotEmpty;
    final notifier = ref.read(vaultSyncProvider.notifier);

    return PopScope(
      // Back leaves selection mode before it leaves the screen.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) notifier.clearSelection();
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: notifier.clearSelection,
                ),
                title: Text(
                  context.l10n.vaultSyncSelectedCount(state.selectedIds.length),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all_rounded),
                    tooltip: context.l10n.selectAll,
                    onPressed: () => notifier.selectIds(
                      _filteredEntries().map((e) => e.id),
                    ),
                  ),
                ],
              )
            : AppBar(
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
        body: _buildMainList(context, state),
        bottomNavigationBar: selecting
            ? _buildSelectionBar(context, state)
            : (!state.isComparing && pendingTotal > 0)
            ? _buildBottomActionBar(context, state, pendingTotal)
            : null,
      ),
    );
  }

  Widget _buildMainList(BuildContext context, VaultSyncState state) {
    final showResults = !state.isComparing &&
        state.progress.stage != VaultSyncScanStage.idle &&
        state.progress.stage != VaultSyncScanStage.cancelled &&
        state.entries.isNotEmpty;
    final filtered = showResults ? _filteredEntries() : const <VaultDiffEntry>[];
    final noMatches = showResults && filtered.isEmpty;
    final isLandscape = context.screen.useWideLayout;

    return ListView.builder(
      padding: isLandscape
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
          : AppSpacing.pagePadding,
      itemCount: 1 + filtered.length + (noMatches ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidePickers(context, state, isLandscape),
              const SizedBox(height: 10),
              if (state.isComparing)
                _buildComparingCard(context, state)
              else if (state.progress.stage == VaultSyncScanStage.failed)
                _buildScanFailedCard(context)
              else if (state.progress.stage == VaultSyncScanStage.idle ||
                  state.progress.stage == VaultSyncScanStage.cancelled)
                _buildIdleCard(context, state)
              else if (state.entries.isEmpty)
                _buildInSyncCard(context, state)
              else ...[
                _buildSummaryCard(context, state, isLandscape),
                if (state.resultsStale) ...[
                  const SizedBox(height: 10),
                  _buildStaleBanner(context),
                ],
                const SizedBox(height: 10),
                _buildFilterBar(context, state),
                const SizedBox(height: 6),
              ],
            ],
          );
        }
        if (noMatches && index == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: context.l10n.noResultsTitle,
              message: context.l10n.vaultSyncFilterNoMatchesMessage,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildDiffTile(context, state, filtered[index - 1], isLandscape),
        );
      },
    );
  }

  // ── SIDE PICKERS ───────────────────────────────────────────────────────────

  Widget _buildSidePickers(BuildContext context, VaultSyncState state, bool isLandscape) {
    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);
    final sameLocationWarning = state.sidesOverlap
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              context.l10n.vaultSyncOverlapWarning,
              style: context.typography.bodySmall?.copyWith(color: context.colors.error),
            ),
          )
        : null;

    final swapButton = IconButton(
      icon: Icon(isLandscape ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded),
      tooltip: context.l10n.vaultSyncSwapTooltip,
      onPressed: (state.left == null && state.right == null) || state.isComparing || state.isSyncing
          ? null
          : () => ref.read(vaultSyncProvider.notifier).swapSides(),
    );

    final leftCard = _buildStorageCard(
      context,
      state,
      isLeft: true,
      side: state.left,
      name: names.left,
    );
    final rightCard = _buildStorageCard(
      context,
      state,
      isLeft: false,
      side: state.right,
      name: names.right,
    );

    return Material(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (isLandscape)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: leftCard),
                swapButton,
                Expanded(child: rightCard),
              ],
            )
          else ...[
            leftCard,
            Center(child: swapButton),
            rightCard,
          ],
          ?sameLocationWarning,
        ],
      ),
    );
  }

  /// One compared storage as a card that clearly reads as changeable: its
  /// name, the folder inside it, what kind of storage it is, and a Change
  /// button. A side that hasn't been picked yet is highlighted with a Choose
  /// button instead. The whole card is tappable too.
  Widget _buildStorageCard(
    BuildContext context,
    VaultSyncState state, {
    required bool isLeft,
    required VaultSyncSide? side,
    required String name,
  }) {
    final cs = context.colors;
    final textTheme = context.typography;
    final busy = state.isComparing || state.isSyncing;
    final isReadOnly = side?.container.readOnly ?? false;
    final unset = side == null;
    final folder = side == null
        ? null
        : (side.relativePath.isEmpty
              ? context.l10n.vaultFolderPickerRootLabel
              : side.relativePath);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: unset ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: unset ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => _pickSide(state, isLeft: isLeft),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    side?.kind.icon ?? Icons.add_rounded,
                    color: cs.primary,
                    size: AppIconSize.small,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
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
                                      style: textTheme.labelSmall?.copyWith(
                                        color: cs.onErrorContainer,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (side == null)
                        Text(
                          context.l10n.vaultSyncTapToSelect,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      else ...[
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 13, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                folder!,
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          side.kind.label(context.l10n),
                          style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _pickSide(state, isLeft: isLeft),
                  icon: Icon(unset ? Icons.add_rounded : Icons.edit_outlined, size: 16),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  label: Text(
                    unset ? context.l10n.vaultSyncChooseButton : context.l10n.vaultSyncChangeButton,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleCard(BuildContext context, VaultSyncState state) {
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
              onPressed: (state.canCompare && !state.isSyncing)
                  ? () => ref.read(vaultSyncProvider.notifier).startCompare()
                  : null,
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

  Widget _buildComparingCard(BuildContext context, VaultSyncState state) {
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
              state.progress.dirsScanned,
              state.progress.entriesCompared,
            ),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => ref.read(vaultSyncProvider.notifier).cancelCompare(),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(context.l10n.vaultSyncCancelCompareButton),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanFailedCard(BuildContext context) {
    return AppEmptyState(
      icon: Icons.error_outline_rounded,
      title: context.l10n.vaultSyncScanFailedTitle,
      message: context.l10n.vaultSyncScanFailedMessage,
      actionLabel: context.l10n.vaultSyncRecompareButton,
      actionIcon: Icons.refresh_rounded,
      onAction: () => ref.read(vaultSyncProvider.notifier).startCompare(),
    );
  }

  Widget _buildInSyncCard(BuildContext context, VaultSyncState state) {
    return Column(
      children: [
        AppEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: context.l10n.vaultSyncInSyncTitle,
          message: context.l10n.vaultSyncInSyncMessage(state.identicalCount),
          actionLabel: context.l10n.vaultSyncRecompareButton,
          actionIcon: Icons.refresh_rounded,
          onAction: () => ref.read(vaultSyncProvider.notifier).startCompare(),
        ),
        TextButton.icon(
          onPressed: () => _openExplorer(),
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: Text(context.l10n.vaultSyncBrowseAllButton),
        ),
      ],
    );
  }

  Future<void> _showSyncDirectionPicker(VaultSyncState state) async {
    final l10n = context.l10n;
    final names = vaultSyncNamesOf(state.left, state.right, l10n);
    var mode = switch (state.direction) {
      SyncDirection.twoWay => _SyncDirectionMode.twoWay,
      SyncDirection.leftToRight || SyncDirection.rightToLeft =>
        _SyncDirectionMode.oneWay,
      SyncDirection.mirrorToRight || SyncDirection.mirrorToLeft =>
        _SyncDirectionMode.mirror,
    };
    var leftToRight = state.direction != SyncDirection.rightToLeft &&
        state.direction != SyncDirection.mirrorToLeft;

    final selected = await showDialog<SyncDirection>(
      context: context,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget modeTitle(
              IconData icon,
              String title, {
              bool destructive = false,
              bool recommended = false,
            }) => Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: destructive ? cs.error : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
                if (recommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      l10n.vaultSyncDirectionRecommendedLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (destructive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: cs.onErrorContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.vaultSyncDirectionMirrorWarning,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );

            Widget modeOption({
              required _SyncDirectionMode value,
              required IconData icon,
              required String title,
              required String subtitle,
              bool destructive = false,
              bool recommended = false,
            }) => InkWell(
              onTap: () => setDialogState(() => mode = value),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -10),
                      child: Radio<_SyncDirectionMode>(
                        value: value,
                        activeColor: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          modeTitle(
                            icon,
                            title,
                            destructive: destructive,
                            recommended: recommended,
                          ),
                          const SizedBox(height: 4),
                          Text(subtitle),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            Widget endpointCard(String name, String label) => Tooltip(
              message: name,
              child: Container(
                height: MediaQuery.textScalerOf(context).scale(68),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _middleEllipsis(name),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );

            SyncDirection chosenDirection() => switch (mode) {
              _SyncDirectionMode.twoWay => SyncDirection.twoWay,
              _SyncDirectionMode.oneWay => leftToRight
                  ? SyncDirection.leftToRight
                  : SyncDirection.rightToLeft,
              _SyncDirectionMode.mirror => leftToRight
                  ? SyncDirection.mirrorToRight
                  : SyncDirection.mirrorToLeft,
            };

            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: mediaQuery.size.height * 0.82,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l10n.vaultSyncDirectionLabel,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RadioGroup<_SyncDirectionMode>(
                                groupValue: mode,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() => mode = value);
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    modeOption(
                                      value: _SyncDirectionMode.twoWay,
                                      icon: Icons.sync_alt_rounded,
                                      title: l10n.vaultSyncDirectionTwoWay,
                                      subtitle:
                                          l10n.vaultSyncDirectionTwoWaySubtitle,
                                      recommended: true,
                                    ),
                                    modeOption(
                                      value: _SyncDirectionMode.oneWay,
                                      icon: Icons.arrow_forward_rounded,
                                      title: l10n.vaultSyncDirectionOneWay,
                                      subtitle:
                                          l10n.vaultSyncDirectionOneWaySubtitle,
                                    ),
                                    modeOption(
                                      value: _SyncDirectionMode.mirror,
                                      icon: Icons.layers_rounded,
                                      title: l10n.vaultSyncDirectionMirror,
                                      subtitle:
                                          l10n.vaultSyncDirectionMirrorSubtitle,
                                      destructive: true,
                                    ),
                                  ],
                                ),
                              ),
                              if (mode != _SyncDirectionMode.twoWay) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    8,
                                    24,
                                    8,
                                  ),
                                  child: Text(
                                    l10n.vaultSyncDirectionSectionTitle,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: endpointCard(
                                          leftToRight
                                              ? names.left
                                              : names.right,
                                          l10n.vaultSyncDirectionSourceLabel,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18,
                                              color: cs.primary,
                                            ),
                                            const SizedBox(height: 6),
                                            OutlinedButton.icon(
                                              onPressed: () => setDialogState(
                                                () => leftToRight = !leftToRight,
                                              ),
                                              icon: const Icon(
                                                Icons.swap_horiz_rounded,
                                                size: 16,
                                              ),
                                              label: Text(
                                                l10n.vaultSyncDirectionSwapButton,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 8,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: endpointCard(
                                          leftToRight
                                              ? names.right
                                              : names.left,
                                          l10n.vaultSyncDirectionTargetLabel,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: Text(l10n.cancel),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                chosenDirection(),
                              ),
                              child: Text(l10n.done),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selected == null) return;
    ref.read(vaultSyncProvider.notifier).setDirection(selected);
  }

  Widget _buildDirectionTile(
    BuildContext context,
    VaultSyncState state,
    VaultSyncNames names,
  ) {
    final l10n = context.l10n;
    final summary = switch (state.direction) {
      SyncDirection.twoWay => l10n.vaultSyncDirectionTwoWay,
      SyncDirection.leftToRight =>
        '${l10n.vaultSyncDirectionOneWay} · ${names.left} → ${names.right}',
      SyncDirection.rightToLeft =>
        '${l10n.vaultSyncDirectionOneWay} · ${names.right} → ${names.left}',
      SyncDirection.mirrorToRight =>
        '${l10n.vaultSyncDirectionMirror} · ${names.left} → ${names.right}',
      SyncDirection.mirrorToLeft =>
        '${l10n.vaultSyncDirectionMirror} · ${names.right} → ${names.left}',
    };

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(Icons.sync_alt_rounded, color: context.colors.primary),
        title: Text(
          l10n.vaultSyncDirectionLabel,
          style: context.typography.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.typography.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ),
        onTap: state.isSyncing ? null : () => _showSyncDirectionPicker(state),
      ),
    );
  }

  // ── SUMMARY & CONTROLS ─────────────────────────────────────────────────────

  Widget _buildSummaryCard(BuildContext context, VaultSyncState state, bool isLandscape) {
    final cs = context.colors;
    final textTheme = context.typography;

    final onlyLeft = state.entries.where((e) => e.status == VaultDiffStatus.onlyLeft).length;
    final onlyRight = state.entries.where((e) => e.status == VaultDiffStatus.onlyRight).length;
    final leftNewer = state.entries.where((e) => e.status == VaultDiffStatus.leftNewer).length;
    final rightNewer = state.entries.where((e) => e.status == VaultDiffStatus.rightNewer).length;
    final conflicts = state.entries.where((e) => e.status == VaultDiffStatus.conflicted).length;
    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);

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
                      context.l10n.vaultSyncDifferencesFoundLabel(state.entries.length),
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      context.l10n.vaultSyncInSyncCountLabel(state.identicalCount),
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                tooltip: context.l10n.vaultSyncBrowseAllButton,
                visualDensity: VisualDensity.compact,
                onPressed: state.isSyncing ? null : () => _openExplorer(),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: context.l10n.vaultSyncRecompareButton,
                visualDensity: VisualDensity.compact,
                onPressed: state.isSyncing
                    ? null
                    : () => ref.read(vaultSyncProvider.notifier).startCompare(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (onlyLeft > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeOnlyIn(onlyLeft, names.left), cs.primary),
              if (onlyRight > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeOnlyIn(onlyRight, names.right), cs.secondary),
              if (leftNewer > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeNewerIn(leftNewer, names.left), cs.tertiary),
              if (rightNewer > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeNewerIn(rightNewer, names.right), cs.tertiary),
              if (conflicts > 0)
                _buildTagBadge(context, context.l10n.vaultSyncBadgeConflicts(conflicts), cs.error),
            ],
          ),
          const SizedBox(height: 10),
          _buildDirectionTile(context, state, names),
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.typography.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  // ── FILTER / SORT ──────────────────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context, VaultSyncState state) {
    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);
    String filterLabel(VaultSyncFilter f) => switch (f) {
      VaultSyncFilter.all => context.l10n.vaultSyncFilterAll,
      VaultSyncFilter.onlyLeft => context.l10n.vaultSyncFilterOnlyIn(names.left),
      VaultSyncFilter.onlyRight => context.l10n.vaultSyncFilterOnlyIn(names.right),
      VaultSyncFilter.newer => context.l10n.vaultSyncFilterNewer,
      VaultSyncFilter.conflicts => context.l10n.vaultSyncFilterConflicts,
      VaultSyncFilter.deletions => context.l10n.vaultSyncFilterDeletions,
    };
    String sortLabel(VaultSyncSort o) => switch (o) {
      VaultSyncSort.path => context.l10n.vaultSyncSortPath,
      VaultSyncSort.size => context.l10n.vaultSyncSortSize,
      VaultSyncSort.modified => context.l10n.vaultSyncSortModified,
      VaultSyncSort.status => context.l10n.vaultSyncSortStatus,
    };
    final notifier = ref.read(vaultSyncProvider.notifier);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in VaultSyncFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filterLabel(f)),
                      showCheckmark: false,
                      selected: state.filter == f,
                      onSelected: (_) => notifier.setFilter(f),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<VaultSyncSort>(
            icon: const Icon(Icons.swap_vert_rounded),
            tooltip: context.l10n.vaultSyncSortTooltip,
            initialValue: state.sort,
            onSelected: notifier.setSort,
            itemBuilder: (_) => [
              for (final o in VaultSyncSort.values)
                PopupMenuItem(value: o, child: Text(sortLabel(o))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStaleBanner(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.vaultSyncResultsStaleMessage,
              style: context.typography.bodySmall?.copyWith(
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(vaultSyncProvider.notifier).startCompare(),
            child: Text(context.l10n.vaultSyncRecompareButton),
          ),
        ],
      ),
    );
  }

  // ── SELECTION BAR ──────────────────────────────────────────────────────────

  Widget _buildSelectionBar(BuildContext context, VaultSyncState state) {
    final cs = context.colors;
    final notifier = ref.read(vaultSyncProvider.notifier);
    final selected = _selectedEntries(state);
    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);
    bool any(EntryAction a) => selected.any((e) => notifier.canApply(e, a));

    void plan(EntryAction action) {
      notifier.setOverrides(state.selectedIds, action);
      notifier.clearSelection();
    }

    Future<void> deleteNow({required bool l, required bool r}) async {
      final changed = await confirmAndDeleteVaultSyncEntries(
        context,
        ref,
        entries: selected,
        fromLeft: l,
        fromRight: r,
      );
      if (changed) notifier.clearSelection();
    }

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
                    ? () => plan(EntryAction.copyToRight)
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
                    ? () => plan(EntryAction.copyToLeft)
                    : null,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(
                  context.l10n.vaultSyncActionCopyTo(names.left),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () => plan(EntryAction.skip),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                label: Text(context.l10n.vaultSyncActionSkip),
              ),
              PopupMenuButton<(bool, bool)>(
                enabled: any(EntryAction.deleteLeft) || any(EntryAction.deleteRight),
                tooltip: context.l10n.delete,
                onSelected: (v) => unawaited(deleteNow(l: v.$1, r: v.$2)),
                itemBuilder: (_) => [
                  if (any(EntryAction.deleteLeft))
                    PopupMenuItem(
                      value: (true, false),
                      child: Text(context.l10n.vaultSyncDeleteFromAction(names.left)),
                    ),
                  if (any(EntryAction.deleteRight))
                    PopupMenuItem(
                      value: (false, true),
                      child: Text(context.l10n.vaultSyncDeleteFromAction(names.right)),
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

  // ── DIFF TILES ─────────────────────────────────────────────────────────────

  Widget _buildDiffTile(
    BuildContext context,
    VaultSyncState state,
    VaultDiffEntry entry,
    bool isLandscape,
  ) {
    if (isLandscape) {
      return _buildDiffTileWide(context, state, entry);
    }
    return _buildDiffTilePortrait(context, state, entry);
  }

  Widget _buildDiffTilePortrait(
    BuildContext context,
    VaultSyncState state,
    VaultDiffEntry entry,
  ) {
    final cs = context.colors;
    final textTheme = context.typography;
    final action = ref.read(vaultSyncProvider.notifier).actionFor(entry);

    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);
    final statusColor = entry.statusColor(cs);
    final statusLabel = entry.statusLabel(context.l10n, names);
    final selected = state.selectedIds.contains(entry.id);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        onTap: () => _onEntryTap(state, entry),
        onLongPress: () => _onEntryLongPress(entry),
        leading: Icon(
          selected
              ? Icons.check_circle_rounded
              : entry.isDir
              ? Icons.folder_rounded
              : iconForFile(entry.name),
          color: selected
              ? cs.primary
              : entry.isDir
              ? cs.secondary
              : colorForFile(entry.name),
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
              _buildDiffDetailText(context, entry, names),
            ],
          ),
        ),
        trailing: _buildActionMenu(context, state, entry, action),
      ),
    );
  }

  Widget _buildDiffTileWide(
    BuildContext context,
    VaultSyncState state,
    VaultDiffEntry entry,
  ) {
    final cs = context.colors;
    final textTheme = context.typography;
    final action = ref.read(vaultSyncProvider.notifier).actionFor(entry);
    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);
    final statusColor = entry.statusColor(cs);
    final statusLabel = entry.statusLabel(context.l10n, names);
    final selected = state.selectedIds.contains(entry.id);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onEntryTap(state, entry),
        onLongPress: () => _onEntryLongPress(entry),
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
                  child: _buildSideDetail(context, entry, names, isLeftSide: true),
                ),
                SizedBox(
                  width: 44,
                  child: Center(child: _buildActionMenu(context, state, entry, action)),
                ),
                Expanded(
                  child: _buildSideDetail(context, entry, names, isLeftSide: false),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSideDetail(
    BuildContext context,
    VaultDiffEntry entry,
    VaultSyncNames names, {
    required bool isLeftSide,
  }) {
    final cs = context.colors;
    final style = context.typography.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final align = isLeftSide ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final textAlign = isLeftSide ? TextAlign.left : TextAlign.right;
    final name = names.of(isLeft: isLeftSide);
    final absentHere = isLeftSide
        ? entry.status == VaultDiffStatus.onlyRight
        : entry.status == VaultDiffStatus.onlyLeft;

    final sizeBytes = isLeftSide ? entry.leftSizeBytes : entry.rightSizeBytes;
    final modifiedSecs = isLeftSide ? entry.leftModifiedSecs : entry.rightModifiedSecs;
    final onlyOnThisSide = isLeftSide
        ? entry.status == VaultDiffStatus.onlyLeft
        : entry.status == VaultDiffStatus.onlyRight;

    final String text;
    if (absentHere) {
      text = '—';
    } else if (entry.isDir && onlyOnThisSide) {
      final sizeText = sizeBytes != null && sizeBytes > 0 ? '${formatBytes(sizeBytes)} · ' : '';
      text = '$sizeText${context.l10n.vaultSyncFolderOnlyInDetail(name)}';
    } else {
      text = '${formatBytes(sizeBytes ?? 0)} · ${formatEntryDateTime(modifiedSecs ?? 0, context)}';
    }

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style,
        ),
      ],
    );
  }

  Widget _buildDiffDetailText(BuildContext context, VaultDiffEntry entry, VaultSyncNames names) {
    final style = context.typography.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    switch (entry.status) {
      case VaultDiffStatus.onlyLeft:
        final sizeText = entry.leftSizeBytes != null && entry.leftSizeBytes! > 0
            ? '${formatBytes(entry.leftSizeBytes!)} · '
            : '';
        return Text(
          entry.isDir
              ? '$sizeText${context.l10n.vaultSyncFolderOnlyInDetail(names.left)}'
              : '${formatBytes(entry.leftSizeBytes ?? 0)} · ${formatEntryDateTime(entry.leftModifiedSecs ?? 0, context)}',
          style: style,
        );
      case VaultDiffStatus.onlyRight:
        final sizeText = entry.rightSizeBytes != null && entry.rightSizeBytes! > 0
            ? '${formatBytes(entry.rightSizeBytes!)} · '
            : '';
        return Text(
          entry.isDir
              ? '$sizeText${context.l10n.vaultSyncFolderOnlyInDetail(names.right)}'
              : '${formatBytes(entry.rightSizeBytes ?? 0)} · ${formatEntryDateTime(entry.rightModifiedSecs ?? 0, context)}',
          style: style,
        );
      case VaultDiffStatus.leftNewer:
      case VaultDiffStatus.rightNewer:
      case VaultDiffStatus.conflicted:
      case VaultDiffStatus.identical:
      case VaultDiffStatus.bothFolders:
        // Two lines, so both full date-times fit without being cut off.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${names.left}  ${formatBytes(entry.leftSizeBytes ?? 0)} · ${formatEntryDateTime(entry.leftModifiedSecs ?? 0, context)}',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${names.right}  ${formatBytes(entry.rightSizeBytes ?? 0)} · ${formatEntryDateTime(entry.rightModifiedSecs ?? 0, context)}',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
    }
  }

  Widget _buildActionMenu(
    BuildContext context,
    VaultSyncState state,
    VaultDiffEntry entry,
    EntryAction action,
  ) {
    final cs = context.colors;

    if (entry.typeMismatch) {
      return Tooltip(
        message: context.l10n.vaultSyncTypeMismatchTooltip,
        child: Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
      );
    }

    final notifier = ref.read(vaultSyncProvider.notifier);
    final names = vaultSyncNamesOf(state.left, state.right, context.l10n);

    final (IconData icon, Color color) = switch (action) {
      EntryAction.copyToRight => (Icons.arrow_forward_rounded, cs.primary),
      EntryAction.copyToLeft => (Icons.arrow_back_rounded, cs.secondary),
      EntryAction.deleteLeft ||
      EntryAction.deleteRight => (Icons.delete_outline_rounded, cs.error),
      EntryAction.skip => (Icons.remove_circle_outline_rounded, cs.onSurfaceVariant),
    };

    if (state.isSyncing) {
      return Icon(icon, color: color.withValues(alpha: 0.5), size: 20);
    }

    return PopupMenuButton<EntryAction>(
      icon: Icon(icon, color: color, size: 20),
      tooltip: context.l10n.vaultSyncChangeActionTooltip,
      onSelected: (a) => notifier.setOverride(entry.id, a),
      itemBuilder: (ctx) => [
        if (notifier.canApply(entry, EntryAction.copyToRight))
          PopupMenuItem(
            value: EntryAction.copyToRight,
            child: Text(context.l10n.vaultSyncActionCopyTo(names.right)),
          ),
        if (notifier.canApply(entry, EntryAction.copyToLeft))
          PopupMenuItem(
            value: EntryAction.copyToLeft,
            child: Text(context.l10n.vaultSyncActionCopyTo(names.left)),
          ),
        if (notifier.canApply(entry, EntryAction.deleteLeft))
          PopupMenuItem(
            value: EntryAction.deleteLeft,
            child: Text(
              context.l10n.vaultSyncPlanDeleteFrom(names.left),
              style: TextStyle(color: cs.error),
            ),
          ),
        if (notifier.canApply(entry, EntryAction.deleteRight))
          PopupMenuItem(
            value: EntryAction.deleteRight,
            child: Text(
              context.l10n.vaultSyncPlanDeleteFrom(names.right),
              style: TextStyle(color: cs.error),
            ),
          ),
        PopupMenuItem(
          value: EntryAction.skip,
          child: Text(context.l10n.vaultSyncActionSkip),
        ),
      ],
    );
  }

  // ── BOTTOM ACTION BAR ──────────────────────────────────────────────────────

  Widget _buildBottomActionBar(
    BuildContext context,
    VaultSyncState state,
    int pendingTotal,
  ) {
    final cs = context.colors;
    final textTheme = context.typography;
    final pendingBytes = _pendingBytesToRight(state) + _pendingBytesToLeft(state);
    final pendingDeletes = ref.read(vaultSyncProvider.notifier).pendingDeleteCount();

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
                    context.l10n.vaultSyncChangesQueuedLabel(pendingTotal),
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    formatBytes(pendingBytes),
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (pendingDeletes > 0)
                    Text(
                      context.l10n.vaultSyncDeletionsQueuedLabel(pendingDeletes),
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.bold,
                      ),
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
              onPressed: state.isSyncing ? null : () => _confirmAndSync(state),
              icon: state.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                state.isSyncing
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
