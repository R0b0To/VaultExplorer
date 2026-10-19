import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';

class ArchivePasteOptions {
  final bool extractIntoSubfolder;
  final bool deleteSourceAfter;
  final int splitSizeBytes;

  const ArchivePasteOptions({
    this.extractIntoSubfolder = true,
    this.deleteSourceAfter = false,
    this.splitSizeBytes = 0,
  });
}

class ArchivePasteOptionsSheet extends StatefulWidget {
  final bool isExtract;
  final String archiveName;
  final String destDirPath;
  final bool isPartialExtract;
  final int itemCount;
  final ArchiveFormatType? format;

  const ArchivePasteOptionsSheet({
    super.key,
    required this.isExtract,
    required this.archiveName,
    required this.destDirPath,
    this.isPartialExtract = false,
    this.itemCount = 1,
    this.format,
  });

  static Future<ArchivePasteOptions?> show(
    BuildContext context, {
    required bool isExtract,
    required String archiveName,
    required String destDirPath,
    bool isPartialExtract = false,
    int itemCount = 1,
    ArchiveFormatType? format,
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
        format: format,
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

  static const _mb = 1024 * 1024;
  static const _fat32PartMb = 4095;
  static const _splitPresetsMb = [100, 500];
  int _splitSizeBytes = 0;
  bool _splitCustom = false;
  late final TextEditingController _splitCustomCtrl;

  @override
  void initState() {
    super.initState();
    _splitCustomCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _splitCustomCtrl.dispose();
    super.dispose();
  }

  ArchiveFormatType get _effectiveFormat {
    if (widget.format != null) return widget.format!;
    final lower = widget.archiveName.toLowerCase();
    if (lower.endsWith('.7z')) return ArchiveFormatType.sevenZip;
    return ArchiveFormatType.zip;
  }

  bool get _supportsSplit => !widget.isExtract && _effectiveFormat.supportsSplit;

  int? get _customSplitMb {
    final mb = int.tryParse(_splitCustomCtrl.text.trim());
    if (mb == null || mb < 1 || mb > _fat32PartMb) return null;
    return mb;
  }

  int get _effectiveSplitBytes {
    if (!_supportsSplit) return 0;
    if (_splitCustom) return (_customSplitMb ?? 0) * _mb;
    return _splitSizeBytes;
  }

  bool get _splitValid =>
      !_splitCustom || !_supportsSplit || _customSplitMb != null;

  bool get _canSubmit => widget.isExtract || _splitValid;

  static String _splitPresetLabel(int mb) {
    if (mb == _fat32PartMb) return '4 GB (FAT32)';
    return mb % 1024 == 0 ? '${mb ~/ 1024} GB' : '$mb MB';
  }

  Widget _buildSplitSection(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final isZip = _effectiveFormat == ArchiveFormatType.zip;
    final active = _splitCustom || _splitSizeBytes > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.createArchiveSplitVolumes,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
           children: [
            ChoiceChip(
              showCheckmark: false,
              label: Text(l10n.createArchiveSplitVolumeNone),
              selected: !active,
              onSelected: (_) => setState(() {
                _splitSizeBytes = 0;
                _splitCustom = false;
              }),
            ),
            for (final mb in _splitPresetsMb)
              ChoiceChip(
                showCheckmark: false,
                label: Text(_splitPresetLabel(mb)),
                selected: !_splitCustom && _splitSizeBytes == mb * _mb,
                onSelected: (_) => setState(() {
                  _splitSizeBytes = mb * _mb;
                  _splitCustom = false;
                }),
              ),
            ChoiceChip(
              showCheckmark: false,
              label: Text(l10n.splitChunkSizeCustom),
              selected: _splitCustom,
              onSelected: (_) => setState(() {
                _splitCustom = true;
                _splitSizeBytes = 0;
              }),
            ),
          ],
        ),
        if (_splitCustom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _splitCustomCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              labelText: l10n.createArchiveCustomVolumeSizeLabel,
              hintText: l10n.createArchiveCustomVolumeSizeHint,
              errorText:
                  _splitCustomCtrl.text.isNotEmpty && _customSplitMb == null
                      ? '1 – $_fat32PartMb'
                      : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final folderStem = p.basenameWithoutExtension(widget.archiveName);
    final targetFolderLabel = widget.destDirPath.isEmpty
        ? context.l10n.rootFolderLabel
        : widget.destDirPath;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

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
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + viewInsetsBottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    widget.isExtract
                        ? Icons.unarchive_rounded
                        : Icons.archive_rounded,
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
                widget.isExtract
                    ? (widget.isPartialExtract
                        ? context.l10n.clipboardSourceLabel(widget.archiveName)
                        : widget.archiveName)
                    : '${widget.archiveName} → $targetFolderLabel/',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              if (widget.isExtract) ...[
                const SizedBox(height: 8),
                RadioGroup<bool>(
                  groupValue: _extractIntoSubfolder,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _extractIntoSubfolder = v);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<bool>(
                        title: Text('${context.l10n.extract} → $folderStem/'),
                        subtitle: Text('$targetFolderLabel/$folderStem/'),
                        value: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<bool>(
                        title: Text(
                          '${context.l10n.extract} → $targetFolderLabel/',
                        ),
                        subtitle: Text('$targetFolderLabel/'),
                        value: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ] else if (_supportsSplit) ...[
                const SizedBox(height: 12),
                _buildSplitSection(cs, textTheme),
                const SizedBox(height: 12),
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
                      onPressed: _canSubmit
                          ? () => Navigator.pop(
                              context,
                              ArchivePasteOptions(
                                extractIntoSubfolder: _extractIntoSubfolder,
                                deleteSourceAfter: _deleteSourceAfter,
                                splitSizeBytes: widget.isExtract
                                    ? 0
                                    : _effectiveSplitBytes,
                              ),
                            )
                          : null,
                      child: Text(
                        widget.isExtract
                            ? context.l10n.extract
                            : context.l10n.create,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}