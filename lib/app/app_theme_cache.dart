import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';

/// Remembers the last light and dark [ThemeData] so a rebuild with the same
/// skin inputs hands `MaterialApp` the identical object (a new-but-equal
/// theme would restart the theme animation).
///
/// One instance per `MaterialApp`: the main app and every secondary window
/// keep their own, but all of them build the theme the same way.
class AppThemeCache {
  Object? _lightThemeKey;
  ThemeData? _cachedLightTheme;
  Object? _darkThemeKey;
  ThemeData? _cachedDarkTheme;

  ThemeData lightThemeFor({
    required ColorScheme? dynamicScheme,
    required AppSkinPreset skinPreset,
    required dynamic customSkin,
    required dynamic manualFileManagerSkin,
    required bool fileManagerFollowsAppSkin,
    required bool editorFollowsAppSkin,
  }) {
    final key = (
      dynamicScheme,
      skinPreset,
      customSkin,
      manualFileManagerSkin,
      fileManagerFollowsAppSkin,
      editorFollowsAppSkin,
    );
    if (_cachedLightTheme != null && _lightThemeKey == key) {
      return _cachedLightTheme!;
    }
    _lightThemeKey = key;
    return _cachedLightTheme = buildLightTheme(
      dynamicScheme: dynamicScheme,
      appSkin: skinPreset,
      customAppSkin: customSkin,
      manualFileManagerSkin: manualFileManagerSkin,
      fileManagerFollowsAppSkin: fileManagerFollowsAppSkin,
      editorFollowsAppSkin: editorFollowsAppSkin,
    );
  }

  ThemeData darkThemeFor({
    required ColorScheme? dynamicScheme,
    required AppSkinPreset skinPreset,
    required dynamic customSkin,
    required dynamic manualFileManagerSkin,
    required bool fileManagerFollowsAppSkin,
    required bool editorFollowsAppSkin,
  }) {
    final key = (
      dynamicScheme,
      skinPreset,
      customSkin,
      manualFileManagerSkin,
      fileManagerFollowsAppSkin,
      editorFollowsAppSkin,
    );
    if (_cachedDarkTheme != null && _darkThemeKey == key) {
      return _cachedDarkTheme!;
    }
    _darkThemeKey = key;
    return _cachedDarkTheme = buildDarkTheme(
      dynamicScheme: dynamicScheme,
      appSkin: skinPreset,
      customAppSkin: customSkin,
      manualFileManagerSkin: manualFileManagerSkin,
      fileManagerFollowsAppSkin: fileManagerFollowsAppSkin,
      editorFollowsAppSkin: editorFollowsAppSkin,
    );
  }
}

/// The localization delegates every `MaterialApp` of this app uses.
final List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// `MaterialApp.localeResolutionCallback`: the device language if the app has
/// it, English otherwise.
Locale appResolveLocale(Locale? deviceLocale, Iterable<Locale> supported) {
  for (final locale in supported) {
    if (locale.languageCode == deviceLocale?.languageCode) return locale;
  }
  return const Locale('en');
}
