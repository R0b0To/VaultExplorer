import 'package:flutter/material.dart';

/// App bar shown whenever the unified clipboard has items pending paste.
///
/// Works for both same-container and cross-container operations — the caller
/// passes [sourceLabel] (the source container's display name) only when the
/// clipboard belongs to a different container, so the user always knows where
/// the items came from.
class ClipboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isCutOperation;
  final int itemCount;

  /// When non-null, shown as "from «sourceLabel»" to indicate a cross-container
  /// operation. Null when pasting within the same container.
  final String? sourceLabel;

  final VoidCallback onCancel;
  final VoidCallback onPaste;

  /// Called when the back arrow is tapped. At root this pops to dashboard;
  /// inside a subfolder it goes up one level. Never null — back is always available.
  final VoidCallback onBack;

  const ClipboardAppBar({
    Key? key,
    required this.isCutOperation,
    required this.itemCount,
    this.sourceLabel,
    required this.onCancel,
    required this.onPaste,
    required this.onBack,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final verb = isCutOperation ? 'Moving' : 'Copying';
    final fromSuffix = sourceLabel != null ? ' from "$sourceLabel"' : '';
    final titleText = '$verb $itemCount item(s)$fromSuffix';

    return AppBar(
      // M3 Contextual App Bars use surfaceContainer to clearly signal 
      // an active, temporary contextual layout state.
      backgroundColor: cs.surfaceContainer,
      foregroundColor: cs.onSurface,
      elevation: 0,
      shape: Border(
        bottom: BorderSide(color: cs.outlineVariant),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Navigate back',
        onPressed: onBack,
      ),
      title: Row(
        children: [
          Icon(
            isCutOperation ? Icons.cut_rounded : Icons.copy_rounded,
            size: 18,
            color: cs.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titleText,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.paste_rounded, size: 18),
          label: const Text('Paste Here'),
          style: TextButton.styleFrom(
            foregroundColor: cs.primary,
            textStyle: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: onCancel,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}