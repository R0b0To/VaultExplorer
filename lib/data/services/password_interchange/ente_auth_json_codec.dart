// Import-only codec for Ente Auth's encrypted export format and local backups
// (EnteAuthExport: Argon2id KDF + libsodium crypto_secretstream_xchacha20poly1305).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_backup_crypto.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_import_shared.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

class EnteAuthJsonCodec implements PasswordFormatCodec {
  final VaultCryptoApi _crypto;
  const EnteAuthJsonCodec({VaultCryptoApi crypto = kDefaultBackupCrypto}) : _crypto = crypto;

  @override
  String get id => 'ente_auth';

  @override
  String get displayName => 'Ente Auth (.json)';

  @override
  String get description =>
      'Ente Auth encrypted export or local backup. Uses Argon2id and libsodium Secretstream.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => false;

  @override
  bool get isEncrypted => true;

  @override
  bool get isOptionallyEncrypted => false;

  @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) {
    final lower = fileName.toLowerCase();
    if (lower.contains('ente') && lower.endsWith('.json')) return true;
    final text = tryDecodeUtf8(bytes);
    if (text == null) return false;
    return text.contains('"kdfParams"') &&
        (text.contains('"encryptedData"') || text.contains('"encryptionNonce"'));
  }

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    if (password == null || password.isEmpty) {
      throw const PasswordFileIncorrectPasswordException();
    }
    final text = tryDecodeUtf8(bytes);
    Object? root;
    try {
      root = text == null ? null : jsonDecode(text);
    } on FormatException {
      // Not JSON at all: fall through to the format error below. (Never log this exception -- a FormatException quotes the input, which is secret here.)
    }
    if (root is! Map ||
        root['kdfParams'] is! Map ||
        root['encryptedData'] == null ||
        root['encryptionNonce'] == null) {
      throw const PasswordFileFormatException('This doesn\'t look like an Ente Auth encrypted export.');
    }

    final version = root['version'];
    if (version != 1) {
      throw const PasswordFileFormatException('Unsupported Ente Auth export version.');
    }

    final kdfParams = Map<String, dynamic>.from(root['kdfParams'] as Map);
    final rawSalt = kdfParams['salt'];
    final rawMemLimit = kdfParams['memLimit'];
    final rawOpsLimit = kdfParams['opsLimit'];

    if (rawSalt is! String || rawMemLimit == null || rawOpsLimit == null) {
      throw const PasswordFileFormatException('This Ente export is missing KDF parameters.');
    }

    final salt = _decodeBase64(rawSalt);
    final memLimit = (rawMemLimit as num).toInt();
    final opsLimit = (rawOpsLimit as num).toInt();

    // libsodium crypto_pwhash: memLimit is in bytes. Argon2id C engine expects KiB.
    int memoryKiB = (memLimit / 1024).round();
    if (memoryKiB < 8) memoryKiB = 8;
    final iterations = opsLimit < 1 ? 1 : opsLimit;

    debugPrint('EnteAuthJsonCodec: Deriving Argon2id key (memoryKiB: $memoryKiB, iterations: $iterations)');

    final key = await deriveArgon2id(
      _crypto,
      password: password,
      salt: salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: 1,
      outputLen: 32,
    );

    Uint8List? plain;
    try {
      final ciphertextWithMac = _decodeBase64(jsonStr(root['encryptedData']));
      final nonceHeader = _decodeBase64(jsonStr(root['encryptionNonce']));

      plain = _openSecretstreamXChaCha20Poly1305(
        key: key,
        header: nonceHeader,
        ciphertext: ciphertextWithMac,
      );
      
      if (plain == null) {
        debugPrint('EnteAuthJsonCodec: Secretstream MAC verification failed. Incorrect password.');
        throw const PasswordFileIncorrectPasswordException();
      }
      debugPrint('EnteAuthJsonCodec: Successfully decrypted using Secretstream XChaCha20-Poly1305');
    } finally {
      zeroizeBytes(key);
    }

    final plainText = utf8.decode(plain);
    final lines = plainText.split(RegExp(r'[\r\n]+'));

    final records = <ExchangeRecord>[];
    final warnings = <String>[];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('"') && line.endsWith('"')) {
        try {
          line = (jsonDecode(line) as String).trim();
        } on FormatException {
          // Not a JSON-quoted string after all: keep the line as it is. (Plaintext -- never log it or the exception.)
        }
      }
      if (!line.startsWith('otpauth://')) continue;

      try {
        final record = exchangeRecordFromOtpAuthUri(
          line,
          onSkip: (reason) => warnings.add(skippedEntryWarning(_shortLabel(line), reason)),
        );
        if (record != null) records.add(record);
      } catch (e) {
        warnings.add(skippedEntryWarning(
          _shortLabel(line),
          e is FormatException ? e.message : 'the URI couldn\'t be read',
        ));
      }
    }

    if (records.isEmpty) throw noImportableEntries(warnings);
    return DecodedExchange(records, warnings: warnings);
  }

  Uint8List _decodeBase64(String str) {
    var normalized = str.trim().replaceAll(RegExp(r'\s+'), '').replaceAll('-', '+').replaceAll('_', '/');
    return base64.decode(base64.normalize(normalized));
  }

  String _shortLabel(String uri) {
    final q = uri.indexOf('?');
    final head = q >= 0 ? uri.substring(0, q) : uri;
    final slash = head.indexOf('/', 'otpauth://'.length);
    if (slash < 0) return head;
    try {
      return Uri.decodeComponent(head.substring(slash + 1));
    } catch (_) {
      return head.substring(slash + 1);
    }
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async =>
      throw UnsupportedError('Exporting to Ente Auth format isn\'t supported.');
}

