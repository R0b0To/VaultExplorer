import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/features/browser/widgets/file_operations_sheet.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_pill.dart';

import '../../utils/format_utils.dart';

/// Live file-operation progress indicator.
///
/// Auto-dismisses [_kLingerDuration] after a clean (no-error) completion.
/// The linger timer is paused while [FileOperationsSheet] is open (tracked
/// via [FileOperationsSheet.isOpenNotifier]) so the pill's underlying history
/// doesn't get cleared out from under the person while they're actively
/// looking at it — it resumes counting down once they close the sheet.
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
    if (FileOperationsSheet.isOpenNotifier.value) return; // paused while viewing

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
            totalOps: ops.length,
            hasActive: hasActive,
          ),
        );
      },
    );
  }
}

class _OperationPillContent extends StatelessWidget {
  final FileOperation primary;
  final int totalOps;
  final bool hasActive;

  const _OperationPillContent({
    required this.primary,
    required this.totalOps,
    required this.hasActive,
  });

  String _progressText(FileOperation op) {
    if (op.totalBytes > 0) {
      final pct = ((op.transferredBytes / op.totalBytes) * 100).clamp(0, 100).round();
      return '${formatBytes(op.transferredBytes)} / ${formatBytes(op.totalBytes)}  ($pct%)';
    }
    final done = op.doneCount + op.skipCount + op.failCount;
    final total = op.totalCount;
    if (total == 0) return '';
    final pct = ((done / total) * 100).round();
    return '$done / $total  ($pct%)';
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

    final multiOp = totalOps > 1;
    final label = multiOp
        ? '$totalOps transfers'
        : (hasActive
              ? (primary.currentActivity.isNotEmpty ? primary.currentActivity : primary.shortSummary)
              : primary.completionSummary);
    final sublabel = multiOp
        ? '${hasActive ? primary.shortSummary : 'Completed'} · tap to view all'
        : (hasActive ? _progressText(primary) : '');

    return FloatingPill(
      color: color,
      onTap: () => FileOperationsSheet.show(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(width: 12),
          Flexible(
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
            Icon(Icons.chevron_right_rounded, size: AppIconSize.standard, color: onColor.withValues(alpha: 0.8))
          else
            IconButton(
              icon: Icon(Icons.close_rounded, size: AppIconSize.standard, color: onColor),
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () => FileOperationService.instance.clearFinished(),
            ),
        ],
      ),
    );
  }
}
