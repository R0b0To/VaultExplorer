import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:vaultexplorer/app/app_bootstrap.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  VaultExplorerApi.initMethodCallHandler();
  if (kDebugMode) {
  }

  configurePlatformIntegrations();

  runApp(const VaultExplorerApp());

  unawaited(runDeferredStartupWork());
}