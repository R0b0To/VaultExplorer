import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

// What ContainerRepository asks secure storage for on a cold start, and that
// overlapping loadAll() calls share one hydrate instead of racing.

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _FakeCryptoApi implements VaultCryptoApi {
  @override
  Future<bool> clearDerivedKey(String filePath,
          {bool removeExpiry = false}) async =>
      true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSecureStorage extends AppSecureStorage {
  final Map<String, String> data = {};

  int unfilteredReadAllCalls = 0;
  final List<List<String>> prefixRequests = [];
  final List<Map<String, String>> prefixResults = [];

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
  Future<void> delete({required String key}) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<Map<String, String>> readAll() async {
    unfilteredReadAllCalls++;
    return Map.of(data);
  }

  @override
  Future<Map<String, String>> readAllWithPrefixes(
    List<String> prefixes, {
    List<String> excludePrefixes = const [],
  }) async {
    prefixRequests.add(prefixes);
    // A real round trip, so a second caller can arrive while this is pending.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final result = {
      for (final e in data.entries)
        if (prefixes.any(e.key.startsWith) &&
            !excludePrefixes.any(e.key.startsWith))
          e.key: e.value,
    };
    prefixResults.add(result);
    return result;
  }

  @override
  Future<bool> containsKey({required String key}) async =>
      data.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uri = 'file:///storage/emulated/0/vault.hc';

  late Directory tempDir;
  late _RecordingSecureStorage storage;

  /// A new repository over the same files and secure storage: its cache is
  /// empty, so loadAll() has to hydrate, as it does on a cold start.
  ContainerRepository coldRepo() =>
      ContainerRepository.withCryptoApi(_FakeCryptoApi(), storage);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('container_hydrate_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    storage = _RecordingSecureStorage();

    await coldRepo().save(
      const ContainerRecord(
        uri: uri,
        label: 'Vault',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'remembered-password',
        keyfiles: [
          {'uri': 'file:///keys/a.key', 'name': 'a.key'},
        ],
      ),
    );
    storage.data[ContainerRepository.pinHashKey(uri)] = 'pin-hash';
    // A read-only vault's device-only bookmarks (VaultMarksStore). They are
    // read on demand, never at startup.
    storage.data[ContainerRepository.marksKey(uri)] = '{"bookmarks":[]}';

    storage.prefixRequests.clear();
    storage.prefixResults.clear();
    storage.unfilteredReadAllCalls = 0;
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('hydrate still restores keyfiles from secure storage', () async {
    final record = (await coldRepo().loadAll())[uri];

    expect(record, isNotNull);
    expect(record!.keyfiles, [
      {'uri': 'file:///keys/a.key', 'name': 'a.key'},
    ]);
  });

  test('hydrate never reads the remembered password or the PIN hash', () async {
    await coldRepo().loadAll();

    expect(storage.unfilteredReadAllCalls, 0);
    expect(storage.prefixResults, hasLength(1));
    final fetched = storage.prefixResults.single.keys;
    expect(fetched.any((k) => k.startsWith('vc2_pw_')), isFalse);
    expect(fetched.any((k) => k.startsWith('vc2_pin_hash_')), isFalse);
    // Nor a vault's bookmarks: those are only read once it is unlocked.
    expect(fetched.any((k) => k.startsWith('vc2_marks_')), isFalse);
    // ...while the metadata it does need was part of the same read.
    expect(fetched, contains(ContainerRepository.keyfilesKey(uri)));
  });

  test('overlapping loadAll() calls share one hydrate and agree', () async {
    final repo = coldRepo();

    final results = await Future.wait([repo.loadAll(), repo.loadAll()]);

    expect(storage.prefixRequests, hasLength(1));
    for (final records in results) {
      expect(records[uri]?.keyfiles, hasLength(1));
    }
  });

  test('a later loadAll() is served from the cache', () async {
    final repo = coldRepo();
    await repo.loadAll();
    await repo.loadAll();

    expect(storage.prefixRequests, hasLength(1));
  });
}
