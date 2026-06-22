import 'package:flutter/material.dart';

/// App bar shown while the user has one or more items selected.
/// Implements [PreferredSizeWidget] so it can be assigned directly to
/// [Scaffold.appBar] without any wrapper.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;

  /// True when exactly one item is selected (enables Rename).
  final bool singleSelected;

  /// True when the single selected item is a file, not a directory
  /// (enables Open with App).
  final bool singleFileSelected;

  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onOpenWithApp;

  const SelectionAppBar({
    Key? key,
    required this.selectedCount,
    required this.singleSelected,
    required this.singleFileSelected,
    required this.onClose,
    required this.onSelectAll,
    required this.onRename,
    required this.onCopy,
    required this.onCut,
    required this.onExport,
    required this.onDelete,
    required this.onOpenWithApp,
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
        onPressed: onClose,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$selectedCount',
              style: TextStyle(
                color: cs.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text('selected', style: TextStyle(fontSize: 13)),
          const Spacer(),
          TextButton(
            onPressed: onSelectAll,
            child: const Text('All', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      actions: [
        if (singleSelected)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: onRename,
          ),
        IconButton(
          icon: const Icon(Icons.copy_outlined),
          tooltip: 'Copy',
          onPressed: onCopy,
        ),
        IconButton(
          icon: const Icon(Icons.cut_outlined),
          tooltip: 'Cut',
          onPressed: onCut,
        ),
        IconButton(
          icon: const Icon(Icons.drive_folder_upload_outlined),
          tooltip: 'Export',
          onPressed: onExport,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: cs.error),
          tooltip: 'Delete',
          onPressed: onDelete,
        ),
        if (singleFileSelected)
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open with App',
            onPressed: onOpenWithApp,
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}