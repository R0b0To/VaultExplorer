import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

// NOTE: authored from scratch (see container_unlock_method_pin_test.dart for
// why), not run against the Flutter toolchain -- please verify with
// `flutter test` locally.
//
// hashPin/verifyPin call through to the native mbedTLS PBKDF2 implementation
// via the `com.aeidolon.vaultexplorer/engine` MethodChannel
// (ChannelMethods.hashPasswordSha256), same as PatternLockView's
// hashPattern/verifyPattern. There's no real crypto to exercise in a pure
// Dart test, so this stubs the channel with a simple deterministic (but
// salt- and input-sensitive) fake KDF -- enough to prove hashPin/verifyPin's
// own Dart-side logic (encoding, salting, matching, malformed-input
// handling) is correct, independent of whatever the real native
// implementation does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const cryptoApi = VaultCryptoApi(channel);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'hashPasswordSha256') {
            final password = call.arguments['password'] as String;
            final salt = call.arguments['salt'] as Uint8List;
            final outputLen = call.arguments['outputLen'] as int;
            // Deterministic fake KDF: NOT real crypto, only used to prove
            // hashPin/verifyPin's own logic round-trips correctly.
            final input = utf8.encode(password) + salt;
            final out = Uint8List(outputLen);
            for (var i = 0; i < outputLen; i++) {
              out[i] = input[i % input.length] ^ (i & 0xff);
            }
            return out;
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('hashPin / verifyPin', () {
    test('hashPin returns "<saltB64>:<hashB64>"', () async {
      final hash = await hashPin(cryptoApi, '1234');
      final parts = hash.split(':');
      expect(parts, hasLength(2));
      expect(() => base64Decode(parts[0]), returnsNormally);
      expect(() => base64Decode(parts[1]), returnsNormally);
    });

    test('verifyPin succeeds for the PIN that produced the hash', () async {
      const pin = '481920';
      final hash = await hashPin(cryptoApi, pin);
      expect(await verifyPin(cryptoApi, pin, hash), isTrue);
    });

    test('verifyPin fails for a different PIN', () async {
      final hash = await hashPin(cryptoApi, '1111');
      expect(await verifyPin(cryptoApi, '1112', hash), isFalse);
    });

    test('verifyPin fails for a null stored hash', () async {
      expect(await verifyPin(cryptoApi, '1234', null), isFalse);
    });

    test('verifyPin fails for a malformed stored hash', () async {
      expect(await verifyPin(cryptoApi, '1234', 'not-a-valid-hash'), isFalse);
      expect(
        await verifyPin(cryptoApi, '1234', 'only:one:colon:too:many'),
        isFalse,
      );
      expect(await verifyPin(cryptoApi, '1234', ''), isFalse);
    });

    test(
      'two hashPin calls for the same PIN use different random salts',
      () async {
        final first = await hashPin(cryptoApi, '0000');
        final second = await hashPin(cryptoApi, '0000');
        expect(first, isNot(second));
        // ...but both still verify correctly against the same PIN.
        expect(await verifyPin(cryptoApi, '0000', first), isTrue);
        expect(await verifyPin(cryptoApi, '0000', second), isTrue);
      },
    );
  });
}
