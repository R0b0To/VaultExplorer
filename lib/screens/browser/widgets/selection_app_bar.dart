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
      title: PopupMenuButton<String>(
        tooltip: 'Selection options',
        offset: const Offset(0, 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(width: 8),
              Text(
                'selected',
                style: TextStyle(fontSize: 13, color: cs.onSurface),
              ),
              Icon(Icons.arrow_drop_down, color: cs.onSurface, size: 20),
            ],
          ),
        ),
        onSelected: (value) {
          if (value == 'select_all') {
            onSelectAll();
          } else if (value == 'clear') {
            onClose();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            value: 'select_all',
            child: Text('Select All'),
          ),
          const PopupMenuItem<String>(
            value: 'clear',
            child: Text('Clear Selection'),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.delete_outline, color: cs.error),
          tooltip: 'Delete',
          onPressed: onDelete,
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
        if (singleSelected)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename',
            onPressed: onRename,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'More options',
          onSelected: (value) {
            if (value == 'export') {
              onExport();
            } else if (value == 'open_with_app') {
              onOpenWithApp();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.drive_folder_upload_outlined, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  const Text('Export'),
                ],
              ),
            ),
            if (singleFileSelected)
              PopupMenuItem<String>(
                value: 'open_with_app',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    const Text('Open with App'),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}