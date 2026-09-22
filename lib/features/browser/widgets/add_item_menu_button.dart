import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';

/// App-bar "add item" popup button: new folder/file, camera capture, import
/// files/folder, and the "Secure Item" submenu for each vault format.
/// [hasArchiveContext] is a plain bool rather than the actual
/// `ArchiveContext?` value: the original method only ever null-checked it
/// (`if (_archiveContext != null)`), never read a property off it, so
/// there's nothing else this widget needs from that type.
class AddItemMenuButton extends ConsumerStatefulWidget {
  final bool isReadOnly;
  final bool hasArchiveContext;
  final MountedContainer container;
  final String currentDirPath;
  final List<RawEntry> currentItems;

  final void Function(String message, {bool error}) onSetStatus;
  final Future<void> Function() onExtractArchive;
  final void Function() onSignalActivity;
  final Future<void> Function(String path) onLoadDirectoryContents;
  final Future<void> Function() onCaptureFromCamera;
  final Future<void> Function() onImportFilesFromDevice;
  final Future<void> Function() onImportFolderFromDevice;
  final Future<void> Function(VaultItemType type) onAddVaultItem;

  /// When true, renders as an elevated round [FloatingActionButton]-style
  /// anchor (56dp, primary-container filled) instead of the plain app-bar
  /// [IconButton]. Used when this is promoted to be the floating-toolbar's
  /// main FAB -- the menu contents and behavior are unchanged either way.
  final bool asFab;

  /// Hides Camera, Import Files/Folder, and the Secure Item submenu.
  /// Those all need a registered native vault session (camera capture
  /// encrypts while recording; import copies through the native engine;
  /// Secure Item creates an encrypted vault-item record) -- none of which
  /// exists for a plain local-storage container. New Folder/New Text File
  /// stay available since they go through the same createDirectory/
  /// writeWholeFile calls that already work for local storage.
  final bool hideVaultOnlyActions;

  const AddItemMenuButton({
    super.key,
    required this.isReadOnly,
    required this.hasArchiveContext,
    required this.container,
    required this.currentDirPath,
    required this.currentItems,
    required this.onSetStatus,
    required this.onExtractArchive,
    required this.onSignalActivity,
    required this.onLoadDirectoryContents,
    required this.onCaptureFromCamera,
    required this.onImportFilesFromDevice,
    required this.onImportFolderFromDevice,
    required this.onAddVaultItem,
    this.hideVaultOnlyActions = false,
    this.asFab = false,
  });

   @override
  ConsumerState<AddItemMenuButton> createState() => _AddItemMenuButtonState();
}

class _AddItemMenuButtonState extends ConsumerState<AddItemMenuButton> {
  // Was `_menuIsOpen` on the parent's State, shared (and never actually
  // read) across three different popup buttons -- see the identical note
  // in sort_menu_button.dart. Kept local here for the same reason.
  bool _menuIsOpen = false;

  /// Renders the anchor as a plain app-bar [IconButton], or -- when
  /// [AddItemMenuButton.asFab] is set -- as a 56dp elevated
  /// [FloatingActionButton], so the same menu (and its three states:
  /// read-only, archive-extract, normal add) can be promoted to the
  /// floating-toolbar's main FAB without duplicating any of the logic below.
  Widget _anchorButton(
    ColorScheme cs, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    if (!widget.asFab) {
      return IconButton(
        icon: Icon(icon, size: 28, color: foregroundColor),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }
    return FloatingActionButton(
      heroTag: 'file_manager_add_fab_${widget.container.volId}',
      tooltip: tooltip,
      backgroundColor: backgroundColor ?? cs.primaryContainer,
      foregroundColor: foregroundColor ?? cs.onPrimaryContainer,
      onPressed: onPressed,
      child: Icon(icon, size: 26),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.isReadOnly) {
      return _anchorButton(
        cs,
        icon: Icons.lock_outline_rounded,
        tooltip: context.l10n.readOnlyCantAddItemsTooltip,
        backgroundColor: widget.asFab ? cs.surfaceContainerHighest : null,
        foregroundColor: cs.onSurfaceVariant.withValues(alpha: widget.asFab ? 1.0 : 0.5),
        onPressed: () => widget.onSetStatus(
          context.l10n.readOnlyContainerWarning,
          error: true,
        ),
      );
    }
     if (widget.hasArchiveContext) {
      return _anchorButton(
        cs,
        icon: Icons.unarchive_rounded,
        tooltip: context.l10n.extractArchive,
        onPressed: () => ref
            .read(sessionLockControllerProvider)
            .withLockSuppression(widget.onExtractArchive),
      );
    }
    return MenuAnchor(
      builder: (context, controller, child) => _anchorButton(
        cs,
        icon: Icons.add_rounded,
        tooltip: context.l10n.newItemTooltip,
        onPressed: () {
          widget.onSignalActivity();
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      onOpen: () => setState(() => _menuIsOpen = true),
      onClose: () => setState(() => _menuIsOpen = false),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.create_new_folder_outlined, color: cs.primary),
          child: Text(context.l10n.newFolderTitle),
          onPressed: () {
            BrowserDialogs.showCreateFolder(
              context,
              container: widget.container,
              currentDirPath: widget.currentDirPath,
              existingEntries: widget.currentItems,
              onSuccess: () => widget.onLoadDirectoryContents(widget.currentDirPath),
              readOnly: widget.isReadOnly,
            );
          },
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.insert_drive_file_outlined, color: cs.primary),
          child: Text(context.l10n.newTextFileTitle),
          onPressed: () {
            BrowserDialogs.showCreateFile(
              context,
              container: widget.container,
              currentDirPath: widget.currentDirPath,
              existingEntries: widget.currentItems,
              onSuccess: () => widget.onLoadDirectoryContents(widget.currentDirPath),
              readOnly: widget.isReadOnly,
            );
          },
        ),
        if (!widget.hideVaultOnlyActions) ...[
          MenuItemButton(
            leadingIcon: Icon(Icons.photo_camera_outlined, color: cs.primary),
            onPressed: () => ref
                .read(sessionLockControllerProvider)
                .withLockSuppression(widget.onCaptureFromCamera),
            child: Text(context.l10n.camera),
          ),
          const PopupMenuDivider(),
          MenuItemButton(
            leadingIcon: Icon(Icons.upload_file_outlined, color: cs.secondary),
            onPressed: () => ref
                .read(sessionLockControllerProvider)
                .withLockSuppression(widget.onImportFilesFromDevice),
            child: Text(context.l10n.importFiles),
          ),
          MenuItemButton(
            leadingIcon: Icon(Icons.drive_folder_upload_outlined, color: cs.secondary),
            onPressed: () => ref
                .read(sessionLockControllerProvider)
                .withLockSuppression(widget.onImportFolderFromDevice),
            child: Text(context.l10n.importFolder),
          ),
          const PopupMenuDivider(),
          SubmenuButton(
            leadingIcon: Icon(Icons.lock_rounded, color: cs.primary),
            menuChildren: [
              ...VaultItemType.values.map(
                (type) => MenuItemButton(
                  leadingIcon: Icon(
                    vaultIconForExt(type.name) ?? Icons.lock_rounded,
                    color: vaultColorForExt(type.name) ?? cs.primary,
                  ),
                  child: Text(type.label(context.l10n)),
                  onPressed: () => widget.onAddVaultItem(type),
                ),
              ),
            ],
            child: Text(context.l10n.secureItem),
          ),
        ],
      ],
    );
  }
}