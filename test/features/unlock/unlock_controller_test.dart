import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/unlock/unlock_controller.dart';

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
        case 'warmContainer':
          return null;
        case 'documentExists':
          return true;
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

  group('UnlockController Tests', () {
    const params = UnlockParams(
      initialUri: 'file:///vault.hc',
      initialName: 'My Vault',
    );

    test('initializes with provided parameters and defaults', () {
      final state = container.read(unlockControllerProvider(params));

      expect(state.selectedUri, 'file:///vault.hc');
      expect(state.selectedName, 'My Vault');
      expect(state.remember, isTrue);
      expect(state.readOnly, isFalse);
      expect(state.protectHiddenVolume, isFalse);
    });

    test('toggles readOnly and updates hidden volume compatibility', () {
      final controller = container.read(unlockControllerProvider(params).notifier);

      controller.setProtectHiddenVolume(true);
      expect(container.read(unlockControllerProvider(params)).protectHiddenVolume, isTrue);

      // Setting read-only must automatically disable hidden volume protection
      controller.setReadOnly(true);
      expect(container.read(unlockControllerProvider(params)).readOnly, isTrue);
      expect(container.read(unlockControllerProvider(params)).protectHiddenVolume, isFalse);
    });

    test('setSelectedVaultKind clears current selection and switches format', () {
      final controller = container.read(unlockControllerProvider(params).notifier);

      controller.setSelectedVaultKind('directory_vault');
      final state = container.read(unlockControllerProvider(params));

      expect(state.containerFormat, 'directory_vault');
      expect(state.isFolderVault, isTrue);
      expect(state.selectedUri, isNull);
      expect(state.selectedName, isNull);
    });

    test('removeKeyfile and removeHiddenKeyfile remove specific items', () {
      final controller = container.read(unlockControllerProvider(params).notifier);

      const k1 = (uri: 'content://k1', displayName: 'k1.key');
      const k2 = (uri: 'content://k2', displayName: 'k2.key');

      // Manipulate outer keyfiles
      controller.removeKeyfile(k1);
      expect(container.read(unlockControllerProvider(params)).keyfiles, isEmpty);

      controller.removeHiddenKeyfile(k2);
      expect(container.read(unlockControllerProvider(params)).hiddenKeyfiles, isEmpty);
    });
  });
}