import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/adaptive_action_strip.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/features/browser/widgets/item_action_menu_config.dart';

class SelectionAppBarWide extends StatelessWidget implements PreferredSizeWidget {
  final double toolbarHeight;
  final bool desktopCompact;
  final int selectedCount;
  final String selectionLabel;
  final bool singleFileSelected;
  final bool singleFolderSelected;
  final bool singleArchiveSelected;
  final bool folderDocumentProviderMounted;
  final bool hideVaultOnlyActions;
  final bool isInsideArchive;
  final bool readOnly;
  final bool showPinOption;
  final bool showUnpinOption;
  final bool showBookmarkOption;
  final bool showUnbookmarkOption;
  final bool showEncryptOption;
  final bool showDecryptOption;
  final bool showActionBar;
  final List<FileManagerAction> visibleActions;
  final Map<FileManagerAction, WidgetBuilder> actionBuilders;

  /// The overflow-menu form of each toolbar action, used when the bar is too
  /// narrow to show them inline. An action without one stays pinned inline.
  final Map<FileManagerAction, Widget? Function(BuildContext)>
  actionMenuEntries;

  /// Rebuilds the bar's overflow menu entries when it changes (music mode).
  final Listenable? actionsRebuildOn;
  final VoidCallback? onFileInfo;

  /// Opens the edit tags / date & time / remove metadata menu. Null hides it.
  final VoidCallback? onEditMetadata;

  /// Set only for a single selected item while a search is showing: offers
  /// "Go to location", which leaves the search and shows the item in the
  /// folder it lives in.
  final VoidCallback? onGoToLocation;

  /// Copies the single selected item's path to the clipboard.
  final VoidCallback? onCopyPath;

  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onRename;
  final bool allowRenameAction;
  final VoidCallback onCopy;
  final VoidCallback onCut;

   /// Desktop compact bar only: a paste button drawn right after copy. It
  /// handles its own enabled state (it works with nothing selected).
  final Widget? pasteAction;

  /// Desktop compact bar only: overflow-menu form of [pasteAction] so Paste
  /// can collapse into the overflow menu when the bar is narrow and idle.
  final Widget? Function(BuildContext)? pasteMenuBuilder;

  /// Desktop compact bar only: whether [pasteAction] currently has pasteable
  /// content and can run. Controls its collapse priority.
  final bool pasteActive;

  /// Desktop compact bar only: whether anything is selected. The selection
  /// buttons dim and ignore taps while it is false; [pasteAction] does not.
  final bool selectionActive;

  /// Set only for a single selected folder while the file manager is in tabs.
  final VoidCallback? onOpenInNewTab;
  final VoidCallback? onOpenInNewWindow;
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
  final VoidCallback onToggleDocumentProvider;
  final VoidCallback? onSyncSettings;
  final VoidCallback onPin;
  final VoidCallback onUnpin;
  final VoidCallback onBookmark;
  final VoidCallback onUnbookmark;
  final VoidCallback onEncrypt;
  final VoidCallback onDecrypt;

  /// The user's item-action configuration. Buttons prioritize quick actions,
  /// and overflow puts quick actions before the rest of the configured order.
  final List<FileItemAction> itemActionOrder;
  final Set<FileItemAction> quickItemActions;
  final Set<FileItemAction> hiddenItemActions;

