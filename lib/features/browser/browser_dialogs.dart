import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/illegal_char_input_formatter.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/advanced_rename_screen.dart';

abstract class BrowserDialogs {
  static void _blockedReadOnly(BuildContext context) {
    showAppSnackBar(
      context,
      message: context.l10n.readOnlyContainerWarning,
      tone: AppBannerTone.warning,
    );
  }

  static void showCreateFolder(
    BuildContext context, {
    required MountedContainer container,
    required String currentDirPath,
    required List<RawEntry> existingEntries,
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
        existingEntries: existingEntries,
        onSuccess: onSuccess,
      ),
    );
  }

  static void showCreateFile(
    BuildContext context, {
    required MountedContainer container,
    required String currentDirPath,
    required List<RawEntry> existingEntries,
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
        existingEntries: existingEntries,
        onSuccess: onSuccess,
      ),
    );
  }

  static Future<void> showRename(
    BuildContext context, {
    required MountedContainer container,
    required List<RawEntry> oldEntries,
    required List<RawEntry> existingEntries,
    required String currentDirPath,
    required VoidCallback onSuccess,
    void Function(String oldPath, String newPath)? onEntryRenamed,
    bool readOnly = false,
  }) {
    if (readOnly) {
      _blockedReadOnly(context);
      return Future.value();
    }
    return showDialog(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        container: container,
        oldEntries: oldEntries,
        existingEntries: existingEntries,
        currentDirPath: currentDirPath,
        onSuccess: onSuccess,
        onEntryRenamed: onEntryRenamed,
      ),
    );
  }

  static Future<void> showAdvancedRename(
    BuildContext context, {
    required MountedContainer container,
    required List<RawEntry> oldEntries,
    required List<RawEntry> existingEntries,
    required String currentDirPath,
    required VoidCallback onSuccess,
    void Function(String oldPath, String newPath)? onEntryRenamed,
    bool readOnly = false,
  }) {
    if (readOnly) {
      _blockedReadOnly(context);
      return Future.value();
    }
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdvancedRenameScreen(
          container: container,
          oldEntries: oldEntries,
          existingEntries: existingEntries,
          currentDirPath: currentDirPath,
          onSuccess: onSuccess,
          onEntryRenamed: onEntryRenamed,
        ),
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
      title: context.l10n.deleteItemsTitle(toDelete.length),
      message: hasDir
          ? context.l10n.deleteFoldersWarning
          : context.l10n.deleteFilesWarning,
      confirmLabel: context.l10n.delete,
      isDestructive: true,
    );
    if (confirmed) onConfirmed(toDelete);
  }
}

