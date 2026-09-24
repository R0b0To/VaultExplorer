import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/inputs/auto_lock_duration_options.dart'
    show kInheritAutoLockDuration;
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      // A never-configured container defaults to "App Default", not "Never"
      // -- it must stay subject to the app-wide lock-all sweep.
      expect(state.autoCloseMins, kInheritAutoLockDuration);
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

    test('saveContainer preserves compositeCarriers from existingRecord', () async {
      final fakeRepo = _FakeContainerRepo();
      final fakeStorage = _FakeAppSecureStorage();
      final fakeLifecycle = _FakeVaultLifecycleApi();
      final localContainer = ProviderContainer(
        overrides: [
          containerRepositoryProvider.overrideWith((ref) => fakeRepo),
          appSecureStorageProvider.overrideWith((ref) => fakeStorage),
          vaultLifecycleApiProvider.overrideWith((ref) => fakeLifecycle),
        ],
      );
      addTearDown(localContainer.dispose);

      final controller = localContainer.read(provider.notifier);

      const existingRecord = ContainerRecord(
        uri: 'composite:test123hash',
        label: 'My Composite Vault',
        compositeCarriers: [
          {'uri': 'file:///carrier1.jpg', 'name': 'carrier1.jpg'},
          {'uri': 'file:///carrier2.png', 'name': 'carrier2.png'},
        ],
        pinnedPaths: ['/Documents/doc.pdf'],
        bookmarkPaths: ['/Photos'],
      );

      final saved = await controller.saveContainer(
        passwordText: 'secret',
        labelText: 'Renamed Composite Vault',
        existingRecord: existingRecord,
      );

      expect(saved, isNotNull);
      expect(saved!.compositeCarriers, [
        {'uri': 'file:///carrier1.jpg', 'name': 'carrier1.jpg'},
        {'uri': 'file:///carrier2.png', 'name': 'carrier2.png'},
      ]);
      expect(saved.pinnedPaths, ['/Documents/doc.pdf']);
      expect(saved.bookmarkPaths, ['/Photos']);
    });
  });

  group('Cached derived key lifetime', () {
    const params = ContainerConfigParams(
      uri: 'file:///vault.hc',
      currentLabel: 'My Vault',
      containerFormat: 'veracrypt',
    );
    final provider = containerConfigControllerProvider(params);

    late _RecordingCryptoApi crypto;
    late ProviderContainer localContainer;

     setUp(() {
      crypto = _RecordingCryptoApi();
      localContainer = ProviderContainer(
        overrides: [
          vaultCryptoApiProvider.overrideWith((ref) => crypto),
          containerRepositoryProvider.overrideWith(
            (ref) => _FakeContainerRepo(cryptoApi: crypto),
          ),
          appSecureStorageProvider.overrideWith((ref) => _FakeAppSecureStorage()),
          vaultLifecycleApiProvider.overrideWith((ref) => _FakeVaultLifecycleApi()),
        ],
      );
      localContainer.listen(provider, (_, __) {});
      addTearDown(localContainer.dispose);
    });

    // initializeFromRecord kicks off _initAsync without awaiting it; wait for
    // it to finish so the stored expiry has been read.
    Future<void> initFromRecord(ContainerRecord record) async {
      localContainer.read(provider.notifier).initializeFromRecord(
            rec: record,
            appSettings: null,
            mountedContainer: null,
          );
      for (var i = 0; i < 500; i++) {
        if (!localContainer.read(provider).loadingPassword) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('controller never finished loading');
    }

    Future<ContainerRecord?> save(ContainerRecord? existing) => localContainer
        .read(provider.notifier)
        .saveContainer(passwordText: '', labelText: 'My Vault', existingRecord: existing);

    test('starts untouched: no pending lifetime and no stored expiry', () {
      final state = localContainer.read(provider);
      expect(state.derivedKeyLifetimeDays, isNull);
      expect(state.derivedKeyExpiresAt, isNull);
      expect(state.effectiveDerivedKeyExpiry(), isNull);
    });

    test('picking a number of days counts from the given moment', () {
      final controller = localContainer.read(provider.notifier);
      controller.setCacheDerivedKey(true);
      controller.setDerivedKeyLifetimeDays(30);

      final state = localContainer.read(provider);
      // UTC so the expected date does not depend on the machine's DST rules.
      final now = DateTime.utc(2026, 9, 23, 12);
      expect(state.derivedKeyLifetimeDays, 30);
      expect(
        state.effectiveDerivedKeyExpiry(now),
        DateTime.utc(2026, 10, 23, 12),
      );
      expect(state.isModified('', 'My Vault'), isTrue);
    });

    test('choosing no expiry when none is stored is not a pending change', () {
      final controller = localContainer.read(provider.notifier);
      controller.setDerivedKeyLifetimeDays(7);
      controller.setDerivedKeyLifetimeDays(kNoDerivedKeyExpiry);

      expect(localContainer.read(provider).derivedKeyLifetimeDays, isNull);
    });

    test('a stored expiry is kept until the user overwrites it', () async {
      final stored = DateTime(2026, 10, 1);
      crypto.expiry = stored;
      await initFromRecord(
        const ContainerRecord(uri: 'file:///vault.hc', label: 'My Vault', cacheDerivedKey: true),
      );
      final controller = localContainer.read(provider.notifier);

      expect(localContainer.read(provider).derivedKeyExpiresAt, stored);
      expect(localContainer.read(provider).effectiveDerivedKeyExpiry(), stored);
      expect(localContainer.read(provider).isModified('', 'My Vault'), isFalse);

      controller.setDerivedKeyLifetimeDays(kNoDerivedKeyExpiry);
      expect(localContainer.read(provider).effectiveDerivedKeyExpiry(), isNull);

      controller.setDerivedKeyLifetimeDays(kKeepDerivedKeyExpiry);
      expect(localContainer.read(provider).derivedKeyLifetimeDays, isNull);
      expect(localContainer.read(provider).effectiveDerivedKeyExpiry(), stored);
    });

    test('saving with a picked lifetime sends the new expiry to the platform', () async {
      final controller = localContainer.read(provider.notifier);
      controller.setCacheDerivedKey(true);
      controller.setDerivedKeyLifetimeDays(7);

      final before = DateTime.now();
      await save(null);
      final after = DateTime.now();

      expect(crypto.setExpiryCalls, hasLength(1));
      final call = crypto.setExpiryCalls.single;
      expect(call.path, 'file:///vault.hc');
      expect(call.expiresAt, isNotNull);
      expect(
        call.expiresAt!.isBefore(before.add(const Duration(days: 7))),
        isFalse,
      );
      expect(
        call.expiresAt!.isAfter(after.add(const Duration(days: 7))),
        isFalse,
      );
    });

    test('saving with an untouched picker leaves the stored expiry alone', () async {
      crypto.expiry = DateTime(2026, 10, 1);
      await initFromRecord(
        const ContainerRecord(uri: 'file:///vault.hc', label: 'My Vault', cacheDerivedKey: true),
      );

      await save(null);

      expect(crypto.setExpiryCalls, isEmpty);
      expect(crypto.clearCalls, isEmpty);
    });

    test('saving with "until I turn it off" removes the stored expiry', () async {
      crypto.expiry = DateTime(2026, 10, 1);
      await initFromRecord(
        const ContainerRecord(uri: 'file:///vault.hc', label: 'My Vault', cacheDerivedKey: true),
      );
      localContainer.read(provider.notifier).setDerivedKeyLifetimeDays(kNoDerivedKeyExpiry);

      await save(null);

      expect(crypto.setExpiryCalls.single.expiresAt, isNull);
    });

    test('switching caching off removes the cached key and its expiry', () async {
      await initFromRecord(
        const ContainerRecord(uri: 'file:///vault.hc', label: 'My Vault', cacheDerivedKey: true),
      );
      localContainer.read(provider.notifier).setCacheDerivedKey(false);

      await save(null);

      expect(crypto.clearCalls, [('file:///vault.hc', true)]);
      expect(crypto.setExpiryCalls, isEmpty);
    });

    test('a USB vault is keyed by its device name, not its usb: URI', () async {
      const usbParams = ContainerConfigParams(
        uri: 'usb:/dev/bus/usb/001/002',
        currentLabel: 'Stick',
        containerFormat: 'veracrypt',
      );
      final usbProvider = containerConfigControllerProvider(usbParams);
      final controller = localContainer.read(usbProvider.notifier);
      controller.setCacheDerivedKey(true);
      controller.setDerivedKeyLifetimeDays(1);

      await controller.saveContainer(
        passwordText: '',
        labelText: 'Stick',
        existingRecord: null,
      );

      expect(crypto.setExpiryCalls.single.path, '/dev/bus/usb/001/002');
    });
  });
}

