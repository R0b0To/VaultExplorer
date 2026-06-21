import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'theme.dart';
import 'screens/dashboard/vault_dashboard.dart';

void main() {
  // Silently neutralize third-party video player disposal race conditions
  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('Cannot add event after closing') || 
        errStr.contains('video_player_mdk')) {
      return true; // Silence this warning to keep your console completely clean
    }
    return false; // Propagate all other actual errors
  };

  fvp.registerWith(options: {
    'platforms': ['android'],
  });

  runApp(const VaultExplorerApp());
}

class VaultExplorerApp extends StatelessWidget {
  const VaultExplorerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaultExplorer',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const VaultDashboard(),
    );
  }
}