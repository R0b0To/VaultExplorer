import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vaultexplorer/app/app_bootstrap.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

void main() async {
  // Ensure bindings are initialised before calling path_provider.
  WidgetsFlutterBinding.ensureInitialized();
  VaultExplorerApi.initMethodCallHandler();
  if (kDebugMode) {
    // Fire-and-forget; asserts internally if the native CascadeId/HashId
    // ordering has drifted from what crypto_algorithms.dart expects.
    //CipherAlgo.verifyNativeCascadeOrdering();
  }

  configurePlatformIntegrations();

  // Get the first frame on screen immediately. Everything below is deferred
  // until after that, so app launch is no longer gated on disk/Keystore/
  // platform-channel I/O (settings load, secure storage, package info,
  // orphaned temp-file cleanup).
  runApp(const VaultExplorerApp());

  unawaited(runDeferredStartupWork());
}
