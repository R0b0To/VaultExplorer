import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/features/browser/widgets/file_operations_sheet.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_pill.dart';
import '../../utils/format_utils.dart';

class OperationActivityPill extends StatefulWidget {
  const OperationActivityPill({super.key});
  @override
  State<OperationActivityPill> createState() => _OperationActivityPillState();
}

class _OperationActivityPillState extends State<OperationActivityPill> {
  static const _kLingerDuration = Duration(seconds: 4);
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    FileOperationService.instance.addListener(_onChanged);
    FileOperationsSheet.isOpenNotifier.addListener(_onChanged);
    _maybeScheduleAutoHide();
  }

  @override
  void dispose() {
    FileOperationService.instance.removeListener(_onChanged);
    FileOperationsSheet.isOpenNotifier.removeListener(_onChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onChanged() => _maybeScheduleAutoHide();

  void _maybeScheduleAutoHide() {
    final svc = FileOperationService.instance;
    _hideTimer?.cancel();
    if (svc.operations.isEmpty || svc.activeCount > 0) return;
    if (FileOperationsSheet.isOpenNotifier.value) return;
    final hasErrors = svc.operations.any(
      (op) =>
          op.status == FileOperationStatus.failed ||
          op.status == FileOperationStatus.diskFull ||
          op.status == FileOperationStatus.completedWithErrors,
    );
    if (hasErrors) return;
    _hideTimer = Timer(_kLingerDuration, () {
      FileOperationService.instance.clearFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FileOperationService.instance,
      builder: (context, _) {
        final svc = FileOperationService.instance;
        final ops = svc.operations;
        if (ops.isEmpty) return const SizedBox.shrink();
        final active = svc.activeOperations;
        final hasActive = active.isNotEmpty;
        final primary = hasActive ? active.last : ops.last;
        return ListenableBuilder(
          listenable: primary,
          builder: (context, _) => _OperationPillContent(
            primary: primary,
            activeCount: active.length,
            hasActive: hasActive,
          ),
        );
      },
    );
  }
}

class _OperationPillContent extends StatelessWidget {
  final FileOperation primary;
  final int activeCount;
  final bool hasActive;

  // Fixed content width so the pill doesn't jump in size
  // and trailing icons remain anchored to the far right.
  static const _kActiveContentWidth = 280.0;

  const _OperationPillContent({
    required this.primary,
    required this.activeCount,
    required this.hasActive,
  });

  String _progressText(BuildContext context, FileOperation op) {
    if (op.isDelete) {
      return context.l10n.fileOpDeletedSoFar(op.removedCount);
    }
    if (op.totalBytes > 0) {
      final pct = ((op.transferredBytes / op.totalBytes) * 100).clamp(0, 100).round();
      return context.l10n.byteProgressText(
        formatBytes(op.transferredBytes),
        formatBytes(op.totalBytes),
        pct,
      );
    }
    final done = op.doneCount + op.skipCount + op.failCount;
    final total = op.totalCount;
    if (total == 0) return '';
    final pct = ((done / total) * 100).round();
    return context.l10n.countProgressText(done, total, pct);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isError =
        primary.status == FileOperationStatus.failed ||
        primary.status == FileOperationStatus.diskFull ||
        primary.status == FileOperationStatus.completedWithErrors;
    final color = isError ? cs.errorContainer : cs.secondaryContainer;
    final onColor = isError ? cs.onErrorContainer : cs.onSecondaryContainer;

    final String label;
    final String sublabel;

    if (hasActive) {
      label = primary.currentActivity.isNotEmpty
          ? primary.currentActivity
          : primary.shortSummary;

      final progress = _progressText(context, primary);
      if (activeCount > 1) {
        sublabel = progress.isNotEmpty
            ? '$progress · +${activeCount - 1} more'
            : '+${activeCount - 1} more';
      } else {
        sublabel = progress;
      }
    } else {
      label = primary.completionSummary;
      sublabel = '';
    }

    return FloatingPill(
      color: color,
      onTap: () => FileOperationsSheet.show(context),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _kActiveContentWidth,
          child: Row(
            children: [
              if (hasActive)
                SizedBox(
                  width: AppIconSize.standard,
                  height: AppIconSize.standard,
                  child: CircularProgressIndicator(
                    value: primary.progressFraction,
                    strokeWidth: 2,
                    color: onColor,
                    backgroundColor: onColor.withValues(alpha: 0.25),
                  ),
                )
              else
                Icon(
                  switch (primary.status) {
                    FileOperationStatus.completed => Icons.check_circle_rounded,
                    FileOperationStatus.cancelled => Icons.cancel_outlined,
                    _ => Icons.error_outline_rounded,
                  },
                  size: AppIconSize.standard,
                  color: onColor,
                ),
              const SizedBox(width: 10),
              // Expanded forces the Column to take all available space,
              // pushing the trailing icon / IconButton to the far right.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: textTheme.labelLarge?.copyWith(
                        color: onColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sublabel.isNotEmpty)
                      Text(
                        sublabel,
                        style: textTheme.labelSmall?.copyWith(
                          color: onColor.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (hasActive)
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppIconSize.standard,
                  color: onColor.withValues(alpha: 0.8),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: AppIconSize.standard,
                    color: onColor,
                  ),
                  tooltip: context.l10n.dismiss,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => FileOperationService.instance.clearFinished(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}