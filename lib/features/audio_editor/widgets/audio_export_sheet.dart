import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';
import 'package:vaultexplorer/features/audio_editor/models/audio_compression.dart';
import 'package:vaultexplorer/features/video_editor/models/video_edit_math.dart';

/// What the user picked in [AudioExportSheet]: the same merge / replace
/// original / name choices as the video editor's export sheet, plus whether to
/// re-encode at a lower bitrate to make the file smaller.
class AudioExportChoice {
  final bool merge;
  final bool replaceOriginal;
  final String? customName;
  final AudioCompression compression;

  const AudioExportChoice({
    required this.merge,
    required this.replaceOriginal,
    this.customName,
    this.compression = AudioCompression.off,
  });
}

/// Bottom sheet shown when the user taps Export in the audio editor. Returns
/// an [AudioExportChoice], or null if it was dismissed.
class AudioExportSheet extends StatefulWidget {
  final int clipCount;
  final int totalDurationUs;
  final String defaultBaseName;
  final String extension;
  final bool isReadOnly;

  /// The cut will be decoded and re-encoded (not copied), so the note under the
  /// options says that instead of promising lossless output.
  final bool reencode;

  /// The "reduce file size" choices on offer, [AudioCompression.off] first.
  /// With only that one, the whole section is hidden.
  final List<AudioCompression> compressionOptions;

  /// Source channel count and bitrate (when known), for the size estimate and
  /// to label each option with the bitrate it will really produce.
  final int? sourceChannels;
  final int? sourceBitrate;

  const AudioExportSheet({
    super.key,
    required this.clipCount,
    required this.totalDurationUs,
    required this.defaultBaseName,
    required this.extension,
    this.isReadOnly = false,
    this.reencode = false,
    this.compressionOptions = const [AudioCompression.off],
    this.sourceChannels,
    this.sourceBitrate,
  });

  static Future<AudioExportChoice?> show(
    BuildContext context, {
    required int clipCount,
    required int totalDurationUs,
    required String defaultBaseName,
    required String extension,
    bool isReadOnly = false,
    bool reencode = false,
    List<AudioCompression> compressionOptions = const [AudioCompression.off],
    int? sourceChannels,
    int? sourceBitrate,
  }) {
    return showModalBottomSheet<AudioExportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AudioExportSheet(
        clipCount: clipCount,
        totalDurationUs: totalDurationUs,
        defaultBaseName: defaultBaseName,
        extension: extension,
        isReadOnly: isReadOnly,
        reencode: reencode,
        compressionOptions: compressionOptions,
        sourceChannels: sourceChannels,
        sourceBitrate: sourceBitrate,
      ),
    );
  }

  @override
  State<AudioExportSheet> createState() => _AudioExportSheetState();
}

class _AudioExportSheetState extends State<AudioExportSheet> {
  late bool _merge = widget.clipCount > 1;
  bool _replaceOriginal = false;
  AudioCompression _compression = AudioCompression.off;
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
      AudioExportChoice(
        merge: widget.clipCount <= 1 ? false : _merge,
        replaceOriginal: _replaceOriginal,
        customName: (_replaceOriginal || customName.isEmpty)
            ? null
            : customName,
        compression: _compression,
      ),
    );
  }

  /// The extension the file will really get: a compressed export is always
  /// an `.m4a`, whatever the source was.
  String get _outputExtension =>
      _compression.isOn ? AudioCompression.outputExtension : widget.extension;

  /// "Estimated size: about 14 MB" for the current choice, or null when it
  /// can't be told (a source with an unknown bitrate, or a format whose
  /// re-encode bitrate isn't known up front).
  int? get _estimatedBytes {
    if (_compression.isOn) {
      return _compression.estimatedBytes(
        durationUs: widget.totalDurationUs,
        sourceChannels: widget.sourceChannels,
      );
    }
    final bitrate = widget.sourceBitrate;
    if (widget.reencode || bitrate == null || bitrate <= 0) return null;
    if (widget.totalDurationUs <= 0) return null;
    return (bitrate * (widget.totalDurationUs / 1000000) / 8).round();
  }

  String _compressionLabel(AudioCompression c) {
    final total = c.totalBitrate(widget.sourceChannels);
    if (total == null) return context.l10n.audioEditorCompressOriginal;
    return '${(total / 1000).round()} kbps';
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

              // Smaller file: re-encode at a lower bitrate.
              if (widget.compressionOptions.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    l10n.audioEditorCompressTitle,
                    style: text.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<AudioCompression>(
                    showSelectedIcon: false,
                    segments: [
                      for (final c in widget.compressionOptions)
                        ButtonSegment(
                          value: c,
                          label: Text(_compressionLabel(c)),
                        ),
                    ],
                    selected: {_compression},
                    onSelectionChanged: (s) =>
                        setState(() => _compression = s.first),
                  ),
                ),
                if (_estimatedBytes != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      l10n.audioEditorCompressEstimate(
                        formatBytes(_estimatedBytes!),
                      ),
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
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
                      suffixText: '.$_outputExtension',
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
                  _compression.isOn
                      ? l10n.audioEditorCompressNote
                      : widget.reencode
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