// ---------------------------------------------------------------------------
// Read-only, pure-Dart port of libsodium's crypto_secretstream_xchacha20poly1305 
// (pull side), specifically for parsing a single-message stream pushed with TAG_FINAL.
// ---------------------------------------------------------------------------

const int _kSecretstreamHeaderBytes = 24;
const int _kSecretstreamABytes = 17; // 1 encrypted tag byte + 16-byte MAC

Uint8List? _openSecretstreamXChaCha20Poly1305({
  required Uint8List key,
  required Uint8List header,
  required Uint8List ciphertext,
}) {
  if (key.length != 32) throw ArgumentError('key must be 32 bytes');
  if (header.length != _kSecretstreamHeaderBytes) {
    throw ArgumentError('header must be $_kSecretstreamHeaderBytes bytes');
  }
  if (ciphertext.length < _kSecretstreamABytes) {
    throw ArgumentError('ciphertext is too short');
  }

  final subkey = _hchacha20(key, header.sublist(0, 16));
  final subkeyWords = _wordsLE(subkey, 8);
  final nonce = Uint32List(3)
    ..[0] = 1
    ..[1] = _readU32LE(header, 16)
    ..[2] = _readU32LE(header, 20);

  final messageLen = ciphertext.length - _kSecretstreamABytes;
  final macStart = 1 + messageLen;
  final expectedMac = ciphertext.sublist(macStart);

  final polyKey = _chachaBlock(subkeyWords, 0, nonce).sublist(0, 32);
  final tagBlockKeystream = _chachaBlock(subkeyWords, 1, nonce);

  final macInput = BytesBuilder(copy: false)
    ..addByte(ciphertext[0])
    ..add(tagBlockKeystream.sublist(1))
    ..add(Uint8List.sublistView(ciphertext, 1, macStart))
    ..add(Uint8List((0x10 - 64 + messageLen) & 0xf));
  final lengths = ByteData(16)
    ..setUint64(0, 0, Endian.little) 
    ..setUint64(8, 64 + messageLen, Endian.little);
  macInput.add(lengths.buffer.asUint8List());

  final mac = _poly1305(polyKey, macInput.toBytes());
  var diff = 0;
  for (var i = 0; i < 16; i++) {
    diff |= mac[i] ^ expectedMac[i];
  }
  if (diff != 0) return null;

  final plain = Uint8List(messageLen);
  var counter = 2;
  for (var offset = 0; offset < messageLen; offset += 64) {
    final ks = _chachaBlock(subkeyWords, counter++, nonce);
    final n = messageLen - offset < 64 ? messageLen - offset : 64;
    for (var i = 0; i < n; i++) {
      plain[offset + i] = ciphertext[1 + offset + i] ^ ks[i];
    }
  }
  return plain;
}

