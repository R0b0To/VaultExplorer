import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/decoy/decoy_pdf_home_screen.dart';
import 'package:vaultexplorer/features/decoy/decoy_pdf_viewer_screen.dart';
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
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeMode,
          home: const _DisguiseModeGate(),
        );
      },
    );
  }
}

/// Decides, once per cold start, whether to boot into the real vault
/// ([LockGateScreen]) or the Discrete Mode decoy reader
/// ([_DecoyRootNavigator]) -- see docs/architecture.md §8 and ADR-025.
///
/// The decision is re-derived from native `PackageManager` state via
/// [DisguiseModeApi.getMode] on every launch rather than cached anywhere in
/// Dart, so it can never drift from what the launcher icon/label are
/// actually showing.
class _DisguiseModeGate extends StatefulWidget {
  const _DisguiseModeGate();

  @override
  State<_DisguiseModeGate> createState() => _DisguiseModeGateState();
}

class _DisguiseModeGateState extends State<_DisguiseModeGate> {
  DisguiseMode? _mode;

  /// Non-null when the app was launched to open a specific PDF from an
  /// external Open-With/Share intent (ADR-029).
  PickedLocalPdf? _pendingExternalOpen;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMode());
  }

  Future<void> _resolveMode() async {
    final mode = await disguiseModeApi.getMode();
    applyDisguiseModeTaskSwitcherLabel(mode);

    if (mode == DisguiseMode.decoy) {
      // Cold-start pull: if we were launched by an external Open-With/Share
      // intent, ExternalOpenBridge buffered it before Dart was even running.
      final pending = await disguiseModeApi.consumePendingOpenRequest();
      if (pending != null) {
        _pendingExternalOpen = pending;
      }
    }

    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    if (mode == null) {
      // Blank splash while the native query resolves -- deliberately no
      // flash of either the vault UI or the decoy UI before we actually
      // know which one belongs on screen.
      return Scaffold(backgroundColor: Theme.of(context).colorScheme.surface);
    }

    return mode == DisguiseMode.decoy
        ? _DecoyRootNavigator(initialPdf: _pendingExternalOpen)
        : const LockGateScreen();
  }
}

/// Root navigator for the Discrete Mode decoy reader.
///
/// Generates both [DecoyPdfHomeScreen] and [DecoyPdfViewerScreen] in
/// [onGenerateInitialRoutes] when launched cold from an external intent.
/// This ensures the app opens directly into the PDF viewer on frame 1
/// without flashing the recents dashboard list, while preserving normal
/// back navigation to the home screen.
class _DecoyRootNavigator extends StatefulWidget {
  final PickedLocalPdf? initialPdf;

  const _DecoyRootNavigator({super.key, this.initialPdf});

  @override
  State<_DecoyRootNavigator> createState() => _DecoyRootNavigatorState();
}

class _DecoyRootNavigatorState extends State<_DecoyRootNavigator> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Warm-start push: if the activity is already alive and a new
    // Open-With/Share intent arrives via onNewIntent, native pushes it
    // as an `externalOpenRequest` method call on the disguise channel.
    disguiseModeApi.setExternalOpenRequestListener((pdf) {
      if (!mounted) return;
      _navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => DecoyPdfViewerScreen(
            uri: pdf.uri,
            displayName: pdf.displayName,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pdf = widget.initialPdf;
    return Navigator(
      key: _navKey,
      onGenerateInitialRoutes: (navigator, initialRoute) {
        final routes = <Route<dynamic>>[
          MaterialPageRoute(builder: (_) => const DecoyPdfHomeScreen()),
        ];
        if (pdf != null) {
          routes.add(
            MaterialPageRoute(
              builder: (_) => DecoyPdfViewerScreen(
                uri: pdf.uri,
                displayName: pdf.displayName,
              ),
            ),
          );
        }
        return routes;
      },
    );
  }
}

/// Updates the Android recents/task-switcher card's label to match the
/// current disguise (docs/architecture.md §8). This is deliberately
/// separate from `MaterialApp.title`: that string is static and only
/// applied once via Flutter's own `Title` widget on first build, which
/// isn't enough once Discrete Mode can also be toggled live from Settings
/// mid-session (see `AppSettingsScreen._setDiscreteMode`, which calls this
/// too) -- without this, a disguised launcher icon could still be undone
/// by an honest "Vault Explorer" card sitting in the app switcher.
void applyDisguiseModeTaskSwitcherLabel(DisguiseMode mode) {
  unawaited(
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: mode == DisguiseMode.decoy ? 'PDF Viewer' : 'Vault Explorer',
      ),
    ),
  );
}