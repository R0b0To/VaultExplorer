import 'package:flutter/material.dart';
import '../../models/file_operation.dart';
import '../../models/mounted_container.dart';
import '../../services/vaultexplorer_api.dart';
import '../../utils/filename_utils.dart';
import '../../widgets/common_widgets.dart';

abstract class BrowserDialogs {
  static void _blockedReadOnly(BuildContext context) {
    showAppSnackBar(
      context,
      message: 'This container is mounted read-only.',
      tone: AppBannerTone.warning,
    );
  }

  static void showCreateFolder(
    BuildContext context, {
    required MountedContainer container,
    required String currentDirPath,
    required VoidCallback onSuccess,
    bool readOnly = false,
  }) {
    if (readOnly) {
      _blockedReadOnly(context);
      return;
    }
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
    bool readOnly = false,
  }) {
    if (readOnly) {
      _blockedReadOnly(context);
      return;
    }
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
    required List<String> oldNames,
    required Set<String> existingNamesInDir,
    required String currentDirPath,
    required VoidCallback onSuccess,
    bool readOnly = false,
  }) {
    if (readOnly) {
      _blockedReadOnly(context);
      return;
    }
    final ctrl = TextEditingController(text: oldNames.length == 1 ? oldNames.first : '');
    final title = oldNames.length == 1 ? 'Rename' : 'Rename ${oldNames.length} items';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: oldNames.length == 1 ? 'New name' : 'Base name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newNameBase = sanitizeFatFileName(ctrl.text.trim());
              if (newNameBase.isEmpty) return;
              Navigator.pop(dialogContext);

              if (oldNames.length == 1) {
                final oldName = oldNames.first;
                if (newNameBase == oldName) return;

                final oldFull = currentDirPath.isEmpty
                    ? oldName
                    : '$currentDirPath/$oldName';
                final newFull = currentDirPath.isEmpty
                    ? newNameBase
                    : '$currentDirPath/$newNameBase';
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
              } else {
                int successCount = 0;
                int failCount = 0;
                final existing = Set<String>.from(existingNamesInDir);

                for (final oldName in oldNames) {
                  final parts = oldName.split('.');
                  final ext = parts.length > 1 ? '.${parts.last}' : '';

                  String desiredName;
                  if (newNameBase.toLowerCase().endsWith(ext.toLowerCase())) {
                    desiredName = newNameBase;
                  } else {
                    desiredName = '$newNameBase$ext';
                  }

                  final uniqueName = FileOperationService.makeUniqueName(desiredName, existing);
                  existing.add(uniqueName.toLowerCase());

                  final oldFull = currentDirPath.isEmpty ? oldName : '$currentDirPath/$oldName';
                  final newFull = currentDirPath.isEmpty ? uniqueName : '$currentDirPath/$uniqueName';

                  final ok = await vaultExplorerApi.renameFile(container, oldFull, newFull);
                  if (ok) {
                    successCount++;
                  } else {
                    failCount++;
                  }
                }

                if (successCount > 0) onSuccess();
                if (failCount > 0 && context.mounted) {
                  showAppSnackBar(
                    context,
                    message: 'Couldn\'t rename $failCount items',
                    tone: AppBannerTone.error,
                  );
                }
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
    bool readOnly = false,
  }) async {
    if (readOnly) {
      _blockedReadOnly(context);
      return;
    }
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