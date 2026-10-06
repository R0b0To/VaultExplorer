// NOTE: authored without running against the Flutter toolchain -- please
// verify with `flutter test test/data/password_interchange/authenticator_backup_crypto_test.dart`.
//
// openAesCbc: the native AES-CBC handler reports a bad padding block (what a
// wrong key produces) and a malformed input as the same error code, so the
// Dart side validates the input's shape first. A malformed backup must read as
// a format problem; only a decrypt failure on well-formed input means "wrong
// password".
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_backup_crypto.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

class _ScriptedCbcCrypto extends VaultCryptoApi {
  _ScriptedCbcCrypto({this.result, this.error}) : super(const MethodChannel('test/unused'));

  final Uint8List? result;
  final PlatformException? error;
  int calls = 0;

  @override
  Future<Uint8List?> aesCbcDecrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (i) => i));

void main() {
  group('openAesCbc', () {
    test('returns the plaintext for well-formed input', () async {
      final crypto = _ScriptedCbcCrypto(result: Uint8List.fromList([1, 2, 3]));
      final plain = await openAesCbc(crypto, key: _bytes(32), iv: _bytes(16), ciphertext: _bytes(48));
      expect(plain, [1, 2, 3]);
    });

    test('a native failure on well-formed input is reported as a wrong password', () async {
      final crypto = _ScriptedCbcCrypto(error: PlatformException(code: 'C++_ERROR', message: 'pad block corrupted'));
      await expectLater(
        openAesCbc(crypto, key: _bytes(32), iv: _bytes(16), ciphertext: _bytes(48)),
        throwsA(isA<PasswordFileIncorrectPasswordException>()),
      );
      expect(crypto.calls, 1);
    });

    for (final c in <({String name, int key, int iv, int ct})>[
      (name: 'an unsupported key size', key: 20, iv: 16, ct: 48),
      (name: 'a wrong-length IV', key: 32, iv: 12, ct: 48),
      (name: 'ciphertext that is not a whole number of blocks', key: 32, iv: 16, ct: 50),
      (name: 'empty ciphertext', key: 32, iv: 16, ct: 0),
    ]) {
      test('${c.name} is a format error and never reaches the native engine', () async {
        final crypto = _ScriptedCbcCrypto(result: Uint8List(0));
        await expectLater(
          openAesCbc(crypto, key: _bytes(c.key), iv: _bytes(c.iv), ciphertext: _bytes(c.ct)),
          throwsA(isA<PasswordFileFormatException>()),
        );
        expect(crypto.calls, 0);
      });
    }
  });
}
