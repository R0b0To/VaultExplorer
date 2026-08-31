import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' hide GlobalMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/decoy/decoy_archive_explorer_screen.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

String appVersion = '0.0.0';
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<bool> appUseDynamicColorNotifier = ValueNotifier(false);
final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier(null);

class VaultExplorerApp extends StatelessWidget {
  const VaultExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeModeNotifier,
          builder: (context, themeMode, child) {
            return ValueListenableBuilder<Locale?>(
              valueListenable: appLocaleNotifier,
              builder: (context, locale, child) {
                return ValueListenableBuilder<bool>(
                  valueListenable: appUseDynamicColorNotifier,
                  builder: (context, useDynamicColor, child) {
                    final useDynamic =
                        useDynamicColor && lightDynamic != null && darkDynamic != null;
                    return MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildLightTheme(
                        dynamicScheme: useDynamic ? lightDynamic : null,
                      ),
                      darkTheme: buildDarkTheme(
                        dynamicScheme: useDynamic ? darkDynamic : null,
                      ),
                      themeMode: themeMode,
                      locale: locale,

                      localizationsDelegates: [
                        AppLocalizations.delegate,
                        GlobalMaterialLocalizations.delegate,
                        GlobalWidgetsLocalizations.delegate,
                      ],
                      supportedLocales: AppLocalizations.supportedLocales,
                      localeResolutionCallback: (deviceLocale, supportedLocales) {
                        for (final supported in supportedLocales) {
                          if (supported.languageCode == deviceLocale?.languageCode) {
                            return supported;
                          }
                        }
                        return const Locale('en');
                      },
                      home: const _DisguiseModeGate(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DisguiseModeGate extends ConsumerStatefulWidget {
  const _DisguiseModeGate();

  @override
  ConsumerState<_DisguiseModeGate> createState() => _DisguiseModeGateState();
}

class _DisguiseModeGateState extends ConsumerState<_DisguiseModeGate> {
  DisguiseMode? _mode;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMode());
  }

  Future<void> _resolveMode() async {
    final mode = await disguiseModeApi.getMode();
    if (mounted) applyDisguiseModeTaskSwitcherLabel(mode, context.l10n);

    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    final secureScreenPolicy = ref.read(secureScreenPolicyProvider);
    VeLog.enabled = settings.debugLoggingEnabled;
    unawaited(ref.read(vaultFileIoApiProvider).setDebugLogging(settings.debugLoggingEnabled));
    if (mode == DisguiseMode.decoy) {
      await secureScreenPolicy.disableForDecoy();
    } else {
      await secureScreenPolicy.apply(preference: settings.blockScreenshots);
    }

    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    if (mode == null) {
      return Scaffold(backgroundColor: Theme.of(context).colorScheme.surface);
    }
    return mode == DisguiseMode.decoy
        ? const DecoyArchiveExplorerScreen()
        : const LockGateScreen();
  }
}

void applyDisguiseModeTaskSwitcherLabel(DisguiseMode mode, AppLocalizations l10n) {
  unawaited(
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: mode == DisguiseMode.decoy ? l10n.appNameZipExplorer : l10n.appNameVaultExplorer,
      ),
    ),
  );
}
