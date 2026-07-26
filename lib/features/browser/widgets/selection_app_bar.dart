import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final String selectionLabel;
  final bool singleSelected;
  final bool singleFileSelected;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onOpenWithApp;
  final bool readOnly;

  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.selectionLabel,
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
    this.readOnly = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Dynamically show actions to prevent truncating the title on narrow screens
    final bool showCopy = screenWidth >= 350;
    final bool showCut = screenWidth >= 390;
    final bool showRename = screenWidth >= 430;

    return AppBar(
      backgroundColor: cs.surfaceContainer,
      foregroundColor: cs.onSurface,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: cs.outlineVariant)),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Clear selection',
        onPressed: onClose,
      ),
      titleSpacing: 0,
      title: PopupMenuButton<String>(
        tooltip: 'Selection options',
        offset: const Offset(0, 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(
                    AppRadius.full,
                  ),
                ),
                child: Text(
                  '$selectedCount',
                  style: textTheme.labelLarge?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  selectionLabel,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down_rounded,
                color: cs.onSurface,
                size: AppIconSize.standard,
              ),
            ],
          ),
        ),
        onSelected: (value) {
          if (value == 'select_all') onSelectAll();
          if (value == 'clear') onClose();
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
          icon: Icon(
            Icons.delete_outline_rounded,
            color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.error,
          ),
          tooltip: readOnly ? 'Read-only container' : 'Delete',
          onPressed: readOnly ? null : onDelete,
        ),
        if (showCopy)
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy',
            onPressed: onCopy,
          ),
        if (showCut)
          IconButton(
            icon: const Icon(Icons.cut_rounded),
            tooltip: readOnly ? 'Read-only container' : 'Move',
            onPressed: readOnly ? null : onCut,
          ),
        if (showRename)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            tooltip: readOnly ? 'Read-only container' : 'Rename',
            onPressed: readOnly ? null : onRename,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'More options',
          onSelected: (value) {
            if (value == 'copy') onCopy();
            if (value == 'cut') onCut();
            if (value == 'rename') onRename();
            if (value == 'export') onExport();
            if (value == 'open_with_app') onOpenWithApp();
          },
          itemBuilder: (context) => [
            if (!showCopy)
              PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(
                      Icons.copy_rounded,
                      color: cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    const Text('Copy'),
                  ],
                ),
              ),
            if (!showCut)
              PopupMenuItem<String>(
                value: 'cut',
                enabled: !readOnly,
                child: Row(
                  children: [
                    Icon(
                      Icons.cut_rounded,
                      color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    const Text('Move'),
                  ],
                ),
              ),
            if (!showRename)
              PopupMenuItem<String>(
                value: 'rename',
                enabled: !readOnly,
                child: Row(
                  children: [
                    Icon(
                      Icons.drive_file_rename_outline_rounded,
                      color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    const Text('Rename'),
                  ],
                ),
              ),
            PopupMenuItem<String>(
              value: 'export',
              child: Row(
                children: [
                  Icon(
                    Icons.drive_folder_upload_rounded,
                    color: cs.onSurfaceVariant,
                    size: AppIconSize.small,
                  ),
                  const SizedBox(width: 12),
                  const Text('Export to device'),
                ],
              ),
            ),
            if (singleFileSelected)
              PopupMenuItem<String>(
                value: 'open_with_app',
                child: Row(
                  children: [
                    Icon(
                      Icons.open_in_new_rounded,
                      color: cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
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