class _FakeContainerRepo extends ContainerRepository {
  _FakeContainerRepo({VaultCryptoApi? cryptoApi})
      : super.withCryptoApi(cryptoApi ?? _FakeVaultCryptoApi());

  ContainerRecord? savedRecord;

  @override
  Future<void> save(ContainerRecord record) async {
    savedRecord = record;
  }
}

class _FakeVaultCryptoApi implements VaultCryptoApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppSecureStorage extends AppSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({required String key}) async => _storage[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _storage.clear();
  }

  @override
  Future<Map<String, String>> readAll() async => Map.unmodifiable(_storage);

  @override
  Future<bool> containsKey({required String key}) async => _storage.containsKey(key);
}

class _FakeVaultLifecycleApi implements VaultLifecycleApi {
  final List<String> lockedUris = [];

  @override
  Future<bool> lockContainer(String filePath) async {
    lockedUris.add(filePath);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCryptoApi implements VaultCryptoApi {
  DateTime? expiry;
  final List<({String path, DateTime? expiresAt})> setExpiryCalls = [];
  final List<(String, bool)> clearCalls = [];

  @override
  Future<DateTime?> getDerivedKeyExpiry(String filePath) async => expiry;

  @override
  Future<bool> setDerivedKeyExpiry(String filePath, DateTime? expiresAt) async {
    setExpiryCalls.add((path: filePath, expiresAt: expiresAt));
    return true;
  }

  @override
  Future<bool> clearDerivedKey(String filePath, {bool removeExpiry = false}) async {
    clearCalls.add((filePath, removeExpiry));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
