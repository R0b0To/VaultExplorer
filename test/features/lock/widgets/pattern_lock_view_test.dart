import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';

/// Fakes [VaultCryptoApi.hashPasswordSha256], the platform-channel call
/// [hashPattern]/[verifyPattern] use for their PBKDF2-SHA256 derivation,
/// mirroring the fake-per-test-file pattern already used elsewhere in this
/// suite (see e.g. hash_verifier_service_test.dart) rather than a real
/// platform channel.
///
/// Deliberately not a real digest -- these tests check hashPattern/
/// verifyPattern's own logic (salt handling, the "salt:hash" storage
/// format, round-trip correctness, and how malformed input is rejected),
/// not that PBKDF2-SHA256 itself is cryptographically sound. What this
/// fake does need, to make those checks meaningful, is to actually depend
/// on both the password and the salt bytes: deterministic for the same
/// (password, salt) pair, but different whenever either one changes.
class _FakeCryptoApi extends VaultCryptoApi {
  int calls = 0;

  _FakeCryptoApi() : super(const MethodChannel('test'));

  @override
  Future<Uint8List?> hashPasswordSha256({
    required String password,
    required Uint8List salt,
    int iterations = 50000,
    int outputLen = 32,
  }) async {
    calls++;
    final input = utf8.encode(password);
    final out = Uint8List(outputLen);
    var acc = iterations;
    for (var i = 0; i < outputLen; i++) {
      final pByte = input.isEmpty ? 0 : input[i % input.length];
      final sByte = salt.isEmpty ? 0 : salt[i % salt.length];
      acc = (acc * 31 + pByte + sByte + i) & 0xFFFFFFFF;
      out[i] = acc & 0xFF;
    }
    return out;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCryptoApi cryptoApi;

  setUp(() => cryptoApi = _FakeCryptoApi());

  group('hashPattern', () {
    test(
      'produces a "salt:hash" string of two non-empty base64 parts',
      () async {
        final stored = await hashPattern(cryptoApi, [0, 1, 2, 5, 8]);

        final parts = stored.split(':');
        expect(parts, hasLength(2));
        expect(() => base64Decode(parts[0]), returnsNormally);
        expect(() => base64Decode(parts[1]), returnsNormally);
        expect(base64Decode(parts[0]), isNotEmpty);
        expect(base64Decode(parts[1]), isNotEmpty);
      },
    );

    test('two calls for the same pattern use different random salts', () async {
      const pattern = [0, 1, 2, 5];

      final first = await hashPattern(cryptoApi, pattern);
      final second = await hashPattern(cryptoApi, pattern);

      expect(
        first,
        isNot(equals(second)),
        reason:
            'a fixed salt would make every stored hash for the same pattern identical',
      );
      expect(first.split(':')[0], isNot(equals(second.split(':')[0])));
    });
  });

  group('verifyPattern round-trip', () {
    test('the pattern that produced a hash verifies against it', () async {
      const pattern = [0, 4, 8, 7, 6];
      final stored = await hashPattern(cryptoApi, pattern);

      expect(await verifyPattern(cryptoApi, pattern, stored), isTrue);
    });

    test(
      'a different pattern does not verify against another pattern\'s hash',
      () async {
        final stored = await hashPattern(cryptoApi, [0, 1, 2, 5]);

        expect(await verifyPattern(cryptoApi, [0, 1, 2, 6], stored), isFalse);
      },
    );

    test(
      'the same dots in a different order do not verify -- order is part of the secret',
      () async {
        final stored = await hashPattern(cryptoApi, [0, 1, 2, 3]);

        expect(await verifyPattern(cryptoApi, [3, 2, 1, 0], stored), isFalse);
      },
    );

    test(
      'verification is stable across repeated calls (deterministic given a fixed salt)',
      () async {
        const pattern = [1, 4, 7, 8, 5, 2];
        final stored = await hashPattern(cryptoApi, pattern);

        expect(await verifyPattern(cryptoApi, pattern, stored), isTrue);
        expect(await verifyPattern(cryptoApi, pattern, stored), isTrue);
        expect(await verifyPattern(cryptoApi, pattern, stored), isTrue);
      },
    );
  });

  group('verifyPattern malformed/absent input', () {
    test('returns false for a null stored value instead of throwing', () async {
      expect(await verifyPattern(cryptoApi, [0, 1, 2, 3], null), isFalse);
    });

    test('returns false for an empty stored value', () async {
      expect(await verifyPattern(cryptoApi, [0, 1, 2, 3], ''), isFalse);
    });

    test(
      'returns false when there is no colon separator (legacy single-hash format)',
      () async {
        // Documents the deliberate breaking change noted in this file's own
        // top-of-file comment: a pre-migration unsalted SHA-256 string has
        // no ':' and must be rejected, not partially parsed.
        expect(
          await verifyPattern(cryptoApi, [
            0,
            1,
            2,
            3,
          ], 'justonestringwithnocolon'),
          isFalse,
        );
      },
    );

    test(
      'returns false when the stored value has more than one colon',
      () async {
        expect(await verifyPattern(cryptoApi, [0, 1, 2, 3], 'a:b:c'), isFalse);
      },
    );

    test(
      'returns false for non-base64 salt or hash instead of throwing',
      () async {
        expect(
          await verifyPattern(cryptoApi, [
            0,
            1,
            2,
            3,
          ], 'not-base64!!:also-not-base64!!'),
          isFalse,
        );
      },
    );
  });
}
