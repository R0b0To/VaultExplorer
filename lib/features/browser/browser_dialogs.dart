import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/filename_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';

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
    showDialog(
      context: context,
      builder: (dialogContext) => _CreateFolderDialog(
        container: container,
        currentDirPath: currentDirPath,
        onSuccess: onSuccess,
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
    showDialog(
      context: context,
      builder: (dialogContext) => _CreateFileDialog(
        container: container,
        currentDirPath: currentDirPath,
        onSuccess: onSuccess,
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
    showDialog(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        container: container,
        oldNames: oldNames,
        existingNamesInDir: existingNamesInDir,
        currentDirPath: currentDirPath,
        onSuccess: onSuccess,
      ),
    );
  }

  static void showBatchDelete(
    BuildContext context, {
    required List<RawEntry> toDelete,
    required void Function(List<RawEntry> items) onConfirmed,
    bool readOnly = false,
  }) async {
    if (readOnly) {
      _blockedReadOnly(context);
      return;
    }
    final hasDir = toDelete.any((item) => item.isDir);
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

class _CreateFolderDialog extends StatefulWidget {
  final MountedContainer container;
  final String currentDirPath;
  final VoidCallback onSuccess;

  const _CreateFolderDialog({
    required this.container,
    required this.currentDirPath,
    required this.onSuccess,
  });

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    final name = sanitizeFatFileName(_ctrl.text.trim());
    if (name.isEmpty) return;

    final parentContext = context;
    Navigator.pop(context);

    final full = widget.currentDirPath.isEmpty
        ? name
        : '${widget.currentDirPath}/$name';
    final ok = await vaultExplorerApi.createDirectory(widget.container, full);
    if (ok) {
      widget.onSuccess();
    } else if (parentContext.mounted) {
      showAppSnackBar(
        parentContext,
        message: 'Couldn\'t create "$name" — check the container is still mounted',
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Folder'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(hintText: 'Folder name'),
        autofocus: true,
        onSubmitted: (_) => _onCreate(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _onCreate,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _CreateFileDialog extends StatefulWidget {
  final MountedContainer container;
  final String currentDirPath;
  final VoidCallback onSuccess;

  const _CreateFileDialog({
    required this.container,
    required this.currentDirPath,
    required this.onSuccess,
  });

  @override
  State<_CreateFileDialog> createState() => _CreateFileDialogState();
}

class _CreateFileDialogState extends State<_CreateFileDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    final name = sanitizeFatFileName(_ctrl.text.trim());
    if (name.isEmpty) return;

    final parentContext = context;
    Navigator.pop(context);

    final full = widget.currentDirPath.isEmpty
        ? name
        : '${widget.currentDirPath}/$name';
    final ok = await vaultExplorerApi.createEmptyFile(widget.container, full);
    if (ok) {
      widget.onSuccess();
    } else if (parentContext.mounted) {
      showAppSnackBar(
        parentContext,
        message: 'Couldn\'t create "$name" — check the container is still mounted',
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Text File'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(hintText: 'filename.txt'),
        autofocus: true,
        onSubmitted: (_) => _onCreate(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _onCreate,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final MountedContainer container;
  final List<String> oldNames;
  final Set<String> existingNamesInDir;
  final String currentDirPath;
  final VoidCallback onSuccess;

  const _RenameDialog({
    required this.container,
    required this.oldNames,
    required this.existingNamesInDir,
    required this.currentDirPath,
    required this.onSuccess,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.oldNames.length == 1 ? widget.oldNames.first : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onRename() async {
    final newNameBase = sanitizeFatFileName(_ctrl.text.trim());
    if (newNameBase.isEmpty) return;

    final parentContext = context;
    Navigator.pop(context);

    if (widget.oldNames.length == 1) {
      final oldName = widget.oldNames.first;
      if (newNameBase == oldName) return;
      final oldFull = widget.currentDirPath.isEmpty
          ? oldName
          : '${widget.currentDirPath}/$oldName';
      final newFull = widget.currentDirPath.isEmpty
          ? newNameBase
          : '${widget.currentDirPath}/$newNameBase';
      final ok = await vaultExplorerApi.renameFile(
        widget.container,
        oldFull,
        newFull,
      );
      if (ok) {
        widget.onSuccess();
      } else if (parentContext.mounted) {
        showAppSnackBar(
          parentContext,
          message: 'Couldn\'t rename "$oldName" — a file with that name may already exist',
          tone: AppBannerTone.error,
        );
      }
    } else {
      int successCount = 0;
      int failCount = 0;
      final existing = Set<String>.from(widget.existingNamesInDir);
      for (final oldName in widget.oldNames) {
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
        final oldFull = widget.currentDirPath.isEmpty ? oldName : '${widget.currentDirPath}/$oldName';
        final newFull = widget.currentDirPath.isEmpty ? uniqueName : '${widget.currentDirPath}/$uniqueName';
        final ok = await vaultExplorerApi.renameFile(widget.container, oldFull, newFull);
        if (ok) {
          successCount++;
        } else {
          failCount++;
        }
      }
      if (successCount > 0) widget.onSuccess();
      if (failCount > 0 && parentContext.mounted) {
        showAppSnackBar(
          parentContext,
          message: 'Couldn\'t rename $failCount items',
          tone: AppBannerTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.oldNames.length == 1 ? 'Rename' : 'Rename ${widget.oldNames.length} items';
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.oldNames.length == 1 ? 'New name' : 'Base name',
        ),
        onSubmitted: (_) => _onRename(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _onRename,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}