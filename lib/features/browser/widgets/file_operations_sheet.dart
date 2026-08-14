import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';

class FileOperationsSheet extends StatelessWidget {
  const FileOperationsSheet({super.key});

  /// True while the sheet is on screen. [OperationActivityPill] watches this
  /// to pause its auto-hide linger timer — otherwise a finished transfer
  /// could clear itself out from under the person while they're actively
  /// looking at "Recent transfers".
  static final isOpenNotifier = ValueNotifier<bool>(false);

  static void show(BuildContext context) {
    isOpenNotifier.value = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FileOperationsSheet(),
    ).whenComplete(() => isOpenNotifier.value = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: FileOperationService.instance,
          builder: (context, _) {
            final ops = FileOperationService.instance.operations.reversed
                .toList();
            final hasActive = FileOperationService.instance.activeCount > 0;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: AppIconSize.standard,
                        color: cs.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm + 2),
                      Expanded(
                        child: Text(
                          hasActive
                              ? context.l10n.fileOpsTransfersInProgressTitle
                              : context.l10n.fileOpsRecentTransfersTitle,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!hasActive)
                        TextButton(
                          onPressed: () {
                            FileOperationService.instance.clearFinished();
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(context.l10n.clearAllButton),
                        ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // ── Operation list ───────────────────────────────────────────
                Expanded(
                  child: ops.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: ops.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 20),
                          itemBuilder: (_, i) => _OperationRow(op: ops[i]),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: Icons.check_circle_outline_rounded,
    title: context.l10n.fileOpsNoRecentTransfersMessage,
    message: context.l10n.fileOpsNoRecentTransfersSubtitle,
  );
}

// ── Single operation row ──────────────────────────────────────────────────────

class _OperationRow extends StatelessWidget {
  final FileOperation op;
  const _OperationRow({required this.op});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: op,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final semantic = context.semanticColors;

        final isActive =
            op.status == FileOperationStatus.pending ||
            op.status == FileOperationStatus.running;
        // A hard failure (nothing salvageable) is visually distinct from a
        // batch that finished with some items skipped/failed but the rest
        // succeeded -- the latter uses the app's amber "warning" token
        // instead of red, so partial success doesn't read as total failure.
        final isError =
            op.status == FileOperationStatus.failed ||
            op.status == FileOperationStatus.diskFull;
        final isWarning = op.status == FileOperationStatus.completedWithErrors;
        final isDone = op.status == FileOperationStatus.completed;
        final isCancelled = op.status == FileOperationStatus.cancelled;

        final statusColor = isError
            ? cs.error
            : isWarning
            ? semantic.warning
            : isDone
            ? cs.primary
            : isCancelled
            ? cs.onSurfaceVariant
            : cs.onSurface;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 4,
            vertical: AppSpacing.md - 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: icon + title + cancel ────────────────────────────
              Row(
                children: [
                  _StatusIcon(op: op, cs: cs, semantic: semantic),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          op.shortSummary,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _routeLabel(context, op),
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: AppIconSize.small,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: context.l10n.fileOpsCancelTooltip,
                      onPressed: op.requestCancel,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.sm + 2),

              // ── Progress bar ───────────────────────────────────────────────
              if (isActive) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm / 4),
                  child: TweenAnimationBuilder<double>(
                    duration: AppMotion.medium1,
                    curve: AppMotion.standard,
                    tween: Tween(end: op.progressFraction ?? 0),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: op.progressFraction == null ? null : value,
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  op.currentActivity.isNotEmpty
                      ? op.currentActivity
                      : op.shortSummary,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // ── Completion summary ─────────────────────────────────────────
              if (!isActive && !isCancelled) ...[
                if (isError && op.errorSummary != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: AppIconSize.inline,
                        color: cs.error,
                      ),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Expanded(
                        child: Text(
                          op.errorSummary!,
                          style: textTheme.bodySmall?.copyWith(color: cs.error),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ] else if (op.skipCount > 0 || op.failCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    op.completionSummary,
                    style: textTheme.bodySmall?.copyWith(
                      color: isWarning ? semantic.warning : cs.onSurfaceVariant,
                      fontWeight: isWarning ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ],

              if (isCancelled) ...[
                const SizedBox(height: 4),
                Text(
                  context.l10n.fileOpsCancelledStatusLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],

              // ── Per-item detail (expandable) ────────
              if (!isActive && (op.items.length > 1 || op.failCount > 0))
                _BatchItemsDetail(op: op, cs: cs, textTheme: textTheme),
            ],
          ),
        );
      },
    );
  }

  String _routeLabel(BuildContext context, FileOperation op) {
    if (op.isCrossContainer) {
      return '${op.sourceDisplayName} → ${op.destDisplayName}';
    }
    final dest = op.destDirPath.isEmpty ? context.l10n.fileOpsRootDestinationLabel : op.destDirPath;
    return '→ $dest';
  }
}

// ── Status icon ───────────────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final FileOperation op;
  final ColorScheme cs;
  final AppSemanticColors semantic;
  const _StatusIcon({required this.op, required this.cs, required this.semantic});

  @override
  Widget build(BuildContext context) {
    // AnimatedSwitcher softens the pending/running -> resolved-status jump
    // (spinner to check/warning/error icon) that previously snapped
    // instantly, matching the motion language (AppMotion) used elsewhere
    // in the app for state transitions.
    return AnimatedSwitcher(
      duration: AppMotion.short2,
      switchInCurve: AppMotion.standard,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: SizedBox(
        key: ValueKey(op.status),
        width: AppIconSize.small,
        height: AppIconSize.small,
        child: _iconFor(context),
      ),
    );
  }

  Widget _iconFor(BuildContext context) {
    switch (op.status) {
      case FileOperationStatus.pending:
      case FileOperationStatus.running:
        return CircularProgressIndicator(
          strokeWidth: 2,
          value: op.progressFraction,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
        );
      case FileOperationStatus.completed:
        return Icon(Icons.check_circle_rounded, size: AppIconSize.small, color: cs.primary);
      case FileOperationStatus.completedWithErrors:
        return Icon(Icons.warning_amber_rounded, size: AppIconSize.small, color: semantic.warning);
      case FileOperationStatus.failed:
      case FileOperationStatus.diskFull:
        return Icon(Icons.error_outline_rounded, size: AppIconSize.small, color: cs.error);
      case FileOperationStatus.cancelled:
        return Icon(
          Icons.cancel_outlined,
          size: AppIconSize.small,
          color: cs.onSurfaceVariant,
        );
    }
  }
}

// ── Batch items detail ────────────────────────────────────────────────────────

class _BatchItemsDetail extends StatelessWidget {
  final FileOperation op;
  final ColorScheme cs;
  final TextTheme textTheme;
  const _BatchItemsDetail({
    required this.op,
    required this.cs,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final hasErrors = op.failCount > 0;

    // Collapsed by default when everything succeeded (the summary line
    // above already covers that case) -- expanded automatically when
    // there are failures, since that's exactly what the person opened
    // this row to look at.
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: hasErrors,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        iconColor: hasErrors ? cs.error : cs.onSurfaceVariant,
        collapsedIconColor: hasErrors ? cs.error : cs.onSurfaceVariant,
        title: Text(
          hasErrors
              ? context.l10n.fileOpsItemsFailedLabel(op.failCount)
              : context.l10n.fileOpsShowDetailsLabel(op.itemStatuses.length),
          style: textTheme.bodySmall?.copyWith(
            color: hasErrors ? cs.error : cs.onSurfaceVariant,
            fontWeight: hasErrors ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildItemList(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildItemList(BuildContext context) {
    // Sort so failures are at the top
    final sorted = List<FileItemStatus>.from(op.itemStatuses)
      ..sort((a, b) {
        if (a.result == FileItemResult.failed && b.result != FileItemResult.failed) return -1;
        if (a.result != FileItemResult.failed && b.result == FileItemResult.failed) return 1;
        return 0;
      });

    final displayCount = sorted.length > 50 ? 50 : sorted.length;
    final toDisplay = sorted.take(displayCount);

    final widgets = toDisplay.map((s) {
      final isFailed = s.result == FileItemResult.failed;
      final itemColor = isFailed ? cs.error : cs.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isFailed ? Icons.close_rounded : Icons.subdirectory_arrow_right_rounded,
                size: AppIconSize.inline - 2,
                color: itemColor,
              ),
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Text(
                s.item.name + (s.errorMessage != null ? ' — ${s.errorMessage}' : ''),
                style: textTheme.bodySmall?.copyWith(
                  color: itemColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();

    if (sorted.length > displayCount) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 2),
          child: Text(
            context.l10n.fileOpsMoreItemsLabel(sorted.length - displayCount),
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}