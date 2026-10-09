import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/decoy/decoy_archive_explorer_screen.dart';
import 'package:vaultexplorer/app/main_shell.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

String appVersion = '0.0.0';
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier(
  ThemeMode.system,
);
final ValueNotifier<bool> appUseDynamicColorNotifier = ValueNotifier(false);
final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier(null);

class VaultExplorerApp extends ConsumerWidget {
  const VaultExplorerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSkin = ref.watch(appSkinSettingsProvider);
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
                        useDynamicColor &&
                        lightDynamic != null &&
                        darkDynamic != null;
                    return MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildLightTheme(
                        dynamicScheme: useDynamic ? lightDynamic : null,
                        appSkin: appSkin.preset,
                        customAppSkin: appSkin.customAppSkin,
                        manualFileManagerSkin: appSkin.fileManagerSkin,
                        fileManagerFollowsAppSkin:
                            appSkin.fileManagerFollowsAppSkin,
                        editorFollowsAppSkin: appSkin.editorFollowsAppSkin,
                      ),
                      darkTheme: buildDarkTheme(
                        dynamicScheme: useDynamic ? darkDynamic : null,
                        appSkin: appSkin.preset,
                        customAppSkin: appSkin.customAppSkin,
                        manualFileManagerSkin: appSkin.fileManagerSkin,
                        fileManagerFollowsAppSkin:
                            appSkin.fileManagerFollowsAppSkin,
                        editorFollowsAppSkin: appSkin.editorFollowsAppSkin,
                      ),
                      themeMode: themeMode,
                      locale: locale,

                      localizationsDelegates: [
                        AppLocalizations.delegate,
                        ...GlobalMaterialLocalizations.delegates,
                      ],
                      supportedLocales: AppLocalizations.supportedLocales,
                      localeResolutionCallback:
                          (deviceLocale, supportedLocales) {
                            for (final supported in supportedLocales) {
                              if (supported.languageCode ==
                                  deviceLocale?.languageCode) {
                                return supported;
                              }
                            }
                            return const Locale('en');
                          },
                      builder: (context, child) {
                        return Consumer(
                          builder: (context, ref, _) {
                            return Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (_) {
                                ref
                                    .read(sessionLockControllerProvider)
                                    .scheduleAutoLock();
                                ref
                                    .read(
                                      vaultDashboardControllerProvider.notifier,
                                    )
                                    .resetAllAutoCloseTimers();
                              },
                              child: child ?? const SizedBox.shrink(),
                            );
                          },
                        );
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
  bool _quickCaptureLaunch = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMode());
  }

  Future<void> _resolveMode() async {
    // None of these depends on another's result, so they no longer queue up
    // behind one another (this screen is blank until all of them finish).
    // loadSettings() and checkPendingQuickCaptureRequest() swallow their own
    // errors; getMode() propagating is unchanged from before.
    final (mode, settings, quickCapturePending) = await (
      disguiseModeApi.getMode(),
      ref.read(appSettingsServiceProvider).loadSettings(),
      ref.read(quickCaptureApiProvider).checkPendingQuickCaptureRequest(),
    ).wait;
    if (mounted) applyDisguiseModeTaskSwitcherLabel(mode, context.l10n);
    // The decoy identity never shows Quick Capture; dropping the request
    // there matches what already happened (it was never acted on, and
    // VaultQuickCaptureActivity.onDestroy clears whatever was left).
    if (quickCapturePending && mode != DisguiseMode.decoy) {
      // Skip the app lock gate for this launch: the capture screen opens
      // immediately and asks for the unlock when something is saved.
      ref
          .read(pendingQuickCaptureLaunchProvider)
          .markPending(
            appUnlockRequired:
                settings.useMasterPassword &&
                settings.masterPasswordHash != null,
          );
      _quickCaptureLaunch = true;
    }
    appLocaleNotifier.value =
        (settings.languageCode != null && settings.languageCode!.isNotEmpty)
        ? Locale(settings.languageCode!)
        : null;
    appThemeModeNotifier.value = settings.themeMode;
    appUseDynamicColorNotifier.value = settings.useDynamicColor;

    await ref
        .read(appSkinSettingsProvider.notifier)
        .applyImportedSettings(settings);

    final secureScreenPolicy = ref.read(secureScreenPolicyProvider);
    VeLog.enabled = settings.debugLoggingEnabled;
    unawaited(
      ref
          .read(vaultFileIoApiProvider)
          .setDebugLogging(settings.debugLoggingEnabled),
    );
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
    if (mode == DisguiseMode.decoy) return const DecoyArchiveExplorerScreen();
    return _quickCaptureLaunch ? const MainShell() : const LockGateScreen();
  }
}

void applyDisguiseModeTaskSwitcherLabel(
  DisguiseMode mode,
  AppLocalizations l10n,
) {
  unawaited(
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: mode == DisguiseMode.decoy
            ? l10n.appNameZipExplorer
            : l10n.appNameVaultExplorer,
        primaryColor: 0x00000000,
      ),
    ).catchError((_) {
      // Non-critical — some Android builds reject the platform call;
      // the app keeps working fine without a custom task-switcher label.
    }),
  );
}
