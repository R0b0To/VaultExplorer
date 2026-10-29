import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/features/browser/widgets/item_action_menu_config.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback? onFileInfo;

  /// Set only for a single selected item while a search is showing: offers
  /// "Go to location", which leaves the search and shows the item in the
  /// folder it lives in.
  final VoidCallback? onGoToLocation;

  /// Copies the single selected item's path to the clipboard.
  final VoidCallback? onCopyPath;
  final String selectionLabel;
  final bool singleSelected;
  final bool singleFileSelected;
  final bool singleFolderSelected;
  final bool singleArchiveSelected;
  final bool folderDocumentProviderMounted;
  final bool hideVaultOnlyActions;
  final bool isInsideArchive;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onRename;
  final bool allowRenameAction;
  final VoidCallback onCopy;
  final VoidCallback onCut;

  /// Set only for a single selected folder while the file manager is in tabs.
  final VoidCallback? onOpenInNewTab;
  final VoidCallback onExport;
  final bool allowExportAction;
  final bool allowExtractAction;
  final VoidCallback onCompressSelection;
  final bool allowCompressAction;
  final VoidCallback onExtractSelectedArchive;
  final VoidCallback onDelete;
  final VoidCallback onOpenWithApp;
  final bool showShareOption;
  final VoidCallback onShare;
  final bool showEditImageOption;
  final VoidCallback onEditImage;
  final bool showEditVideoOption;
  final VoidCallback onEditVideo;
  final bool showEditAudioOption;
  final VoidCallback? onEditAudio;
  final VoidCallback? onToggleDocumentProvider;
  final VoidCallback? onSyncSettings;
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

  /// The user's item-action configuration: hidden actions are removed from
  /// the buttons and the overflow menu, and the menu follows this order.
  final List<FileItemAction> itemActionOrder;
  final Set<FileItemAction> hiddenItemActions;

  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.selectionLabel,
    required this.singleSelected,
    required this.singleFileSelected,
    this.singleFolderSelected = false,
    this.singleArchiveSelected = false,
    this.folderDocumentProviderMounted = false,
    this.hideVaultOnlyActions = false,
    this.isInsideArchive = false,
    this.onFileInfo,
    this.onGoToLocation,
    this.onCopyPath,
    required this.onClose,
    required this.onSelectAll,
    required this.onRename,
    this.allowRenameAction = true,
    required this.onCopy,
    required this.onCut,
    this.onOpenInNewTab,
    required this.onExport,
    this.allowExportAction = true,
    this.allowExtractAction = true,
    required this.onCompressSelection,
    this.allowCompressAction = true,
    required this.onExtractSelectedArchive,
    required this.onDelete,
    required this.onOpenWithApp,
    this.showShareOption = false,
    required this.onShare,
    this.showEditImageOption = false,
    required this.onEditImage,
    this.showEditVideoOption = false,
    required this.onEditVideo,
    this.showEditAudioOption = false,
    this.onEditAudio,
    this.onToggleDocumentProvider,
    this.onSyncSettings,
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
    this.itemActionOrder = FileItemAction.values,
    this.hiddenItemActions = const {},
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    bool shown(FileItemAction action) => !hiddenItemActions.contains(action);
    final bool showExtractButton =
        allowExtractAction &&
        (singleArchiveSelected || isInsideArchive) &&
        shown(FileItemAction.extract);
    final bool showShareButton =
        showShareOption && shown(FileItemAction.share);
    final bool showDeleteButton =
        !isInsideArchive && shown(FileItemAction.delete);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double barWidth = constraints.maxWidth;

        const double leadingWidth = 40.0;
        final double deleteBtnWidth = showDeleteButton ? 48.0 : 0.0;
        final double extractBtnWidth = showExtractButton ? 48.0 : 0.0;
        const double overflowBtnWidth = 48.0;
        const double endPadding = 4.0;
        const double minTitleWidth = 100.0;
        const double actionButtonWidth = 48.0;

        final double shareBtnWidth = showShareButton ? 48.0 : 0.0;

        final double fixedOverhead = leadingWidth +
            deleteBtnWidth +
            shareBtnWidth +
            extractBtnWidth +
            overflowBtnWidth +
            endPadding +
            minTitleWidth;

        final double availableWidth = barWidth - fixedOverhead;
        final int availableSlots = (availableWidth / actionButtonWidth).floor().clamp(0, 3);

        // Copy, move and rename take the free slots in that order; an action
        // the user hid does not use one up, so the next one moves into it.
        var freeSlots = availableSlots;
        bool takeSlot(bool wanted) {
          if (!wanted || freeSlots <= 0) return false;
          freeSlots--;
          return true;
        }

        final bool showCopy =
            takeSlot(!isInsideArchive && shown(FileItemAction.copy));
        final bool showCut =
            takeSlot(!isInsideArchive && shown(FileItemAction.move));
        final bool showRename = takeSlot(
          !isInsideArchive &&
              allowRenameAction &&
              shown(FileItemAction.rename),
        );

          return AppBar(
          backgroundColor: cs.surfaceContainer,
          foregroundColor: cs.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: Theme.of(context).brightness,
          ),
      
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
            if (showExtractButton)
              IconButton(
                icon: const Icon(Icons.unarchive_outlined),
                tooltip: context.l10n.extract,
                onPressed: onExtractSelectedArchive,
              ),
            if (showShareButton)
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: context.l10n.shareAction,
                onPressed: onShare,
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
            if (showDeleteButton)
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.error,
                ),
                tooltip: readOnly ? context.l10n.readOnlyContainerTooltip : context.l10n.delete,
                onPressed: readOnly ? null : onDelete,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: context.l10n.moreOptionsTooltip,
              onSelected: (value) {
                if (value == 'open_in_new_tab') onOpenInNewTab?.call();
                if (value == 'open_with_app') onOpenWithApp();
                if (value == 'edit_image') onEditImage();
                if (value == 'edit_video') onEditVideo();
                if (value == 'edit_audio') onEditAudio?.call();
                if (value == 'rename') onRename();
                if (value == 'copy') onCopy();
                if (value == 'cut') onCut();
                if (value == 'compress') onCompressSelection();
                if (value == 'export') onExport();
                if (value == 'encrypt') onEncrypt();
                if (value == 'decrypt') onDecrypt();
                if (value == 'doc_provider') onToggleDocumentProvider?.call();
                if (value == 'sync_settings') onSyncSettings?.call();
                if (value == 'pin') onPin();
                if (value == 'unpin') onUnpin();
                if (value == 'bookmark') onBookmark();
                if (value == 'unbookmark') onUnbookmark();
                if (value == 'go_to_location') onGoToLocation?.call();
                if (value == 'copy_path') onCopyPath?.call();
                if (value == 'file_info') onFileInfo?.call();
              },
              itemBuilder: (context) => applyItemActionMenuConfig(
                [
                // 1. Consumption
                if (onOpenInNewTab != null)
                  PopupMenuItem<String>(
                    value: 'open_in_new_tab',
                    child: Row(
                      children: [
                        Icon(Icons.tab_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.browserTabOpenInNewTab),
                      ],
                    ),
                  ),
                if (singleFileSelected)
                  PopupMenuItem<String>(
                    value: 'open_with_app',
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.openWithAppAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showEditImageOption)
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
                        Text(context.l10n.editImageAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showEditVideoOption)
                  PopupMenuItem<String>(
                    value: 'edit_video',
                    enabled: !readOnly,
                    child: Row(
                      children: [
                        Icon(
                          Icons.content_cut_rounded,
                          color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.videoEditorEditAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showEditAudioOption)
                  PopupMenuItem<String>(
                    value: 'edit_audio',
                    enabled: !readOnly,
                    child: Row(
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.audioEditorEditAction),
                      ],
                    ),
                  ),

                // 2. Core File Operations (if overflowed)
                if (!isInsideArchive && allowRenameAction && !showRename)
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
                if (!isInsideArchive && !showCopy)
                  PopupMenuItem<String>(
                    value: 'copy',
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.copyAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && !showCut)
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
                if (!isInsideArchive && allowCompressAction)
                  PopupMenuItem<String>(
                    value: 'compress',
                    enabled: !readOnly,
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_zip_outlined,
                          color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant,
                          size: AppIconSize.small,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.archiveSelectionAction),
                      ],
                    ),
                  ),

                // 3. Vault & Integrations
                if (allowExportAction &&
                    !hideVaultOnlyActions &&
                    !isInsideArchive)
                  PopupMenuItem<String>(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.drive_folder_upload_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.exportToDeviceAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showEncryptOption)
                  PopupMenuItem<String>(
                    value: 'encrypt',
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.cryptoDirectionEncrypt),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showDecryptOption)
                  PopupMenuItem<String>(
                    value: 'decrypt',
                    child: Row(
                      children: [
                        Icon(Icons.lock_open_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.cryptoDirectionDecrypt),
                      ],
                    ),
                  ),
                if (!isInsideArchive && singleFolderSelected && !hideVaultOnlyActions)
                  PopupMenuItem<String>(
                    value: 'doc_provider',
                    child: Row(
                      children: [
                        Icon(
                          folderDocumentProviderMounted ? Icons.folder_shared_rounded : Icons.folder_shared_outlined,
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
                if (!isInsideArchive && singleFolderSelected && !hideVaultOnlyActions)
                  PopupMenuItem<String>(
                    value: 'sync_settings',
                    child: Row(
                      children: [
                        Icon(Icons.sync_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.autoSyncMenuAction),
                      ],
                    ),
                  ),

                // 4. Bookmarks & Shortcuts
                if (!isInsideArchive && showPinOption)
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_rounded, color: cs.primary, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(selectedCount > 1 ? context.l10n.pinSelectedAction : context.l10n.pinAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showUnpinOption)
                  PopupMenuItem<String>(
                    value: 'unpin',
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_outlined, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(selectedCount > 1 ? context.l10n.unpinSelectedAction : context.l10n.unpinAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showBookmarkOption)
                  PopupMenuItem<String>(
                    value: 'bookmark',
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, color: context.semanticColors.bookmark, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(selectedCount > 1 ? context.l10n.bookmarkSelectedAction : context.l10n.bookmarkAction),
                      ],
                    ),
                  ),
                if (!isInsideArchive && showUnbookmarkOption)
                  PopupMenuItem<String>(
                    value: 'unbookmark',
                    child: Row(
                      children: [
                        Icon(Icons.star_outline_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(selectedCount > 1 ? context.l10n.unbookmarkSelectedAction : context.l10n.unbookmarkAction),
                      ],
                    ),
                  ),

                // 5. Location + Properties / Info (Bottom Anchor)
                if (onGoToLocation != null)
                  PopupMenuItem<String>(
                    value: 'go_to_location',
                    child: Row(
                      children: [
                        Icon(Icons.folder_open_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.goToLocationAction),
                      ],
                    ),
                  ),
                if (onCopyPath != null)
                  PopupMenuItem<String>(
                    value: 'copy_path',
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.copyPathAction),
                      ],
                    ),
                  ),
                if (singleSelected)
                  PopupMenuItem<String>(
                    value: 'file_info',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                        const SizedBox(width: 12),
                        Text(context.l10n.fileInfoAction),
                      ],
                    ),
                  ),
                ],
                order: itemActionOrder,
                hidden: hiddenItemActions,
              ),
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}
