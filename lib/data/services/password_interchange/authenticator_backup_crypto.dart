// Key derivation and AEAD decryption for the *encrypted* backups of other
// authenticator apps (Aegis, andOTP, 2FAS), routed through the app's native
// C++ engine (BoringSSL / mbedTLS / the bundled scrypt) via [VaultCryptoApi]
// -- the same primitives that already open volumes -- rather than a
// pure-Dart crypto package.
//
//   Aegis   scrypt                + AES-256-GCM
//   andOTP  PBKDF2-HMAC-SHA1      + AES-256-GCM
//   2FAS    PBKDF2-HMAC-SHA256    + AES-256-GCM
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// The native crypto the codecs use unless a caller (a test, say) injects
/// another [VaultCryptoApi]. Same channel `vaultCryptoApiProvider` wraps;
/// constructed directly, as `app_secure_storage.dart` does, because a
/// codec is a plain const object with no `ref` to read a provider from.
const VaultCryptoApi kDefaultBackupCrypto = VaultCryptoApi(kVaultEngineChannel);

/// Limits on the key-derivation cost a backup file may ask for. The
/// parameters are read straight out of the (untrusted) file, so without a
/// ceiling a hostile one could make an import chew through minutes of CPU
/// or gigabytes of memory.
const int kMaxBackupPbkdf2Iterations = 10000000;
const int kMaxBackupScryptBytes = 256 * 1024 * 1024; // 128 * r * N

/// AES-256-GCM decryption of `ciphertext || 16-byte tag` (the layout all
/// three apps use once their tag is appended). A tag mismatch -- the
/// signature of a wrong password, since the key came from it -- surfaces as
/// [PasswordFileIncorrectPasswordException].
/// Safely clears sensitive byte buffers, ignoring unmodifiable views.
void zeroizeBytes(Uint8List? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.length, 0);
  } catch (e) {
    VeLog.w('authenticator_backup_crypto', 'zeroizeBytes: buffer not wiped (${e.runtimeType})');
  }
}

Future<Uint8List> openAesGcm(
  VaultCryptoApi crypto, {
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertextAndTag,
  Uint8List? aad,
}) async {
  try {
    final plain = await crypto.aesGcmDecrypt(
      key: key,
      iv: iv,
      ciphertextAndTag: ciphertextAndTag,
      aad: aad,
    );
    if (plain == null) throw const PasswordFileIncorrectPasswordException();
    return Uint8List.fromList(plain);
  } on PlatformException catch (e) {
    if (e.code == 'CRYPTO_FAILED') {
      throw const PasswordFileIncorrectPasswordException();
    }
    throw PasswordFileFormatException(
      'This backup couldn\'t be decrypted (${e.message ?? e.code}).',
    );
  }
}

/// AES-256-CBC decryption with PKCS7 unpadding.
Future<Uint8List> openAesCbc(
  VaultCryptoApi crypto, {
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertext,
}) async {
  // The native handler reports every failure -- a bad padding block (the
  // wrong-password signature) and a malformed input alike -- as the same
  // `C++_ERROR`, so shape problems are caught here, where they can be told
  // apart from a wrong password.
  if (key.length != 16 && key.length != 24 && key.length != 32) {
    throw const PasswordFileFormatException('This backup uses an unsupported key size.');
  }
  if (iv.length != 16) {
    throw const PasswordFileFormatException('This backup has an invalid IV.');
  }
  if (ciphertext.isEmpty || ciphertext.length % 16 != 0) {
    throw const PasswordFileFormatException('This backup\'s encrypted data is truncated or corrupt.');
  }
  try {
    final plain = await crypto.aesCbcDecrypt(
      key: key,
      iv: iv,
      ciphertext: ciphertext,
    );
    if (plain == null) throw const PasswordFileIncorrectPasswordException();
    return Uint8List.fromList(plain);
  } on PlatformException {
    throw const PasswordFileIncorrectPasswordException();
  }
}

/// One-shot HMAC via the native engine. Unlike [openAesCbc], a failure here is
/// never "wrong password" -- the MAC is computed, not verified -- so both a
/// null result and a platform error surface as a format exception; callers
/// decide what a *mismatching* MAC means.
Future<Uint8List> computeHmac(
  VaultCryptoApi crypto, {
  required Uint8List key,
  required Uint8List data,
  required HmacHash hash,
}) async {
  try {
    final mac = await crypto.hmac(key: key, data: data, hash: hash);
    if (mac == null || mac.isEmpty) {
      throw const PasswordFileFormatException('Integrity check failed.');
    }
    return Uint8List.fromList(mac);
  } on PlatformException catch (e) {
    throw PasswordFileFormatException('Integrity check failed (${e.message ?? e.code}).');
  }
}

