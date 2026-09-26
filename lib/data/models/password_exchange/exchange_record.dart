// Intermediate representation used by every codec in
// lib/data/services/password_interchange/. Every format (KDBX, CSV,
// Bitwarden JSON, ...) only ever has to convert to/from [ExchangeRecord] --
// it never talks to [VaultItem] directly. That keeps each codec independent
// of the Item Vault's storage details and makes it trivial to add another
// format later without touching the others.
//
// This mirrors, at the data layer, the same "one shared shape, many
// converters" idea [VaultItemTemplate] already uses for the six item types.
library;

import 'package:vaultexplorer/data/models/vault_item.dart';

/// Field keys that hold secret material across every [VaultItemType]'s
/// template (see [VaultItemTemplate.fieldsFor]). Kept here as a flat,
/// l10n-independent set -- rather than importing the localized template --
/// so codecs can decide "should this be a protected/hidden field in the
/// target format?" without needing an [AppLocalizations] instance.
///
/// If a new secret-typed field is ever added to [VaultItemTemplate], add its
/// key here too, or it will round-trip through KDBX unprotected.
const Set<String> kSecretExchangeFieldKeys = {
  'password',
  'totp_secret',
  'number', // payment card number
  'cvv',
  'pin',
  'passport_no',
  'national_id',
  'account_number',
  'routing_number',
  'iban',
  'license_key',
};

/// One login/note/card/... as it travels between VaultExplorer's Item Vault
/// and an external password manager file. [type] and [fields] use exactly
/// the same [VaultItemType] enum and field *keys* as [VaultItem] --
/// [fromVaultItem]/[toVaultItem] are therefore a lossless, non-lossy
/// round-trip. Fields that don't exist in [VaultItemTemplate] for [type]
/// (e.g. a foreign format's custom field with no VaultExplorer equivalent)
/// are still carried along in [fields] under their original key; they just
/// won't have a dedicated widget in the edit screen.
class ExchangeRecord {
  VaultItemType type;
  String title;

  /// Field key -> value, using VaultExplorer's own internal keys where a
  /// field maps onto one of [VaultItemTemplate]'s known keys (e.g.
  /// `username`, `password`, `account_number`) so a round-trip through our
  /// own export/import never loses or renames anything. Codecs may also
  /// stash extra, format-specific keys here (e.g. a foreign CSV's odd
  /// column) -- those simply won't appear in the Item Vault's edit form.
  Map<String, String> fields;

  /// Folder path, relative to the export/import root, split into segments
  /// (e.g. `['Work', 'Banking']`). Empty for a top-level item. Used to
  /// rebuild a KeePass group hierarchy on export and to place an imported
  /// item back into the matching vault subfolder.
  List<String> folderPath;

  bool favorite;
  DateTime? createdAt;
  DateTime? updatedAt;

  ExchangeRecord({
    required this.type,
    required this.title,
    Map<String, String>? fields,
    List<String>? folderPath,
    this.favorite = false,
    this.createdAt,
    this.updatedAt,
  })  : fields = fields ?? {},
        folderPath = folderPath ?? const [];

  /// A short, human-readable secondary line for import-preview lists --
  /// the first non-secret, non-empty field, same rule as
  /// [VaultItem.subtitle], but without needing an [AppLocalizations].
  String get previewSubtitle {
    for (final key in const ['issuer', 'account', 'username', 'url', 'cardholder', 'bank_name', 'full_name', 'product']) {
      final v = fields[key];
      if (v != null && v.isNotEmpty) return v;
    }
    if (type == VaultItemType.secureNote) {
      final content = fields['content'] ?? '';
      return content.length > 80 ? '${content.substring(0, 80)}…' : content;
    }
    return '';
  }

  /// Value of the single field a target format is most likely to treat as
  /// "the secret" for this record (used by formats that only have one
  /// protected slot per item, e.g. a plain CSV's `password` column).
  String get primarySecret {
    const byType = {
      VaultItemType.password: 'password',
      VaultItemType.paymentCard: 'number',
      VaultItemType.bankAccount: 'account_number',
      VaultItemType.softwareLicense: 'license_key',
      VaultItemType.identity: 'national_id',
      VaultItemType.authenticator: 'totp_secret',
    };
    final key = byType[type];
    return key == null ? '' : (fields[key] ?? '');
  }

  factory ExchangeRecord.fromVaultItem(VaultItem item, {List<String> folderPath = const []}) => ExchangeRecord(
        type: item.type,
        title: item.title,
        fields: Map.from(item.fields),
        folderPath: folderPath,
        favorite: item.bookmark,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      );

  VaultItem toVaultItem() {
    // Delegates id generation to VaultItem.create's own (collision-resistant,
    // already-battle-tested) scheme rather than minting one here -- this is
    // always a *new* item as far as the vault it's landing in is concerned,
    // same as creating one by hand in the Item Vault editor would be.
    final item = VaultItem.create(type, title.isEmpty ? '(untitled)' : title);
    return item.copyWithFields(fields, item.title).copyWithBookmark(favorite);
  }
}

/// Outcome of decoding an external file into [ExchangeRecord]s, kept
/// separate from the raw list so the import preview screen can show
/// non-fatal issues (rows a codec couldn't confidently place) alongside the
/// records it did recover, rather than failing the whole import over them.
class DecodedExchange {
  final List<ExchangeRecord> records;

  /// Human-readable notes about rows/entries that were skipped or only
  /// partially understood. Never fatal -- if a codec can't make sense of
  /// the file at all it throws instead (see `password_format_codec.dart`).
  final List<String> warnings;

  const DecodedExchange(this.records, {this.warnings = const []});
}
