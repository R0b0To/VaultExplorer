import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/app/app_bootstrap.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/sync/services/scheduled_sync_background.dart';

final _scheduledSyncControl = MethodChannel(
  'com.aeidolon.vaultexplorer/scheduled_sync',
);
final _scheduledSyncBackgroundRunner = ScheduledSyncBackgroundRunner();

@pragma('vm:entry-point')
void scheduledSyncBackgroundEntrypoint() {
  WidgetsFlutterBinding.ensureInitialized();
  _scheduledSyncControl.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'runScheduledSync':
        final raw = call.arguments;
        if (raw is! Map) return const {'success': false};
        return _scheduledSyncBackgroundRunner.run(
          Map<Object?, Object?>.from(raw),
        );
      case 'cancelScheduledSync':
        _scheduledSyncBackgroundRunner.cancel();
        return const {'success': true};
      default:
        throw MissingPluginException(
          'Unknown scheduled sync method: ${call.method}',
        );
    }
  });
  unawaited(_scheduledSyncControl.invokeMethod<void>('ready'));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Not awaited: the platform message is queued ahead of runApp either way,
  // and waiting for its reply only delayed the first frame.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  final appContainer = ProviderContainer();
  appContainer.read(vaultEngineEventsProvider);

  configurePlatformIntegrations(appContainer);

  runApp(
    UncontrolledProviderScope(
      container: appContainer,
      child: const VaultExplorerApp(),
    ),
  );

  unawaited(runDeferredStartupWork(appContainer));
}
