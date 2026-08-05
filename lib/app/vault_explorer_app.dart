import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/decoy/decoy_water_tracker_screen.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

String appVersion = '0.0.0';
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier(ThemeMode.system);

/// `null` = follow the system locale. Otherwise one of
/// [AppLocalizations.supportedLocales], set from `AppSettings.languageCode`
/// at startup (`runDeferredStartupWork`) and live-updated from the language
/// picker in [AppSettingsScreen] the same way [appThemeModeNotifier] is.
final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier(null);

class VaultExplorerApp extends StatelessWidget {
  const VaultExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeModeNotifier,
      builder: (context, themeMode, child) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: appLocaleNotifier,
          builder: (context, locale, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              themeMode: themeMode,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const _DisguiseModeGate(),
            );
          },
        );
      },
    );
  }
}

class _DisguiseModeGate extends StatefulWidget {
  const _DisguiseModeGate();

  @override
  State<_DisguiseModeGate> createState() => _DisguiseModeGateState();
}

class _DisguiseModeGateState extends State<_DisguiseModeGate> {
  DisguiseMode? _mode;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMode());
  }

  Future<void> _resolveMode() async {
    final mode = await disguiseModeApi.getMode();
    if (mounted) applyDisguiseModeTaskSwitcherLabel(mode, context.l10n);
    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    if (mode == null) {
      return Scaffold(backgroundColor: Theme.of(context).colorScheme.surface);
    }
    return mode == DisguiseMode.decoy
        ? const DecoyWaterTrackerScreen()
        : const LockGateScreen();
  }
}

void applyDisguiseModeTaskSwitcherLabel(DisguiseMode mode, AppLocalizations l10n) {
  unawaited(
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: mode == DisguiseMode.decoy ? l10n.appNameHydroTracker : l10n.appNameVaultExplorer,
      ),
    ),
  );
}