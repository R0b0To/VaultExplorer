import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/biometric_enrollment_guard.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

/// Stands in for the Keystore: each sentinel id maps to a status, and the
/// calls the guard makes are recorded.
class _FakeCryptoApi implements VaultCryptoApi {
  final Map<String, BiometricKeyStatus> statuses = {};
  final List<String> created = [];
  final List<String> deleted = [];
  final List<String> clearedPaths = [];
  bool createSucceeds = true;
  bool createThrows = false;

  @override
  Future<bool> createBiometricKey(String id) async {
    if (createThrows) throw StateError('keystore unavailable');
    if (!createSucceeds) return false;
    created.add(id);
    statuses[id] = BiometricKeyStatus.valid;
    return true;
  }

  @override
  Future<BiometricKeyStatus> biometricKeyStatus(String id) async {
    return statuses[id] ?? BiometricKeyStatus.missing;
  }

  @override
  Future<bool> deleteBiometricKey(String id) async {
    deleted.add(id);
    statuses.remove(id);
    return true;
  }

  @override
  Future<bool> clearDerivedKey(String filePath, {bool removeExpiry = false}) async {
    clearedPaths.add(filePath);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySecureStorage extends AppSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({required String key}) async => data[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    data.clear();
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(data);

  @override
  Future<Map<String, String>> readAllWithPrefixes(
    List<String> prefixes, {
    List<String> excludePrefixes = const [],
  }) async => {
    for (final e in data.entries)
      if (prefixes.any(e.key.startsWith) &&
          !excludePrefixes.any(e.key.startsWith))
        e.key: e.value,
  };

  @override
  Future<bool> containsKey({required String key}) async =>
      data.containsKey(key);
}

/// Keeps the master-lock settings in memory instead of on disk.
class _FakeSettingsService implements AppSettingsService {
  _FakeSettingsService(this.settings);
  AppSettings settings;

  @override
  Future<AppSettings> updateSettings(
    AppSettings Function(AppSettings current) updater,
  ) async => settings = updater(settings);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uriA = 'content://tree/vault-a';
  const uriB = 'content://tree/vault-b';

  late Directory tempDir;
  late _MemorySecureStorage secureStorage;
  late _FakeCryptoApi crypto;
  late ContainerRepository repo;
  late _FakeSettingsService settings;
  late BiometricEnrollmentGuard guard;

  ContainerRecord biometricVault(String uri) => ContainerRecord(
    uri: uri,
    label: 'Vault',
    containerFormat: 'cryptomator',
    unlockMethod: ContainerUnlockMethod.biometrics,
    pendingPassword: 'Secret',
    cacheDerivedKey: true,
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('biometric_guard_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    secureStorage = _MemorySecureStorage();
    crypto = _FakeCryptoApi();
    repo = ContainerRepository.withCryptoApi(crypto, secureStorage);
    settings = _FakeSettingsService(
      AppSettings(
        useMasterPassword: true,
        masterUnlockMethod: MasterUnlockMethod.biometrics,
      ),
    );
    guard = BiometricEnrollmentGuard(
      cryptoApi: crypto,
      repository: repo,
      settings: settings,
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('BiometricKeyStatus', () {
    test('maps the platform strings, treating anything unknown as an error', () {
      expect(BiometricKeyStatus.fromWire('valid'), BiometricKeyStatus.valid);
      expect(
        BiometricKeyStatus.fromWire('invalidated'),
        BiometricKeyStatus.invalidated,
      );
      expect(BiometricKeyStatus.fromWire('missing'), BiometricKeyStatus.missing);
      expect(BiometricKeyStatus.fromWire('error'), BiometricKeyStatus.error);
      expect(BiometricKeyStatus.fromWire(null), BiometricKeyStatus.error);
      expect(BiometricKeyStatus.fromWire('???'), BiometricKeyStatus.error);
    });

    test('only invalidated and missing require a revert', () {
      expect(BiometricKeyStatus.valid.requiresRevert, isFalse);
      expect(BiometricKeyStatus.error.requiresRevert, isFalse);
      expect(BiometricKeyStatus.invalidated.requiresRevert, isTrue);
      expect(BiometricKeyStatus.missing.requiresRevert, isTrue);
    });
  });

  group('master lock', () {
    test('a valid sentinel leaves biometrics on', () async {
      crypto.statuses[kMasterBiometricKeyId] = BiometricKeyStatus.valid;

      expect(await guard.checkMaster(), BiometricGuardResult.ok);
      expect(settings.settings.masterUnlockMethod, MasterUnlockMethod.biometrics);
      expect(crypto.deleted, isEmpty);
    });

    test('an invalidated sentinel (new biometric enrolled) switches the gate '
        'back to the master password', () async {
      crypto.statuses[kMasterBiometricKeyId] = BiometricKeyStatus.invalidated;

      expect(await guard.checkMaster(), BiometricGuardResult.reverted);
      expect(settings.settings.masterUnlockMethod, MasterUnlockMethod.password);
      expect(settings.settings.useMasterPassword, isTrue);
      expect(crypto.deleted, [kMasterBiometricKeyId]);
    });

    test('a missing sentinel counts as changed -- biometrics set up before '
        'the guard existed fail closed', () async {
      expect(await guard.checkMaster(), BiometricGuardResult.reverted);
      expect(settings.settings.masterUnlockMethod, MasterUnlockMethod.password);
    });

    test('a keystore error refuses the attempt without switching anything '
        'off', () async {
      crypto.statuses[kMasterBiometricKeyId] = BiometricKeyStatus.error;

      expect(await guard.checkMaster(), BiometricGuardResult.unavailable);
      expect(settings.settings.masterUnlockMethod, MasterUnlockMethod.biometrics);
      expect(crypto.deleted, isEmpty);
    });

    test('revertMaster leaves a method other than biometrics alone', () async {
      settings.settings = AppSettings(
        useMasterPassword: true,
        masterUnlockMethod: MasterUnlockMethod.pin,
      );

      await guard.revertMaster();

      expect(settings.settings.masterUnlockMethod, MasterUnlockMethod.pin);
    });

    test('enableMaster creates the sentinel and reports a refusal', () async {
      expect(await guard.enableMaster(), isTrue);
      expect(crypto.created, [kMasterBiometricKeyId]);

      crypto.createSucceeds = false;
      expect(await guard.enableMaster(), isFalse);

      crypto.createThrows = true;
      expect(await guard.enableMaster(), isFalse);
    });

    test('forgetMaster deletes the sentinel', () async {
      crypto.statuses[kMasterBiometricKeyId] = BiometricKeyStatus.valid;
      await guard.forgetMaster();
      expect(crypto.deleted, [kMasterBiometricKeyId]);
    });
  });

  group('vaults', () {
    test('a valid sentinel leaves the vault on biometrics', () async {
      await repo.save(biometricVault(uriA));
      crypto.statuses[vaultBiometricKeyId(uriA)] = BiometricKeyStatus.valid;

      expect(await guard.checkVault(uriA), BiometricGuardResult.ok);
      final record = (await repo.loadAll())[uriA]!;
      expect(record.unlockMethod, ContainerUnlockMethod.biometrics);
      expect(await repo.getPassword(uriA), 'Secret');
    });

    test('an invalidated sentinel reverts the vault to a manual password and '
        'drops its saved credentials', () async {
      await repo.save(biometricVault(uriA));
      crypto.statuses[vaultBiometricKeyId(uriA)] =
          BiometricKeyStatus.invalidated;

      expect(await guard.checkVault(uriA), BiometricGuardResult.reverted);

      final record = (await repo.loadAll())[uriA]!;
      expect(record.unlockMethod, ContainerUnlockMethod.password);
      expect(record.cacheDerivedKey, isFalse);
      expect(await repo.getPassword(uriA), isNull);
      expect(crypto.clearedPaths, contains(derivedKeyPathForUri(uriA)));
      expect(crypto.deleted, contains(vaultBiometricKeyId(uriA)));
    });

    test('a missing sentinel reverts the vault too', () async {
      await repo.save(biometricVault(uriA));

      expect(await guard.checkVault(uriA), BiometricGuardResult.reverted);
      expect(
        (await repo.loadAll())[uriA]!.unlockMethod,
        ContainerUnlockMethod.password,
      );
    });

    test('a keystore error refuses the attempt and keeps the saved '
        'credentials', () async {
      await repo.save(biometricVault(uriA));
      crypto.statuses[vaultBiometricKeyId(uriA)] = BiometricKeyStatus.error;

      expect(await guard.checkVault(uriA), BiometricGuardResult.unavailable);
      expect(
        (await repo.loadAll())[uriA]!.unlockMethod,
        ContainerUnlockMethod.biometrics,
      );
      expect(await repo.getPassword(uriA), 'Secret');
    });

    test('vault sentinels are independent: reverting one does not touch '
        'another', () async {
      await repo.save(biometricVault(uriA));
      await repo.save(biometricVault(uriB));
      crypto.statuses[vaultBiometricKeyId(uriA)] =
          BiometricKeyStatus.invalidated;
      crypto.statuses[vaultBiometricKeyId(uriB)] = BiometricKeyStatus.valid;

      await guard.checkVault(uriA);

      expect(await guard.checkVault(uriB), BiometricGuardResult.ok);
      expect(
        (await repo.loadAll())[uriB]!.unlockMethod,
        ContainerUnlockMethod.biometrics,
      );
    });

    test('re-enabling a reverted vault trusts the biometrics enrolled now',
        () async {
      await repo.save(biometricVault(uriA));
      await guard.checkVault(uriA);

      expect(await guard.enableVault(uriA), isTrue);
      expect(crypto.created, contains(vaultBiometricKeyId(uriA)));
      expect(await guard.checkVault(uriA), BiometricGuardResult.ok);
    });

    test('the sentinel ids of the master lock and a vault never collide', () {
      expect(vaultBiometricKeyId('master'), isNot(kMasterBiometricKeyId));
    });
  });
}
