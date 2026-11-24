import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/vault_relocation_record_store.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _FakeCryptoApi implements VaultCryptoApi {
  @override
  Future<bool> deleteBiometricKey(String id) async => true;

  @override
  Future<bool> clearDerivedKey(String filePath, {bool removeExpiry = false}) async => true;

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
  Future<bool> containsKey({required String key}) async => data.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const oldUri = 'content://com.android.externalstorage.documents/document/primary%3AVaults%2Fwork.hc';
  const newUri = 'file:///data/user/0/com.aeidolon.vaultexplorer/files/vaults/work.hc';

  late Directory tempDir;
  late ContainerRepository repo;

  // Scripted collaborators.
  var biometricTrusted = true;
  Object? biometricCheckError;
  var armResult = true;
  Object? armError;
  final checked = <String>[];
  final armed = <String>[];
  final carried = <(String, String)>[];
  Object? carryError;

  late RepositoryRelocationRecordStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('relocation_store_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    repo = ContainerRepository.withCryptoApi(_FakeCryptoApi(), _MemorySecureStorage());
    biometricTrusted = true;
    biometricCheckError = null;
    armResult = true;
    armError = null;
    carryError = null;
    checked.clear();
    armed.clear();
    carried.clear();
    store = RepositoryRelocationRecordStore(
      repository: repo,
      isBiometricTrusted: (uri) async {
        checked.add(uri);
        if (biometricCheckError != null) throw biometricCheckError!;
        return biometricTrusted;
      },
      armBiometrics: (uri) async {
        armed.add(uri);
        if (armError != null) throw armError!;
        return armResult;
      },
      carryLockouts: ({required fromUri, required toUri}) async {
        carried.add((fromUri, toUri));
        if (carryError != null) throw carryError!;
      },
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> saveVault(ContainerUnlockMethod method, {String? password = 'pw'}) => repo.save(
    ContainerRecord(
      uri: oldUri,
      label: 'Work',
      containerFormat: 'veracrypt',
      unlockMethod: method,
      rememberPassword: method != ContainerUnlockMethod.password,
      pendingPassword: method == ContainerUnlockMethod.password ? null : password,
    ),
  );

  group('biometric unlock', () {
    test('is carried over when the old sentinel is still trusted', () async {
      await saveVault(ContainerUnlockMethod.biometrics);
      final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);

      expect(checked, [oldUri]);
      expect(armed, [newUri]);
      expect(move.biometricsDropped, isFalse);
      final moved = (await repo.loadAll())[newUri]!;
      expect(moved.unlockMethod, ContainerUnlockMethod.biometrics);
      expect(await repo.getPassword(newUri), 'pw');
    });

    test('is dropped, and never re-armed, when the old sentinel is no longer trusted', () async {
      biometricTrusted = false;
      await saveVault(ContainerUnlockMethod.biometrics);
      final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);

      // A new sentinel would trust whatever fingerprint is enrolled now, so it must not be created.
      expect(armed, isEmpty);
      expect(move.biometricsDropped, isTrue);
      final moved = (await repo.loadAll())[newUri]!;
      expect(moved.unlockMethod, ContainerUnlockMethod.password);
      expect(moved.rememberPassword, isFalse);
      expect(await repo.getPassword(newUri), isNull);
    });

    test('is dropped when the check itself cannot be completed', () async {
      biometricCheckError = StateError('keystore unavailable');
      await saveVault(ContainerUnlockMethod.biometrics);
      final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);

      expect(armed, isEmpty);
      expect(move.biometricsDropped, isTrue);
      expect((await repo.loadAll())[newUri]!.unlockMethod, ContainerUnlockMethod.password);
      expect(await repo.getPassword(newUri), isNull);
    });

    test('falls back to the password if Android refuses the new key', () async {
      armResult = false;
      await saveVault(ContainerUnlockMethod.biometrics);
      final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);

      expect(armed, [newUri]);
      expect(move.biometricsDropped, isTrue);
      expect((await repo.loadAll())[newUri]!.unlockMethod, ContainerUnlockMethod.password);
      expect(await repo.getPassword(newUri), isNull);
    });

    test('falls back to the password if creating the new key throws', () async {
      armError = StateError('boom');
      await saveVault(ContainerUnlockMethod.biometrics);
      final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);

      expect(move.biometricsDropped, isTrue);
      expect((await repo.loadAll())[newUri]!.unlockMethod, ContainerUnlockMethod.password);
    });

    test('other unlock methods never touch the biometric machinery', () async {
      for (final method in [
        ContainerUnlockMethod.password,
        ContainerUnlockMethod.rememberPassword,
        ContainerUnlockMethod.pattern,
        ContainerUnlockMethod.pin,
      ]) {
        await repo.remove(oldUri);
        await repo.remove(newUri);
        await saveVault(method);
        final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);
        expect(move.biometricsDropped, isFalse, reason: '$method');
        expect((await repo.loadAll())[newUri]!.unlockMethod, method, reason: '$method');
      }
      expect(checked, isEmpty);
      expect(armed, isEmpty);
    });
  });

  group('lockout state', () {
    test('moves with the vault', () async {
      await saveVault(ContainerUnlockMethod.pin);
      await store.moveRecord(oldUri: oldUri, newUri: newUri);
      expect(carried, [(oldUri, newUri)]);
    });

    test('a failure to carry it does not undo the move', () async {
      carryError = StateError('secure storage down');
      await saveVault(ContainerUnlockMethod.pin);
      final move = await store.moveRecord(oldUri: oldUri, newUri: newUri);
      expect(move.biometricsDropped, isFalse);
      expect((await repo.loadAll()).keys.toList(), [newUri]);
    });

    test('is not touched if the move itself fails', () async {
      await saveVault(ContainerUnlockMethod.pin);
      await repo.save(const ContainerRecord(uri: newUri, label: 'Already here'));
      await expectLater(
        store.moveRecord(oldUri: oldUri, newUri: newUri),
        throwsA(isA<StateError>()),
      );
      expect(carried, isEmpty);
    });
  });

  test('an unknown vault is rejected before anything is changed', () async {
    await expectLater(
      store.moveRecord(oldUri: oldUri, newUri: newUri),
      throwsA(isA<StateError>()),
    );
    expect(checked, isEmpty);
    expect(carried, isEmpty);
  });
}