// ---- ChaCha20 / HChaCha20 (RFC 8439, draft-irtf-cfrg-xchacha) ------------

const List<int> _sigma = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574];

int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

void _quarterRound(Uint32List s, int a, int b, int c, int d) {
  s[a] = (s[a] + s[b]) & 0xFFFFFFFF;
  s[d] = _rotl32(s[d] ^ s[a], 16);
  s[c] = (s[c] + s[d]) & 0xFFFFFFFF;
  s[b] = _rotl32(s[b] ^ s[c], 12);
  s[a] = (s[a] + s[b]) & 0xFFFFFFFF;
  s[d] = _rotl32(s[d] ^ s[a], 8);
  s[c] = (s[c] + s[d]) & 0xFFFFFFFF;
  s[b] = _rotl32(s[b] ^ s[c], 7);
}

void _twentyRounds(Uint32List s) {
  for (var i = 0; i < 10; i++) {
    _quarterRound(s, 0, 4, 8, 12);
    _quarterRound(s, 1, 5, 9, 13);
    _quarterRound(s, 2, 6, 10, 14);
    _quarterRound(s, 3, 7, 11, 15);
    _quarterRound(s, 0, 5, 10, 15);
    _quarterRound(s, 1, 6, 11, 12);
    _quarterRound(s, 2, 7, 8, 13);
    _quarterRound(s, 3, 4, 9, 14);
  }
}

Uint8List _chachaBlock(Uint32List keyWords, int counter, Uint32List nonce) {
  final init = Uint32List(16)
    ..setRange(0, 4, _sigma)
    ..setRange(4, 12, keyWords)
    ..[12] = counter
    ..setRange(13, 16, nonce);
  final work = Uint32List.fromList(init);
  _twentyRounds(work);
  final out = ByteData(64);
  for (var i = 0; i < 16; i++) {
    out.setUint32(i * 4, (work[i] + init[i]) & 0xFFFFFFFF, Endian.little);
  }
  return out.buffer.asUint8List();
}

Uint8List _hchacha20(Uint8List key, Uint8List nonce16) {
  final s = Uint32List(16)
    ..setRange(0, 4, _sigma)
    ..setRange(4, 12, _wordsLE(key, 8))
    ..setRange(12, 16, _wordsLE(nonce16, 4));
  _twentyRounds(s);
  final out = ByteData(32);
  for (var i = 0; i < 4; i++) {
    out.setUint32(i * 4, s[i], Endian.little);
    out.setUint32(16 + i * 4, s[12 + i], Endian.little);
  }
  return out.buffer.asUint8List();
}

int _readU32LE(Uint8List b, int offset) =>
    ByteData.sublistView(b).getUint32(offset, Endian.little);

Uint32List _wordsLE(Uint8List b, int count) {
  final out = Uint32List(count);
  final view = ByteData.sublistView(b);
  for (var i = 0; i < count; i++) {
    out[i] = view.getUint32(i * 4, Endian.little);
  }
  return out;
}

// ---- Poly1305 (RFC 8439 §2.5) ---------------------------------------------

final BigInt _poly1305Prime = (BigInt.one << 130) - BigInt.from(5);
final BigInt _mask128 = (BigInt.one << 128) - BigInt.one;

Uint8List _poly1305(Uint8List key, Uint8List message) {
  final rBytes = Uint8List.fromList(key.sublist(0, 16));
  rBytes[3] &= 15;
  rBytes[7] &= 15;
  rBytes[11] &= 15;
  rBytes[15] &= 15;
  rBytes[4] &= 252;
  rBytes[8] &= 252;
  rBytes[12] &= 252;
  final r = _readLEBig(rBytes);
  final s = _readLEBig(key.sublist(16, 32));

  var acc = BigInt.zero;
  for (var i = 0; i < message.length; i += 16) {
    final end = i + 16 < message.length ? i + 16 : message.length;
    final block = Uint8List(17)..setRange(0, end - i, message, i);
    block[end - i] = 1;
    acc = ((acc + _readLEBig(block)) * r) % _poly1305Prime;
  }
  var tag = (acc + s) & _mask128;

  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = (tag & BigInt.from(0xFF)).toInt();
    tag >>= 8;
  }
  return out;
}

BigInt _readLEBig(Uint8List bytes) {
  var result = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}
