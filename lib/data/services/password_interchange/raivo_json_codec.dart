// Import-only codec for Raivo OTP's JSON export -- an array of
// `{"kind", "issuer", "account", "secret", "algorithm", "digits", "timer",
// "counter"}` objects, every number written as a string. Raivo exports a
// .zip; unzip it first and pick the .json inside.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/core/utils/totp_engine.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/authenticator_import_shared.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

class RaivoJsonCodec implements PasswordFormatCodec {
  const RaivoJsonCodec();

  @override
  String get id => 'raivo';

  @override
  String get displayName => 'Raivo OTP (.json)';

  @override
  String get description =>
      'Raivo OTP\'s JSON export. Raivo saves a .zip -- unzip it and pick the .json inside. Not encrypted.';

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
    final text = tryDecodeUtf8(bytes)?.trimLeft();
    if (text == null || !text.startsWith('[')) return false;
    return text.contains('"kind"') && text.contains('"timer"') && text.contains('"secret"');
  }

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    // "PK\x03\x04": a zip archive.
    if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b && bytes[2] == 0x03 && bytes[3] == 0x04) {
      throw const PasswordFileFormatException(
        'This is a .zip archive. Unzip it first, then pick the .json file inside.',
      );
    }
    final text = tryDecodeUtf8(bytes);
    Object? root;
    try {
      root = text == null ? null : jsonDecode(text);
    } on FormatException {
      // Not JSON at all: fall through to the format error below. (Never log this exception -- a FormatException quotes the input, which is secret here.)
    }
    if (root is! List) {
      throw const PasswordFileFormatException('This doesn\'t look like a Raivo OTP export.');
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];
    for (final raw in root) {
      if (raw is! Map) continue;
      final issuer = jsonStr(raw['issuer']);
      final account = jsonStr(raw['account']);
      final label = authenticatorTitle(issuer: issuer, account: account);
      final kind = switch (jsonStr(raw['kind']).toLowerCase()) {
        'totp' || '' => OtpKind.totp,
        'hotp' => OtpKind.hotp,
        'steam' => OtpKind.steam,
        _ => null,
      };
      if (kind == null) {
        warnings.add(skippedEntryWarning(label, 'the "${jsonStr(raw['kind'])}" code type isn\'t supported'));
        continue;
      }
      final secret = jsonStr(raw['secret']);
      if (secret.isEmpty) {
        warnings.add(skippedEntryWarning(label, 'it has no secret key'));
        continue;
      }
      final algo = jsonStr(raw['algorithm']);
      if (kind != OtpKind.steam && normalizeOtpAlgorithm(algo) == null) {
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
            kind: kind,
            algorithm: algo,
            digits: jsonInt(raw['digits']),
            period: jsonInt(raw['timer']),
            counter: jsonInt(raw['counter']),
          ),
        ),
      );
    }
    if (records.isEmpty) throw noImportableEntries(warnings);
    return DecodedExchange(records, warnings: warnings);
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async =>
      throw UnsupportedError('Exporting to Raivo OTP isn\'t supported.');
}
