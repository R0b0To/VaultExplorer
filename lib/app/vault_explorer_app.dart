import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

/// App version string (e.g. "0.8.10"), resolved asynchronously during
/// [runDeferredStartupWork] via `package_info_plus` since it requires a
/// platform channel round-trip. Reads as '0.0.0' for the brief window
/// before that resolves, and 'unknown' if the platform call fails.
String appVersion = '0.0.0';

/// Drives the app's [ThemeMode]. Seeded from [AppSettingsService] during
/// [runDeferredStartupWork] and updated live from the settings screen.
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier(ThemeMode.system);

class VaultExplorerApp extends StatelessWidget {
  const VaultExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'VaultExplorer',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeMode,
          home: const LockGateScreen(),
        );
      },
    );
  }
}
