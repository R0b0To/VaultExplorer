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

    final verb = isCutOperation ? 'Moving' : 'Copying';
    final fromSuffix =
        sourceLabel != null ? ' from "$sourceLabel"' : '';
    final titleText = '$verb $itemCount item(s)$fromSuffix';

    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: cs.primary.withOpacity(0.4))),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Navigate back',
        onPressed: onBack,
      ),
      title: Row(
        children: [
          Icon(
            isCutOperation ? Icons.cut : Icons.copy,
            size: 15,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titleText,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: cs.primary),
          onPressed: onPaste,
          icon: const Icon(Icons.paste, size: 16),
          label: const Text('Paste Here',
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: onCancel,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}