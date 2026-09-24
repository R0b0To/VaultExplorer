import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/derived_key_expiry_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _FakeCryptoApi implements VaultCryptoApi {
  _FakeCryptoApi([this.purged = const []]);
  final List<String> purged;
  int purgeCalls = 0;

  @override
  Future<List<String>> purgeExpiredDerivedKeys() async {
    purgeCalls++;
    return purged;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRepository extends ContainerRepository {
  _RecordingRepository(VaultCryptoApi api, {this.result = 0})
    : super.withCryptoApi(api);

  final int result;
  Iterable<String>? received;

  @override
  Future<int> disableDerivedKeyCachingFor(Iterable<String> keyPaths) async {
    received = keyPaths.toList();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('derivedKeyPathForUri', () {
    test('strips the synthetic usb: scheme down to the device name', () {
      expect(
        derivedKeyPathForUri('usb:/dev/bus/usb/001/002'),
        '/dev/bus/usb/001/002',
      );
    });

    test('leaves every other URI untouched', () {
      expect(derivedKeyPathForUri('content://a/b'), 'content://a/b');
      expect(derivedKeyPathForUri('file:///vault.hc'), 'file:///vault.hc');
      expect(derivedKeyPathForUri('composite:abc'), 'composite:abc');
    });
  });

  group('DerivedKeyExpiryService', () {
    test('does nothing when no key had expired', () async {
      final api = _FakeCryptoApi();
      final repo = _RecordingRepository(api);

      final changed = await DerivedKeyExpiryService(
        cryptoApi: api,
        repository: repo,
      ).purgeExpired();

      expect(changed, 0);
      expect(api.purgeCalls, 1);
      expect(repo.received, isNull);
    });

    test('switches caching off for the vaults whose keys were purged', () async {
      final api = _FakeCryptoApi(['content://a', '/dev/bus/usb/001/002']);
      final repo = _RecordingRepository(api, result: 2);

      final changed = await DerivedKeyExpiryService(
        cryptoApi: api,
        repository: repo,
      ).purgeExpired();

      expect(changed, 2);
      expect(repo.received, ['content://a', '/dev/bus/usb/001/002']);
    });
  });

  group('ContainerRepository.disableDerivedKeyCachingFor', () {
    late Directory tempDir;
    late PathProviderPlatform originalPlatform;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('container_repo_test_');
      originalPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPlatform;
      tempDir.deleteSync(recursive: true);
    });

    Map<String, dynamic> record(String uri, {required bool cache}) => {
      'uri': uri,
      'label': uri,
      'cacheDerivedKey': cache,
    };

    void seed(List<Map<String, dynamic>> records) => File(
      '${tempDir.path}/containers_v2.json',
    ).writeAsStringSync(jsonEncode(records));

    List<dynamic> onDisk() =>
        jsonDecode(File('${tempDir.path}/containers_v2.json').readAsStringSync())
            as List<dynamic>;

    test('only switches off caching for the listed vaults', () async {
      seed([
        record('content://a', cache: true),
        record('usb:/dev/bus/usb/001/002', cache: true),
        record('content://b', cache: true),
        record('content://c', cache: false),
      ]);
      final repo = ContainerRepository.withCryptoApi(_FakeCryptoApi());

      final changed = await repo.disableDerivedKeyCachingFor([
        'content://a',
        '/dev/bus/usb/001/002',
        'content://c',
      ]);

      expect(changed, 2);
      final records = await repo.loadAll();
      expect(records['content://a']!.cacheDerivedKey, isFalse);
      expect(records['usb:/dev/bus/usb/001/002']!.cacheDerivedKey, isFalse);
      expect(records['content://b']!.cacheDerivedKey, isTrue);

      final persisted = {
        for (final r in onDisk().cast<Map<String, dynamic>>())
          r['uri'] as String: r['cacheDerivedKey'] as bool,
      };
      expect(persisted, {
        'content://a': false,
        'usb:/dev/bus/usb/001/002': false,
        'content://b': true,
        'content://c': false,
      });
    });

    test('a second call has nothing left to change', () async {
      seed([record('content://a', cache: true)]);
      final repo = ContainerRepository.withCryptoApi(_FakeCryptoApi());

      expect(await repo.disableDerivedKeyCachingFor(['content://a']), 1);
      expect(await repo.disableDerivedKeyCachingFor(['content://a']), 0);
    });
  });
}
