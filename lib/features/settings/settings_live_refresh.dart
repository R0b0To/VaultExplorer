import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_appearance_provider.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// Pushes settings that an import has just persisted into everything that is
/// already on screen.
///
/// Both imports end here: Settings -> Import (configuration) and App skin ->
/// Import (skins and interface). Pass the values the import actually
/// *persisted* -- the merged [AppSettings] and toolbar config it returns --
/// never the partial ones parsed from the file. Each export only carries half
/// of the settings, so the file on its own would reset the other half in
/// memory.
Future<void> refreshLiveSettings(
  WidgetRef ref,
  AppSettings settings,
  FileManagerToolbarConfig toolbarConfig,
) async {
  await ref
      .read(appSettingsControllerProvider.notifier)
      .applyImportedSettings(settings);
  await ref
      .read(appSkinSettingsProvider.notifier)
      .applyImportedSettings(settings);
  ref
      .read(fileManagerToolbarSettingsProvider(null).notifier)
      .applyImportedConfig(toolbarConfig);
  ref.invalidate(fileManagerToolbarSettingsProvider);
  ref.invalidate(textEditorAppearanceProvider);

  VeLog.enabled = settings.debugLoggingEnabled;
  appThemeModeNotifier.value = settings.themeMode;
  appUseDynamicColorNotifier.value = settings.useDynamicColor;
  appLocaleNotifier.value = settings.languageCode != null
      ? Locale(settings.languageCode!)
      : null;
}
