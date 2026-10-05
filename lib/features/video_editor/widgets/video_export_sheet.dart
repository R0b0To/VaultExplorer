import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';

import '../models/video_edit_math.dart';

/// What the user chose in [VideoExportSheet].
class VideoExportChoice {
  /// Join every clip into one file (true) or write one file per clip (false).
  final bool merge;

  /// Replace / overwrite original source file instead of saving as a new file.
  final bool replaceOriginal;

  /// Custom base file name (without extension), or null for automatic default.
  final String? customName;

  const VideoExportChoice({
    required this.merge,
    this.replaceOriginal = false,
    this.customName,
  });
}

/// Bottom sheet shown when the user taps Export.
class VideoExportSheet extends StatefulWidget {
  final int clipCount;
  final int totalDurationUs;
  final String defaultBaseName;
  final String extension;
  final bool isReadOnly;
  final bool hasSubtitles;

  const VideoExportSheet({
    super.key,
    required this.clipCount,
    required this.totalDurationUs,
    required this.defaultBaseName,
    required this.extension,
    this.isReadOnly = false,
    this.hasSubtitles = false,
  });

  static Future<VideoExportChoice?> show(
    BuildContext context, {
    required int clipCount,
    required int totalDurationUs,
    required String defaultBaseName,
    required String extension,
    bool isReadOnly = false,
    bool hasSubtitles = false,
  }) {
    return showModalBottomSheet<VideoExportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VideoExportSheet(
        clipCount: clipCount,
        totalDurationUs: totalDurationUs,
        defaultBaseName: defaultBaseName,
        extension: extension,
        isReadOnly: isReadOnly,
        hasSubtitles: hasSubtitles,
      ),
    );
  }

  @override
  State<VideoExportSheet> createState() => _VideoExportSheetState();
}

class _VideoExportSheetState extends State<VideoExportSheet> {
  late bool _merge = true;
  late bool _replaceOriginal = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _merge = widget.clipCount > 1;
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
        customName: (_replaceOriginal || customName.isEmpty) ? null : customName,
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
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
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

              // Multiple clips: Merge vs Separate toggle
              if (!isSingleClip && !_replaceOriginal) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.merge_type_rounded),
                        label: Text(l10n.videoEditorExportMerge),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.video_library_outlined),
                        label: Text(l10n.videoEditorExportSeparate),
                      ),
                    ],
                    selected: {_merge},
                    onSelectionChanged: (s) => setState(() => _merge = s.first),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Replace original toggle (only if not read-only)
              if (!widget.isReadOnly) ...[
                SwitchListTile(
                  title: Text(l10n.videoEditorReplaceOriginal),
                  subtitle: Text(
                    l10n.videoEditorReplaceOriginalHint,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  value: _replaceOriginal,
                  onChanged: (val) {
                    setState(() {
                      _replaceOriginal = val;
                      if (val) _merge = true;
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],

              // Custom File Name input (hidden if replacing original)
              if (!_replaceOriginal) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

              // Subtitles Warning if video has subtitle tracks
              if (widget.hasSubtitles) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.subtitles_off_rounded, size: 20, color: cs.onTertiaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.videoEditorSubtitlesWarning,
                            style: text.bodySmall?.copyWith(color: cs.onTertiaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Lossless note
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  l10n.videoEditorLosslessNote,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),

              // Export submit button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(
                    _replaceOriginal ? l10n.videoEditorReplaceOriginal : l10n.videoEditorExportAction,
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
