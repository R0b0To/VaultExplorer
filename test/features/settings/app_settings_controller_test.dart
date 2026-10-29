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
  // What the platform answers when asked to create a biometric sentinel key,
  // and the ids it was asked to delete.
  late bool sentinelCreationSucceeds;
  late List<String> deletedSentinels;

  setUp(() {
    sentinelCreationSucceeds = true;
    deletedSentinels = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'biometricKeyCreate':
          return sentinelCreationSucceeds;
        case 'biometricKeyDelete':
          deletedSentinels.add((call.arguments as Map)['id'] as String);
          return true;
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
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
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
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);

      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      await controller.updateSettings((s) => s.copyWith(
            containerSortMode: ContainerSortMode.newest,
            blockScreenshots: false,
            autoLockMins: 15,
          ));

      final state = container.read(appSettingsControllerProvider);
      expect(state.settings.containerSortMode, ContainerSortMode.newest);
      expect(state.settings.blockScreenshots, isFalse);
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

    test('password, PIN and pattern are independent credentials: saving one '
        'leaves the others stored, and only makeActive moves the active '
        'method', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      expect(await controller.saveMasterPattern('patternhash1'), isTrue);
      var state = container.read(appSettingsControllerProvider);
      expect(state.settings.masterPatternHash, 'patternhash1');
      expect(state.settings.masterUnlockMethod, MasterUnlockMethod.pattern);

      expect(await controller.saveMasterPin('pinhash1'), isTrue);
      state = container.read(appSettingsControllerProvider);
      expect(state.settings.masterPinHash, 'pinhash1');
      expect(state.settings.masterUnlockMethod, MasterUnlockMethod.pin);
      // The pattern set earlier is still there to switch back to.
      expect(state.settings.masterPatternHash, 'patternhash1');

      // Changing a credential without making it the active method.
      expect(
        await controller.saveMasterPattern('patternhash2', makeActive: false),
        isTrue,
      );
      state = container.read(appSettingsControllerProvider);
      expect(state.settings.masterPatternHash, 'patternhash2');
      expect(state.settings.masterPinHash, 'pinhash1');
      expect(state.settings.masterUnlockMethod, MasterUnlockMethod.pin);
    });

    test('a PIN alone is a complete master lock: no master password is '
        'needed behind it', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      await controller.updateSettings((s) => s.copyWith(useMasterPassword: true));
      expect(
        container.read(appSettingsControllerProvider).settings.masterLockActive,
        isFalse,
        reason: 'the flag alone, with nothing to unlock with, is no lock',
      );

      await controller.saveMasterPin('pinhash1');

      final settings = container.read(appSettingsControllerProvider).settings;
      expect(settings.hasMasterPassword, isFalse);
      expect(settings.masterLockActive, isTrue);
      expect(settings.masterUnlockMethod, MasterUnlockMethod.pin);
    });

    test('setMasterUnlockMethod refuses a credential that is not set, and '
        'biometrics with no credential behind them', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      expect(await controller.setMasterUnlockMethod(MasterUnlockMethod.pin), isFalse);
      expect(
        await controller.setMasterUnlockMethod(MasterUnlockMethod.biometrics),
        isFalse,
      );
      expect(deletedSentinels, isEmpty);
      expect(
        container.read(appSettingsControllerProvider).settings.masterUnlockMethod,
        MasterUnlockMethod.password,
      );
    });

    test('biometrics sit in front of a stored credential and leave it '
        'stored', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      await controller.saveMasterPin('pinhash1');
      expect(
        await controller.setMasterUnlockMethod(MasterUnlockMethod.biometrics),
        isTrue,
      );

      final state = container.read(appSettingsControllerProvider);
      expect(state.settings.masterUnlockMethod, MasterUnlockMethod.biometrics);
      expect(state.settings.masterPinHash, 'pinhash1');
    });

    test('setMasterUnlockMethod(biometrics) does not switch when the '
        'biometric sentinel key cannot be created', () async {
      sentinelCreationSucceeds = false;
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();
      await controller.saveMasterPin('pinhash1');

      final changed = await controller.setMasterUnlockMethod(
        MasterUnlockMethod.biometrics,
      );

      expect(changed, isFalse);
      expect(
        container.read(appSettingsControllerProvider).settings.masterUnlockMethod,
        MasterUnlockMethod.pin,
      );
    });

    test('leaving biometrics deletes the master biometric sentinel key', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();
      await controller.saveMasterPin('pinhash1');

      expect(
        await controller.setMasterUnlockMethod(MasterUnlockMethod.biometrics),
        isTrue,
      );
      expect(deletedSentinels, isEmpty);

      await controller.setMasterUnlockMethod(MasterUnlockMethod.pin);

      expect(deletedSentinels, ['master']);
    });

    test('removeMasterCredential never removes the last credential, and '
        'removing the active one hands over to another', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();
      await controller.saveMasterPattern('patternhash1');
      await controller.saveMasterPin('pinhash1'); // now the active method

      expect(await controller.removeMasterCredential(MasterUnlockMethod.pin), isTrue);
      var settings = container.read(appSettingsControllerProvider).settings;
      expect(settings.masterPinHash, isNull);
      expect(settings.masterPatternHash, 'patternhash1');
      expect(settings.masterUnlockMethod, MasterUnlockMethod.pattern);

      expect(
        await controller.removeMasterCredential(MasterUnlockMethod.pattern),
        isFalse,
      );
      settings = container.read(appSettingsControllerProvider).settings;
      expect(settings.masterPatternHash, 'patternhash1');
      expect(settings.masterUnlockMethod, MasterUnlockMethod.pattern);
    });

    test('setMasterUnlockMethod is a no-op when the target already matches '
        'the current method -- picking the already-active option again '
        'must not wipe its own hash', () async {
      final subscription = container.listen(appSettingsControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appSettingsControllerProvider.notifier);
      await controller.load();

      await controller.saveMasterPattern('patternhash1');
      await controller.setMasterUnlockMethod(MasterUnlockMethod.pattern);

      final state = container.read(appSettingsControllerProvider);
      expect(state.settings.masterUnlockMethod, MasterUnlockMethod.pattern);
      expect(state.settings.masterPatternHash, 'patternhash1');
    });
  });
}