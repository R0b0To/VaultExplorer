import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/vaultexplorer_api.dart';

import '../../models/mounted_container.dart';
import '../../models/vault_item.dart';
import '../../services/vault_items_service.dart';

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
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _titleCtrl.addListener(() => setState(() => _dirty = true));

    _fields = VaultItemTemplate.fieldsFor(widget.type)
        .map((t) => VaultField.fromTemplate(t, existing?.fields ?? {}))
        .toList();

    for (final f in _fields) {
      final ctrl = TextEditingController(text: f.value);
      ctrl.addListener(() => setState(() => _dirty = true));
      _ctrls[f.key] = ctrl;
      _revealed[f.key] = false;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  bool get _isNew => widget.existing == null;

  bool _validate() {
    // Only the title is required now
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('Title is required');
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

    final newTitle = _titleCtrl.text.trim();
    final safeTitle = newTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    String finalPath = widget.filePath ?? '';

    if (_isNew) {
      String name = '$safeTitle.${widget.type.name}';
      finalPath = widget.currentDirPath.isEmpty ? name : '${widget.currentDirPath}/$name';
      
      int c = 1;
      while (await vaultExplorerApi.getFileSize(widget.container, finalPath) > 0) {
         name = '$safeTitle ($c).${widget.type.name}';
         finalPath = widget.currentDirPath.isEmpty ? name : '${widget.currentDirPath}/$name';
         c++;
      }
    } else if (widget.existing!.title != newTitle) {
      // Rename file on disk if title changed
      final oldPath = widget.filePath!;
      final dir = oldPath.contains('/') ? oldPath.substring(0, oldPath.lastIndexOf('/')) : '';
      
      String newName = '$safeTitle.${widget.type.name}';
      String tempPath = dir.isEmpty ? newName : '$dir/$newName';
      
      int c = 1;
      while (await vaultExplorerApi.getFileSize(widget.container, tempPath) > 0) {
         newName = '$safeTitle ($c).${widget.type.name}';
         tempPath = dir.isEmpty ? newName : '$dir/$newName';
         c++;
      }
      await vaultExplorerApi.renameFile(widget.container, oldPath, tempPath);
      finalPath = tempPath;
    }

    final item = _isNew
        ? VaultItem.create(widget.type, newTitle).copyWithFields(fieldMap, newTitle)
        : widget.existing!.copyWithFields(fieldMap, newTitle);

    final ok = await VaultItemsService.instance.saveItem(widget.container, finalPath, item);

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      // Return finalPath so caller knows if it was renamed
      Navigator.pop(context, finalPath);
    } else {
      _showSnack('Failed to save — check container is still mounted');
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

return PopScope(
      canPop: !_dirty, 
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldDiscard = await _confirmDiscard();
        if (shouldDiscard && context.mounted) {
          Navigator.pop(context); 
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New ${widget.type.label}' : 'Edit ${widget.existing!.title}'),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else
              TextButton(
                onPressed: _save,
                child: Text('Save', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // ── Title ───────────────────────────────────────────────────────
            _SectionLabel('TITLE'),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: '${widget.type.label} name',
                prefixIcon: Icon(Icons.label_outline_rounded, size: 18, color: cs.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 24),
            _SectionLabel('FIELDS'),
            const SizedBox(height: 8),

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
                'All fields are stored encrypted inside the container.',
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
      maxLines: isMultiline ? 5 : 1,
      minLines: isMultiline ? 3 : 1,
      keyboardType: _keyboardType(field.type),
      textCapitalization: field.type == FieldType.multiline
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: field.label, // Removed the `+ (field.required ? ' *' : '')`
        prefixIcon: Icon(_prefixIcon(field.type), size: 18, color: cs.onSurfaceVariant),
        suffixIcon: isSecret
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: onToggleReveal,
                    tooltip: revealed ? 'Hide' : 'Show',
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: controller.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${field.label} copied')),
                      );
                    },
                    tooltip: 'Copy',
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Text(
      label,
      style: textTheme.labelSmall?.copyWith(
        color: cs.primary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.4,
      ),
    );
  }
}