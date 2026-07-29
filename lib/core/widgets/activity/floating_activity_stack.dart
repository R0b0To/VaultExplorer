import 'package:flutter/material.dart';

import '../../../data/models/file_operation.dart';
import 'floating_activity_stack.dart';

// Barrel exports: this file used to contain FloatingPill, ClipboardActivityPill,
// and OperationActivityPill directly. They now live in their own files below —
// re-exported here so existing imports of 'floating_activity_stack.dart' keep
// working without every call site needing to be updated individually.
export 'package:vaultexplorer/core/widgets/activity/floating_pill.dart';
export 'package:vaultexplorer/core/widgets/activity/clipboard_activity_pill.dart';
export 'package:vaultexplorer/core/widgets/activity/operation_activity_pill.dart';
export 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';

/// Renders floating activity pills centered at the bottom of the screen.
/// Modern UI pattern: floating pill is used strictly for active background
/// file operations/transfers, while clipboard copy/cut status is displayed
/// directly in the Top AppBar header.
class FloatingActivityStack extends StatelessWidget {
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
          listenable: FileOperationService.instance,
          builder: (context, _) {
            final hasOps = FileOperationService.instance.operations.isNotEmpty;
            if (!hasOps) return const SizedBox.shrink();

            return const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OperationActivityPill(),
              ],
            );
          },
        ),
      ),
    );
  }
}

