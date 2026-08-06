import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final String selectionLabel;
  final bool singleSelected;
  final bool singleFileSelected;
  final bool singleFolderSelected;
  final bool folderDocumentProviderMounted;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onOpenWithApp;
  final VoidCallback? onToggleDocumentProvider;
  final bool readOnly;
  final bool showPinOption;
  final bool showUnpinOption;
  final VoidCallback onPin;
  final VoidCallback onUnpin;

  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.selectionLabel,
    required this.singleSelected,
    required this.singleFileSelected,
    this.singleFolderSelected = false,
    this.folderDocumentProviderMounted = false,
    required this.onClose,
    required this.onSelectAll,
    required this.onRename,
    required this.onCopy,
    required this.onCut,
    required this.onExport,
    required this.onDelete,
    required this.onOpenWithApp,
    this.onToggleDocumentProvider,
    this.readOnly = false,
    required this.showPinOption,
    required this.showUnpinOption,
    required this.onPin,
    required this.onUnpin,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
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
        tooltip: context.l10n.clearSelectionTooltip,
        onPressed: onClose,
      ),
      titleSpacing: 0,
      title: PopupMenuButton<String>(
        tooltip: context.l10n.selectionOptionsTooltip,
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
          PopupMenuItem<String>(
            value: 'select_all',
            child: Text(context.l10n.selectAllAction),
          ),
          PopupMenuItem<String>(
            value: 'clear',
            child: Text(context.l10n.clearSelectionAction),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.delete_outline_rounded,
            color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.error,
          ),
          tooltip: readOnly ? context.l10n.readOnlyContainerTooltip : context.l10n.delete,
          onPressed: readOnly ? null : onDelete,
        ),
        if (showCopy)
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: context.l10n.copyTooltip,
            onPressed: onCopy,
          ),
        if (showCut)
          IconButton(
            icon: const Icon(Icons.cut_rounded),
            tooltip: readOnly ? context.l10n.readOnlyContainerTooltip : context.l10n.moveAction,
            onPressed: readOnly ? null : onCut,
          ),
        if (showRename)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            tooltip: readOnly ? context.l10n.readOnlyContainerTooltip : context.l10n.renameTooltip,
            onPressed: readOnly ? null : onRename,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: context.l10n.moreOptionsTooltip,
          onSelected: (value) {
            if (value == 'copy') onCopy();
            if (value == 'cut') onCut();
            if (value == 'rename') onRename();
            if (value == 'export') onExport();
            if (value == 'pin') onPin();
            if (value == 'unpin') onUnpin();
            if (value == 'open_with_app') onOpenWithApp();
            if (value == 'doc_provider') onToggleDocumentProvider?.call();
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
                    Text(context.l10n.copyAction),
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
                    Text(context.l10n.moveAction),
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
                    Text(context.l10n.renameAction),
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
                  Text(context.l10n.exportToDeviceAction),
                ],
              ),
            ),
            if (showPinOption)
              PopupMenuItem<String>(
                value: 'pin',
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin_rounded,
                      color: cs.primary,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    Text(selectedCount > 1 ? context.l10n.pinSelectedAction : context.l10n.pinAction),
                  ],
                ),
              ),
            if (showUnpinOption)
              PopupMenuItem<String>(
                value: 'unpin',
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin_outlined,
                      color: cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    Text(selectedCount > 1 ? context.l10n.unpinSelectedAction : context.l10n.unpinAction),
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
                    Text(context.l10n.openWithAppAction),
                  ],
                ),
              ),
            if (singleFolderSelected)
              PopupMenuItem<String>(
                value: 'doc_provider',
                child: Row(
                  children: [
                    Icon(
                      folderDocumentProviderMounted
                          ? Icons.folder_shared_rounded
                          : Icons.folder_shared_outlined,
                      color: folderDocumentProviderMounted ? cs.tertiary : cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    Text(folderDocumentProviderMounted
                        ? context.l10n.documentProviderSettingsMenu
                        : context.l10n.exposeAsDocumentProviderMenu),
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