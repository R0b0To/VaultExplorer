import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';
import 'package:vaultexplorer/features/video_editor/models/video_edit_math.dart';
import 'package:vaultexplorer/features/video_editor/widgets/video_export_sheet.dart'
    show VideoExportChoice;

/// Bottom sheet shown when the user taps Export in the audio editor. Returns
/// the video editor's [VideoExportChoice] (merge / replace original / name):
/// the choices are the same, only the wording differs.
class AudioExportSheet extends StatefulWidget {
  final int clipCount;
  final int totalDurationUs;
  final String defaultBaseName;
  final String extension;
  final bool isReadOnly;

  /// The cut will be decoded and re-encoded (not copied), so the note under the
  /// options says that instead of promising lossless output.
  final bool reencode;

  const AudioExportSheet({
    super.key,
    required this.clipCount,
    required this.totalDurationUs,
    required this.defaultBaseName,
    required this.extension,
    this.isReadOnly = false,
    this.reencode = false,
  });

  static Future<VideoExportChoice?> show(
    BuildContext context, {
    required int clipCount,
    required int totalDurationUs,
    required String defaultBaseName,
    required String extension,
    bool isReadOnly = false,
    bool reencode = false,
  }) {
    return showModalBottomSheet<VideoExportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AudioExportSheet(
        clipCount: clipCount,
        totalDurationUs: totalDurationUs,
        defaultBaseName: defaultBaseName,
        extension: extension,
        isReadOnly: isReadOnly,
        reencode: reencode,
      ),
    );
  }

  @override
  State<AudioExportSheet> createState() => _AudioExportSheetState();
}

class _AudioExportSheetState extends State<AudioExportSheet> {
  late bool _merge = widget.clipCount > 1;
  bool _replaceOriginal = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultBaseName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final customName = _nameController.text.trim();
    Navigator.pop(
      context,
      VideoExportChoice(
        merge: widget.clipCount <= 1 ? false : _merge,
        replaceOriginal: _replaceOriginal,
        customName: (_replaceOriginal || customName.isEmpty)
            ? null
            : customName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final text = context.typography;
    final isSingleClip = widget.clipCount <= 1;

    return AppBottomSheet(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l10n.videoEditorExportTitle, style: text.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  l10n.videoEditorExportSummary(
                    widget.clipCount,
                    formatTimecode(widget.totalDurationUs, millis: false),
                  ),
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),

              // Several clips: one merged file, or one file each.
              if (!isSingleClip && !_replaceOriginal) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.merge_type_rounded),
                        label: Text(l10n.audioEditorExportMerge),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.library_music_outlined),
                        label: Text(l10n.audioEditorExportSeparate),
                      ),
                    ],
                    selected: {_merge},
                    onSelectionChanged: (s) => setState(() => _merge = s.first),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (!widget.isReadOnly) ...[
                SwitchListTile(
                  title: Text(l10n.audioEditorReplaceOriginal),
                  subtitle: Text(
                    l10n.audioEditorReplaceOriginalHint,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  value: _replaceOriginal,
                  onChanged: (val) {
                    setState(() {
                      _replaceOriginal = val;
                      // Replacing the original needs everything in one file.
                      if (val) _merge = true;
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],

              if (!_replaceOriginal) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.videoEditorCustomFileName,
                      suffixText: '.${widget.extension}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  widget.reencode
                      ? l10n.audioEditorReencodeNote
                      : l10n.audioEditorLosslessNote,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(
                    _replaceOriginal
                        ? l10n.audioEditorReplaceOriginal
                        : l10n.videoEditorExportAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
