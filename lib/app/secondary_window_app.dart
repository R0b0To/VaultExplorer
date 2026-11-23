import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/app/app_theme_cache.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';

/// The content of one native secondary window (see `SecondaryWindows`).
///
/// Each window is its own `MaterialApp`, because a `Navigator`, `Theme` and
/// `Localizations` cannot be shared across windows. The theme, theme mode,
/// locale and dynamic-colour setting come from the same sources as
/// `VaultExplorerApp`, so the two cannot drift apart; everything else (the
/// providers, and so every service and all state) is shared with the main
/// window.
///
/// What the main window's `MaterialApp` adds and this one deliberately does
/// not: the skin editor overlay, the picture-in-picture layer, the Flutter
/// drawn caption row (this window has a native title bar, see
/// [NativeWindowChrome]) and the disguise-mode gate.
class SecondaryWindowApp extends ConsumerStatefulWidget {
  const SecondaryWindowApp({super.key, required this.entry});

  final SecondaryWindowEntry entry;

  @override
  ConsumerState<SecondaryWindowApp> createState() => _SecondaryWindowAppState();
}

class _SecondaryWindowAppState extends ConsumerState<SecondaryWindowApp> {
  final AppThemeCache _themes = AppThemeCache();
  late final _CloseWhenPageLeaves _observer = _CloseWhenPageLeaves(
    widget.entry.close,
  );

  @override
  Widget build(BuildContext context) {
    final appSkin = ref.watch(appSkinSettingsProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            appThemeModeNotifier,
            appLocaleNotifier,
            appUseDynamicColorNotifier,
          ]),
          builder: (context, _) {
            final useDynamic =
                appUseDynamicColorNotifier.value &&
                lightDynamic != null &&
                darkDynamic != null;
            return MaterialApp(
              navigatorKey: widget.entry.navigatorKey,
              navigatorObservers: [_observer],
              debugShowCheckedModeBanner: false,
              title: widget.entry.title,
              theme: _themes.lightThemeFor(
                dynamicScheme: useDynamic ? lightDynamic : null,
                skinPreset: appSkin.preset,
                customSkin: appSkin.customAppSkin,
                manualFileManagerSkin: appSkin.fileManagerSkin,
                fileManagerFollowsAppSkin: appSkin.fileManagerFollowsAppSkin,
                editorFollowsAppSkin: appSkin.editorFollowsAppSkin,
              ),
              darkTheme: _themes.darkThemeFor(
                dynamicScheme: useDynamic ? darkDynamic : null,
                skinPreset: appSkin.preset,
                customSkin: appSkin.customAppSkin,
                manualFileManagerSkin: appSkin.fileManagerSkin,
                fileManagerFollowsAppSkin: appSkin.fileManagerFollowsAppSkin,
                editorFollowsAppSkin: appSkin.editorFollowsAppSkin,
              ),
              themeMode: appThemeModeNotifier.value,
              locale: appLocaleNotifier.value,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              localeResolutionCallback: appResolveLocale,
              builder: (context, child) => NativeWindowChrome(
                child: _SecondaryWindowShell(
                  entry: widget.entry,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              home: _SecondaryWindowRoot(entry: widget.entry),
            );
          },
        );
      },
    );
  }
}

/// Counts interaction in this window as activity (so working in vault
/// settings does not let the auto-lock timers run out, as in the main window)
/// and gives the mouse's back button its usual meaning here.
class _SecondaryWindowShell extends ConsumerWidget {
  const _SecondaryWindowShell({required this.entry, required this.child});

  final SecondaryWindowEntry entry;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        ref.read(sessionLockControllerProvider).scheduleAutoLock();
        ref
            .read(vaultDashboardControllerProvider.notifier)
            .resetAllAutoCloseTimers();
        // MouseNavDispatcher only serves the main window; closing the topmost
        // dialog, sheet or page is what Back does there too.
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons & kBackMouseButton != 0) {
          unawaited(entry.navigatorKey.currentState?.maybePop());
        }
      },
      child: child,
    );
  }
}

/// A blank bottom route. The window's page is pushed on top of it, so that the
/// page leaving (its own `Navigator.pop` after saving, or Back) is a pop that
/// [_CloseWhenPageLeaves] can see and turn into closing the window.
class _SecondaryWindowRoot extends StatefulWidget {
  const _SecondaryWindowRoot({required this.entry});

  final SecondaryWindowEntry entry;

  @override
  State<_SecondaryWindowRoot> createState() => _SecondaryWindowRootState();
}

class _SecondaryWindowRootState extends State<_SecondaryWindowRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => widget.entry.contentBuilder(context),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}

/// Closes the window once the page on top of the blank root route is gone.
/// Pages pushed above that page (a sub-screen of vault settings) leave without
/// closing anything.
class _CloseWhenPageLeaves extends NavigatorObserver {
  _CloseWhenPageLeaves(this._closeWindow);

  final VoidCallback _closeWindow;

  void _onLeft(Route<dynamic>? previousRoute) {
    if (previousRoute == null || !previousRoute.isFirst) return;
    // After the navigator has finished the pop it is in the middle of.
    scheduleMicrotask(_closeWindow);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _onLeft(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _onLeft(previousRoute);
}
