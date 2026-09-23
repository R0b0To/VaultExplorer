// Shared interface every password-manager interchange format implements.
// See password_format_registry.dart for the list of codecs and
// password_interchange_service.dart for how a codec is actually driven
// from a vault folder or an external file.
library;

import 'dart:typed_data';

import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';

/// Thrown when a file doesn't parse as the format its codec was asked to
/// read -- wrong magic bytes/header, unrecognized CSV columns, malformed
/// JSON, etc. Distinct from [PasswordFileIncorrectPasswordException] so the
/// UI can tell "this isn't a KDBX file" apart from "this is a KDBX file but
/// the password was wrong".
class PasswordFileFormatException implements Exception {
  final String message;
  const PasswordFileFormatException(this.message);
  @override
  String toString() => message;
}

/// Thrown by an encrypted format's decoder (currently only KDBX) when the
/// master password/keyfile didn't open the file. Kept distinct from
/// [PasswordFileFormatException] -- see its doc comment.
class PasswordFileIncorrectPasswordException implements Exception {
  const PasswordFileIncorrectPasswordException();
  @override
  String toString() => 'Incorrect password, or this file needs a keyfile VaultExplorer doesn\'t support.';
}

/// One interchange format VaultExplorer can read and/or write. Codecs are
/// deliberately format-only: they never touch a [MountedContainer] or the
/// Item Vault's storage -- see [PasswordInterchangeService] for the layer
/// that connects a codec to an actual vault folder or picked file.
abstract class PasswordFormatCodec {
  /// Stable identifier, also used as the default file extension (without a
  /// leading dot), e.g. `'kdbx'`, `'csv'`, `'json'`.
  String get id;

  /// Short, user-facing name, e.g. "KeePass (.kdbx)".
  String get displayName;

  /// One line describing what this format is good for / its limitations,
  /// shown under the format picker.
  String get description;

  bool get supportsImport;
  bool get supportsExport;

  /// True for formats that are themselves encrypted (currently only KDBX)
  /// -- the UI prompts for a master password before calling [decode], and
  /// requires one to be set before calling [encode].
  bool get isEncrypted;

  /// Whether a byte sequence looks like this format, used to suggest a
  /// format from a picked file's name/content before the person confirms
  /// it. Should be cheap and never throw -- a `false` here just means "not
  /// auto-selected", not "rejected"; the person can still pick this format
  /// explicitly and [decode] will report a real error if it truly doesn't
  /// match.
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes});

  /// Parses [bytes] into exchange records. [password] is required when
  /// [isEncrypted] is true. Throws [PasswordFileFormatException] if the
  /// bytes don't parse as this format at all, or
  /// [PasswordFileIncorrectPasswordException] if they do but the password
  /// didn't open them.
  Future<DecodedExchange> decode(Uint8List bytes, {String? password});

  /// Serializes [records] into this format's bytes. [password] is required
  /// when [isEncrypted] is true.
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password});
}
