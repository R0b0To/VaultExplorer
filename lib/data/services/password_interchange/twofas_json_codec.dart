// Import-only codec for a 2FAS Authenticator backup (`.2fas`, JSON inside).
// Either a plain `services` array, or -- when the backup was password
// protected -- a `servicesEncrypted` string of three base64 parts joined by
// colons: `ciphertext+tag : salt : iv`, keyed by PBKDF2-HMAC-SHA256
// (10,000 iterations) over the password and decrypted with AES-256-GCM.
//
// PBKDF2 and AES-GCM run in the native engine -- see
// authenticator_backup_crypto.dart.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/utils/totp_engine.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_backup_crypto.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_import_shared.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

class TwoFasJsonCodec implements PasswordFormatCodec {
  final VaultCryptoApi _crypto;
  const TwoFasJsonCodec({VaultCryptoApi crypto = kDefaultBackupCrypto}) : _crypto = crypto;

  static const int _pbkdf2Iterations = 10000;

  @override
  String get id => 'twofas';

  @override
  String get displayName => '2FAS Authenticator (.2fas)';

  @override
  String get description =>
      '2FAS backup -- plain or password-protected. Time-based, counter-based (HOTP) '
      'and Steam Guard entries are imported.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => false;

  @override
  bool get isEncrypted => false;

  @override
  bool get isOptionallyEncrypted => true;

 @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.2fas') || (lower.contains('2fas') && lower.endsWith('.json'))) {
      return true;
    }
    final text = tryDecodeUtf8(bytes);
    if (text == null) return false;
    return text.contains('"schemaVersion"') &&
        (text.contains('"services"') || text.contains('"servicesEncrypted"'));
  }

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    final text = tryDecodeUtf8(bytes);
    Object? root;
    try {
      root = text == null ? null : jsonDecode(text);
    } on FormatException {
      // Not JSON at all: fall through to the format error below. (Never log this exception -- a FormatException quotes the input, which is secret here.)
    }
    if (root is! Map || root['schemaVersion'] == null) {
      throw const PasswordFileFormatException('This doesn\'t look like a 2FAS backup.');
    }

    final warnings = <String>[];
    final schema = jsonInt(root['schemaVersion']) ?? 0;
    if (schema > 4) {
      warnings.add(
        'This backup uses a newer 2FAS format (version $schema) than this import was written '
        'for; some entries may not have been read correctly.',
      );
    }

    final List<dynamic> services;
    final encrypted = root['servicesEncrypted'];
    if (encrypted is String && encrypted.isNotEmpty) {
      services = await _decryptServices(encrypted, password);
    } else if (root['services'] is List) {
      services = root['services'] as List;
    } else {
      throw const PasswordFileFormatException('No services were found in this 2FAS backup.');
    }

    final groupNames = <String, String>{};
    final groups = root['groups'];
    if (groups is List) {
      for (final g in groups) {
        if (g is Map) groupNames[jsonStr(g['id'])] = jsonStr(g['name']);
      }
    }
    return _parse(services, groupNames, warnings);
  }

  Future<List<dynamic>> _decryptServices(String encrypted, String? password) async {
    if (password == null || password.isEmpty) {
      throw const PasswordFileIncorrectPasswordException();
    }
    final parts = encrypted.split(':');
    if (parts.length < 3) {
      throw const PasswordFileFormatException('This 2FAS backup is malformed.');
    }
    try {
      final ciphertextAndTag = base64.decode(base64.normalize(parts[0]));
      final salt = base64.decode(base64.normalize(parts[1]));
      final iv = base64.decode(base64.normalize(parts[2]));

      final key = await derivePbkdf2(
        _crypto,
        password: password,
        salt: salt,
        iterations: _pbkdf2Iterations,
        keyLength: 32,
        hash: Pbkdf2Hash.sha256,
      );
      try {
        final plain = await openAesGcm(
          _crypto,
          key: key,
          iv: iv,
          ciphertextAndTag: ciphertextAndTag,
        );
        final decoded = jsonDecode(utf8.decode(plain));
        if (decoded is! List) {
          throw const PasswordFileFormatException('This 2FAS backup is malformed.');
        }
        return decoded;
      } finally {
        zeroizeBytes(key);
      }
    } on FormatException {
      throw const PasswordFileFormatException('This 2FAS backup is malformed.');
    }
  }

  DecodedExchange _parse(
    List<dynamic> services,
    Map<String, String> groupNames,
    List<String> warnings,
  ) {
    final records = <ExchangeRecord>[];
    for (final raw in services) {
      if (raw is! Map) continue;
      final name = jsonStr(raw['name']);
      final otp = raw['otp'] is Map ? raw['otp'] as Map : const {};
      final issuer = jsonStr(otp['issuer']).isNotEmpty ? jsonStr(otp['issuer']) : name;
      final account = jsonStr(otp['account']);
      final label = authenticatorTitle(issuer: issuer, account: account);
      try {
        final type = jsonStr(otp['tokenType']).toLowerCase();
        final kind = switch (type) {
          'totp' || '' => OtpKind.totp,
          'hotp' => OtpKind.hotp,
          'steam' => OtpKind.steam,
          _ => null,
        };
        if (kind == null) {
          warnings.add(skippedEntryWarning(label, 'the "$type" code type isn\'t supported'));
          continue;
        }
        final secret = jsonStr(raw['secret']);
        if (secret.isEmpty) {
          warnings.add(skippedEntryWarning(label, 'it has no secret key'));
          continue;
        }
        final algo = jsonStr(otp['algorithm']);
        if (kind != OtpKind.steam && normalizeOtpAlgorithm(algo) == null) {
          warnings.add(skippedEntryWarning(label, unsupportedAlgorithmReason(algo.toUpperCase())));
          continue;
        }
        final group = groupNames[jsonStr(raw['groupId'])] ?? '';
        records.add(
          ExchangeRecord(
            type: VaultItemType.authenticator,
            title: label,
            fields: authenticatorFields(
              issuer: issuer,
              account: account,
              secret: secret,
              kind: kind,
              algorithm: algo,
              digits: jsonInt(otp['digits']),
              period: jsonInt(otp['period']),
              counter: jsonInt(otp['counter']),
              notes: buildNotes(null, [group]),
            ),
          ),
        );
      } catch (_) {
        warnings.add(skippedEntryWarning(label, 'the entry couldn\'t be read'));
      }
    }
    if (records.isEmpty) throw noImportableEntries(warnings);
    return DecodedExchange(records, warnings: warnings);
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async =>
      throw UnsupportedError('Exporting to 2FAS isn\'t supported.');
}
