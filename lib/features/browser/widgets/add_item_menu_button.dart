import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';

/// App-bar "add item" popup button: new folder/file, camera capture, import
/// files/folder, and the "Secure Item" submenu for each vault format.
///
/// Extracted verbatim from `FileBrowserScreen`'s private
/// `_buildAddPopupButton` -- fourth slice of the `file_browser_screen.dart`
/// decomposition (docs/tech-debt.md TD-8), and deliberately the last of the
/// four `_build*PopupButton`-style methods to be extracted: it has roughly
/// 14 distinct dependencies versus 2-3 for each of the other three, so it
/// was held back for its own careful pass rather than rushed through on the
/// same momentum. Every dependency below is either a read-only value or a
/// callback, each checked against the original method's exact usage before
/// being wired up -- no behavior change, only a location change.
///
/// [hasArchiveContext] is a plain bool rather than the actual
/// `ArchiveContext?` value: the original method only ever null-checked it
/// (`if (_archiveContext != null)`), never read a property off it, so
/// there's nothing else this widget needs from that type.
class AddItemMenuButton extends StatefulWidget {
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
  });

  @override
  State<AddItemMenuButton> createState() => _AddItemMenuButtonState();
}

class _AddItemMenuButtonState extends State<AddItemMenuButton> {
  // Was `_menuIsOpen` on the parent's State, shared (and never actually
  // read) across three different popup buttons -- see the identical note
  // in sort_menu_button.dart. Kept local here for the same reason.
  bool _menuIsOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.isReadOnly) {
      return IconButton(
        icon: Icon(
          Icons.lock_outline_rounded,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        tooltip: 'Read-only — can\'t add items',
        onPressed: () => widget.onSetStatus(
          'This container is mounted read-only.',
          error: true,
        ),
      );
    }
    if (widget.hasArchiveContext) {
      return IconButton(
        icon: const Icon(Icons.unarchive_rounded, size: 28),
        tooltip: 'Extract Archive',
        onPressed: widget.onExtractArchive,
      );
    }
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.add_rounded, size: 28),
        tooltip: 'New item',
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
          child: const Text('New Folder'),
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
          child: const Text('New Text File'),
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
        MenuItemButton(
          leadingIcon: Icon(Icons.photo_camera_outlined, color: cs.primary),
          child: const Text('Camera'),
          onPressed: widget.onCaptureFromCamera,
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.upload_file_outlined, color: cs.secondary),
          child: const Text('Import Files'),
          onPressed: widget.onImportFilesFromDevice,
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.drive_folder_upload_outlined, color: cs.secondary),
          child: const Text('Import Folder'),
          onPressed: widget.onImportFolderFromDevice,
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
                child: Text(type.label),
                onPressed: () => widget.onAddVaultItem(type),
              ),
            ),
          ],
          child: const Text('Secure Item'),
        ),
      ],
    );
  }
}
