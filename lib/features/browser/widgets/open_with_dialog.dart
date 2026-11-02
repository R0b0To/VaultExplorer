import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

typedef OpenWithChoice = ({
  String? action, // 'editor' | 'media' | 'external' | 'open_as' | null
  bool remember,
  String? mimeType, // only meaningful when action == 'open_as'
  // Only meaningful when action == 'open_as': true when the user asked for
  // the system app chooser (with [mimeType] as the type hint) instead of
  // trying the in-app viewer for that type.
  bool openExternally,
});

typedef _OpenAsPick = ({String mimeType, bool external});

/// Result of [OpenWithDialog.showApkChooser]. [action] is `'installer'`,
/// `'archive'`, or null when the dialog was dismissed.
typedef ApkOpenChoice = ({String? action, bool remember});

class OpenWithDialog {
  const OpenWithDialog._();

  /// Asks what to do with an `.apk`: hand it to the system package installer
  /// or open it as a ZIP archive. An APK is both, so this is shown instead of
  /// guessing. [ext] is only used for the "remember" checkbox label.
  static Future<ApkOpenChoice> showApkChooser(
    BuildContext context, {
    required String fileName,
    required String ext,
  }) async {
    bool remember = false;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;

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
                      context.l10n.alwaysRememberChoiceExt(ext),
                      style: textTheme.bodySmall ?? textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );

            final tiles = [
              _ActionTile(
                icon: Icons.android_rounded,
                iconColor: cs.primary,
                title: context.l10n.apkOpenPackageInstaller,
                subtitle: context.l10n.apkOpenPackageInstallerSubtitle,
                dense: isLandscape,
                onTap: () => Navigator.of(context).pop('installer'),
              ),
              _ActionTile(
                icon: Icons.folder_zip_outlined,
                iconColor: cs.secondary,
                title: context.l10n.apkOpenAsZip,
                subtitle: context.l10n.apkOpenAsZipSubtitle,
                dense: isLandscape,
                onTap: () => Navigator.of(context).pop('archive'),
              ),
            ];

            return AlertDialog(
              scrollable: true,
              constraints: BoxConstraints(maxWidth: isLandscape ? 640 : 420),
              title: isLandscape ? null : Text(context.l10n.openFileDialogTitle),
              content: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              tiles[0],
                              const SizedBox(height: 8),
                              tiles[1],
                            ],
                          ),
                        ),
                      ],
                    )
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

    return (action: result, remember: remember);
  }

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
                onTap: () => Navigator.of(context).pop(
                  isMedia ? 'media' : 'editor',
                ),
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
      return (
        action: result,
        remember: remember,
        mimeType: null,
        openExternally: false,
      );
    }
    if (!context.mounted) {
      return (
        action: 'open_as',
        remember: remember,
        mimeType: null,
        openExternally: false,
      );
    }

   // --- Dialog 2: Choose the type to open the file as ---
    // Tapping a card tries the app's own viewer for that type. The trailing
    // tonal button hands the file to another app with that MIME type hint.
    // "Other" has no in-app counterpart, so both open externally.
    final pick = await showDialog<_OpenAsPick>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;

        Widget row({
          required IconData icon,
          required String title,
          required String mimeType,
          bool inApp = true,
        }) {
          final externalButton = IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            tooltip: context.l10n.fileAssocExternalApp,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              foregroundColor: cs.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(
              (mimeType: mimeType, external: true),
            ),
          );

          return Padding(
            padding: EdgeInsets.symmetric(vertical: isLandscape ? 2 : 3),
            child: Material(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(
                  (mimeType: mimeType, external: !inApp),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isLandscape ? 7 : 9,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      externalButton,
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final mimeTiles = [
          row(
            icon: Icons.text_fields_rounded,
            title: context.l10n.mimeTypeText,
            mimeType: 'text/plain',
          ),
          row(
            icon: Icons.image_outlined,
            title: context.l10n.mimeTypeImage,
            mimeType: 'image/*',
          ),
          row(
            icon: Icons.ondemand_video_outlined,
            title: context.l10n.mimeTypeVideo,
            mimeType: 'video/*',
          ),
          row(
            icon: Icons.audio_file_outlined,
            title: context.l10n.mimeTypeAudio,
            mimeType: 'audio/*',
          ),
          row(
            icon: Icons.archive_outlined,
            title: context.l10n.mimeTypeArchive,
            mimeType: 'application/zip',
          ),
          row(
            icon: Icons.insert_drive_file_outlined,
            title: context.l10n.mimeTypeOther,
            mimeType: '*/*',
            inApp: false,
          ),
        ];

        return AlertDialog(
          scrollable: true,
          constraints: BoxConstraints(
            minWidth: isLandscape ? 500 : 290,
            maxWidth: isLandscape ? 580 : 360,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.openAsDialogTitle),
              const SizedBox(height: 4),
              Text(
                context.l10n.chooseFileTypeToOpenAs,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: isLandscape ? 500 : 290,
            child: isLandscape
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

    return (
      action: 'open_as',
      remember: remember,
      mimeType: pick?.mimeType,
      openExternally: pick?.external ?? false,
    );
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