import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class ArchivePasteOptions {
  final bool extractIntoSubfolder;
  final bool deleteSourceAfter;

  const ArchivePasteOptions({
    this.extractIntoSubfolder = true,
    this.deleteSourceAfter = false,
  });
}

class ArchivePasteOptionsSheet extends StatefulWidget {
  final bool isExtract;
  final String archiveName;
  final String destDirPath;
  final bool isPartialExtract;
  final int itemCount;

  const ArchivePasteOptionsSheet({
    super.key,
    required this.isExtract,
    required this.archiveName,
    required this.destDirPath,
    this.isPartialExtract = false,
    this.itemCount = 1,
  });

  static Future<ArchivePasteOptions?> show(
    BuildContext context, {
    required bool isExtract,
    required String archiveName,
    required String destDirPath,
    bool isPartialExtract = false,
    int itemCount = 1,
  }) {
    return showModalBottomSheet<ArchivePasteOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ArchivePasteOptionsSheet(
        isExtract: isExtract,
        archiveName: archiveName,
        destDirPath: destDirPath,
        isPartialExtract: isPartialExtract,
        itemCount: itemCount,
      ),
    );
  }

  @override
  State<ArchivePasteOptionsSheet> createState() =>
      _ArchivePasteOptionsSheetState();
}

class _ArchivePasteOptionsSheetState extends State<ArchivePasteOptionsSheet> {
  bool _extractIntoSubfolder = true;
  bool _deleteSourceAfter = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final folderStem = p.basenameWithoutExtension(widget.archiveName);
    final targetFolderLabel = widget.destDirPath.isEmpty
        ? context.l10n.rootFolderLabel
        : widget.destDirPath;

    final String titleText;
    if (widget.isExtract) {
      titleText = widget.isPartialExtract
          ? '${context.l10n.extract} (${context.l10n.fileOpItemsCount(widget.itemCount)})'
          : context.l10n.extractArchive;
    } else {
      titleText = context.l10n.createArchiveTitle;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  widget.isExtract ? Icons.unarchive_rounded : Icons.archive_rounded,
                  color: cs.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titleText,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.isPartialExtract
                  ? context.l10n.clipboardSourceLabel(widget.archiveName)
                  : widget.archiveName,
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            if (widget.isExtract) ...[
              const SizedBox(height: 8),
              RadioListTile<bool>(
                title: Text('${context.l10n.extract} → $folderStem/'),
                subtitle: Text('$targetFolderLabel/$folderStem/'),
                value: true,
                groupValue: _extractIntoSubfolder,
                onChanged: (v) => setState(() => _extractIntoSubfolder = v ?? true),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                title: Text('${context.l10n.extract} → $targetFolderLabel/'),
                subtitle: Text('$targetFolderLabel/'),
                value: false,
                groupValue: _extractIntoSubfolder,
                onChanged: (v) => setState(() => _extractIntoSubfolder = v ?? false),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 1),
            ],
            if (!widget.isPartialExtract)
              SwitchListTile(
                title: Text(
                  widget.isExtract
                      ? '${context.l10n.deleteOriginalButton} (${widget.archiveName})'
                      : context.l10n.deleteOriginalButton,
                ),
                value: _deleteSourceAfter,
                onChanged: (v) => setState(() => _deleteSourceAfter = v),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      ArchivePasteOptions(
                        extractIntoSubfolder: _extractIntoSubfolder,
                        deleteSourceAfter: _deleteSourceAfter,
                      ),
                    ),
                    child: Text(
                      widget.isExtract ? context.l10n.extract : context.l10n.create,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}