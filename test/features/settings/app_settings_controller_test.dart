import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAllFilesAccess':
          return true;
        case 'getAndroidSdkInt':
          return 34;
        case 'getDisguiseMode':
          return 'vault';
        default:
          return null;
      }
    });

    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('AppSettingsController Tests', () {
    test('initializes and loads settings state', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, __) {});
      addTearDown(subscription.close);

      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      final state = container.read(appSettingsControllerProvider);
      expect(state.loading, isFalse);
      expect(state.hasAllStorageAccess, isTrue);
      expect(state.androidSdkInt, 34);
      expect(state.disguiseMode, DisguiseMode.vault);
    });

    test('updateSettings modifies state values', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, __) {});
      addTearDown(subscription.close);

      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      await controller.updateSettings((s) => s.copyWith(
            containerSortMode: ContainerSortMode.newest,
            blockScreenshots: true,
            autoLockMins: 15,
          ));

      final state = container.read(appSettingsControllerProvider);
      expect(state.settings.containerSortMode, ContainerSortMode.newest);
      expect(state.settings.blockScreenshots, isTrue);
      expect(state.settings.autoLockMins, 15);
    });

    test('setShowPwFields and setPwError manage master password form state', () {
      final controller = container.read(appSettingsControllerProvider.notifier);

      controller.setShowPwFields(true);
      expect(container.read(appSettingsControllerProvider).showPwFields, isTrue);

      controller.setPwError('Password mismatch');
      expect(container.read(appSettingsControllerProvider).pwError, 'Password mismatch');

      controller.setPwError(null);
      expect(container.read(appSettingsControllerProvider).pwError, isNull);
    });

    test('setBackupBusy toggles backup activity indicator', () {
      final controller = container.read(appSettingsControllerProvider.notifier);

      controller.setBackupBusy(true);
      expect(container.read(appSettingsControllerProvider).backupBusy, isTrue);

      controller.setBackupBusy(false);
      expect(container.read(appSettingsControllerProvider).backupBusy, isFalse);
    });
  });
}