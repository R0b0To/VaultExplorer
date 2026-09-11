import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

/// Result of [OpenWithDialog.show] -- mirrors the two chained dialogs
/// `_showOpenWithDialog` previously built inline in file_browser_screen.dart
/// (first pick an action; if that action is "open as", pick a MIME type
/// next). [action] is `null` if the person dismissed the first dialog
/// without choosing anything, in which case [remember] and [mimeType] are
/// meaningless -- the caller does nothing, exactly as the original's
/// `result` not matching any `if`/`else if` branch did nothing.
///
/// [remember] is only ever true for the `'editor'`/`'media'`/`'external'`
/// actions -- the original's "open as" branch never read the checkbox
/// state at all, a quirk preserved here rather than "fixed", since a
/// person picking "open as" for a one-off MIME type most likely wasn't
/// intending to permanently remember that choice for the extension.
typedef OpenWithChoice = ({
  String? action, // 'editor' | 'media' | 'external' | 'open_as' | null
  bool remember,
  String? mimeType, // only meaningful when action == 'open_as'
});

class OpenWithDialog {
  const OpenWithDialog._();

  static Future<OpenWithChoice> show(
    BuildContext context, {
    required String fileName,
    required String ext,
  }) async {
    bool remember = false;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMedia = MediaViewerConstants.isSupported(fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.l10n.openFileDialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.chooseHowToOpen(fileName),
                    style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(isMedia ? 'media' : 'editor'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMedia ? Icons.play_circle_outline_rounded : Icons.edit_note_rounded,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMedia
                                      ? context.l10n.fileAssocInAppMediaViewer
                                      : context.l10n.fileAssocInAppTextEditor,
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  isMedia
                                      ? context.l10n.playVideoAudioViewImageInApp
                                      : context.l10n.viewEditTextMarkdownCode,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop('external'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new_rounded, color: cs.secondary, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.fileAssocExternalApp,
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  context.l10n.sendFileToThirdPartyApp,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop('open_as'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.app_registration_rounded, color: cs.secondary, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.openAsEllipsis,
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  context.l10n.chooseFileTypeToOpenAs,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: remember,
                        onChanged: (val) {
                          setDialogState(() {
                            remember = val ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          ext.isNotEmpty
                              ? context.l10n.alwaysRememberChoiceExt(ext)
                              : context.l10n.alwaysRememberChoiceNoExt,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != 'open_as') {
      return (action: result, remember: remember, mimeType: null);
    }
    if (!context.mounted) {
      return (action: 'open_as', remember: remember, mimeType: null);
    }
    final mimeType = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.openAsDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_fields_rounded),
                title: Text(context.l10n.mimeTypeText),
                onTap: () => Navigator.of(context).pop('text/plain'),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(context.l10n.mimeTypeImage),
                onTap: () => Navigator.of(context).pop('image/*'),
              ),
              ListTile(
                leading: const Icon(Icons.ondemand_video_outlined),
                title: Text(context.l10n.mimeTypeVideo),
                onTap: () => Navigator.of(context).pop('video/*'),
              ),
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: Text(context.l10n.mimeTypeAudio),
                onTap: () => Navigator.of(context).pop('audio/*'),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(context.l10n.mimeTypeArchive),
                onTap: () => Navigator.of(context).pop('application/zip'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(context.l10n.mimeTypeOther),
                onTap: () => Navigator.of(context).pop('*/*'),
              ),
            ],
          ),
        );
      },
    );
    return (action: 'open_as', remember: remember, mimeType: mimeType);
  }
}
