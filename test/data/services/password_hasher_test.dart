import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';

/// Fakes the native PBKDF2 call with a simple, deterministic, in-Dart
/// stand-in: `hash = sha-like fold of password bytes XORed with salt`,
/// repeated to a fixed 64-byte output. It doesn't need to be
/// cryptographically meaningful -- it only needs to be a pure function of
/// (password, salt) so PasswordHasher's own derive/verify/compare logic can
/// be exercised without the real mbedTLS/JNI layer.
class _FakePbkdf2Api extends VaultCryptoApi {
  int callCount = 0;
  bool returnNull = false;
  bool returnEmpty = false;

  _FakePbkdf2Api() : super(const MethodChannel('test'));

  @override
  Future<Uint8List?> hashPassword({
    required String password,
    required Uint8List salt,
    int iterations = 200000,
  }) async {
    callCount++;
    if (returnNull) return null;
    if (returnEmpty) return Uint8List(0);

    final pwBytes = utf8.encode(password);
    final out = Uint8List(64);
    for (var i = 0; i < out.length; i++) {
      final p = pwBytes.isEmpty ? 0 : pwBytes[i % pwBytes.length];
      final s = salt.isEmpty ? 0 : salt[i % salt.length];
      out[i] = (p ^ s ^ (iterations & 0xff)) & 0xff;
    }
    return out;
  }
}

void main() {
  late _FakePbkdf2Api fake;
  late PasswordHasher hasher;

  setUp(() {
    fake = _FakePbkdf2Api();
    hasher = PasswordHasher(fake);
  });

  group('deriveHash', () {
    test('returns base64-encoded hash and salt', () async {
      final result = await hasher.deriveHash('correct horse battery');

      expect(() => base64Decode(result.hash), returnsNormally);
      expect(() => base64Decode(result.salt), returnsNormally);
      expect(fake.callCount, 1);
    });

    test('generates a 16-byte salt', () async {
      final result = await hasher.deriveHash('anything');

      expect(base64Decode(result.salt), hasLength(16));
    });

    test('two calls produce different salts', () async {
      final a = await hasher.deriveHash('same password');
      final b = await hasher.deriveHash('same password');

      // Different random salts should (overwhelmingly likely) produce
      // different hashes even for the same password.
      expect(a.salt, isNot(equals(b.salt)));
      expect(a.hash, isNot(equals(b.hash)));
    });

    test('throws StateError when the native layer returns null', () async {
      fake.returnNull = true;

      expect(() => hasher.deriveHash('pw'), throwsA(isA<StateError>()));
    });

    test(
      'throws StateError when the native layer returns empty bytes',
      () async {
        fake.returnEmpty = true;

        expect(() => hasher.deriveHash('pw'), throwsA(isA<StateError>()));
      },
    );
  });

  group('verify', () {
    test(
      'returns true for the exact password that produced the hash',
      () async {
        final derived = await hasher.deriveHash('my-real-password');

        final ok = await hasher.verify(
          candidate: 'my-real-password',
          hash: derived.hash,
          salt: derived.salt,
        );

        expect(ok, isTrue);
      },
    );

    test('returns false for a wrong password', () async {
      final derived = await hasher.deriveHash('my-real-password');

      final ok = await hasher.verify(
        candidate: 'a-wrong-guess',
        hash: derived.hash,
        salt: derived.salt,
      );

      expect(ok, isFalse);
    });

    test('returns false when hash is null', () async {
      final ok = await hasher.verify(
        candidate: 'anything',
        hash: null,
        salt: base64Encode(Uint8List(16)),
      );

      expect(ok, isFalse);
      // Should short-circuit before touching the native layer at all.
      expect(fake.callCount, 0);
    });

    test('returns false when salt is null', () async {
      final ok = await hasher.verify(
        candidate: 'anything',
        hash: base64Encode(Uint8List(64)),
        salt: null,
      );

      expect(ok, isFalse);
      expect(fake.callCount, 0);
    });

    test('returns false when salt is empty', () async {
      final ok = await hasher.verify(
        candidate: 'anything',
        hash: base64Encode(Uint8List(64)),
        salt: '',
      );

      expect(ok, isFalse);
      expect(fake.callCount, 0);
    });

    test('returns false when the native layer returns null', () async {
      final derived = await hasher.deriveHash('pw');
      fake.returnNull = true;

      final ok = await hasher.verify(
        candidate: 'pw',
        hash: derived.hash,
        salt: derived.salt,
      );

      expect(ok, isFalse);
    });

    test('a stored hash of different length than the candidate never '
        'throws (constant-time compare short-circuits on length)', () async {
      // A 32-byte "stored hash" can never match a 64-byte freshly-derived
      // one, but _secureEqual must not throw a range error while checking.
      final shortHash = base64Encode(Uint8List(32));

      final ok = await hasher.verify(
        candidate: 'anything',
        hash: shortHash,
        salt: base64Encode(Uint8List(16)),
      );

      expect(ok, isFalse);
    });
  });
}
