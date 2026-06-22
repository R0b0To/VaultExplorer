import 'package:flutter/material.dart';

/// App bar shown while items are queued for a copy or move operation.
class ClipboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isCutOperation;
  final int itemCount;
  final VoidCallback onCancel;
  final VoidCallback onPaste;

  const ClipboardAppBar({
    Key? key,
    required this.isCutOperation,
    required this.itemCount,
    required this.onCancel,
    required this.onPaste,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: cs.primary.withOpacity(0.4))),
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel',
        onPressed: onCancel,
      ),
      title: Row(
        children: [
          Icon(
            isCutOperation ? Icons.cut : Icons.copy,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Text(
            isCutOperation
                ? 'Moving $itemCount item(s)'
                : 'Copying $itemCount item(s)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: cs.primary),
          onPressed: onPaste,
          icon: const Icon(Icons.paste, size: 16),
          label: const Text(
            'Paste Here',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}