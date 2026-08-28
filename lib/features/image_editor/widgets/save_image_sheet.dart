import 'package:flutter/material.dart';

import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';
import 'package:vaultexplorer/core/widgets/sheets/sheet_option_tile.dart';

/// What the user chose in [SaveImageSheet].
sealed class SaveImageChoice {
  const SaveImageChoice();
}

/// Write the edited image to a new file called [fileName], leaving the
/// original untouched.
class SaveAsNewFile extends SaveImageChoice {
  final String fileName;
  const SaveAsNewFile(this.fileName);
}

/// Replace the original file's bytes with the edited image.
class OverwriteOriginal extends SaveImageChoice {
  const OverwriteOriginal();
}

/// Bottom sheet offering how to save the image editor's current changes.
/// The actual write happens in the caller once this returns a choice --
/// this widget only decides *what* to write, plus (for the new-file case)
/// validates and de-conflicts the chosen name the same way every other
/// create/rename flow in the app does.
class SaveImageSheet extends StatefulWidget {
  final String suggestedFileName;
  final List<RawEntry> existingEntries;
  final FilesystemType fsType;
  final bool caseSensitive;

  const SaveImageSheet({
    super.key,
    required this.suggestedFileName,
    required this.existingEntries,
    required this.fsType,
    required this.caseSensitive,
  });

  static Future<SaveImageChoice?> show(
    BuildContext context, {
    required String suggestedFileName,
    required List<RawEntry> existingEntries,
    required FilesystemType fsType,
    required bool caseSensitive,
  }) {
    return showModalBottomSheet<SaveImageChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaveImageSheet(
        suggestedFileName: suggestedFileName,
        existingEntries: existingEntries,
        fsType: fsType,
        caseSensitive: caseSensitive,
      ),
    );
  }

  @override
  State<SaveImageSheet> createState() => _SaveImageSheetState();
}

enum _Step { choose, newFileName }

class _SaveImageSheetState extends State<SaveImageSheet> {
  _Step _step = _Step.choose;
  late final TextEditingController _nameController =
      TextEditingController(text: widget.suggestedFileName);
  List<NameValidationIssue> _issues = const [];
  EntryConflictResult _conflict = const EntryConflictResult(EntryConflictKind.none, null);

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_revalidate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revalidate());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _revalidate() {
    if (!mounted) return;
    final name = _nameController.text;
    final validation = validateEntryName(
      name,
      widget.fsType,
      entryType: EntryType.file,
      l10n: context.l10n,
    );
    final conflict = checkEntryConflict(
      candidateName: name,
      candidateIsDir: false,
      existingEntries: widget.existingEntries,
      caseSensitive: widget.caseSensitive,
    );
    setState(() {
      _issues = validation.issues;
      _conflict = conflict;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      child: _step == _Step.choose ? _buildChooseStep(context) : _buildNameStep(context),
    );
  }

  Widget _buildChooseStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.saveImageSheetTitle, style: context.typography.titleMedium),
        const SizedBox(height: 4),
        Text(
          l10n.imageEditorPngNoteMessage,
          style: context.typography.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SheetOptionTile(
          icon: Icons.note_add_outlined,
          title: l10n.saveAsNewFileOption,
          subtitle: l10n.saveAsNewFileDescription,
          onTap: () => setState(() => _step = _Step.newFileName),
        ),
        SheetOptionTile(
          icon: Icons.save_outlined,
          iconColor: context.colors.error,
          title: l10n.overwriteOriginalOption,
          subtitle: l10n.overwriteOriginalDescription,
          onTap: () => Navigator.of(context).pop(const OverwriteOriginal()),
        ),
      ],
    );
  }

  Widget _buildNameStep(BuildContext context) {
    final l10n = context.l10n;
    final hasIssues = _issues.isNotEmpty;
    final errorText = hasIssues
        ? _issues.first.message
        : _conflict.isConflict
            ? _conflict.message(l10n, _nameController.text)
            : null;
    final canSave = !hasIssues && !_conflict.isConflict && _nameController.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: l10n.backTooltip,
              onPressed: () => setState(() => _step = _Step.choose),
            ),
            Expanded(
              child: Text(l10n.saveAsNewFileOption, style: context.typography.titleMedium),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.newFileNameLabel,
                  errorText: errorText,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) {
                  if (canSave) {
                    Navigator.of(context).pop(SaveAsNewFile(_nameController.text));
                  }
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSave
                      ? () => Navigator.of(context).pop(SaveAsNewFile(_nameController.text))
                      : null,
                  child: Text(l10n.save),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
