// KDBX (KeePass 2.x, database version 3 or 4) read/write, built on the
// pure-Dart `kpasslib` package (MIT license, no native/FFI code -- see
// pubspec.yaml). VaultExplorer's native C++ engine handles container
// crypto; this format's crypto (AES/ChaCha20 + Argon2id/AES-KDF) is a
// property of the *file being interchanged*, not of a mounted container, so
// it's decoded/encoded here in Dart the same way the rest of this app's
// Flutter layer is pure UI/orchestration around the native engine -- there's
// nothing container-shaped about a .kdbx file for the native side to own.
//
// Layout convention (see also docs/password-interchange.md):
//   - One top-level group per VaultItemType VaultExplorer actually has
//     items for ("Logins", "Payment Cards", "Identities", "Secure Notes",
//     "Bank Accounts", "Software Licenses"), with [ExchangeRecord.folderPath]
//     mirrored as nested subgroups under that.
//   - The four fields every KeePass client already knows how to show
//     (Title/UserName/Password/URL/Notes) are used wherever a VaultExplorer
//     field means the same thing, so a VaultExplorer export is immediately
//     readable in real KeePass/KeePassXC, not just round-trippable through
//     this app.
//   - Every other VaultExplorer field is written as a custom string field
//     named after VaultExplorer's own internal field key (e.g.
//     `account_number`, `cvv`, `passport_no`) -- self-explanatory in KeePass's
//     "Advanced" tab, and exactly recovers the original field key when the
//     file is re-imported here, whichever direction it travelled.
//   - A TOTP secret is written to a custom field named `otp`, protected.
//     That's the de-facto standard KeePassXC/Strongbox/KeeWeb also read for
//     showing a live TOTP code, so this isn't just a private convention.
//
// A .kdbx produced by a *real* KeePass (not this app) won't have any of the
// above group names, so import falls back to a simple heuristic: an entry
// with a non-empty Password or UserName becomes a `password` item, anything
// else becomes a `secureNote` with the body in `content` -- see
// [_inferForeignType]. Nothing is dropped either way: every custom field
// that isn't one of VaultExplorer's own known keys for the inferred type is
// still carried into [ExchangeRecord.fields] under its original name.
library;

import 'dart:typed_data';

import 'package:kpasslib/kpasslib.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

/// KDBX magic bytes (base signature `0x9AA2D903` + version signature
/// `0xB54BFB67`, both little-endian) -- fixed by the file format, not by
/// `kpasslib`, so this check is safe regardless of which KDBX library
/// version is in use.
const List<int> _kdbxMagic = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5];

const Map<VaultItemType, String> _groupNameForType = {
  VaultItemType.password: 'Logins',
  VaultItemType.paymentCard: 'Payment Cards',
  VaultItemType.identity: 'Identities',
  VaultItemType.secureNote: 'Secure Notes',
  VaultItemType.bankAccount: 'Bank Accounts',
  VaultItemType.softwareLicense: 'Software Licenses',
};

/// Accepted spellings for each group name when *reading* a file -- a bit
/// more forgiving than the exact strings this codec writes, so a group the
/// person renamed slightly (or created by hand in real KeePass, e.g.
/// "Passwords" instead of "Logins") is still recognized.
final Map<String, VaultItemType> _typeForGroupName = {
  for (final entry in _groupNameForType.entries) entry.value.toLowerCase(): entry.key,
  'passwords': VaultItemType.password,
  'login': VaultItemType.password,
  'logins': VaultItemType.password,
  'cards': VaultItemType.paymentCard,
  'payment card': VaultItemType.paymentCard,
  'identity': VaultItemType.identity,
  'secure note': VaultItemType.secureNote,
  'notes': VaultItemType.secureNote,
  'bank account': VaultItemType.bankAccount,
  'bank accounts': VaultItemType.bankAccount,
  'software license': VaultItemType.softwareLicense,
  'licenses': VaultItemType.softwareLicense,
  'licences': VaultItemType.softwareLicense,
};

const String _fieldTitle = 'Title';
const String _fieldUserName = 'UserName';
const String _fieldPassword = 'Password';
const String _fieldUrl = 'URL';
const String _fieldNotes = 'Notes';
const String _fieldOtp = 'otp';

