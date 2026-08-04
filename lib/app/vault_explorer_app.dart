import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/decoy/decoy_water_tracker_screen.dart';
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
    applyDisguiseModeTaskSwitcherLabel(mode);
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

void applyDisguiseModeTaskSwitcherLabel(DisguiseMode mode) {
  unawaited(
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: mode == DisguiseMode.decoy ? 'Hydro Tracker' : 'Vault Explorer',
      ),
    ),
  );
}