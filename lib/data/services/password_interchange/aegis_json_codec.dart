// Import-only codec for Aegis Authenticator's vault export (Settings ->
// Tools -> Export). Handles both flavours Aegis can write: a plain export
// (`db` is an inline JSON object) and the default password-protected one
// (`db` is AES-256-GCM ciphertext, whose key sits in one or more scrypt-
// protected "slots" in the header). See
// https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md.
//
// The scrypt and AES-GCM steps run in the native engine -- see
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

class AegisJsonCodec implements PasswordFormatCodec {
  final VaultCryptoApi _crypto;
  const AegisJsonCodec({VaultCryptoApi crypto = kDefaultBackupCrypto}) : _crypto = crypto;

  @override
  String get id => 'aegis';

  @override
  String get displayName => 'Aegis Authenticator (.json)';

  @override
  String get description =>
      'Aegis vault export -- plain or password-protected. In Aegis: Settings > Tools > Export. '
      'Time-based, counter-based (HOTP) and Steam Guard entries are imported.';

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
    if (lower.contains('aegis') && lower.endsWith('.json')) return true;
    final text = tryDecodeUtf8(bytes);
    if (text == null) return false;
    return (text.contains('"header"') && text.contains('"db"')) ||
        (text.contains('"slots"') && text.contains('"db"'));
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
    if (root is! Map || root['header'] is! Map || root['db'] == null) {
      throw const PasswordFileFormatException('This doesn\'t look like an Aegis vault export.');
    }
    final header = Map<String, dynamic>.from(root['header'] as Map);
    final db = root['db'];

    final Map<String, dynamic> vault;
    final slots = header['slots'];
    if (slots is List && slots.isNotEmpty) {
      vault = await _decryptDb(header, slots, db, password);
    } else if (db is Map) {
      vault = Map<String, dynamic>.from(db);
    } else {
      throw const PasswordFileFormatException('This Aegis export is missing its vault data.');
    }
    return _parseVault(vault);
  }

  Future<Map<String, dynamic>> _decryptDb(
    Map<String, dynamic> header,
    List<dynamic> slots,
    Object? db,
    String? password,
  ) async {
    if (password == null || password.isEmpty) {
      throw const PasswordFileIncorrectPasswordException();
    }
    final params = header['params'];
    if (db is! String || params is! Map) {
      throw const PasswordFileFormatException('This Aegis export is malformed.');
    }

    try {
      // Only password slots (type 1) can be opened here -- raw/keyfile
      // (0) and biometric (2) slots hold keys this app has no way to
      // reproduce. Each password slot wraps the same master key, so the
      // first one the password opens is enough.
      Uint8List? masterKey;
      for (final slot in slots) {
        if (slot is! Map || jsonInt(slot['type']) != 1) continue;
        masterKey = await _unwrapSlot(Map<String, dynamic>.from(slot), password);
        if (masterKey != null) break;
      }
      if (masterKey == null) throw const PasswordFileIncorrectPasswordException();

       final Uint8List plain;
      try {
        plain = await openAesGcm(
          _crypto,
          key: masterKey,
          iv: hexDecode(jsonStr(params['nonce'])),
          ciphertextAndTag: concatBytes(
            base64.decode(base64.normalize(db.trim())),
            hexDecode(jsonStr(params['tag'])),
          ),
        );
      } finally {
        zeroizeBytes(masterKey);
      }
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) {
        throw const PasswordFileFormatException('This Aegis export is malformed.');
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const PasswordFileFormatException('This Aegis export is malformed.');
    }
  }

  /// The master key inside one password slot, or null if [password]
  /// doesn't open it.
  Future<Uint8List?> _unwrapSlot(Map<String, dynamic> slot, String password) async {
    final n = jsonInt(slot['n']);
    final r = jsonInt(slot['r']);
    final p = jsonInt(slot['p']);
    final keyParams = slot['key_params'];
    if (n == null || r == null || p == null || keyParams is! Map) {
      throw const PasswordFileFormatException('This Aegis export is malformed.');
    }
    final wrappingKey = await deriveScrypt(
      _crypto,
      password: password,
      salt: hexDecode(jsonStr(slot['salt'])),
      n: n,
      r: r,
      p: p,
      dkLen: 32,
    );
    try {
      return await openAesGcm(
        _crypto,
        key: wrappingKey,
        iv: hexDecode(jsonStr(keyParams['nonce'])),
        ciphertextAndTag: concatBytes(
          hexDecode(jsonStr(slot['key'])),
          hexDecode(jsonStr(keyParams['tag'])),
        ),
      );
   } on PasswordFileIncorrectPasswordException {
      return null;
    } finally {
      zeroizeBytes(wrappingKey);
    }
  }

  DecodedExchange _parseVault(Map<String, dynamic> vault) {
    final entries = vault['entries'];
    if (entries is! List) {
      throw const PasswordFileFormatException('No entries were found in this Aegis export.');
    }

    final groupNames = <String, String>{};
    final groups = vault['groups'];
    if (groups is List) {
      for (final g in groups) {
        if (g is Map) groupNames[jsonStr(g['uuid'])] = jsonStr(g['name']);
      }
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];
    for (final raw in entries) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final issuer = jsonStr(entry['issuer']);
      final account = jsonStr(entry['name']);
      final label = authenticatorTitle(issuer: issuer, account: account);
      try {
        final info = entry['info'];
        if (info is! Map) {
          warnings.add(skippedEntryWarning(label, 'it has no key information'));
          continue;
        }
        final type = jsonStr(entry['type']).toLowerCase();
        final kind = switch (type) {
          'totp' => OtpKind.totp,
          'hotp' => OtpKind.hotp,
          'steam' => OtpKind.steam,
          _ => null,
        };
        if (kind == null) {
          warnings.add(skippedEntryWarning(label, 'the "$type" code type isn\'t supported'));
          continue;
        }
        final secret = jsonStr(info['secret']);
        if (secret.isEmpty) {
          warnings.add(skippedEntryWarning(label, 'it has no secret key'));
          continue;
        }
        final algo = jsonStr(info['algo']);
        if (kind != OtpKind.steam && normalizeOtpAlgorithm(algo) == null) {
          warnings.add(skippedEntryWarning(label, unsupportedAlgorithmReason(algo.toUpperCase())));
          continue;
        }

        // Aegis v1 vaults name one `group`; v2 lists several under `groups`.
        final groupIds = <String>[
          if (entry['groups'] is List) ...(entry['groups'] as List).map(jsonStr),
          if (entry['group'] != null) jsonStr(entry['group']),
        ];
        final tags = groupIds.map((g) => groupNames[g] ?? '').where((n) => n.isNotEmpty);

        records.add(
          ExchangeRecord(
            type: VaultItemType.authenticator,
            title: label,
            favorite: entry['favorite'] == true,
            fields: authenticatorFields(
              issuer: issuer,
              account: account,
              secret: secret,
              kind: kind,
              algorithm: algo,
              digits: jsonInt(info['digits']),
              period: jsonInt(info['period']),
              counter: jsonInt(info['counter']),
              notes: buildNotes(jsonStr(entry['note']), tags),
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
      throw UnsupportedError('Exporting to Aegis isn\'t supported.');
}