/// Every VaultExplorer field key that maps onto one of the five standard
/// KeePass fields above, keyed by [VaultItemType] then VaultExplorer field
/// key. Anything for a type NOT listed here falls through to a custom
/// field named after its own key -- see the class doc comment.
const Map<VaultItemType, Map<String, String>> _standardFieldMap = {
  // 'username'/'password'/'url'/'totp_secret' are handled by the explicit
  // password-only branches in _entryToRecord/_fillStandardAndCustomFields
  // instead of through this generic table, because 'password' and
  // 'totp_secret' need their protected flag set -- something this table
  // (shared with fields that are never secret) doesn't carry.
  VaultItemType.password: {'notes': _fieldNotes},
  VaultItemType.paymentCard: {'notes': _fieldNotes},
  VaultItemType.identity: {'email': _fieldUserName, 'notes': _fieldNotes},
  VaultItemType.secureNote: {'content': _fieldNotes},
  VaultItemType.bankAccount: {'notes': _fieldNotes},
  VaultItemType.softwareLicense: {
    'email': _fieldUserName,
    'download_url': _fieldUrl,
    'notes': _fieldNotes,
  },
};

class KdbxCodec implements PasswordFormatCodec {
  const KdbxCodec();

  @override
  String get id => 'kdbx';

  @override
  String get displayName => 'KeePass (.kdbx)';

  @override
  String get description =>
      'Full-fidelity, works with KeePass, KeePassXC, Strongbox, and every other KeePass-compatible app. Best choice when both ends support it.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => true;

  @override
  bool get isEncrypted => true;