/// PBKDF2-HMAC over the UTF-8 bytes of [password].
Future<Uint8List> derivePbkdf2(
  VaultCryptoApi crypto, {
  required String password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
  required Pbkdf2Hash hash,
}) async {
  if (iterations < 1 || iterations > kMaxBackupPbkdf2Iterations) {
    throw const PasswordFileFormatException(
      'This backup asks for an unreasonable amount of key-derivation work, so it was not opened.',
    );
  }
  if (salt.isEmpty) {
    throw const PasswordFileFormatException('This backup is missing its salt.');
  }
 final pw = Uint8List.fromList(utf8.encode(password));
  try {
    final key = await crypto.pbkdf2(
      password: pw,
      salt: salt,
      iterations: iterations,
      outputLen: keyLength,
      hash: hash,
    );
    if (key == null) {
      throw const PasswordFileFormatException('Key derivation failed.');
    }
    return Uint8List.fromList(key);
  } on PlatformException catch (e) {
    throw PasswordFileFormatException('Key derivation failed (${e.message ?? e.code}).');
  } finally {
    zeroizeBytes(pw);
  }
}

/// scrypt over the UTF-8 bytes of [password].
Future<Uint8List> deriveScrypt(
  VaultCryptoApi crypto, {
  required String password,
  required Uint8List salt,
  required int n,
  required int r,
  required int p,
  required int dkLen,
}) async {
  final validCost = n > 1 && (n & (n - 1)) == 0 && r > 0 && r <= 32 && p > 0 && p <= 16;
  if (!validCost || 128 * r * n > kMaxBackupScryptBytes) {
    throw const PasswordFileFormatException(
      'This backup asks for an unreasonable amount of key-derivation work, so it was not opened.',
    );
  }
  final pw = Uint8List.fromList(utf8.encode(password));
  try {
    final key = await crypto.scrypt(
      password: pw,
      salt: salt,
      n: n,
      r: r,
      p: p,
      dkLen: dkLen,
    );
    if (key == null) {
      throw const PasswordFileFormatException('Key derivation failed.');
    }
    return Uint8List.fromList(key);
  } on PlatformException catch (e) {
    throw PasswordFileFormatException('Key derivation failed (${e.message ?? e.code}).');
  } finally {
    zeroizeBytes(pw);
  }
}

/// Decodes a hex string ("0a1b...") into bytes; throws [FormatException]
/// if it isn't valid hex.
Uint8List hexDecode(String hex) {
  final s = hex.trim();
  if (s.length.isOdd) throw const FormatException('Odd-length hex string');
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final v = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
    if (v == null) throw const FormatException('Invalid hex string');
    out[i] = v;
  }
  return out;
}

Uint8List concatBytes(Uint8List a, Uint8List b) {
  final out = Uint8List(a.length + b.length);
  out.setRange(0, a.length, a);
  out.setRange(a.length, out.length, b);
  return out;
}

Future<Uint8List> openXchacha20Poly1305(
  VaultCryptoApi crypto, {
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertextAndTag,
  Uint8List? aad,
}) async {
  try {
    final plain = await crypto.xchacha20Poly1305Open(
      key: key,
      nonce: nonce,
      ciphertextAndTag: ciphertextAndTag,
      aad: aad,
    );
    if (plain == null) throw const PasswordFileIncorrectPasswordException();
    return Uint8List.fromList(plain);
  } on PlatformException catch (e) {
    if (e.code == 'CRYPTO_FAILED') {
      throw const PasswordFileIncorrectPasswordException();
    }
    throw PasswordFileFormatException(
      'This backup couldn\'t be decrypted (${e.message ?? e.code}).',
    );
  }
}

/// Argon2id over the UTF-8 bytes of [password].
Future<Uint8List> deriveArgon2id(
  VaultCryptoApi crypto, {
  required String password,
  required Uint8List salt,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
  required int outputLen,
}) async {
  // Allow up to 1 GiB (1024 * 1024 KiB), matching Ente Auth's sensitive KDF profile
  if (memoryKiB < 8 || memoryKiB > 1024 * 1024 || iterations < 1 || iterations > 100) {
    throw const PasswordFileFormatException(
      'This backup asks for an unreasonable amount of key-derivation work, so it was not opened.',
    );
  }
  final pw = Uint8List.fromList(utf8.encode(password));
  try {
    final key = await crypto.argon2id(
      password: pw,
      salt: salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      outputLen: outputLen,
    );
    if (key == null) {
      throw const PasswordFileFormatException('Argon2id key derivation failed.');
    }
    return Uint8List.fromList(key);
  } on PlatformException catch (e) {
    throw PasswordFileFormatException('Argon2id key derivation failed (${e.message ?? e.code}).');
  } finally {
    zeroizeBytes(pw);
  }
}
