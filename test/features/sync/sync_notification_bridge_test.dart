import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/sync/services/sync_notification_bridge.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';

class FakeLifecycleApi implements VaultLifecycleApi {
  final List<bool> hasActiveCalls = [];
  final List<String?> textCalls = [];

  @override
  Future<void> updateBackgroundServiceProgress({
    required bool hasActive,
    String? title,
    String? text,
    int? progress,
    int max = 1000,
    bool indeterminate = false,
  }) async {
    hasActiveCalls.add(hasActive);
    textCalls.add(text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsService implements AppSettingsService {
  AppSettings settings;
  Completer<void>? delayLoad;

  FakeSettingsService({
    AppSettings? settings,
  }) : settings = settings ?? AppSettings(keepVaultsRunningInBackground: true);

  @override
  Future<AppSettings> loadSettings() async {
    if (delayLoad != null) {
      await delayLoad!.future;
    }
    return settings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFileOpsService implements FileOperationService {
  List<FileOperation> active = [];

  @override
  List<FileOperation> get activeOperations => active;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLifecycleApi lifecycle;
  late FakeSettingsService settings;
  late FakeFileOpsService fileOps;
  late SyncNotificationBridge bridge;

  setUp(() {
    lifecycle = FakeLifecycleApi();
    settings = FakeSettingsService();
    fileOps = FakeFileOpsService();
    bridge = SyncNotificationBridge(
      lifecycle: lifecycle,
      fileOps: fileOps,
      settings: settings,
    );
  });

  test('clear() unconditionally tells native layer that progress is inactive', () async {
    await bridge.clear();
    expect(lifecycle.hasActiveCalls, [false]);
  });

  test('update() followed by clear() ends in inactive state', () async {
    await bridge.update(
      const SyncStatus(running: true, doneActions: 10, totalActions: 20),
    );
    expect(lifecycle.hasActiveCalls.contains(true), isTrue);

    await bridge.clear();
    expect(lifecycle.hasActiveCalls.last, isFalse);
  });

  test('clear() while update() is in flight cancels update and leaves progress inactive', () async {
    // Simulate slow settings loading
    settings.delayLoad = Completer<void>();

    final updateFuture = bridge.update(
      const SyncStatus(running: true, doneActions: 45, totalActions: 45),
    );

    // clear() is called while update is still awaiting loadSettings
    await bridge.clear();

    // Now let update finish loading settings
    settings.delayLoad!.complete();
    await updateFuture;

    // Must NOT have posted progress after clear()!
    expect(lifecycle.hasActiveCalls.last, isFalse);
    expect(lifecycle.hasActiveCalls.contains(true), isFalse);
  });

  test('does not push progress if keepVaultsRunningInBackground is disabled', () async {
    settings.settings = AppSettings(keepVaultsRunningInBackground: false);
    await bridge.update(
      const SyncStatus(running: true, doneActions: 1, totalActions: 10),
    );
    expect(lifecycle.hasActiveCalls.contains(true), isFalse);
  });
}
