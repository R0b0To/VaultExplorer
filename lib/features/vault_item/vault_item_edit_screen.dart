import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/filesystem/illegal_char_input_formatter.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

import '../../core/filesystem/filesystem_type.dart';

class VaultItemEditScreen extends StatefulWidget {
  final MountedContainer container;
  final VaultItemType type;
  final VaultItem? existing; // null = new item
  
  
  final String? filePath; // Path if editing existing
  final String currentDirPath; // Destination dir if creating new

  const VaultItemEditScreen({
    super.key,
    required this.container,
    required this.type,
    this.existing,
    this.filePath,
    required this.currentDirPath,
  });

  @override
  State<VaultItemEditScreen> createState() => _VaultItemEditScreenState();
}

class _VaultItemEditScreenState extends State<VaultItemEditScreen> {
  late final TextEditingController _titleCtrl;
  late final List<VaultField> _fields;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, bool> _revealed = {};
  bool _saving = false;
  late final FilesystemType _fsType;
  bool _isContainerLocked = false;
  
  // Track initial values to determine if actual text edits occurred
  late final String _initialTitle;
  late final Map<String, String> _initialFieldValues;
  bool _wasDirty = false;
  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    final existing = widget.existing;
    
    _fsType = resolveFilesystemType(widget.container);
    _initialTitle = existing?.title ?? '';
    _titleCtrl = TextEditingController(text: _initialTitle);
    _titleCtrl.addListener(_onTextChanged);

    _fields = VaultItemTemplate.fieldsFor(widget.type, context.l10n)
        .map((t) => VaultField.fromTemplate(t, existing?.fields ?? {}))
        .toList();

