import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';

/// App-bar settings button: directly opens the file manager settings screen.
class SettingsMenuButton extends StatelessWidget {
  /// Called after returning from [FileManagerToolbarSettingsScreen].
  final Future<void> Function() onSettingsClosed;
  
  /// To pass to the settings screen for bookmark reordering.
  final String? containerUri;

  /// Whether the file manager this button sits on top of is browsing real
  /// device storage rather than an unlocked vault -- passed straight
  /// through to [FileManagerToolbarSettingsScreen], which uses it to
  /// decide whether to show the thumbnail-cache picker (see that screen's
  /// `isLocalStorage` doc).
  final bool isLocalStorage;

  const SettingsMenuButton({
    super.key,
    required this.onSettingsClosed,
    this.containerUri,
    this.isLocalStorage = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: context.l10n.settingsMenuItem,
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FileManagerToolbarSettingsScreen(
              containerUri: containerUri,
              isLocalStorage: isLocalStorage,
            ),
          ),
        );
        await onSettingsClosed();
      },
    );
  }
}