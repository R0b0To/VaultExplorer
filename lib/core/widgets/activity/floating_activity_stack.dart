import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';

import '../../../data/models/file_operation.dart';
import 'floating_activity_stack.dart';

// Barrel exports: this file used to contain FloatingPill, ClipboardActivityPill,
// and OperationActivityPill directly. They now live in their own files below —
// re-exported here so existing imports of 'floating_activity_stack.dart' keep
// working without every call site needing to be updated individually.
export 'package:vaultexplorer/core/widgets/activity/floating_pill.dart';
export 'package:vaultexplorer/core/widgets/activity/clipboard_activity_pill.dart';
export 'package:vaultexplorer/core/widgets/activity/operation_activity_pill.dart';

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