  @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) {
    if (bytes != null && bytes.length >= 8) {
      var matches = true;
      for (var i = 0; i < _kdbxMagic.length; i++) {
        if (bytes[i] != _kdbxMagic[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return fileName.toLowerCase().endsWith('.kdbx');
  }

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    if (password == null || password.isEmpty) {
      throw const PasswordFileFormatException('A master password is required to open a KDBX file.');
    }
    if (!looksLikeThisFormat(fileName: '.kdbx', bytes: bytes)) {
      throw const PasswordFileFormatException('This doesn\'t look like a KDBX file.');
    }

    final KdbxDatabase db;
    try {
      db = await KdbxDatabase.fromBytes(
        data: bytes,
        credentials: KdbxCredentials(password: ProtectedData.fromString(password)),
      );
    } on FileCorruptedError {
      throw const PasswordFileIncorrectPasswordException();
    } catch (e) {
      throw PasswordFileFormatException('Could not read this KDBX file: $e');
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];
    final recycleBin = db.recycleBin;

    void walk(KdbxGroup group, List<String> path, VaultItemType? inheritedType) {
      if (recycleBin != null && group == recycleBin) return; // never resurrect deleted items

      final groupType = _typeForGroupName[group.name.trim().toLowerCase()] ?? inheritedType;

      for (final entry in group.entries) {
        try {
          records.add(_entryToRecord(entry, path: path, groupType: groupType));
        } catch (e) {
          warnings.add('Skipped an entry that could not be read: $e');
        }
      }
      for (final child in group.groups) {
        // Only the six type groups this codec writes carry a folder path of
        // their own beneath them; anything deeper (or under a foreign
        // group) is still walked so nothing is missed, just without adding
        // more path segments than the group hierarchy actually has.
        final nextPath = groupType != null ? [...path, child.name] : path;
        walk(child, nextPath, groupType);
      }
    }

    for (final topGroup in db.root.groups) {
      walk(topGroup, const [], null);
    }
    for (final entry in db.root.entries) {
      try {
        records.add(_entryToRecord(entry, path: const [], groupType: null));
      } catch (e) {
        warnings.add('Skipped an entry that could not be read: $e');
      }
    }

    return DecodedExchange(records, warnings: warnings);
  }

  ExchangeRecord _entryToRecord(
    KdbxEntry entry, {
    required List<String> path,
    required VaultItemType? groupType,
  }) {
    final raw = <String, String>{};
    for (final e in entry.fields.entries) {
      raw[e.key] = e.value.text;
    }
    final title = raw.remove(_fieldTitle) ?? '';
    final username = raw.remove(_fieldUserName) ?? '';
    final password = raw.remove(_fieldPassword) ?? '';
    final url = raw.remove(_fieldUrl) ?? '';
    final notes = raw.remove(_fieldNotes) ?? '';
    final otp = raw.remove(_fieldOtp) ?? '';

    final type = groupType ?? _inferForeignType(username: username, password: password);
    final fields = <String, String>{};
    final template = _standardFieldMap[type] ?? const {};
    // Reverse of _standardFieldMap: which VaultExplorer key(s) pull from
    // which standard KDBX field for this type.
    for (final key in template.keys) {
      switch (template[key]) {
        case _fieldUserName:
          fields[key] = username;
          break;
        case _fieldPassword:
          fields[key] = password;
          break;
        case _fieldUrl:
          fields[key] = url;
          break;
        case _fieldNotes:
          fields[key] = notes;
          break;
      }
    }
    // password items also get the two fields with no standard-field mapping.
    if (type == VaultItemType.password) {
      fields['username'] = username;
      fields['password'] = password;
      fields['url'] = url;
      if (otp.isNotEmpty) fields['totp_secret'] = otp;
    }
    // A foreign entry outside any recognized group still carries its
    // UserName/URL/Notes even when inferred as a secureNote, so nothing
    // typed into those standard fields is silently dropped.
    if (type == VaultItemType.secureNote) {
      final parts = <String>[];
      if (notes.isNotEmpty) parts.add(notes);
      if (username.isNotEmpty) parts.add('Username: $username');
      if (url.isNotEmpty) parts.add('URL: $url');
      if (password.isNotEmpty) parts.add('Password: $password');
      fields['content'] = parts.join('\n');
    }
    // Anything left in `raw` is a custom field this codec didn't already
    // consume above -- carry it through verbatim under its own name.
    for (final e in raw.entries) {
      fields.putIfAbsent(e.key, () => e.value);
    }

    return ExchangeRecord(type: type, title: title, fields: fields, folderPath: path);
  }

  VaultItemType _inferForeignType({required String username, required String password}) =>
      (username.isNotEmpty || password.isNotEmpty) ? VaultItemType.password : VaultItemType.secureNote;

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async {
    if (password == null || password.isEmpty) {
      throw const PasswordFileFormatException('A master password is required to create a KDBX file.');
    }

    final db = KdbxDatabase.create(
      credentials: KdbxCredentials(password: ProtectedData.fromString(password)),
      name: 'VaultExplorer export',
    );

    final typeGroups = <VaultItemType, KdbxGroup>{};
    final folderGroups = <String, KdbxGroup>{}; // "type|a/b" -> group

    KdbxGroup groupFor(ExchangeRecord r) {
      final typeGroup = typeGroups.putIfAbsent(
        r.type,
        () => db.createGroup(parent: db.root, name: _groupNameForType[r.type]!),
      );
      var current = typeGroup;
      var pathSoFar = r.type.name;
      for (final segment in r.folderPath) {
        if (segment.isEmpty) continue;
        pathSoFar = '$pathSoFar/$segment';
        current = folderGroups.putIfAbsent(
          pathSoFar,
          () => db.createGroup(parent: current, name: segment),
        );
      }
      return current;
    }

    for (final record in records) {
      final entry = db.createEntry(parent: groupFor(record));
      final values = <String, String>{};
      final protectedKeys = <String>{};
      _fillStandardAndCustomFields(record, values, protectedKeys);

      entry.fields[_fieldTitle] = KdbxTextField.fromText(text: record.title);
      for (final e in values.entries) {
        entry.fields[e.key] = KdbxTextField.fromText(
          text: e.value,
          protected: protectedKeys.contains(e.key),
        );
      }
      entry.times.touch();
    }

   try {
      return Uint8List.fromList(await db.save());
    } catch (e) {
      throw PasswordFileFormatException('Could not create the KDBX file: $e');
    }
  }

  /// Splits [record.fields] into the standard KDBX fields (Title is handled
  /// by the caller) plus a flat `key -> value` map of everything else
  /// (standard fields UserName/Password/URL/Notes go in under those exact
  /// names too, so this one map is all [encode] needs to write). Also fills
  /// [protectedKeys] with which of those keys should be written protected.
  void _fillStandardAndCustomFields(
    ExchangeRecord record,
    Map<String, String> out,
    Set<String> protectedKeys,
  ) {
    final template = _standardFieldMap[record.type] ?? const {};
    for (final e in record.fields.entries) {
      if (e.value.isEmpty) continue;
      final key = e.key;
      final standardName = template[key];
      if (standardName != null) {
        out[standardName] = e.value;
        continue;
      }
      if (record.type == VaultItemType.password) {
        switch (key) {
          case 'username':
            out[_fieldUserName] = e.value;
            continue;
          case 'password':
            out[_fieldPassword] = e.value;
            protectedKeys.add(_fieldPassword);
            continue;
          case 'url':
            out[_fieldUrl] = e.value;
            continue;
          case 'totp_secret':
            out[_fieldOtp] = e.value;
            protectedKeys.add(_fieldOtp);
            continue;
        }
      }
      out[key] = e.value;
      if (kSecretExchangeFieldKeys.contains(key)) protectedKeys.add(key);
    }
  }
}
