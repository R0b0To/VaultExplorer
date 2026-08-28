import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback? onFileInfo;
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
  final bool showEditImageOption;
  final VoidCallback onEditImage;
  final VoidCallback? onToggleDocumentProvider;
  final bool readOnly;
  final bool showPinOption;
  final bool showUnpinOption;
  final VoidCallback onPin;
  final VoidCallback onUnpin;
  final bool showBookmarkOption;
  final bool showUnbookmarkOption;
  final VoidCallback onBookmark;
  final VoidCallback onUnbookmark;
  final bool showEncryptOption;
  final bool showDecryptOption;
  final VoidCallback onEncrypt;
  final VoidCallback onDecrypt;

  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.selectionLabel,
    required this.singleSelected,
    required this.singleFileSelected,
    this.singleFolderSelected = false,
    this.folderDocumentProviderMounted = false,
    this.onFileInfo,
    required this.onClose,
    required this.onSelectAll,
    required this.onRename,
    required this.onCopy,
    required this.onCut,
    required this.onExport,
    required this.onDelete,
    required this.onOpenWithApp,
    this.showEditImageOption = false,
    required this.onEditImage,
    this.onToggleDocumentProvider,
    this.readOnly = false,
    required this.showPinOption,
    required this.showUnpinOption,
    required this.onPin,
    required this.onUnpin,
    required this.showBookmarkOption,
    required this.showUnbookmarkOption,
    required this.onBookmark,
    required this.onUnbookmark,
    required this.showEncryptOption,
    required this.showDecryptOption,
    required this.onEncrypt,
    required this.onDecrypt,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double barWidth = constraints.maxWidth;

        // ── Dynamic Slot Calculation ─────────────────────────────────────────
        // Constants matching AppBar layout dimensions:
        const double leadingWidth = 40.0;      // Leading close button slot
        const double deleteBtnWidth = 48.0;     // Delete button
        const double overflowBtnWidth = 48.0;   // More options (overflow) button
        const double endPadding = 4.0;          // Trailing spacing
        const double minTitleWidth = 100.0;     // Reserved space for count + label + arrow
        const double actionButtonWidth = 48.0;  // Standard touch target per action

        const double fixedOverhead = leadingWidth +
            deleteBtnWidth +
            overflowBtnWidth +
            endPadding +
            minTitleWidth;

        final double availableWidth = barWidth - fixedOverhead;

        // Calculate how many optional buttons fit (0 to 3)
        final int availableSlots = (availableWidth / actionButtonWidth).floor().clamp(0, 3);

        // Priority order: 1st Copy, 2nd Cut, 3rd Rename
        final bool showCopy = availableSlots >= 1;
        final bool showCut = availableSlots >= 2;
        final bool showRename = availableSlots >= 3;

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
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$selectedCount',
                          style: textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          selectionLabel,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.normal,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: cs.onSurfaceVariant,
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
                if (value == 'bookmark') onBookmark();
                if (value == 'unbookmark') onUnbookmark();
                if (value == 'edit_image') onEditImage();
                if (value == 'open_with_app') onOpenWithApp();
                if (value == 'doc_provider') onToggleDocumentProvider?.call();
                if (value == 'encrypt') onEncrypt();
                if (value == 'decrypt') onDecrypt();
                if (value == 'file_info') onFileInfo?.call();
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
                if (showEncryptOption)
                  PopupMenuItem<String>(
                    value: 'encrypt',
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          color: cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.cryptoDirectionEncrypt),
                      ],
                    ),
                  ),
                if (showDecryptOption)
                  PopupMenuItem<String>(
                    value: 'decrypt',
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_open_rounded,
                          color: cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.cryptoDirectionDecrypt),
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
                if (showBookmarkOption)
                  PopupMenuItem<String>(
                    value: 'bookmark',
                    child: Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: context.semanticColors.bookmark,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(selectedCount > 1 ? context.l10n.bookmarkSelectedAction : context.l10n.bookmarkAction),
                      ],
                    ),
                  ),
                if (showUnbookmarkOption)
                  PopupMenuItem<String>(
                    value: 'unbookmark',
                    child: Row(
                      children: [
                        Icon(
                          Icons.star_outline_rounded,
                          color: cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(selectedCount > 1 ? context.l10n.unbookmarkSelectedAction : context.l10n.unbookmarkAction),
                      ],
                    ),
                  ),
                if (singleSelected)
                  PopupMenuItem<String>(
                    value: 'file_info',
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.fileInfoAction),
                      ],
                    ),
                  ),
                if (showEditImageOption)
                  PopupMenuItem<String>(
                    value: 'edit_image',
                    enabled: !readOnly,
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          context.l10n.editImageAction,
                          style: readOnly
                              ? TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.4))
                              : null,
                        ),
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
      },
    );
  }
}