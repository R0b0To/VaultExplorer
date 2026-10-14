import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _FakeCryptoApi implements VaultCryptoApi {
  final List<String> clearedPaths = [];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _MemorySecureStorage secureStorage;
  late _FakeCryptoApi cryptoApi;
  late ContainerRepository repo;

  // URIs representing SAF tree URIs from the same cloud/nested location.
  // They share the first 140+ characters so their base64 encoding exceeds 180 characters.
  const sharedPrefix =
      'content://com.android.externalstorage.documents/tree/primary%3ACloudStorage%2FVeryLongParentDirectoryNameInsideCloudDriveAccount%2FNestedFolderStructure%2FVaults%2F';
  const uriA = '${sharedPrefix}CryptomatorVaultA_WithAVeryLongNameThatExceedsLimits';
  const uriB = '${sharedPrefix}CryptomatorVaultB_WithAVeryLongNameThatExceedsLimits';
  const uriC = '${sharedPrefix}CryptomatorVaultC_WithAVeryLongNameThatExceedsLimits';
  const shortUri = 'file:///storage/emulated/0/vault.hc';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('container_repo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    secureStorage = _MemorySecureStorage();
    cryptoApi = _FakeCryptoApi();
    repo = ContainerRepository.withCryptoApi(cryptoApi, secureStorage);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Key Generation & Collision Avoidance', () {
    test('short URIs match legacy keys exactly for full backward compatibility', () {
      expect(
        ContainerRepository.keystoreKey(shortUri),
        ContainerRepository.legacyKeystoreKey(shortUri),
      );
      expect(
        ContainerRepository.patternHashKey(shortUri),
        ContainerRepository.legacyPatternHashKey(shortUri),
      );
      expect(
        ContainerRepository.pinHashKey(shortUri),
        ContainerRepository.legacyPinHashKey(shortUri),
      );
      expect(
        ContainerRepository.bookmarkKey(shortUri),
        ContainerRepository.legacyBookmarkKey(shortUri),
      );
      expect(
        ContainerRepository.pinnedKey(shortUri),
        ContainerRepository.legacyPinnedKey(shortUri),
      );
      expect(
        ContainerRepository.docFoldersKey(shortUri),
        ContainerRepository.legacyDocFoldersKey(shortUri),
      );
      expect(
        ContainerRepository.keyfilesKey(shortUri),
        ContainerRepository.legacyKeyfilesKey(shortUri),
      );
      expect(
        ContainerRepository.compositeCarriersKey(shortUri),
        ContainerRepository.legacyCompositeCarriersKey(shortUri),
      );
    });

    test('long URIs sharing prefixes collide under legacy derivation', () {
      final legacyA = ContainerRepository.legacyKeystoreKey(uriA);
      final legacyB = ContainerRepository.legacyKeystoreKey(uriB);
      final legacyC = ContainerRepository.legacyKeystoreKey(uriC);

      // Verify that the legacy algorithm did in fact collide
      expect(legacyA, equals(legacyB));
      expect(legacyA, equals(legacyC));
    });

    test('long URIs generate unique, collision-free keys with required prefixes', () {
      final keyA = ContainerRepository.keystoreKey(uriA);
      final keyB = ContainerRepository.keystoreKey(uriB);
      final keyC = ContainerRepository.keystoreKey(uriC);

      // Distinct keys
      expect(keyA, isNot(equals(keyB)));
      expect(keyA, isNot(equals(keyC)));
      expect(keyB, isNot(equals(keyC)));

      // Required prefixes for panic wipe / StorageShredder
      expect(keyA.startsWith('vc2_pw_'), isTrue);
      expect(ContainerRepository.patternHashKey(uriA).startsWith('vc2_pattern_'), isTrue);
      expect(ContainerRepository.pinHashKey(uriA).startsWith('vc2_pin_hash_'), isTrue);
      expect(ContainerRepository.bookmarkKey(uriA).startsWith('vc2_fav_'), isTrue);
      expect(ContainerRepository.pinnedKey(uriA).startsWith('vc2_pin_'), isTrue);
      expect(ContainerRepository.docFoldersKey(uriA).startsWith('vc2_docfolders_'), isTrue);
      expect(ContainerRepository.keyfilesKey(uriA).startsWith('vc2_keyfiles_'), isTrue);
      expect(ContainerRepository.compositeCarriersKey(uriA).startsWith('vc2_composite_carriers_'), isTrue);

      // Key lengths are bounded and safe
      expect(keyA.length, lessThan(150));
      expect(ContainerRepository.compositeCarriersKey(uriA).length, lessThan(150));
    });
  });

  group('Biometric Credentials Collision Prevention (User Reported Issue)', () {
    test('saving an unremembered vault does not wipe another vault\'s saved password', () async {
      // Step 1: Save Vault A with biometric / remembered password
      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordA',
      );
      await repo.save(recordA);

      // Step 2: Save Vault B with biometric / remembered password
      final recordB = ContainerRecord(
        uri: uriB,
        label: 'Vault B',
        containerFormat: 'gocryptfs',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordB',
      );
      await repo.save(recordB);

      // Both passwords are saved independently
      expect(await repo.getPassword(uriA), 'PasswordA');
      expect(await repo.getPassword(uriB), 'PasswordB');

      // Step 3: Import Vault C as manual password (unlockMethod == password)
      final recordC = ContainerRecord(
        uri: uriC,
        label: 'Vault C',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.password,
      );
      await repo.save(recordC);

      // CRITICAL VERIFICATION:
      // In the legacy code, saving Vault C would have called _secure.delete(legacyKey),
      // which wiped Vault A & Vault B's shared password!
      // In the fixed code, Vault A and Vault B remain fully intact!
      expect(await repo.getPassword(uriA), 'PasswordA');
      expect(await repo.getPassword(uriB), 'PasswordB');
      expect(await repo.getPassword(uriC), isNull);
    });

    test('enabling biometric unlock on Vault C does not overwrite Vault A or B', () async {
      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordA',
      );
      await repo.save(recordA);

      final recordB = ContainerRecord(
        uri: uriB,
        label: 'Vault B',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordB',
      );
      await repo.save(recordB);

      final recordC = ContainerRecord(
        uri: uriC,
        label: 'Vault C',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordC',
      );
      await repo.save(recordC);

      expect(await repo.getPassword(uriA), 'PasswordA');
      expect(await repo.getPassword(uriB), 'PasswordB');
      expect(await repo.getPassword(uriC), 'PasswordC');
    });

    test('switching Vault A back to manual password does not delete Vault B\'s password', () async {
      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordA',
      );
      await repo.save(recordA);

      final recordB = ContainerRecord(
        uri: uriB,
        label: 'Vault B',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordB',
      );
      await repo.save(recordB);

      // Switch Vault A to password
      await repo.save(recordA.copyWith(unlockMethod: ContainerUnlockMethod.password));

      expect(await repo.getPassword(uriA), isNull);
      expect(await repo.getPassword(uriB), 'PasswordB');
    });

    test('removing Vault A does not delete Vault B\'s credentials', () async {
      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordA',
        bookmarkPaths: ['/docA'],
      );
      await repo.save(recordA);

      final recordB = ContainerRecord(
        uri: uriB,
        label: 'Vault B',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
        pendingPassword: 'PasswordB',
        bookmarkPaths: ['/docB'],
      );
      await repo.save(recordB);

      await repo.remove(uriA);

      expect(await repo.getPassword(uriA), isNull);
      expect(await repo.getPassword(uriB), 'PasswordB');

      final loadedB = (await repo.loadAll())[uriB];
      expect(loadedB, isNotNull);
      expect(loadedB!.bookmarkPaths, ['/docB']);
    });
  });

  group('Legacy Key Migration on Read', () {
    test('getPassword migrates legacy key to collision-free key', () async {
      final legacyKey = ContainerRepository.legacyKeystoreKey(uriA);
      final primaryKey = ContainerRepository.keystoreKey(uriA);
      expect(legacyKey, isNot(equals(primaryKey)));

      // Simulate a legacy vault saved by an older version of the app
      secureStorage.data[legacyKey] = 'OldSavedPassword';

      // Record in containers file
      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
      );
      final containersFile = File('${tempDir.path}/containers_v2.json');
      await containersFile.writeAsString(jsonEncode([recordA.toJson()]));

      // getPassword should find the legacy password, write to primaryKey, and clean up legacyKey
      final pw = await repo.getPassword(uriA);
      expect(pw, 'OldSavedPassword');
      expect(secureStorage.data[primaryKey], 'OldSavedPassword');
      expect(secureStorage.data[legacyKey], isNull);
    });

    test('getPatternHash and getPinHash migrate legacy keys', () async {
      final legacyPatternKey = ContainerRepository.legacyPatternHashKey(uriA);
      final primaryPatternKey = ContainerRepository.patternHashKey(uriA);
      final legacyPinKey = ContainerRepository.legacyPinHashKey(uriA);
      final primaryPinKey = ContainerRepository.pinHashKey(uriA);

      secureStorage.data[legacyPatternKey] = 'pattern_hash_123';
      secureStorage.data[legacyPinKey] = 'pin_hash_456';

      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.pattern,
      );
      final containersFile = File('${tempDir.path}/containers_v2.json');
      await containersFile.writeAsString(jsonEncode([recordA.toJson()]));

      expect(await repo.getPatternHash(uriA), 'pattern_hash_123');
      expect(secureStorage.data[primaryPatternKey], 'pattern_hash_123');
      expect(secureStorage.data[legacyPatternKey], isNull);

      expect(await repo.getPinHash(uriA), 'pin_hash_456');
      expect(secureStorage.data[primaryPinKey], 'pin_hash_456');
      expect(secureStorage.data[legacyPinKey], isNull);
    });

    test('preserves legacy key if another cached vault still shares it', () async {
      final legacyKey = ContainerRepository.legacyKeystoreKey(uriA);
      final primaryKeyA = ContainerRepository.keystoreKey(uriA);

      // Both vaults in containers file
      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
      );
      final recordB = ContainerRecord(
        uri: uriB,
        label: 'Vault B',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.biometrics,
      );
      final containersFile = File('${tempDir.path}/containers_v2.json');
      await containersFile.writeAsString(
        jsonEncode([recordA.toJson(), recordB.toJson()]),
      );

      // Legacy slot has a password
      secureStorage.data[legacyKey] = 'SharedLegacyPassword';

      // Load cache
      await repo.loadAll();

      // Read password for A
      final pwA = await repo.getPassword(uriA);
      expect(pwA, 'SharedLegacyPassword');
      expect(secureStorage.data[primaryKeyA], 'SharedLegacyPassword');
      // Legacy key must NOT be deleted yet because Vault B also shares it!
      expect(secureStorage.data[legacyKey], 'SharedLegacyPassword');

      // Now read password for B
      final pwB = await repo.getPassword(uriB);
      expect(pwB, 'SharedLegacyPassword');
      final primaryKeyB = ContainerRepository.keystoreKey(uriB);
      expect(secureStorage.data[primaryKeyB], 'SharedLegacyPassword');
    });
  });

  group('Hydration & Legacy Migration of Secure Metadata', () {
    test('_hydrate migrates legacy bookmarks, pinned paths, and doc folders', () async {
      final legacyBookmarkKey = ContainerRepository.legacyBookmarkKey(uriA);
      final primaryBookmarkKey = ContainerRepository.bookmarkKey(uriA);
      final legacyPinnedKey = ContainerRepository.legacyPinnedKey(uriA);
      final primaryPinnedKey = ContainerRepository.pinnedKey(uriA);
      final legacyDocFoldersKey = ContainerRepository.legacyDocFoldersKey(uriA);
      final primaryDocFoldersKey = ContainerRepository.docFoldersKey(uriA);

      secureStorage.data[legacyBookmarkKey] = jsonEncode(['/legacy/bookmark']);
      secureStorage.data[legacyPinnedKey] = jsonEncode(['/legacy/pinned']);
      secureStorage.data[legacyDocFoldersKey] = jsonEncode([
        {'path': '/legacy/docs', 'autoMount': true},
      ]);

      final recordA = ContainerRecord(
        uri: uriA,
        label: 'Vault A',
        containerFormat: 'cryptomator',
        unlockMethod: ContainerUnlockMethod.password,
      );
      final containersFile = File('${tempDir.path}/containers_v2.json');
      await containersFile.writeAsString(jsonEncode([recordA.toJson()]));

      // Hydrate
      final all = await repo.loadAll();
      final loaded = all[uriA]!;

      expect(loaded.bookmarkPaths, ['/legacy/bookmark']);
      expect(loaded.pinnedPaths, ['/legacy/pinned']);
      expect(loaded.documentProviderFolders.length, 1);
      expect(loaded.documentProviderFolders.first.path, '/legacy/docs');
      expect(loaded.documentProviderFolders.first.autoMount, isTrue);

      // Should be migrated into primary keys
      expect(secureStorage.data[primaryBookmarkKey], jsonEncode(['/legacy/bookmark']));
      expect(secureStorage.data[primaryPinnedKey], jsonEncode(['/legacy/pinned']));
      expect(
        secureStorage.data[primaryDocFoldersKey],
        jsonEncode([{'path': '/legacy/docs', 'autoMount': true}]),
      );
    });
  });

  group('Saved PIM (custom unlock credentials)', () {
    // Pattern / PIN / biometric unlock replays the saved credentials, so the
    // PIM saved by the config flow has to be readable through the repository.
    test('getPim returns null when no PIM was saved', () async {
      expect(await repo.getPim(shortUri), isNull);
    });

    test('getPim reads the PIM the config flow stored', () async {
      secureStorage.data[pimStorageKey(shortUri)] = ' 485 ';
      expect(await repo.getPim(shortUri), '485');
    });

    test('getPim treats a blank stored value as no PIM', () async {
      secureStorage.data[pimStorageKey(shortUri)] = '   ';
      expect(await repo.getPim(shortUri), isNull);
    });

    test('getPim is keyed per container', () async {
      secureStorage.data[pimStorageKey(uriA)] = '12';
      expect(await repo.getPim(uriA), '12');
      expect(await repo.getPim(uriB), isNull);
    });

    test('setPim saves a PIM that getPim reads back', () async {
      await repo.setPim(shortUri, 485);
      expect(secureStorage.data[pimStorageKey(shortUri)], '485');
      expect(await repo.getPim(shortUri), '485');
    });

    test('setPim with null or 0 clears the saved PIM', () async {
      await repo.setPim(shortUri, 485);
      await repo.setPim(shortUri, 0);
      expect(await repo.getPim(shortUri), isNull);

      await repo.setPim(shortUri, 485);
      await repo.setPim(shortUri, null);
      expect(await repo.getPim(shortUri), isNull);
    });

    test('setTempPim is separate from the saved PIM and clears on 0', () async {
      await repo.setPim(shortUri, 100);
      await repo.setTempPim(shortUri, 485);
      expect(secureStorage.data[tempPimStorageKey(shortUri)], '485');
      expect(await repo.getPim(shortUri), '100');

      await repo.setTempPim(shortUri, 0);
      expect(secureStorage.data.containsKey(tempPimStorageKey(shortUri)), isFalse);
      expect(await repo.getPim(shortUri), '100');
    });

    test('remove drops the saved PIM with the rest of the record', () async {
      await repo.save(
        ContainerRecord(
          uri: shortUri,
          label: 'Vault',
          unlockMethod: ContainerUnlockMethod.pattern,
          pendingPassword: 'pw',
          pendingPatternHash: 'hash',
        ),
      );
      secureStorage.data[pimStorageKey(shortUri)] = '485';

      await repo.remove(shortUri);

      expect(secureStorage.data.containsKey(pimStorageKey(shortUri)), isFalse);
      expect(await repo.getPim(shortUri), isNull);
    });
  });

  group('Temp keyfiles of the current manual unlock', () {
    const kf = [
      {'uri': 'content://keys/a.key', 'name': 'a.key'},
      {'uri': 'content://keys/b.key', 'name': 'b.key'},
    ];

    test('getTempKeyfiles is empty when nothing was kept', () async {
      expect(await repo.getTempKeyfiles(shortUri), isEmpty);
    });

    test('setTempKeyfiles round-trips uri and name in order', () async {
      await repo.setTempKeyfiles(shortUri, kf);
      expect(await repo.getTempKeyfiles(shortUri), kf);
    });

    test('setTempKeyfiles with an empty list clears them', () async {
      await repo.setTempKeyfiles(shortUri, kf);
      await repo.setTempKeyfiles(shortUri, const []);
      expect(
        secureStorage.data.containsKey(tempKeyfilesStorageKey(shortUri)),
        isFalse,
      );
      expect(await repo.getTempKeyfiles(shortUri), isEmpty);
    });

    test('temp keyfiles are keyed per container', () async {
      await repo.setTempKeyfiles(uriA, kf);
      expect(await repo.getTempKeyfiles(uriA), kf);
      expect(await repo.getTempKeyfiles(uriB), isEmpty);
    });

    test('malformed stored value reads back as no keyfiles', () async {
      secureStorage.data[tempKeyfilesStorageKey(shortUri)] = 'not json';
      expect(await repo.getTempKeyfiles(shortUri), isEmpty);
    });

    test('remove drops temp keyfiles and temp PIM with the record', () async {
      await repo.save(
        ContainerRecord(uri: shortUri, label: 'Vault', keyfiles: kf),
      );
      await repo.setTempKeyfiles(shortUri, kf);
      await repo.setTempPim(shortUri, 485);

      await repo.remove(shortUri);

      expect(
        secureStorage.data.containsKey(tempKeyfilesStorageKey(shortUri)),
        isFalse,
      );
      expect(
        secureStorage.data.containsKey(tempPimStorageKey(shortUri)),
        isFalse,
      );
    });
  });
}
