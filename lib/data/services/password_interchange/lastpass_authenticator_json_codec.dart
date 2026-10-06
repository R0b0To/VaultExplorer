// Import-only codec for LastPass Authenticator's JSON export:
// `{"accounts": [{"issuerName", "userName", "secret", "timeStep",
// "digits", "algorithm", ...}]}`. Not encrypted. (LastPass Authenticator
// only holds time-based codes.)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_import_shared.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

class LastPassAuthenticatorJsonCodec implements PasswordFormatCodec {
  const LastPassAuthenticatorJsonCodec();

  @override
  String get id => 'lastpass_authenticator';

  @override
  String get displayName => 'LastPass Authenticator (.json)';

  @override
  String get description =>
      'LastPass Authenticator\'s JSON export (not the LastPass password vault). Not encrypted.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => false;

  @override
  bool get isEncrypted => false;

  @override
  bool get isOptionallyEncrypted => false;

  @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) {
    final text = tryDecodeUtf8(bytes);
    if (text == null) return false;
    return text.contains('"accounts"') &&
        (text.contains('"issuerName"') || text.contains('"userName"') || text.contains('"deviceId"'));
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
    if (root is! Map || root['accounts'] is! List) {
      throw const PasswordFileFormatException(
        'This doesn\'t look like a LastPass Authenticator export.',
      );
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];
    for (final raw in root['accounts'] as List) {
      if (raw is! Map) continue;
      final issuer = jsonStr(raw['issuerName']);
      final account = jsonStr(raw['userName']);
      final label = authenticatorTitle(issuer: issuer, account: account);
      final secret = jsonStr(raw['secret']);
      if (secret.isEmpty) {
        warnings.add(skippedEntryWarning(label, 'it has no secret key'));
        continue;
      }
      final algo = jsonStr(raw['algorithm']);
      if (normalizeOtpAlgorithm(algo) == null) {
        warnings.add(skippedEntryWarning(label, unsupportedAlgorithmReason(algo.toUpperCase())));
        continue;
      }
      records.add(
        ExchangeRecord(
          type: VaultItemType.authenticator,
          title: label,
          fields: authenticatorFields(
            issuer: issuer,
            account: account,
            secret: secret,
            algorithm: algo,
            digits: jsonInt(raw['digits']),
            period: jsonInt(raw['timeStep']),
          ),
        ),
      );
    }
    if (records.isEmpty) throw noImportableEntries(warnings);
    return DecodedExchange(records, warnings: warnings);
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async =>
      throw UnsupportedError('Exporting to LastPass Authenticator isn\'t supported.');
}