mixin _LiveNameValidation<T extends StatefulWidget> on State<T> {
  List<NameValidationIssue> issues = [];
  EntryConflictResult conflict = const EntryConflictResult(EntryConflictKind.none, null);
  bool get isValid => issues.isEmpty && !conflict.isConflict;

  void _computeValidation({
    required String text,
    required FilesystemType fsType,
    required EntryType entryType,
    required List<RawEntry> existingEntries,
    RawEntry? excluding,
  }) {
    final nameResult = validateEntryName(text, fsType, entryType: entryType, l10n: context.l10n);
    final conflictResult = text.isEmpty
        ? const EntryConflictResult(EntryConflictKind.none, null)
        : checkEntryConflict(
            candidateName: text,
            candidateIsDir: entryType == EntryType.folder,
            existingEntries: existingEntries,
            caseSensitive: FilesystemRules.of(fsType).caseSensitive,
            excluding: excluding,
          );
    issues = nameResult.issues;
    conflict = conflictResult;
  }

  void seedValidation({
    required String text,
    required FilesystemType fsType,
    required EntryType entryType,
    required List<RawEntry> existingEntries,
    RawEntry? excluding,
  }) =>
      _computeValidation(
        text: text,
        fsType: fsType,
        entryType: entryType,
        existingEntries: existingEntries,
        excluding: excluding,
      );

  void revalidate({
    required String text,
    required FilesystemType fsType,
    required EntryType entryType,
    required List<RawEntry> existingEntries,
    RawEntry? excluding,
  }) =>
      setState(() => _computeValidation(
            text: text,
            fsType: fsType,
            entryType: entryType,
            existingEntries: existingEntries,
            excluding: excluding,
          ));

  List<String> get allMessages => [
        ...issues.map((i) => i.message),
        if (conflict.isConflict) conflict.message(context.l10n, '')!,
      ];

  Widget buildIssuesList(String candidateName) {
    final hasIssues = issues.isNotEmpty || conflict.isConflict;
    final messages = hasIssues
        ? [
            ...issues.map((i) => i.message),
            if (conflict.isConflict) conflict.message(context.l10n, candidateName)!,
          ]
        : const <String>[];
    final errorColor = Theme.of(context).colorScheme.error;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: hasIssues
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: messages
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            m,
                            style: TextStyle(
                              color: errorColor,
                              fontSize: 12,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  final MountedContainer container;
  final String currentDirPath;
  final List<RawEntry> existingEntries;
  final VoidCallback onSuccess;
  const _CreateFolderDialog({
    required this.container,
    required this.currentDirPath,
    required this.existingEntries,
    required this.onSuccess,
  });

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog>
    with _LiveNameValidation<_CreateFolderDialog> {
  late final TextEditingController _ctrl;
  late final FilesystemType _fsType;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _fsType = resolveFilesystemType(widget.container);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) => revalidate(
        text: text,
        fsType: _fsType,
        entryType: EntryType.folder,
        existingEntries: widget.existingEntries,
      );

  Future<void> _onCreate() async {
    final name = _ctrl.text;
    if (name.isEmpty || !isValid) return;
    final l10n = context.l10n;
    final parentSegments =
        widget.currentDirPath.isEmpty ? <String>[] : widget.currentDirPath.split('/');
    final built = PathComponents(
      parentSegments: parentSegments,
      name: name,
      type: EntryType.folder,
      fsType: _fsType,
    ).validateAndBuild(l10n);
    if (built is! PathBuildSuccess) return;
    final parentContext = context;
    Navigator.pop(context);
    final ok = await vaultExplorerApi.createDirectory(widget.container, built.path);
    if (ok) {
      widget.onSuccess();
    } else if (parentContext.mounted) {
      showAppSnackBar(
        parentContext,
        message: l10n.couldntCreateItem(name),
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _ctrl.text;
    return AlertDialog(
      title: Text(context.l10n.newFolderTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(hintText: context.l10n.folderNameHint),
              autofocus: true,
              inputFormatters: [IllegalCharacterInputFormatter(_fsType)],
              onChanged: _onChanged,
              onSubmitted: (_) => _onCreate(),
            ),
            buildIssuesList(name),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: name.isNotEmpty && isValid ? _onCreate : null,
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}

class _CreateFileDialog extends StatefulWidget {
  final MountedContainer container;
  final String currentDirPath;
  final List<RawEntry> existingEntries;
  final VoidCallback onSuccess;
  const _CreateFileDialog({
    required this.container,
    required this.currentDirPath,
    required this.existingEntries,
    required this.onSuccess,
  });

  @override
  State<_CreateFileDialog> createState() => _CreateFileDialogState();
}

class _CreateFileDialogState extends State<_CreateFileDialog>
    with _LiveNameValidation<_CreateFileDialog> {
  late final TextEditingController _ctrl;
  late final FilesystemType _fsType;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _fsType = resolveFilesystemType(widget.container);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) => revalidate(
        text: text,
        fsType: _fsType,
        entryType: EntryType.file,
        existingEntries: widget.existingEntries,
      );

  Future<void> _onCreate() async {
    final name = _ctrl.text;
    if (name.isEmpty || !isValid) return;
    final l10n = context.l10n;
    final parentSegments =
        widget.currentDirPath.isEmpty ? <String>[] : widget.currentDirPath.split('/');
    final built = PathComponents(
      parentSegments: parentSegments,
      name: name,
      type: EntryType.file,
      fsType: _fsType,
    ).validateAndBuild(l10n);
    if (built is! PathBuildSuccess) return;
    final parentContext = context;
    Navigator.pop(context);
    final ok = await vaultExplorerApi.createEmptyFile(widget.container, built.path);
    if (ok) {
      widget.onSuccess();
    } else if (parentContext.mounted) {
      showAppSnackBar(
        parentContext,
        message: l10n.couldntCreateItem(name),
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _ctrl.text;
    return AlertDialog(
      title: Text(context.l10n.newTextFileTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(hintText: context.l10n.filenameHint),
              autofocus: true,
              inputFormatters: [IllegalCharacterInputFormatter(_fsType)],
              onChanged: _onChanged,
              onSubmitted: (_) => _onCreate(),
            ),
            buildIssuesList(name),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: name.isNotEmpty && isValid ? _onCreate : null,
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final MountedContainer container;
  final List<RawEntry> oldEntries;
  final List<RawEntry> existingEntries;
  final String currentDirPath;
  final VoidCallback onSuccess;
  final void Function(String oldPath, String newPath)? onEntryRenamed;

  const _RenameDialog({
    required this.container,
    required this.oldEntries,
    required this.existingEntries,
    required this.currentDirPath,
    required this.onSuccess,
    this.onEntryRenamed,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog>
    with _LiveNameValidation<_RenameDialog> {
  late final TextEditingController _ctrl;
  late final FilesystemType _fsType;
  bool _validationSeeded = false;
  bool get _isSingle => widget.oldEntries.length == 1;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: _isSingle ? widget.oldEntries.first.name : '',
    );
    _fsType = resolveFilesystemType(widget.container);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_validationSeeded) {
      _validationSeeded = true;
      if (_isSingle) {
        seedValidation(
          text: _ctrl.text,
          fsType: _fsType,
          entryType: widget.oldEntries.first.isDir ? EntryType.folder : EntryType.file,
          existingEntries: widget.existingEntries,
          excluding: widget.oldEntries.first,
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    if (_isSingle) {
      revalidate(
        text: text,
        fsType: _fsType,
        entryType: widget.oldEntries.first.isDir ? EntryType.folder : EntryType.file,
        existingEntries: widget.existingEntries,
        excluding: widget.oldEntries.first,
      );
    } else {
      final result = validateEntryName(
        text,
        _fsType,
        entryType: EntryType.file,
        l10n: context.l10n,
      );
      setState(() => issues = result.issues);
    }
  }

  Future<void> _onRename() async {
    final newNameBase = _ctrl.text;
    if (newNameBase.isEmpty) return;
    final l10n = context.l10n;
    if (_isSingle) {
      if (!isValid) return;
      final oldEntry = widget.oldEntries.first;
      final oldName = oldEntry.name;
      if (newNameBase == oldName) {
        Navigator.pop(context);
        return;
      }
      final parentSegments =
          widget.currentDirPath.isEmpty ? <String>[] : widget.currentDirPath.split('/');
      final built = PathComponents(
        parentSegments: parentSegments,
        name: newNameBase,
        type: oldEntry.isDir ? EntryType.folder : EntryType.file,
        fsType: _fsType,
      ).validateAndBuild(l10n);
      if (built is! PathBuildSuccess) return;
      final parentContext = context;
      Navigator.pop(context);
      final oldFull = widget.currentDirPath.isEmpty
          ? oldName
          : '${widget.currentDirPath}/$oldName';
      final ok = await vaultExplorerApi.renameFile(
        widget.container,
        oldFull,
        built.path,
      );
      if (ok) {
        widget.onSuccess();
        widget.onEntryRenamed?.call(oldFull, built.path);
      } else if (parentContext.mounted) {
        showAppSnackBar(
          parentContext,
          message: l10n.couldntRenameSingle(oldName),
          tone: AppBannerTone.error,
        );
      }
      return;
    }
    final parentContext = context;
    Navigator.pop(context);
    int successCount = 0;
    int failCount = 0;
    String? firstFailureReason;
    final existingLower =
        Set<String>.from(widget.existingEntries.map((e) => e.name.toLowerCase()));
    for (final oldEntry in widget.oldEntries) {
      final oldName = oldEntry.name;
      final parts = oldName.split('.');
      final ext = parts.length > 1 ? '.${parts.last}' : '';
      String desiredName;
      if (newNameBase.toLowerCase().endsWith(ext.toLowerCase())) {
        desiredName = newNameBase;
      } else {
        desiredName = '$newNameBase$ext';
      }
      final uniqueName = FileOperationService.makeUniqueName(desiredName, existingLower);
      final nameCheck = validateEntryName(
        uniqueName,
        _fsType,
        entryType: oldEntry.isDir ? EntryType.folder : EntryType.file,
        l10n: l10n,
      );
      if (nameCheck.issues.isNotEmpty) {
        failCount++;
        firstFailureReason ??= nameCheck.issues.first.message;
        continue;
      }
      final conflictCheck = checkEntryConflict(
        candidateName: uniqueName,
        candidateIsDir: oldEntry.isDir,
        existingEntries: widget.existingEntries,
        caseSensitive: FilesystemRules.of(_fsType).caseSensitive,
        excluding: oldEntry,
      );
      if (conflictCheck.kind == EntryConflictKind.crossType) {
        failCount++;
        firstFailureReason ??= conflictCheck.message(l10n, uniqueName);
        continue;
      }
      existingLower.add(uniqueName.toLowerCase());
      final oldFull = widget.currentDirPath.isEmpty
          ? oldName
          : '${widget.currentDirPath}/$oldName';
      final newFull = widget.currentDirPath.isEmpty
          ? uniqueName
          : '${widget.currentDirPath}/$uniqueName';
      final ok = await vaultExplorerApi.renameFile(widget.container, oldFull, newFull);
      if (ok) {
        successCount++;
        widget.onEntryRenamed?.call(oldFull, newFull);
      } else {
        failCount++;
      }
    }
    if (successCount > 0) widget.onSuccess();
    if (failCount > 0 && parentContext.mounted) {
      showAppSnackBar(
        parentContext,
        message: firstFailureReason != null
            ? l10n.couldntRenameMultiWithReason(failCount, firstFailureReason)
            : l10n.couldntRenameMultiNoReason(failCount),
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSingle
        ? context.l10n.rename
        : context.l10n.renameMultipleTitle(widget.oldEntries.length);
    final name = _ctrl.text;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: Text(context.l10n.advancedRenameButton),
            onPressed: () {
              Navigator.pop(context);
              BrowserDialogs.showAdvancedRename(
                context,
                container: widget.container,
                oldEntries: widget.oldEntries,
                existingEntries: widget.existingEntries,
                currentDirPath: widget.currentDirPath,
                onSuccess: widget.onSuccess,
                onEntryRenamed: widget.onEntryRenamed,
              );
            },
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _isSingle ? context.l10n.newNameHint : context.l10n.baseNameHint,
              ),
              inputFormatters: [IllegalCharacterInputFormatter(_fsType)],
              onChanged: _onChanged,
              onSubmitted: (_) => _onRename(),
            ),
            buildIssuesList(name),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: name.isNotEmpty && (_isSingle ? isValid : issues.isEmpty)
              ? _onRename
              : null,
          child: Text(context.l10n.rename),
        ),
      ],
    );
  }
}