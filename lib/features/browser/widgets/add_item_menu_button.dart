import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

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
  final Future<void> Function() onCaptureFromCamera;
  final Future<void> Function() onRecordAudio;
  final Future<void> Function() onImportFilesFromDevice;
  final Future<void> Function() onImportFolderFromDevice;
  final Future<void> Function(VaultItemType type) onAddVaultItem;

  /// When true, renders as an elevated round [FloatingActionButton]-style
  /// anchor (56dp, primary-container filled) instead of the plain app-bar
  /// [IconButton]. Used when this is promoted to be the floating-toolbar's
  /// main FAB -- the menu contents and behavior are unchanged either way.
  final bool asFab;

  /// Hides Import Files/Folder and the Secure Item submenu, which require a
  /// registered vault session. Camera and audio capture also work with plain
  /// storage containers and remain available there.
  final bool hideImportAndSecureItemActions;

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
    required this.onCaptureFromCamera,
    required this.onRecordAudio,
    required this.onImportFilesFromDevice,
    required this.onImportFolderFromDevice,
    required this.onAddVaultItem,
    this.hideImportAndSecureItemActions = false,
    this.asFab = false,
  });

  @override
  ConsumerState<AddItemMenuButton> createState() => _AddItemMenuButtonState();
}

class _AddItemMenuButtonState extends ConsumerState<AddItemMenuButton> {
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
      // The page's own round-button colors come from its (scoped) theme.
      backgroundColor:
          backgroundColor ??
          Theme.of(context).floatingActionButtonTheme.backgroundColor ??
          cs.primaryContainer,
      foregroundColor:
          foregroundColor ??
          Theme.of(context).floatingActionButtonTheme.foregroundColor ??
          cs.onPrimaryContainer,
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
        foregroundColor: cs.onSurfaceVariant.withValues(
          alpha: widget.asFab ? 1.0 : 0.5,
        ),
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
    return BackDismissibleMenuAnchor(
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
      menuChildren: buildAddItemMenuChildren(
        context: context,
        ref: ref,
        container: widget.container,
        currentDirPath: widget.currentDirPath,
        currentItems: widget.currentItems,
        isReadOnly: widget.isReadOnly,
        hideImportAndSecureItemActions: widget.hideImportAndSecureItemActions,
        onCaptureFromCamera: widget.onCaptureFromCamera,
        onRecordAudio: widget.onRecordAudio,
        onImportFilesFromDevice: widget.onImportFilesFromDevice,
        onImportFolderFromDevice: widget.onImportFolderFromDevice,
        onAddVaultItem: widget.onAddVaultItem,
      ),
    );
  }
}

/// The entries of the "new item" menu: new folder/file/symlink, camera and
/// audio capture, import files/folder and the "Secure Item" submenu. Shared by
/// the app-bar/FAB [AddItemMenuButton] and the right-click menu of the empty
/// area of a folder, so both always offer the same actions.
List<Widget> buildAddItemMenuChildren({
  required BuildContext context,
  required WidgetRef ref,
  required MountedContainer container,
  required String currentDirPath,
  required List<RawEntry> currentItems,
  required bool isReadOnly,
  required bool hideImportAndSecureItemActions,
  required Future<void> Function() onCaptureFromCamera,
  required Future<void> Function() onRecordAudio,
  required Future<void> Function() onImportFilesFromDevice,
  required Future<void> Function() onImportFolderFromDevice,
  required Future<void> Function(VaultItemType type) onAddVaultItem,
}) {
  final cs = Theme.of(context).colorScheme;
  return [
    MenuItemButton(
      leadingIcon: Icon(
        Icons.create_new_folder_outlined,
        color: cs.primary,
      ),
      child: Text(context.l10n.newFolderTitle),
      onPressed: () {
        BrowserDialogs.showCreateFolder(
          context,
          container: container,
          currentDirPath: currentDirPath,
          existingEntries: currentItems,
          onSuccess: () {},
          readOnly: isReadOnly,
        );
      },
    ),
    MenuItemButton(
      leadingIcon: Icon(
        Icons.insert_drive_file_outlined,
        color: cs.primary,
      ),
      child: Text(context.l10n.newTextFileTitle),
      onPressed: () {
        BrowserDialogs.showCreateFile(
          context,
          container: container,
          currentDirPath: currentDirPath,
          existingEntries: currentItems,
          onSuccess: () {},
          readOnly: isReadOnly,
        );
      },
    ),
    // Cryptomator stores encrypted virtual links; ext/NTFS disk-image
    // filesystems store native links. FAT/exFAT and unknown filesystems
    // deliberately do not expose this action.
    if (!hideImportAndSecureItemActions &&
        supportsVaultSymbolicLinks(container))
      MenuItemButton(
        leadingIcon: Icon(Icons.add_link, color: cs.primary),
        child: Text(context.l10n.newSymbolicLinkTitle),
        onPressed: () {
          BrowserDialogs.showCreateSymlink(
            context,
            container: container,
            currentDirPath: currentDirPath,
            existingEntries: currentItems,
            onSuccess: () {},
            readOnly: isReadOnly,
          );
        },
      ),
    if (PlatformFeatures.camera)
    MenuItemButton(
      leadingIcon: Icon(Icons.photo_camera_outlined, color: cs.primary),
      // The callback awaits the camera route. Holding lock suppression
      // around it would disable screen-off auto-lock for the whole time
      // the camera is open.
      onPressed: onCaptureFromCamera,
      child: Text(context.l10n.camera),
    ),
    if (PlatformFeatures.audioRecorder)
    MenuItemButton(
      leadingIcon: Icon(Icons.mic_none_rounded, color: cs.primary),
      onPressed: () => ref
          .read(sessionLockControllerProvider)
          .withLockSuppression(onRecordAudio),
      child: Text(context.l10n.audioRecorder),
    ),
    if (!hideImportAndSecureItemActions) ...[
      const PopupMenuDivider(),
      MenuItemButton(
        leadingIcon: Icon(Icons.upload_file_outlined, color: cs.secondary),
        onPressed: () => ref
            .read(sessionLockControllerProvider)
            .withLockSuppression(onImportFilesFromDevice),
        child: Text(context.l10n.importFiles),
      ),
      MenuItemButton(
        leadingIcon: Icon(
          Icons.drive_folder_upload_outlined,
          color: cs.secondary,
        ),
        onPressed: () => ref
            .read(sessionLockControllerProvider)
            .withLockSuppression(onImportFolderFromDevice),
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
              onPressed: () => onAddVaultItem(type),
            ),
          ),
        ],
        child: Text(context.l10n.secureItem),
      ),
    ],
  ];
}
