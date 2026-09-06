import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/unlock/unlock_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

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

    test('initializes correctly when initialCompositeCarriers are provided', () {
      const compositeParams = UnlockParams(
        initialCompositeCarriers: ['file:///carrier1.png', 'file:///carrier2.mp4'],
        initialName: 'My Composite Vault',
      );

      final state = container.read(unlockControllerProvider(compositeParams));

      expect(state.isComposite, isTrue);
      expect(state.compositeCarrierUris, ['file:///carrier1.png', 'file:///carrier2.mp4']);
      expect(state.compositeCarrierCount, 2);
      expect(state.containerFormat, 'composite');
      expect(state.hasAdvancedSettings, isTrue);
    });

    test('initializes correctly when initialUri has composite scheme', () {
      const compositeUriParams = UnlockParams(
        initialUri: 'composite:abc123hash',
        initialName: 'Saved Composite Vault',
      );

      final state = container.read(unlockControllerProvider(compositeUriParams));

      expect(state.isComposite, isTrue);
      expect(state.containerFormat, 'composite');
      expect(state.hasAdvancedSettings, isTrue);
    });

    test('setCompositeCarriers updates carrier files, name, and format', () {
      final controller = container.read(unlockControllerProvider(params).notifier);

      controller.setCompositeCarriers([
        (uri: 'file:///img1.jpg', displayName: 'img1.jpg'),
        (uri: 'file:///img2.jpg', displayName: 'img2.jpg'),
        (uri: 'file:///img3.jpg', displayName: 'img3.jpg'),
      ]);
      final state = container.read(unlockControllerProvider(params));

      expect(state.isComposite, isTrue);
      expect(state.compositeCarrierCount, 3);
      expect(state.containerFormat, 'composite');
      expect(state.selectedName, 'Composite Container (3 files)');
    });

    test('clearSelection resets composite carriers and restores format', () {
      final controller = container.read(unlockControllerProvider(params).notifier);

      controller.setCompositeCarriers([
        (uri: 'file:///img1.jpg', displayName: 'img1.jpg'),
        (uri: 'file:///img2.jpg', displayName: 'img2.jpg'),
      ]);
      expect(container.read(unlockControllerProvider(params)).isComposite, isTrue);

      controller.clearSelection();
      final state = container.read(unlockControllerProvider(params));

      expect(state.compositeCarrierUris, isEmpty);
      expect(state.isComposite, isFalse);
      expect(state.selectedUri, isNull);
      expect(state.selectedName, isNull);
    });

    test('pickFile automatically recognizes multi-selection as composite container', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'pickCryptoFiles':
            return [
              {'uri': 'file:///img1.jpg', 'displayName': 'img1.jpg'},
              {'uri': 'file:///img2.jpg', 'displayName': 'img2.jpg'},
            ];
          case 'hasAllFilesAccess':
            return true;
          default:
            return null;
        }
      });

      const emptyParams = UnlockParams();
      final sub = container.listen(unlockControllerProvider(emptyParams), (_, __) {});
      final controller = container.read(unlockControllerProvider(emptyParams).notifier);
      await controller.pickFile(AppLocalizationsEn());

      final state = container.read(unlockControllerProvider(emptyParams));
      expect(state.isComposite, isTrue);
      expect(state.compositeCarrierCount, 2);
      expect(state.compositeCarrierUris, ['file:///img1.jpg', 'file:///img2.jpg']);
      expect(state.containerFormat, 'composite');
      sub.close();
    });

    test('pickFile automatically recognizes single carrier file via trailer', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'pickCryptoFiles':
            return [
              {'uri': 'file:///carrier.jpg', 'displayName': 'carrier.jpg'},
            ];
          case 'profileCarriers':
            return {
              'totalAllocatableBytes': 500000,
              'carriers': [
                {
                  'fileIndex': 0,
                  'path': 'file:///carrier.jpg',
                  'detectedFormat': 'composite_carrier',
                  'fileSize': 1000000,
                  'payloadOffset': 500000,
                  'allocatableBytes': 500000,
                  'tier': 2,
                }
              ],
            };
          case 'hasAllFilesAccess':
            return true;
          default:
            return null;
        }
      });

      const emptyParams = UnlockParams();
      final sub = container.listen(unlockControllerProvider(emptyParams), (_, __) {});
      final controller = container.read(unlockControllerProvider(emptyParams).notifier);
      await controller.pickFile(AppLocalizationsEn());

      final state = container.read(unlockControllerProvider(emptyParams));
      expect(state.isComposite, isTrue);
      expect(state.compositeCarrierCount, 1);
      expect(state.compositeCarrierUris, ['file:///carrier.jpg']);
      expect(state.containerFormat, 'composite');
      sub.close();
    });
  });
}