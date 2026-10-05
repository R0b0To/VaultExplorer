import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';

import '../models/edit_segment.dart';
import '../models/video_edit_math.dart';
import '../video_editor_controller.dart';

/// Bottom sheet displaying the full list of segments, selection, and mode settings.
class VideoSegmentsSheet extends StatelessWidget {
  final VideoEditorController editor;
  final ValueChanged<int> onSeekTo;

  const VideoSegmentsSheet({
    super.key,
    required this.editor,
    required this.onSeekTo,
  });

  static Future<void> show(
    BuildContext context, {
    required VideoEditorController editor,
    required ValueChanged<int> onSeekTo,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VideoSegmentsSheet(
        editor: editor,
        onSeekTo: onSeekTo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final text = context.typography;

    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final segments = editor.segments;
        final selectedId = editor.selectedId;

        return AppBottomSheet(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        '${l10n.videoEditorSegments} (${segments.length})',
                        style: text.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Mode toggle (Keep vs Cut out)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<VideoEditMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: VideoEditMode.keep,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l10n.videoEditorModeKeep),
                      ),
                      ButtonSegment(
                        value: VideoEditMode.cutOut,
                        icon: const Icon(Icons.content_cut_rounded),
                        label: Text(l10n.videoEditorModeCutOut),
                      ),
                    ],
                    selected: {editor.mode},
                    onSelectionChanged: (s) => editor.setMode(s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Text(
                    editor.mode == VideoEditMode.keep
                        ? l10n.videoEditorKeepModeDescription
                        : l10n.videoEditorCutOutModeDescription,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),

                const Divider(),

                // Segments list — Flexible so it shrinks in landscape
                if (segments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        l10n.videoEditorNoSegments,
                        style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: segments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final s = segments[i];
                        final isSelected = s.id == selectedId;
                        return Material(
                          color: isSelected
                              ? cs.primaryContainer.withValues(alpha: 0.5)
                              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              editor.select(s.id);
                              onSeekTo(s.startUs);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isSelected ? cs.primary : cs.outlineVariant,
                                    foregroundColor: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${formatTimecode(s.startUs)} – ${formatTimecode(s.endUs)}',
                                          style: text.bodyMedium?.copyWith(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        Text(
                                          formatTimecode(s.lengthUs, millis: false),
                                          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    tooltip: l10n.videoEditorDeleteSegment,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      editor.select(s.id);
                                      editor.deleteSelected();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const Divider(),

                // Output total
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    l10n.videoEditorOutputSummary(
                      editor.plannedRanges.length,
                      formatTimecode(editor.totalSnappedUs, millis: false),
                    ),
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
