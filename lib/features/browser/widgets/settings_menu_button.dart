import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';

/// App-bar settings button: directly opens the file manager settings screen.
class SettingsMenuButton extends StatelessWidget {
  /// Called after returning from [FileManagerToolbarSettingsScreen].
  final Future<void> Function() onSettingsClosed;
  
  /// To pass to the settings screen for favourite reordering.
  final String? containerUri;

  const SettingsMenuButton({
    super.key,
    required this.onSettingsClosed,
    this.containerUri,
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
            builder: (_) => FileManagerToolbarSettingsScreen(containerUri: containerUri),
          ),
        );
        await onSettingsClosed();
      },
    );
  }
}