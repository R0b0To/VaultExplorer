import 'package:flutter/material.dart';
import '../../models/mounted_container.dart';
import '../../services/vaultexplorer_api.dart';
import '../../utils/filename_utils.dart';
import '../../widgets/common_widgets.dart';


abstract class BrowserDialogs {
  static void showCreateFolder(
    BuildContext context, {
    required MountedContainer container,
    required String currentDirPath,
    required VoidCallback onSuccess,
  }) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'New Folder',
        ),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = sanitizeFatFileName(ctrl.text.trim());
              if (name.isEmpty) return;
              Navigator.pop(dialogContext);
              final full = currentDirPath.isEmpty
                  ? name
                  : '$currentDirPath/$name';
              final ok = await vaultExplorerApi.createDirectory(container, full);

              if (ok) {
                onSuccess();
              } else if (context.mounted) {
                showAppSnackBar(
                  context,
                  message: 'Couldn\'t create "$name" — check the container is still mounted',
                  tone: AppBannerTone.error,
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  static void showCreateFile(
    BuildContext context, {
    required MountedContainer container,
    required String currentDirPath,
    required VoidCallback onSuccess,
  }) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Text File'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'filename.txt'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = sanitizeFatFileName(ctrl.text.trim());
              if (name.isEmpty) return;
              Navigator.pop(dialogContext);
              final full = currentDirPath.isEmpty
                  ? name
                  : '$currentDirPath/$name';
              final ok = await vaultExplorerApi.createEmptyFile(container, full);
              if (ok) {
                onSuccess();
              } else if (context.mounted) {
                showAppSnackBar(
                  context,
                  message: 'Couldn\'t create "$name" — check the container is still mounted',
                  tone: AppBannerTone.error,
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  static void showRename(
    BuildContext context, {
    required MountedContainer container,
    required String oldName,
    required String currentDirPath,
    required VoidCallback onSuccess,
  }) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = sanitizeFatFileName(ctrl.text.trim());
              if (newName.isEmpty || newName == oldName) return;
              Navigator.pop(dialogContext);
              final oldFull = currentDirPath.isEmpty
                  ? oldName
                  : '$currentDirPath/$oldName';
              final newFull = currentDirPath.isEmpty
                  ? newName
                  : '$currentDirPath/$newName';
              final ok = await vaultExplorerApi.renameFile(
                container,
                oldFull,
                newFull,
              );
              if (ok) {
                onSuccess();
              } else if (context.mounted) {
                showAppSnackBar(
                  context,
                  message: 'Couldn\'t rename "$oldName" — a file with that name may already exist',
                  tone: AppBannerTone.error,
                );
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  static void showBatchDelete(
    BuildContext context, {
    required List<String> toDelete,
    required void Function(List<String> items) onConfirmed,
  }) async {
    final hasDir = toDelete.any((item) => item.startsWith('[DIR] '));

    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete ${toDelete.length} item(s)?',
      message: hasDir
          ? 'These items will be permanently deleted, including all contents of any selected folders.'
          : 'These items will be permanently erased from your encrypted volume.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed) onConfirmed(toDelete);
  }
}