    _initialFieldValues = {};
    for (final f in _fields) {
      final val = f.value;
      _initialFieldValues[f.key] = val;

      final ctrl = TextEditingController(text: val);
      ctrl.addListener(_onTextChanged);
      _ctrls[f.key] = ctrl;
      _revealed[f.key] = false;
    }
  }

  @override
  void dispose() {
     VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    _titleCtrl.removeListener(_onTextChanged);
    _titleCtrl.dispose();
    for (final c in _ctrls.values) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }

  // Determines if the form's current values differ from the initial ones
  bool get _isDirty {
    if (_titleCtrl.text != _initialTitle) return true;
    for (final f in _fields) {
      final currentVal = _ctrls[f.key]?.text ?? '';
      final initialVal = _initialFieldValues[f.key] ?? '';
      if (currentVal != initialVal) return true;
    }
    return false;
  }

  // Only triggers setState when transitioning between dirty and clean states
  void _onTextChanged() {
    final currentlyDirty = _isDirty;
    if (currentlyDirty != _wasDirty) {
      setState(() {
        _wasDirty = currentlyDirty;
      });
    }
  }

  bool get _isNew => widget.existing == null;

  /// The title doubles as the on-disk file name (with `.{type}` appended —
  /// see [_save]), so it's validated as one here rather than mutated. See
  /// docs/architecture.md ADR-002: this used to run through
  /// `sanitizeFatFileName`, which silently rewrote illegal characters —
  /// the title displayed in the UI and the name actually saved to disk
  /// were both derived from the user's input, but no longer matched each
  /// other. Now an invalid title is rejected with the specific reason
  /// instead.
  bool _validate() {
    if (_titleCtrl.text.isEmpty) {
      _showSnack(context.l10n.titleRequired);
      return false;
    }
    final desiredName = '${_titleCtrl.text}.${widget.type.name}';
    final result = validateEntryName(desiredName, _fsType, entryType: EntryType.file, l10n: context.l10n);
    if (result.issues.isNotEmpty) {
      _showSnack(result.issues.first.message);
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);

    final fieldMap = {
      for (final f in _fields) f.key: _ctrls[f.key]?.text.trim() ?? '',
    };

    final newTitle = _titleCtrl.text;

    String finalPath = widget.filePath ?? '';

    final destDirPath = _isNew
        ? widget.currentDirPath
        : (widget.filePath!.contains('/')
            ? widget.filePath!.substring(0, widget.filePath!.lastIndexOf('/'))
            : '');

    final existingRaw =
        await vaultExplorerApi.listDirectory(widget.container, destDirPath) ?? [];
    final existingNames = existingRaw
        .where((e) => !e.startsWith('System:'))
        .map((e) => RawEntry.parse(e).name.toLowerCase())
        .toSet();

    if (_isNew) {
      final desiredName = '$newTitle.${widget.type.name}';
      final uniqueName = FileOperationService.makeUniqueName(desiredName, existingNames);
      finalPath = destDirPath.isEmpty ? uniqueName : '$destDirPath/$uniqueName';
    } else if (widget.existing!.title != newTitle) {
      final oldPath = widget.filePath!;
      final oldName = oldPath.contains('/')
          ? oldPath.substring(oldPath.lastIndexOf('/') + 1)
          : oldPath;

      final namesExcludingSelf = existingNames.difference({oldName.toLowerCase()});

      final desiredName = '$newTitle.${widget.type.name}';
      final uniqueName = FileOperationService.makeUniqueName(desiredName, namesExcludingSelf);
      final newPath = destDirPath.isEmpty ? uniqueName : '$destDirPath/$uniqueName';

      await vaultExplorerApi.renameFile(widget.container, oldPath, newPath);
      finalPath = newPath;
    }

    final item = _isNew
        ? VaultItem.create(widget.type, newTitle).copyWithFields(fieldMap, newTitle)
        : widget.existing!.copyWithFields(fieldMap, newTitle);

    final ok = await VaultItemsService.instance.saveItem(widget.container, finalPath, item);

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.pop(context, finalPath);
    } else {
      _showSnack(context.l10n.failedToSaveCheckMounted);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_wasDirty) return true;

    return showAppConfirmDialog(
      context,
      title: context.l10n.discardChangesTitle,
      message: context.l10n.discardChangesMessage,
      confirmLabel: context.l10n.discard,
      cancelLabel: context.l10n.keepEditing,
      isDestructive: true,
    );
  }

  void _showSnack(String msg) {
    showAppSnackBar(context, message: msg, tone: AppBannerTone.error);
  }

  @override
  Widget build(BuildContext context) {
     if (_isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_wasDirty, 
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldDiscard = await _confirmDiscard();
        if (shouldDiscard && context.mounted) {
          Navigator.pop(context); 
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? context.l10n.newTypeTitle(widget.type.label(context.l10n)) : context.l10n.editItemTitle(widget.existing!.title)),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else
              TextButton(
                onPressed: _save,
                child: Text(context.l10n.save, style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            // ── Title ───────────────────────────────────────────────────────
            SectionLabel(context.l10n.titleSectionLabel),
            TextField(
              controller: _titleCtrl,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [IllegalCharacterInputFormatter(_fsType)],
              decoration: InputDecoration(
                hintText: context.l10n.typeNameHint(widget.type.label(context.l10n)),
                prefixIcon: Icon(Icons.label_outline_rounded, size: AppIconSize.small, color: cs.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 24),
            SectionLabel(context.l10n.fieldsSectionLabel),

            // ── Fields ──────────────────────────────────────────────────────
            ...(_fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FieldInput(
                field: f,
                controller: _ctrls[f.key]!,
                revealed: _revealed[f.key] ?? false,
                onToggleReveal: () => setState(() => _revealed[f.key] = !(_revealed[f.key] ?? false)),
              ),
            ))),

            // ── Custom fields hint ────────────────────────────────────────
            const SizedBox(height: 8),
            Center(
              child: Text(
                context.l10n.encryptedStorageHint,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Field input widget ────────────────────────────────────────────────────────

class _FieldInput extends StatelessWidget {
  final VaultField field;
  final TextEditingController controller;
  final bool revealed;
  final VoidCallback onToggleReveal;

  const _FieldInput({
    required this.field,
    required this.controller,
    required this.revealed,
    required this.onToggleReveal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSecret = field.type == FieldType.secret;
    final isMultiline = field.type == FieldType.multiline;
    final obscure = isSecret && !revealed;

    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: isMultiline ? null : 1,
      minLines: isMultiline ? 12 : 1,
      keyboardType: _keyboardType(field.type),
      textCapitalization: field.type == FieldType.multiline
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: field.label,
        suffixIcon: isSecret
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PasswordVisibilityToggle(
                    obscured: !revealed,
                    onToggle: onToggleReveal,
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: AppIconSize.small),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: controller.text));

                      showAppSnackBar(
                        context,
                        message: context.l10n.copiedSuffix(field.label),
                        tone: AppBannerTone.success,
                      );
                    },
                    tooltip: context.l10n.copy,
                  ),
                ],
              )
            : null,
        alignLabelWithHint: isMultiline,
      ),
    );
  }

  TextInputType _keyboardType(FieldType type) => switch (type) {
    FieldType.email  => TextInputType.emailAddress,
    FieldType.phone  => TextInputType.phone,
    FieldType.url    => TextInputType.url,
    FieldType.number => TextInputType.number,
    FieldType.multiline => TextInputType.multiline,
    _ => TextInputType.text,
  };

  IconData _prefixIcon(FieldType type) => switch (type) {
    FieldType.secret    => Icons.lock_outline_rounded,
    FieldType.email     => Icons.email_outlined,
    FieldType.phone     => Icons.phone_outlined,
    FieldType.url       => Icons.link_rounded,
    FieldType.number    => Icons.numbers_rounded,
    FieldType.multiline => Icons.notes_rounded,
    FieldType.date      => Icons.calendar_today_outlined,
    FieldType.text      => Icons.text_fields_rounded,
  };
}