import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const api = VaultCryptoApi(channel);

  final calls = <MethodCall>[];
  Object? nextResult;

  setUp(() {
    calls.clear();
    nextResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return nextResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('vaultCryptoApiProvider resolves from ProviderContainer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final resolvedApi = container.read(vaultCryptoApiProvider);
    expect(resolvedApi, isA<VaultCryptoApi>());
  });

  group('hashPassword', () {
    test('sends method name, password, salt and iterations', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      nextResult = Uint8List.fromList(List.filled(64, 7));

      final result = await api.hashPassword(
        password: 'hunter2',
        salt: salt,
        iterations: 12345,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'hashPassword');
      expect(calls.single.arguments['password'], 'hunter2');
      expect(calls.single.arguments['salt'], salt);
      expect(calls.single.arguments['iterations'], 12345);
      expect(result, nextResult);
    });

    test('defaults iterations to 200000', () async {
      nextResult = Uint8List(64);
      await api.hashPassword(password: 'x', salt: Uint8List.fromList([1]));

      expect(calls.single.arguments['iterations'], 200000);
    });
  });

  group('hashPasswordSha256', () {
    test('defaults iterations to 50000 and outputLen to 32', () async {
      nextResult = Uint8List(32);
      await api.hashPasswordSha256(
        password: 'x',
        salt: Uint8List.fromList([1]),
      );

      expect(calls.single.method, 'hashPasswordSha256');
      expect(calls.single.arguments['iterations'], 50000);
      expect(calls.single.arguments['outputLen'], 32);
    });
  });

  group('aesGcmEncrypt / aesGcmDecrypt', () {
    test('encrypt sends key, iv and plaintext, returns raw bytes', () async {
      final key = Uint8List.fromList(List.filled(32, 1));
      final iv = Uint8List.fromList(List.filled(12, 2));
      final plaintext = Uint8List.fromList([9, 9, 9]);
      nextResult = Uint8List.fromList([1, 2, 3, 4]);

      final result = await api.aesGcmEncrypt(
        key: key,
        iv: iv,
        plaintext: plaintext,
      );

      expect(calls.single.method, 'aesGcmEncrypt');
      expect(calls.single.arguments['key'], key);
      expect(calls.single.arguments['iv'], iv);
      expect(calls.single.arguments['plaintext'], plaintext);
      expect(result, nextResult);
    });

    test('decrypt sends key, iv and ciphertextAndTag', () async {
      final key = Uint8List.fromList(List.filled(32, 1));
      final iv = Uint8List.fromList(List.filled(12, 2));
      final ciphertext = Uint8List.fromList([5, 6, 7]);
      nextResult = Uint8List.fromList([9, 9]);

      final result = await api.aesGcmDecrypt(
        key: key,
        iv: iv,
        ciphertextAndTag: ciphertext,
      );

      expect(calls.single.method, 'aesGcmDecrypt');
      expect(calls.single.arguments['ciphertextAndTag'], ciphertext);
      expect(result, nextResult);
    });
  });

  group('getAvifInfo', () {
    test('parses a well-formed 4-element result', () async {
      nextResult = <Object?>[100, 200, 5, 1500];

      final info = await api.getAvifInfo(Uint8List.fromList([1]));

      expect(info, isNotNull);
      expect(info!.width, 100);
      expect(info.height, 200);
      expect(info.frameCount, 5);
      expect(info.totalDurationMs, 1500);
    });

    test('returns null when the channel returns null', () async {
      nextResult = null;
      final info = await api.getAvifInfo(Uint8List.fromList([1]));
      expect(info, isNull);
    });

    test('returns null when the result has fewer than 4 elements', () async {
      nextResult = <Object?>[100, 200];
      final info = await api.getAvifInfo(Uint8List.fromList([1]));
      expect(info, isNull);
    });
  });

  group('decodeAvif', () {
    test('parses dimensions and frames, defaulting missing durationMs to 100', () async {
      final rgba = Uint8List.fromList([1, 2, 3]);
      nextResult = <String, dynamic>{
        'width': 64,
        'height': 48,
        'totalDurationMs': 300,
        'frames': [
          {'rgbaBytes': rgba},
          {'rgbaBytes': rgba, 'durationMs': 250},
        ],
      };

      final decoded = await api.decodeAvif(Uint8List.fromList([1]));

      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 48);
      expect(decoded.totalDurationMs, 300);
      expect(decoded.frames, hasLength(2));
      expect(decoded.frames[0].durationMs, 100);
      expect(decoded.frames[1].durationMs, 250);
    });

    test('returns null when the channel returns null', () async {
      nextResult = null;
      final decoded = await api.decodeAvif(Uint8List.fromList([1]));
      expect(decoded, isNull);
    });

    test('treats a missing frames key as an empty frame list', () async {
      nextResult = <String, dynamic>{
        'width': 1,
        'height': 1,
        'totalDurationMs': 0,
      };

      final decoded = await api.decodeAvif(Uint8List.fromList([1]));

      expect(decoded, isNotNull);
      expect(decoded!.frames, isEmpty);
    });
  });

  group('decodeAvifFrame', () {
    test('parses a single frame and passes frameIndex through', () async {
      final rgba = Uint8List.fromList([4, 5, 6]);
      nextResult = <String, dynamic>{'rgbaBytes': rgba, 'durationMs': 80};

      final frame = await api.decodeAvifFrame(Uint8List.fromList([1]), 3);

      expect(calls.single.arguments['frameIndex'], 3);
      expect(frame, isNotNull);
      expect(frame!.rgbaBytes, rgba);
      expect(frame.durationMs, 80);
    });

    test('returns null when the channel returns null', () async {
      nextResult = null;
      final frame = await api.decodeAvifFrame(Uint8List.fromList([1]), 0);
      expect(frame, isNull);
    });
  });

  group('deriveDerivedKey', () {
    test('base64-decodes a non-empty result', () async {
      final keyBytes = Uint8List.fromList(List.filled(64, 3));
      nextResult = base64Encode(keyBytes);

      final result = await api.deriveDerivedKey(
        filePath: '/tmp/vault.hc',
        password: 'pw',
        pim: 0,
      );

      expect(result, keyBytes);
    });

    test('returns null on a null or empty result', () async {
      nextResult = null;
      expect(
        await api.deriveDerivedKey(
          filePath: '/tmp/a',
          password: 'pw',
          pim: 0,
        ),
        isNull,
      );

      nextResult = '';
      expect(
        await api.deriveDerivedKey(
          filePath: '/tmp/a',
          password: 'pw',
          pim: 0,
        ),
        isNull,
      );
    });

    test('defaults cipherId and hashId to 255 when omitted', () async {
      nextResult = null;
      await api.deriveDerivedKey(filePath: '/tmp/a', password: 'pw', pim: 0);

      expect(calls.single.arguments['cipherId'], 255);
      expect(calls.single.arguments['hashId'], 255);
      expect(calls.single.arguments.containsKey('keyfilePaths'), isFalse);
    });

    test('includes keyfilePaths only when non-empty', () async {
      nextResult = null;
      await api.deriveDerivedKey(
        filePath: '/tmp/a',
        password: 'pw',
        pim: 0,
        keyfilePaths: const ['/tmp/key1'],
      );

      expect(calls.single.arguments['keyfilePaths'], ['/tmp/key1']);
    });
  });

  group('storeDerivedKey / loadDerivedKey / clearDerivedKey', () {
    test('storeDerivedKey base64-encodes the key and returns the bool result', () async {
      final derivedKey = Uint8List.fromList([10, 20, 30]);
      nextResult = true;

      final ok = await api.storeDerivedKey('/tmp/a', derivedKey);

      expect(calls.single.arguments['derivedKey'], base64Encode(derivedKey));
      expect(ok, isTrue);
    });

    test('storeDerivedKey defaults to false when the channel returns null', () async {
      nextResult = null;
      final ok = await api.storeDerivedKey('/tmp/a', Uint8List.fromList([1]));
      expect(ok, isFalse);
    });

    test('loadDerivedKey base64-decodes a non-empty result', () async {
      final keyBytes = Uint8List.fromList([1, 2, 3, 4]);
      nextResult = base64Encode(keyBytes);

      final result = await api.loadDerivedKey('/tmp/a');

      expect(result, keyBytes);
    });

    test('loadDerivedKey returns null on a null or empty result', () async {
      nextResult = null;
      expect(await api.loadDerivedKey('/tmp/a'), isNull);

      nextResult = '';
      expect(await api.loadDerivedKey('/tmp/a'), isNull);
    });

    test('clearDerivedKey defaults to false when the channel returns null', () async {
      nextResult = null;
      expect(await api.clearDerivedKey('/tmp/a'), isFalse);

      nextResult = true;
      expect(await api.clearDerivedKey('/tmp/a'), isTrue);
    });
  });
}