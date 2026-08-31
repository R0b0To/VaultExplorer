import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/app/app_bootstrap.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final appContainer = ProviderContainer();
  appContainer.read(vaultEngineEventsProvider);
  if (kDebugMode) {}

  configurePlatformIntegrations(appContainer);

  runApp(
    UncontrolledProviderScope(
      container: appContainer,
      child: const VaultExplorerApp(),
    ),
  );

  unawaited(runDeferredStartupWork(appContainer));
}
