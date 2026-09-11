import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

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
    final isMedia = MediaViewerConstants.isSupported(fileName);

    // --- Dialog 1: Choose Action ---
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;

            // Common checkbox widget
            final rememberCheckbox = InkWell(
              onTap: () => setDialogState(() => remember = !remember),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Checkbox(
                    value: remember,
                    onChanged: (val) {
                      setDialogState(() => remember = val ?? false);
                    },
                  ),
                  Expanded(
                    child: Text(
                      ext.isNotEmpty
                          ? context.l10n.alwaysRememberChoiceExt(ext)
                          : context.l10n.alwaysRememberChoiceNoExt,
                      style: textTheme.bodySmall ?? textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );

            // The 3 action tiles
            final tiles = [
              _ActionTile(
                icon: isMedia
                    ? Icons.play_circle_outline_rounded
                    : Icons.edit_note_rounded,
                iconColor: cs.primary,
                title: isMedia
                    ? context.l10n.fileAssocInAppMediaViewer
                    : context.l10n.fileAssocInAppTextEditor,
                subtitle: isMedia
                    ? context.l10n.playVideoAudioViewImageInApp
                    : context.l10n.viewEditTextMarkdownCode,
                dense: isLandscape,
                onTap: () =>
                    Navigator.of(context).pop(isMedia ? 'media' : 'editor'),
              ),
              _ActionTile(
                icon: Icons.open_in_new_rounded,
                iconColor: cs.secondary,
                title: context.l10n.fileAssocExternalApp,
                subtitle: context.l10n.sendFileToThirdPartyApp,
                dense: isLandscape,
                onTap: () => Navigator.of(context).pop('external'),
              ),
              _ActionTile(
                icon: Icons.app_registration_rounded,
                iconColor: cs.secondary,
                title: context.l10n.openAsEllipsis,
                subtitle: context.l10n.chooseFileTypeToOpenAs,
                dense: isLandscape,
                onTap: () => Navigator.of(context).pop('open_as'),
              ),
            ];

            return AlertDialog(
              // Keep scrollable as a fallback for small screens/large font scaling
              scrollable: true,
              constraints: BoxConstraints(maxWidth: isLandscape ? 640 : 420),
              title: isLandscape ? null : Text(context.l10n.openFileDialogTitle),
              content: isLandscape
                  // Landscape: Two-pane split view
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Title, description, and preference checkbox
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.openFileDialogTitle,
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.l10n.chooseHowToOpen(fileName),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              rememberCheckbox,
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Right Pane: 3 action cards
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              tiles[0],
                              const SizedBox(height: 8),
                              tiles[1],
                              const SizedBox(height: 8),
                              tiles[2],
                            ],
                          ),
                        ),
                      ],
                    )
                  // Portrait: Standard vertical layout
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.l10n.chooseHowToOpen(fileName),
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        tiles[0],
                        const SizedBox(height: 12),
                        tiles[1],
                        const SizedBox(height: 12),
                        tiles[2],
                        const SizedBox(height: 16),
                        rememberCheckbox,
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

    // --- Dialog 2: Choose MIME Type ---
    final mimeType = await showDialog<String>(
      context: context,
      builder: (context) {
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;

        final mimeTiles = [
          ListTile(
            dense: isLandscape,
            leading: const Icon(Icons.text_fields_rounded),
            title: Text(context.l10n.mimeTypeText),
            onTap: () => Navigator.of(context).pop('text/plain'),
          ),
          ListTile(
            dense: isLandscape,
            leading: const Icon(Icons.image_outlined),
            title: Text(context.l10n.mimeTypeImage),
            onTap: () => Navigator.of(context).pop('image/*'),
          ),
          ListTile(
            dense: isLandscape,
            leading: const Icon(Icons.ondemand_video_outlined),
            title: Text(context.l10n.mimeTypeVideo),
            onTap: () => Navigator.of(context).pop('video/*'),
          ),
          ListTile(
            dense: isLandscape,
            leading: const Icon(Icons.audio_file_outlined),
            title: Text(context.l10n.mimeTypeAudio),
            onTap: () => Navigator.of(context).pop('audio/*'),
          ),
          ListTile(
            dense: isLandscape,
            leading: const Icon(Icons.archive_outlined),
            title: Text(context.l10n.mimeTypeArchive),
            onTap: () => Navigator.of(context).pop('application/zip'),
          ),
          ListTile(
            dense: isLandscape,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(context.l10n.mimeTypeOther),
            onTap: () => Navigator.of(context).pop('*/*'),
          ),
        ];

        return AlertDialog(
          scrollable: true,
          constraints: BoxConstraints(maxWidth: isLandscape ? 600 : 380),
          title: Text(context.l10n.openAsDialogTitle),
          content: isLandscape
              // Landscape: 2 columns of 3 items side-by-side
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: mimeTiles.sublist(0, 3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: mimeTiles.sublist(3, 6),
                      ),
                    ),
                  ],
                )
              // Portrait: Single vertical list
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: mimeTiles,
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

    return (action: 'open_as', remember: remember, mimeType: mimeType);
  }
}

/// Helper card component for consistent styling and adaptive sizing.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: dense ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: dense ? 24 : 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: dense ? 14 : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: dense ? 12 : null,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}