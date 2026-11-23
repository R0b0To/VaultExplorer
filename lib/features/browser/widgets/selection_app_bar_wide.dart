import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/adaptive_action_strip.dart';
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

    Widget buildActionButton(FileItemAction action, {bool enabled = true}) =>
        switch (action) {
      FileItemAction.extract => IconButton(
        icon: const Icon(Icons.unarchive_outlined),
        tooltip: context.l10n.extract,
        onPressed: enabled ? onExtractSelectedArchive : null,
      ),
      FileItemAction.share => IconButton(
        icon: const Icon(Icons.share_rounded),
        tooltip: context.l10n.shareAction,
        onPressed: enabled ? onShare : null,
      ),
      FileItemAction.copy => IconButton(
        icon: const Icon(Icons.copy_rounded),
        tooltip: context.l10n.copyTooltip,
        onPressed: enabled ? onCopy : null,
      ),
      FileItemAction.move => IconButton(
        icon: Icon(
          Icons.cut_rounded,
          color: enabled && readOnly
              ? cs.onSurfaceVariant.withValues(alpha: 0.5)
              : null,
        ),
        tooltip: readOnly ? context.l10n.readOnlyCantMoveTooltip : context.l10n.moveAction,
        onPressed: enabled ? onCut : null,
      ),
      FileItemAction.rename => IconButton(
        icon: Icon(
          Icons.drive_file_rename_outline_rounded,
          color: enabled && readOnly
              ? cs.onSurfaceVariant.withValues(alpha: 0.5)
              : null,
        ),
        tooltip: readOnly ? context.l10n.readOnlyCantRenameTooltip : context.l10n.renameTooltip,
        onPressed: enabled ? onRename : null,
      ),
      FileItemAction.delete => IconButton(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: !enabled
              ? null
              : readOnly
              ? cs.onSurfaceVariant.withValues(alpha: 0.5)
              : cs.error,
        ),
        tooltip: readOnly ? context.l10n.readOnlyCantDeleteTooltip : context.l10n.delete,
        onPressed: enabled ? onDelete : null,
      ),
      _ => throw StateError('Unexpected selection-bar action: $action'),
    };

    // The same action as an overflow-menu entry, for when the bar is too
    // narrow to show every button.
    Widget buildActionMenuItem(FileItemAction action, {bool enabled = true}) {
      final l10n = context.l10n;
      final IconData icon;
      final String label;
      final VoidCallback callback;
      Color? color;
      switch (action) {
        case FileItemAction.extract:
          icon = Icons.unarchive_outlined;
          label = l10n.extract;
          callback = onExtractSelectedArchive;
        case FileItemAction.share:
          icon = Icons.share_rounded;
          label = l10n.shareAction;
          callback = onShare;
        case FileItemAction.copy:
          icon = Icons.copy_rounded;
          label = l10n.copyTooltip;
          callback = onCopy;
        case FileItemAction.move:
          icon = Icons.cut_rounded;
          label = readOnly ? l10n.readOnlyCantMoveTooltip : l10n.moveAction;
          callback = onCut;
          if (readOnly) color = cs.onSurfaceVariant.withValues(alpha: 0.5);
        case FileItemAction.rename:
          icon = Icons.drive_file_rename_outline_rounded;
          label = readOnly
              ? l10n.readOnlyCantRenameTooltip
              : l10n.renameTooltip;
          callback = onRename;
          if (readOnly) color = cs.onSurfaceVariant.withValues(alpha: 0.5);
        case FileItemAction.delete:
          icon = Icons.delete_outline_rounded;
          label = readOnly ? l10n.readOnlyCantDeleteTooltip : l10n.delete;
          callback = onDelete;
          color = readOnly
              ? cs.onSurfaceVariant.withValues(alpha: 0.5)
              : cs.error;
        default:
          throw StateError('Unexpected selection-bar action: $action');
      }
      return MenuItemButton(
        leadingIcon: Icon(icon, color: enabled ? color : null),
        onPressed: enabled ? callback : null,
        child: Text(label),
      );
    }

    if (desktopCompact) {
      // The desktop bar never adds or removes buttons as the selection
      // changes: every action stays in place and the ones that do not apply
      // right now are greyed out.
      final compactOrder = orderFileItemActions(
        [
          if (shown(FileItemAction.extract)) FileItemAction.extract,
          if (shown(FileItemAction.share)) FileItemAction.share,
          if (shown(FileItemAction.copy)) FileItemAction.copy,
          if (shown(FileItemAction.move)) FileItemAction.move,
          if (shown(FileItemAction.rename)) FileItemAction.rename,
          if (shown(FileItemAction.delete)) FileItemAction.delete,
        ],
        order: itemActionOrder,
        quickActions: quickItemActions,
      );
      bool compactEnabled(FileItemAction action) => switch (action) {
        FileItemAction.extract =>
          selectionActive &&
              allowExtractAction &&
              (singleArchiveSelected || isInsideArchive),
        FileItemAction.share => selectionActive && showShareOption,
        FileItemAction.rename =>
          selectionActive && !isInsideArchive && allowRenameAction,
        _ => selectionActive && !isInsideArchive,
      };
      // Whatever does not fit the window moves into a "more" menu instead of
      // being clipped or only reachable by scrolling. Paste has no menu form,
      // so it stays inline.
      final compactItems = <AdaptiveActionItem>[
        if (pasteAction != null && !compactOrder.contains(FileItemAction.copy))
          AdaptiveActionItem(id: 'paste', builder: (_) => pasteAction!),
        for (final action in compactOrder) ...[
          AdaptiveActionItem(
            id: action,
            builder: (_) =>
                buildActionButton(action, enabled: compactEnabled(action)),
            menuBuilder: (_) =>
                buildActionMenuItem(action, enabled: compactEnabled(action)),
          ),
          if (action == FileItemAction.copy && pasteAction != null)
            AdaptiveActionItem(id: 'paste', builder: (_) => pasteAction!),
        ],
      ];
      return Material(
        color: cs.surfaceContainer,
        child: SizedBox(
          height: toolbarHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AdaptiveActionStrip(itemExtent: 40, items: compactItems),
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
