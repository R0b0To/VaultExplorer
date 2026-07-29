import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

String appVersion = '0.0.0';
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