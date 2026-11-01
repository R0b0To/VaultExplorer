// The crypto primitives of the engine channel (hashPassword, pbkdf2, hmac, aesGcm*, scrypt, argon2id,
// ...), answered by the native engine through the C ABI.
//
// The app uses them for password hashing (app lock, PIN, pattern), encrypting its thumbnail cache,
// TOTP, and importing other authenticators' backups. They run in the worker isolates: scrypt and
// Argon2id are deliberately slow, and even HMAC would otherwise contend with the UI isolate.
//
// Same contract as the Android handlers: a primitive that fails (bad tag, wrong key, impossible
// parameters) answers null; a malformed request answers INVALID_ARGS.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'engine_worker_pool.dart';
import 've_native.dart';

class DesktopCrypto {
  DesktopCrypto(this.pool);

  final EngineWorkerPool pool;

  static Uint8List? _bytes(Object? v) =>
      v is Uint8List ? v : (v is String ? Uint8List.fromList(utf8.encode(v)) : null);

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  static PlatformException _invalid(String what) =>
      PlatformException(code: 'INVALID_ARGS', message: what);

  /// Runs a primitive in a worker; null unless it succeeded.
  Future<Uint8List?> _run(String op, List<Object?> args) async {
    final r = await pool.call(op, args) as List<Object?>;
    return r[0] == veOk ? r[1] as Uint8List? : null;
  }

  static int _hashId(Object? name) => switch ('$name'.toLowerCase()) {
        'sha1' => veHashSha1,
        'sha256' => veHashSha256,
        'sha512' => veHashSha512,
        _ => 0,
      };

  /// Answers [method] if it is one of the primitives; returns (handled, result).
  Future<(bool, Object?)> handle(String method, Map<Object?, Object?> a) async {
    switch (method) {
      case 'hashPassword': // PBKDF2-HMAC-SHA512, 64 bytes
        {
          final pw = _bytes(a['password']);
          final salt = a['salt'];
          if (pw == null || salt is! Uint8List || salt.isEmpty) return (true, null);
          final it = _int(a['iterations'], 0);
          return (true, await _run('pbkdf2', [veHashSha512, pw, salt, it > 0 ? it : 200000, 64]));
        }
      case 'hashPasswordSha256': // PBKDF2-HMAC-SHA256, caller-chosen length
        {
          final pw = _bytes(a['password']);
          final salt = a['salt'];
          final outLen = _int(a['outputLen'], 0);
          if (pw == null || salt is! Uint8List || salt.isEmpty || outLen <= 0) return (true, null);
          final it = _int(a['iterations'], 0);
          return (true, await _run('pbkdf2', [veHashSha256, pw, salt, it > 0 ? it : 50000, outLen]));
        }
      case 'pbkdf2':
        {
          final pw = _bytes(a['password']);
          final salt = a['salt'];
          final hash = _hashId(a['hash']);
          final it = _int(a['iterations'], 0);
          final outLen = _int(a['outputLen'], 0);
          if (pw == null || salt is! Uint8List || salt.isEmpty || hash == 0 || it <= 0 || outLen <= 0) {
            throw _invalid('password, salt (non-empty), iterations, outputLen and hash (sha1|sha256|sha512) required');
          }
          return (true, await _run('pbkdf2', [hash, pw, salt, it, outLen]));
        }
      case 'hmac':
        {
          final key = a['key'];
          final data = a['data'];
          final hash = _hashId(a['hash']);
          if (key is! Uint8List || key.isEmpty || data is! Uint8List || hash == 0) {
            throw _invalid('key (non-empty), data and hash (sha1|sha256|sha512) required');
          }
          return (true, await _run('hmac', [hash, key, data]));
        }
      case 'scrypt':
        {
          final pw = _bytes(a['password']);
          final salt = a['salt'];
          if (pw == null || salt is! Uint8List) return (true, null);
          return (true, await _run('scrypt', [pw, salt, _int(a['n'], 0), _int(a['r'], 0), _int(a['p'], 0), _int(a['dkLen'], 0)]));
        }
      case 'argon2id':
        {
          final pw = _bytes(a['password']);
          final salt = a['salt'];
          if (pw == null || salt is! Uint8List) return (true, null);
          return (true, await _run('argon2id', [
            pw,
            salt,
            _int(a['memoryKiB'], 0),
            _int(a['iterations'], 0),
            _int(a['parallelism'], 0),
            _int(a['outputLen'], 0),
          ]));
        }
      case 'aesGcmEncrypt':
        {
          final key = a['key'], iv = a['iv'], pt = a['plaintext'];
          if (key is! Uint8List || iv is! Uint8List || pt is! Uint8List) return (true, null);
          return (true, await _run('gcmSeal', [key, iv, null, pt]));
        }
      case 'aesGcmDecrypt':
        {
          final key = a['key'], iv = a['iv'], ct = a['ciphertextAndTag'];
          if (key is! Uint8List || iv is! Uint8List || ct is! Uint8List) return (true, null);
          return (true, await _run('gcmOpen', [key, iv, a['aad'] as Uint8List?, ct]));
        }
      case 'aesCbcDecrypt':
        {
          final key = a['key'], iv = a['iv'], ct = a['ciphertext'];
          if (key is! Uint8List || iv is! Uint8List || ct is! Uint8List) return (true, null);
          return (true, await _run('cbcDecrypt', [key, iv, ct]));
        }
      case 'xchacha20Poly1305Open':
        {
          final key = a['key'], nonce = a['nonce'], ct = a['ciphertextAndTag'];
          if (key is! Uint8List || nonce is! Uint8List || ct is! Uint8List) return (true, null);
          return (true, await _run('xchachaOpen', [key, nonce, a['aad'] as Uint8List?, ct]));
        }
    }
    return (false, null);
  }
}
