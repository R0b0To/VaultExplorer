import 'dart:async';
import 'package:flutter/material.dart';
import '../models/file_operation.dart';
import '../screens/browser/widgets/file_operations_sheet.dart';
import '../services/cross_container_clipboard.dart';
import '../theme.dart';

/// Shared floating-pill shell used by every transient "activity" surface
/// (clipboard pending, file operation progress).
class FloatingPill extends StatelessWidget {
  final Widget child;
  final Color color;
  final VoidCallback? onTap;

  const FloatingPill({
    super.key,
    required this.child,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color,
      elevation: 6,
      shadowColor: cs.shadow.withValues(alpha: 0.4),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

/// Pending copy/move clipboard indicator.
class ClipboardActivityPill extends StatelessWidget {
  final bool isCutOperation;
  final int itemCount;
  final String? sourceLabel;
  final VoidCallback onCancel;
  final VoidCallback? onPaste;

  const ClipboardActivityPill({
    super.key,
    required this.isCutOperation,
    required this.itemCount,
    this.sourceLabel,
    required this.onCancel,
    this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final verb = isCutOperation ? 'Moving' : 'Copying';
    final fromSuffix = sourceLabel != null ? ' from "$sourceLabel"' : '';
    final title = '$verb $itemCount item${itemCount == 1 ? '' : 's'}$fromSuffix';

    return FloatingPill(
      color: cs.primaryContainer,
      onTap: onPaste,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCutOperation ? Icons.cut_rounded : Icons.copy_rounded,
            size: AppIconSize.standard,
            color: cs.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: onPaste != null
                ? Text(
                    title,
                    style: textTheme.labelLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.labelLarge?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Open a container to paste',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
          ),
          if (onPaste != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onPaste,
              style: TextButton.styleFrom(
                foregroundColor: cs.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              child: const Text('Paste'),
            ),
          ],
          Container(
            width: 1,
            height: 20,
            color: cs.onPrimaryContainer.withValues(alpha: 0.2),
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: AppIconSize.standard, color: cs.onPrimaryContainer),
            tooltip: 'Cancel',
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

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

    final color = isError ? cs.errorContainer : cs.primaryContainer;
    final onColor = isError ? cs.onErrorContainer : cs.onPrimaryContainer;

    final multiOp = totalOps > 1;
    final label = multiOp
        ? '$totalOps transfers'
        : (hasActive && primary.currentActivity.isNotEmpty
              ? primary.currentActivity
              : primary.shortSummary);
    final sublabel = multiOp
        ? '${primary.shortSummary} · tap to view all'
        : (hasActive ? _progressText(primary) : primary.completionSummary);

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

/// Vertically stacks the operation pill above the clipboard pill (when
/// present), with consistent spacing, centered and width-capped for tablets.
///
/// FIX: previously this widget's visibility of the clipboard pill was driven
/// by the *caller* passing a nullable [clipboardPill] built from whatever
/// state the caller happened to have at its last build — but neither
/// FileBrowserScreen nor VaultDashboard actually listen to
/// [CrossContainerClipboard], so calling `_clip.clear()` after enqueueing a
/// paste didn't trigger a rebuild here. The result: the clipboard pill kept
/// showing (stale) at the same time the new operation pill appeared, instead
/// of being replaced by it. FloatingActivityStack now listens to
/// [CrossContainerClipboard.instance] itself and decides on its own whether
/// to render the clipboard pill, so it can never go stale relative to the
/// operation pill sitting right above it.
class FloatingActivityStack extends StatelessWidget {
  /// Optional restriction so a screen can show the clipboard pill only when
  /// relevant to it (e.g. the dashboard never offers a "Paste" action).
  /// When null, the clipboard pill renders as soon as the clipboard has
  /// items, with an onPaste callback if provided.
  final VoidCallback? onPaste;
  final bool showClipboard;

  const FloatingActivityStack({
    super.key,
    this.onPaste,
    this.showClipboard = true,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            FileOperationService.instance,
            CrossContainerClipboard.instance,
          ]),
          builder: (context, _) {
            final hasOps = FileOperationService.instance.operations.isNotEmpty;
            final clip = CrossContainerClipboard.instance;
            final showClip = showClipboard && clip.hasItems;

            if (!hasOps && !showClip) return const SizedBox.shrink();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasOps) const OperationActivityPill(),
                if (hasOps && showClip) const SizedBox(height: 10),
                if (showClip)
                  ClipboardActivityPill(
                    isCutOperation: clip.isCutOperation,
                    itemCount: clip.items.length,
                    sourceLabel: clip.sourceDisplayName,
                    onCancel: clip.clear,
                    onPaste: onPaste,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}