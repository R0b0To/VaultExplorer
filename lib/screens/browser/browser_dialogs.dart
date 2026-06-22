import 'package:flutter/material.dart';
import '../../models/mounted_container.dart';
import '../../services/vaultexplorer_api.dart';

/// Static helpers that show the browser's confirmation / input dialogs.
///
/// Keeping dialog code here means [_FileBrowserScreenState] doesn't have to
/// declare four heavy methods that share no mutable state with each other.
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
      builder: (_) => AlertDialog(
        title: const Text('New Folder', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              final full =
                  currentDirPath.isEmpty ? name : '$currentDirPath/$name';
              if (await vaultExplorerApi.createDirectory(container, full)) {
                onSuccess();
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
      builder: (_) => AlertDialog(
        title: const Text('New Text File', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'filename.txt'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              final full =
                  currentDirPath.isEmpty ? name : '$currentDirPath/$name';
              if (await vaultExplorerApi.createEmptyFile(container, full)) {
                onSuccess();
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
      builder: (_) => AlertDialog(
        title: const Text('Rename', style: TextStyle(fontSize: 16)),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == oldName) return;
              Navigator.pop(context);
              final oldFull = currentDirPath.isEmpty
                  ? oldName
                  : '$currentDirPath/$oldName';
              final newFull = currentDirPath.isEmpty
                  ? newName
                  : '$currentDirPath/$newName';
              if (await vaultExplorerApi.renameFile(
                  container, oldFull, newFull)) {
                onSuccess();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  /// Asks the user to confirm, then calls [onConfirmed] with the item list.
  /// Actual deletion + loading-state management is the caller's responsibility.
  static void showBatchDelete(
    BuildContext context, {
    required List<String> toDelete,
    required void Function(List<String> items) onConfirmed,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Delete ${toDelete.length} item(s)?',
          style: const TextStyle(fontSize: 16),
        ),
        content: const Text(
          'These items will be permanently erased from your encrypted volume.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirmed(toDelete);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}