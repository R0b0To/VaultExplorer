import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('ContainerConfigController Tests', () {
    const params = ContainerConfigParams(
      uri: 'file:///vault.hc',
      currentLabel: 'My Vault',
      containerFormat: 'veracrypt',
    );
    final provider = containerConfigControllerProvider(params);

    test('initializes with default container configuration parameters', () {
      final state = container.read(provider);

      expect(state.label, 'My Vault');
      expect(state.unlockMethod, ContainerUnlockMethod.password);
      expect(state.autoCloseMins, 0);
      expect(state.documentProvider, isFalse);
      expect(state.cacheDerivedKey, isFalse);
      expect(state.cipherId, 255);
      expect(state.hashId, 255);
    });

    test('setUnlockMethod switches unlock mode', () {
      final controller = container.read(provider.notifier);

      controller.setUnlockMethod(ContainerUnlockMethod.pin);
      expect(container.read(provider).unlockMethod, ContainerUnlockMethod.pin);

      controller.setUnlockMethod(ContainerUnlockMethod.biometrics);
      expect(container.read(provider).unlockMethod, ContainerUnlockMethod.biometrics);
    });

    test('configuration mutators update respective parameters', () {
      final controller = container.read(provider.notifier);

      controller.setAutoCloseMins(15);
      expect(container.read(provider).autoCloseMins, 15);

      controller.setDocumentProvider(true);
      expect(container.read(provider).documentProvider, isTrue);

      controller.setThumbnailCacheMode(ThumbnailCacheMode.inContainer);
      expect(container.read(provider).thumbnailCacheMode, ThumbnailCacheMode.inContainer);

      controller.setThumbnailQuality(const ThumbnailQuality(quality: 90, size: 280));
      expect(container.read(provider).thumbnailQuality?.quality, 90);

      controller.setCacheDerivedKey(true);
      expect(container.read(provider).cacheDerivedKey, isTrue);
    });

    test('canSave returns false when required PIN or pattern hash is missing', () {
      final controller = container.read(provider.notifier);

      controller.setUnlockMethod(ContainerUnlockMethod.pin);
      controller.setPinHash(null);
      expect(container.read(provider).canSave('password123'), isFalse);

      controller.setPinHash('salt:hash');
      expect(container.read(provider).canSave('password123'), isTrue);

      controller.setUnlockMethod(ContainerUnlockMethod.pattern);
      controller.setPatternHash(null);
      expect(container.read(provider).canSave('password123'), isFalse);

      controller.setPatternHash('salt:hash');
      expect(container.read(provider).canSave('password123'), isTrue);
    });
  });
}