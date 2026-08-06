import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// Landscape-mode selection AppBar -- the wide-screen sibling of
/// [SelectionAppBar] (`selection_app_bar.dart`), which is used in portrait.
///
/// Extracted verbatim from `FileBrowserScreen`'s private `_buildAppBar`
/// (the `isLandscape` branch inside `if (isSelectionMode)`) -- fifth slice
/// of the `file_browser_screen.dart` decomposition (docs/tech-debt.md
/// TD-8). Unlike the four popup-button slices, this one was deliberately
/// read in full and designed before being touched, the same way TD-7 was:
/// it looked riskier at first glance (three local closures --
/// `onRename`/`onOpenWithApp`/`onToggleDocumentProvider` -- shared between
/// this branch and the portrait `SelectionAppBar` call), but those closures
/// turned out not to need moving or dissecting at all. They already get
/// passed into `SelectionAppBar` as plain `VoidCallback`s today; this
/// widget receives them the identical way. No behavior change, only a
/// location change.
///
/// This genuinely was an *unfinished* extraction, not just an unextracted
/// one: it duplicates most of what [SelectionAppBar] already covers, laid
/// out differently (a single AppBar row with an overflow menu, instead of
/// [SelectionAppBar]'s own layout) because landscape has less vertical
/// space to work with. Kept as its own widget rather than unified with
/// [SelectionAppBar] into one parameterized widget, since the two really do
/// have different visual shapes, not just different data -- unifying them
/// would be a UX-level call, not a pure decomposition, the same reasoning
/// that kept [SortMenuButton] separate from the unused `SortOptionsSheet`
/// (TD-13).
class SelectionAppBarWide extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final String selectionLabel;
  final bool singleFileSelected;
  final bool singleFolderSelected;
  final bool folderDocumentProviderMounted;
  final bool readOnly;
  final bool showPinOption;
  final bool showUnpinOption;
  final bool showActionBar;
  final List<FileManagerAction> visibleActions;
  final Map<FileManagerAction, WidgetBuilder> actionBuilders;

  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onOpenWithApp;
  final VoidCallback onToggleDocumentProvider;
  final VoidCallback onPin;
  final VoidCallback onUnpin;

  const SelectionAppBarWide({
    super.key,
    required this.selectedCount,
    required this.selectionLabel,
    required this.singleFileSelected,
    required this.singleFolderSelected,
    required this.folderDocumentProviderMounted,
    required this.readOnly,
    required this.showPinOption,
    required this.showUnpinOption,
    required this.showActionBar,
    required this.visibleActions,
    required this.actionBuilders,
    required this.onClose,
    required this.onSelectAll,
    required this.onRename,
    required this.onCopy,
    required this.onCut,
    required this.onExport,
    required this.onDelete,
    required this.onOpenWithApp,
    required this.onToggleDocumentProvider,
    required this.onPin,
    required this.onUnpin,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppBar(
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
        IconButton(
          icon: Icon(
            Icons.delete_outline_rounded,
            color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.error,
          ),
          tooltip: readOnly ? context.l10n.readOnlyCantDeleteTooltip : context.l10n.delete,
          onPressed: onDelete,
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: context.l10n.copyTooltip,
          onPressed: onCopy,
        ),
        IconButton(
          icon: Icon(
            Icons.cut_rounded,
            color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : null,
          ),
          tooltip: readOnly ? context.l10n.readOnlyCantMoveTooltip : context.l10n.moveAction,
          onPressed: onCut,
        ),
        IconButton(
          icon: Icon(
            Icons.drive_file_rename_outline_rounded,
            color: readOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : null,
          ),
          tooltip: readOnly ? context.l10n.readOnlyCantRenameTooltip : context.l10n.renameTooltip,
          onPressed: onRename,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: context.l10n.moreOptionsTooltip,
          onSelected: (value) {
            if (value == 'export') onExport();
            if (value == 'pin') onPin();
            if (value == 'unpin') onUnpin();
            if (value == 'open_with_app') onOpenWithApp();
            if (value == 'doc_provider') onToggleDocumentProvider();
            if (value == 'select_all') onSelectAll();
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'select_all',
              child: Text(context.l10n.selectAllAction),
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
        const SizedBox(width: 8),
        VerticalDivider(width: 1, indent: 12, endIndent: 12, color: cs.outlineVariant),
        const SizedBox(width: 4),
        if (showActionBar)
          ...visibleActions.map((action) => actionBuilders[action]!(context)),
        const SizedBox(width: 4),
      ],
    );
  }
}