  const SelectionAppBarWide({
    super.key,
    this.toolbarHeight = kToolbarHeight,
    this.desktopCompact = false,
    required this.selectedCount,
    required this.selectionLabel,
    required this.singleFileSelected,
    required this.singleFolderSelected,
    required this.singleArchiveSelected,
    required this.folderDocumentProviderMounted,
    this.hideVaultOnlyActions = false,
    this.isInsideArchive = false,
    this.onFileInfo,
    this.onEditMetadata,
    this.onGoToLocation,
    this.onCopyPath,
    required this.readOnly,
    required this.showPinOption,
    required this.showUnpinOption,
    required this.showBookmarkOption,
    required this.showUnbookmarkOption,
    required this.showEncryptOption,
    required this.showDecryptOption,
    required this.showActionBar,
    required this.visibleActions,
    required this.actionBuilders,
    this.actionMenuEntries = const {},
    this.actionsRebuildOn,
    required this.onClose,
    required this.onSelectAll,
    required this.onRename,
    this.allowRenameAction = true,
    required this.onCopy,
    required this.onCut,
  this.pasteAction,
    this.pasteMenuBuilder,
    this.pasteActive = false,
    this.selectionActive = true,
    this.onOpenInNewTab,
    this.onOpenInNewWindow,
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
    required this.onToggleDocumentProvider,
    this.onSyncSettings,
    required this.onPin,
    required this.onUnpin,
    required this.onBookmark,
    required this.onUnbookmark,
    required this.onEncrypt,
    required this.onDecrypt,
    this.itemActionOrder = FileItemAction.values,
    this.quickItemActions = FileItemAction.defaultQuickActions,
    this.hiddenItemActions = const {},
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    bool shown(FileItemAction action) => !hiddenItemActions.contains(action);
    final bool showExtractButton =
        allowExtractAction &&
        (singleArchiveSelected || isInsideArchive) &&
        shown(FileItemAction.extract);
    final visibleActionOrder = orderFileItemActions(
      [
        if (showExtractButton) FileItemAction.extract,
        if (showShareOption && shown(FileItemAction.share))
          FileItemAction.share,
        if (!isInsideArchive && shown(FileItemAction.copy))
          FileItemAction.copy,
        if (!isInsideArchive && shown(FileItemAction.move))
          FileItemAction.move,
        if (!isInsideArchive &&
            allowRenameAction &&
            shown(FileItemAction.rename))
          FileItemAction.rename,
        if (!isInsideArchive && shown(FileItemAction.delete))
          FileItemAction.delete,
      ],
      order: itemActionOrder,
      quickActions: quickItemActions,
    );

    ({IconData icon, String label, VoidCallback? callback, Color? color})
    describeAction(FileItemAction action, {required bool enabled}) {
      final l10n = context.l10n;
      final muted = cs.onSurfaceVariant.withValues(alpha: 0.5);
      return switch (action) {
        FileItemAction.goToLocation => (
          icon: Icons.folder_open_rounded,
          label: l10n.goToLocationAction,
          callback: onGoToLocation,
          color: null,
        ),
        FileItemAction.openInNewTab => (
          icon: Icons.tab_rounded,
          label: l10n.browserTabOpenInNewTab,
          callback: onOpenInNewTab,
          color: null,
        ),
        FileItemAction.openInNewWindow => (
          icon: Icons.launch_rounded,
          label: l10n.browserTabOpenInNewWindow,
          callback: onOpenInNewWindow,
          color: null,
        ),
        FileItemAction.extract => (
          icon: Icons.unarchive_outlined,
          label: l10n.extract,
          callback: onExtractSelectedArchive,
          color: null,
        ),
        FileItemAction.openWith => (
          icon: Icons.open_in_new_rounded,
          label: l10n.openWithAppAction,
          callback: onOpenWithApp,
          color: null,
        ),
        FileItemAction.share => (
          icon: Icons.share_rounded,
          label: l10n.shareAction,
          callback: onShare,
          color: null,
        ),
        FileItemAction.editImage => (
          icon: Icons.edit_outlined,
          label: l10n.editImageAction,
          callback: onEditImage,
          color: readOnly ? muted : null,
        ),
        FileItemAction.editVideo => (
          icon: Icons.content_cut_rounded,
          label: l10n.videoEditorEditAction,
          callback: onEditVideo,
          color: readOnly ? muted : null,
        ),
        FileItemAction.editAudio => (
          icon: Icons.graphic_eq_rounded,
          label: l10n.audioEditorEditAction,
          callback: onEditAudio,
          color: readOnly ? muted : null,
        ),
        FileItemAction.editMetadata => (
          icon: Icons.sell_outlined,
          label: l10n.editMetadataAction,
          callback: onEditMetadata,
          color: readOnly ? muted : null,
        ),
        FileItemAction.rename => (
          icon: Icons.drive_file_rename_outline_rounded,
          label: readOnly
              ? l10n.readOnlyCantRenameTooltip
              : l10n.renameTooltip,
          callback: onRename,
          color: readOnly ? muted : null,
        ),
        FileItemAction.copy => (
          icon: Icons.copy_rounded,
          label: l10n.copyTooltip,
          callback: onCopy,
          color: null,
        ),
        FileItemAction.move => (
          icon: Icons.cut_rounded,
          label: readOnly ? l10n.readOnlyCantMoveTooltip : l10n.moveAction,
          callback: onCut,
          color: readOnly ? muted : null,
        ),
        FileItemAction.archive => (
          icon: Icons.folder_zip_outlined,
          label: l10n.archiveSelectionAction,
          callback: onCompressSelection,
          color: readOnly ? muted : null,
        ),
        FileItemAction.exportToDevice => (
          icon: Icons.drive_folder_upload_rounded,
          label: l10n.exportToDeviceAction,
          callback: onExport,
          color: null,
        ),
        FileItemAction.encrypt => (
          icon: Icons.lock_outline_rounded,
          label: l10n.cryptoDirectionEncrypt,
          callback: onEncrypt,
          color: null,
        ),
        FileItemAction.decrypt => (
          icon: Icons.lock_open_rounded,
          label: l10n.cryptoDirectionDecrypt,
          callback: onDecrypt,
          color: null,
        ),
        FileItemAction.docProvider => (
          icon: folderDocumentProviderMounted
              ? Icons.folder_shared_rounded
              : Icons.folder_shared_outlined,
          label: folderDocumentProviderMounted
              ? l10n.documentProviderSettingsMenu
              : l10n.exposeAsDocumentProviderMenu,
          callback: onToggleDocumentProvider,
          color: folderDocumentProviderMounted ? cs.tertiary : null,
        ),
        FileItemAction.syncSettings => (
          icon: Icons.sync_rounded,
          label: l10n.autoSyncMenuAction,
          callback: onSyncSettings,
          color: null,
        ),
        FileItemAction.pin => (!showPinOption && showUnpinOption)
            ? (
                icon: Icons.push_pin_outlined,
                label: selectedCount > 1
                    ? l10n.unpinSelectedAction
                    : l10n.unpinAction,
                callback: onUnpin,
                color: null,
              )
            : (
                icon: Icons.push_pin_rounded,
                label: selectedCount > 1
                    ? l10n.pinSelectedAction
                    : l10n.pinAction,
                callback: onPin,
                color: enabled && showPinOption ? cs.primary : null,
              ),
        FileItemAction.bookmark => (!showBookmarkOption && showUnbookmarkOption)
            ? (
                icon: Icons.star_outline_rounded,
                label: selectedCount > 1
                    ? l10n.unbookmarkSelectedAction
                    : l10n.unbookmarkAction,
                callback: onUnbookmark,
                color: null,
              )
            : (
                icon: Icons.star_rounded,
                label: selectedCount > 1
                    ? l10n.bookmarkSelectedAction
                    : l10n.bookmarkAction,
                callback: onBookmark,
                color: enabled && showBookmarkOption
                    ? context.semanticColors.bookmark
                    : null,
              ),
        FileItemAction.copyPath => (
          icon: Icons.link_rounded,
          label: l10n.copyPathAction,
          callback: onCopyPath,
          color: null,
        ),
        FileItemAction.delete => (
          icon: Icons.delete_outline_rounded,
          label: readOnly ? l10n.readOnlyCantDeleteTooltip : l10n.delete,
          callback: onDelete,
          color: readOnly ? muted : cs.error,
        ),
        FileItemAction.info => (
          icon: Icons.info_outline_rounded,
          label: l10n.fileInfoAction,
          callback: onFileInfo,
          color: null,
        ),
      };
    }

    Widget buildActionButton(FileItemAction action, {bool enabled = true}) {
      final desc = describeAction(action, enabled: enabled);
      return IconButton(
        icon: Icon(desc.icon, color: enabled ? desc.color : null),
        tooltip: desc.label,
        onPressed: enabled ? desc.callback : null,
      );
    }

    // The same action as an overflow-menu entry, for when the bar is too
    // narrow to show every button or inside the desktop "More item actions"
    // menu.
    Widget buildActionMenuItem(FileItemAction action, {bool enabled = true}) {
      final desc = describeAction(action, enabled: enabled);
      return MenuItemButton(
        leadingIcon: Icon(desc.icon, color: enabled ? desc.color : null),
        onPressed: enabled ? desc.callback : null,
        child: Text(desc.label),
      );
    }

    if (desktopCompact) {
      bool desktopInlineVisible(FileItemAction action) {
        if (!shown(action)) return false;
        if (hideVaultOnlyActions &&
            (action == FileItemAction.exportToDevice ||
                action == FileItemAction.docProvider ||
                action == FileItemAction.syncSettings)) {
          return false;
        }
        return true;
      }

      // At untouched defaults, show Cut / Copy / Paste / Rename / Delete /
      // Share inline. Once the user customizes Quick actions or Menu list in
      // settings, inline buttons follow their Quick actions row exactly
      // (supporting all 24 FileItemActions), and every remaining applicable
      // action lives in the adjacent "More item actions" menu.
      final bool isUntouchedDefaults =
          listEquals(itemActionOrder, FileItemAction.values) &&
          setEquals(quickItemActions, FileItemAction.defaultQuickActions);
      final List<FileItemAction> compactOrder;
      if (isUntouchedDefaults) {
        const desktopDefaultQuick = [
          FileItemAction.move,
          FileItemAction.copy,
          FileItemAction.rename,
          FileItemAction.delete,
          FileItemAction.share,
        ];
        compactOrder = [
          for (final action in desktopDefaultQuick)
            if (desktopInlineVisible(action)) action,
        ];
      } else {
        compactOrder = [
          for (final action in itemActionOrder)
            if (quickItemActions.contains(action) &&
                desktopInlineVisible(action))
              action,
          for (final action in quickItemActions)
            if (!itemActionOrder.contains(action) &&
                desktopInlineVisible(action))
              action,
        ];
      }
      final inlineActionSet = compactOrder.toSet();

      bool compactVisibleInMoreMenu(FileItemAction action) => switch (action) {
        FileItemAction.goToLocation => selectionActive && onGoToLocation != null,
        FileItemAction.openInNewTab => selectionActive && onOpenInNewTab != null,
        FileItemAction.openInNewWindow =>
          selectionActive && onOpenInNewWindow != null,
        FileItemAction.extract =>
          selectionActive &&
              allowExtractAction &&
              (singleArchiveSelected || isInsideArchive),
        FileItemAction.openWith => selectionActive && singleFileSelected,
        FileItemAction.share => selectionActive && showShareOption,
        FileItemAction.editImage =>
          selectionActive && !isInsideArchive && showEditImageOption,
        FileItemAction.editVideo =>
          selectionActive && !isInsideArchive && showEditVideoOption,
        FileItemAction.editAudio =>
          selectionActive &&
              !isInsideArchive &&
              showEditAudioOption &&
              onEditAudio != null,
        FileItemAction.editMetadata =>
          selectionActive && !isInsideArchive && onEditMetadata != null,
        FileItemAction.rename =>
          selectionActive && !isInsideArchive && allowRenameAction,
        FileItemAction.copy => selectionActive && !isInsideArchive,
        FileItemAction.move => selectionActive && !isInsideArchive,
        FileItemAction.archive =>
          selectionActive && !isInsideArchive && allowCompressAction,
        FileItemAction.exportToDevice =>
          selectionActive &&
              allowExportAction &&
              !hideVaultOnlyActions &&
              !isInsideArchive,
        FileItemAction.encrypt =>
          selectionActive && !isInsideArchive && showEncryptOption,
        FileItemAction.decrypt =>
          selectionActive && !isInsideArchive && showDecryptOption,
        FileItemAction.docProvider =>
          selectionActive &&
              !isInsideArchive &&
              singleFolderSelected &&
              !hideVaultOnlyActions,
        FileItemAction.syncSettings =>
          selectionActive &&
              !isInsideArchive &&
              singleFolderSelected &&
              !hideVaultOnlyActions &&
              onSyncSettings != null,
        FileItemAction.pin =>
          selectionActive &&
              !isInsideArchive &&
              (showPinOption || showUnpinOption),
        FileItemAction.bookmark =>
          selectionActive &&
              !isInsideArchive &&
              (showBookmarkOption || showUnbookmarkOption),
        FileItemAction.copyPath => selectionActive && onCopyPath != null,
        FileItemAction.delete => selectionActive && !isInsideArchive,
        FileItemAction.info =>
          selectionActive &&
              !isInsideArchive &&
              (singleFileSelected || singleFolderSelected) &&
              onFileInfo != null,
      };

      bool compactEnabled(FileItemAction action) {
        if (!compactVisibleInMoreMenu(action)) return false;
        if (readOnly &&
            (action == FileItemAction.editImage ||
                action == FileItemAction.editVideo ||
                action == FileItemAction.editAudio ||
                action == FileItemAction.editMetadata ||
                action == FileItemAction.archive)) {
          return false;
        }
        return true;
      }

      List<Widget> buildDesktopMoreMenuChildren() {
        final orderedMenuActions = [
          for (final action in itemActionOrder)
            if (!inlineActionSet.contains(action) &&
                shown(action) &&
                compactVisibleInMoreMenu(action))
              action,
          for (final action in FileItemAction.values)
            if (!itemActionOrder.contains(action) &&
                !inlineActionSet.contains(action) &&
                shown(action) &&
                compactVisibleInMoreMenu(action))
              action,
        ];
        return [
          MenuItemButton(
            leadingIcon: const Icon(Icons.select_all_rounded),
            onPressed: onSelectAll,
            child: Text(context.l10n.selectAllAction),
          ),
          if (orderedMenuActions.isNotEmpty) const Divider(height: 1),
          for (final action in orderedMenuActions)
            buildActionMenuItem(action, enabled: compactEnabled(action)),
        ];
      }

      int compactActionPriority(FileItemAction action) {
        if (!selectionActive) return 1;
        return switch (action) {
          FileItemAction.copy ||
          FileItemAction.move ||
          FileItemAction.delete ||
          FileItemAction.rename => 4,
          FileItemAction.extract =>
            (allowExtractAction && (singleArchiveSelected || isInsideArchive))
                ? 4
                : 2,
          FileItemAction.share => 2,
          _ => 3,
        };
      }

      int toolbarActionPriority(FileManagerAction action) {
        return switch (action) {
          FileManagerAction.viewToggle ||
          FileManagerAction.sort ||
          FileManagerAction.filter ||
          FileManagerAction.options => selectionActive ? 3 : 4,
          FileManagerAction.gallery ||
          FileManagerAction.musicMode ||
          FileManagerAction.playMedia => selectionActive ? 1 : 3,
          FileManagerAction.search => selectionActive ? 1 : 2,
          FileManagerAction.add => 5,
        };
      }

      final hasAddAction =
          showActionBar &&
          visibleActions.contains(FileManagerAction.add) &&
          actionBuilders.containsKey(FileManagerAction.add);
      final otherToolbarActions = showActionBar
          ? [
              for (final action in visibleActions)
                if (action != FileManagerAction.add &&
                    actionBuilders.containsKey(action))
                  action,
            ]
          : const <FileManagerAction>[];

      // One unified adaptive strip on desktop: Add (pinned), the user's Quick
      // actions (plus steady Paste, which collapses first when empty), a
      // "More item actions" menu (Select All + all remaining Menu list actions),
      // and folder view/mode controls.
      final compactItems = <AdaptiveActionItem>[
        if (hasAddAction) ...[
          AdaptiveActionItem(
            id: FileManagerAction.add,
            builder: actionBuilders[FileManagerAction.add]!,
          ),
          const AdaptiveActionItem.separator(id: 'add-separator'),
        ],
        if (pasteAction != null && !compactOrder.contains(FileItemAction.copy))
          AdaptiveActionItem(
            id: 'paste',
            builder: (_) => pasteAction!,
            menuBuilder: pasteMenuBuilder,
            priority: pasteActive ? 4 : 0,
          ),
        for (final action in compactOrder) ...[
          AdaptiveActionItem(
            id: action,
            builder: (_) =>
                buildActionButton(action, enabled: compactEnabled(action)),
            menuBuilder: (_) =>
                buildActionMenuItem(action, enabled: compactEnabled(action)),
            priority: compactActionPriority(action),
          ),
          if (action == FileItemAction.copy && pasteAction != null)
            AdaptiveActionItem(
              id: 'paste',
              builder: (_) => pasteAction!,
              menuBuilder: pasteMenuBuilder,
              priority: pasteActive ? 4 : 0,
            ),
        ],
        AdaptiveActionItem(
          id: 'selection-more',
          priority: selectionActive ? 3 : 0,
          builder: (_) => BackDismissibleMenuAnchor(
            menuChildren: buildDesktopMoreMenuChildren(),
            builder: (ctx, controller, _) => IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: ctx.l10n.moreOptionsTooltip,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
          menuBuilder: (ctx) => SubmenuButton(
            leadingIcon: const Icon(Icons.more_vert_rounded),
            menuChildren: buildDesktopMoreMenuChildren(),
            child: Text(ctx.l10n.moreOptionsTooltip),
          ),
        ),
        if (otherToolbarActions.isNotEmpty) ...[
          const AdaptiveActionItem.separator(id: 'toolbar-separator'),
          for (final action in otherToolbarActions)
            AdaptiveActionItem(
              id: action,
              builder: actionBuilders[action]!,
              menuBuilder: actionMenuEntries[action],
              priority: toolbarActionPriority(action),
            ),
        ],
      ];
      return Material(
        color: cs.surfaceContainer,
        child: SizedBox(
          height: toolbarHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AdaptiveActionStrip(
              itemExtent: 40,
              rebuildOn: actionsRebuildOn,
              items: compactItems,
            ),
          ),
        ),
      );
    }
    final Widget selectionMoreMenu = PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: context.l10n.moreOptionsTooltip,
          onSelected: (value) {
            if (value == 'select_all') onSelectAll();
            if (value == 'share') onShare();
            if (value == 'open_in_new_tab') onOpenInNewTab?.call();
            if (value == 'open_in_new_window') onOpenInNewWindow?.call();
            if (value == 'open_with_app') onOpenWithApp();
            if (value == 'edit_image') onEditImage();
            if (value == 'edit_video') onEditVideo();
            if (value == 'edit_audio') onEditAudio?.call();
            if (value == 'compress') onCompressSelection();
            if (value == 'export') onExport();
            if (value == 'encrypt') onEncrypt();
            if (value == 'decrypt') onDecrypt();
            if (value == 'doc_provider') onToggleDocumentProvider();
            if (value == 'sync_settings') onSyncSettings?.call();
            if (value == 'pin') onPin();
            if (value == 'unpin') onUnpin();
            if (value == 'bookmark') onBookmark();
            if (value == 'unbookmark') onUnbookmark();
            if (value == 'go_to_location') onGoToLocation?.call();
            if (value == 'copy_path') onCopyPath?.call();
            if (value == 'file_info') onFileInfo?.call();
                if (value == 'edit_metadata') onEditMetadata?.call();
          },
          itemBuilder: (context) => applyItemActionMenuConfig(
            [
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
            if (onOpenInNewWindow != null)
              PopupMenuItem<String>(
                value: 'open_in_new_window',
                child: Row(
                  children: [
                    Icon(Icons.launch_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                    const SizedBox(width: 12),
                    Text(context.l10n.browserTabOpenInNewWindow),
                  ],
                ),
              ),
            // 1. Selection Utility
            PopupMenuItem<String>(
              value: 'select_all',
              child: Row(
                children: [
                  Icon(Icons.select_all_rounded, color: cs.onSurfaceVariant, size: AppIconSize.small),
                  const SizedBox(width: 12),
                  Text(context.l10n.selectAllAction),
                ],
              ),
            ),

            // 2. Consumption / External Actions
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

            // 3. Core Archive Operations
            if (!isInsideArchive && allowCompressAction)
              PopupMenuItem<String>(
                value: 'compress',
                enabled: !readOnly,
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_zip_outlined,
                      color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    Text(context.l10n.archiveSelectionAction),
                  ],
                ),
              ),

            // 4. Vault & System Integrations
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

            // 5. Bookmarks & Shortcuts
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

            // 6. Location + Properties / Info (Always at the bottom)
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
            if (!isInsideArchive && onEditMetadata != null)
              PopupMenuItem<String>(
                value: 'edit_metadata',
                enabled: !readOnly,
                child: Row(
                  children: [
                    Icon(Icons.sell_outlined, color: cs.onSurfaceVariant, size: AppIconSize.small),
                    const SizedBox(width: 12),
                    Text(context.l10n.editMetadataAction),
                  ],
                ),
              ),
            if (!isInsideArchive && (singleFileSelected || singleFolderSelected))
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
            order: quickActionsFirstOrder(
              itemActionOrder,
              quickItemActions,
            ),
            hidden: hiddenItemActions,
          ),
        );

    // An AppBar lays its actions out with unbounded width, so the bar's own
    // width is measured here and the actions are given what the leading
    // button and the title leave.
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final stripBudget = appBarActionsBudget(
          barWidth: barWidth,
          hasLeading: true,
          minTitleWidth: 120,
          otherActionsWidth: 4,
        );
        return AppBar(
          toolbarHeight: toolbarHeight,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: context.l10n.clearSelectionTooltip,
            onPressed: onClose,
          ),
          titleSpacing: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.full),
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
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ),
          actions: [
            AdaptiveActionStrip(
              availableWidth: stripBudget,
              rebuildOn: actionsRebuildOn,
              items: [
                // The selection's own actions come first and collapse last; the
                // general toolbar actions give way to them.
                for (final action in visibleActionOrder)
                  AdaptiveActionItem(
                    id: action,
                    builder: (_) => buildActionButton(action),
                    menuBuilder: (_) => buildActionMenuItem(action),
                    priority: 2,
                  ),
                AdaptiveActionItem(
                  id: 'selection-more',
                  builder: (_) => selectionMoreMenu,
                ),
                if (showActionBar &&
                    visibleActions.any(actionBuilders.containsKey)) ...[
                  const AdaptiveActionItem.separator(id: 'toolbar-separator'),
                  for (final action in visibleActions)
                    if (actionBuilders.containsKey(action))
                      AdaptiveActionItem(
                        id: action,
                        builder: actionBuilders[action]!,
                        menuBuilder: actionMenuEntries[action],
                        priority: 1,
                      ),
                ],
              ],
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}
