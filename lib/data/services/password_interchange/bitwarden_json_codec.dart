// Bitwarden's unencrypted JSON vault export
// (Settings -> Export vault -> .json, NOT the password-protected export).
// This format has a real type system (login/note/card/identity) that maps
// onto VaultItemType almost one-to-one, and a generic `fields` array on
// every item for anything that doesn't -- so, unlike CSV, this is a
// high-fidelity round trip for every VaultExplorer item type, not just
// logins. See docs/password-interchange.md for the exact field mapping.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

// Bitwarden's own item type numbers -- fixed by their export schema, not
// something this codec invents.
const int _bwTypeLogin = 1;
const int _bwTypeSecureNote = 2;
const int _bwTypeCard = 3;
const int _bwTypeIdentity = 4;

class BitwardenJsonCodec implements PasswordFormatCodec {
  const BitwardenJsonCodec();

  @override
  String get id => 'bitwarden_json';

  @override
  String get displayName => 'Bitwarden (.json)';

  @override
  String get description =>
      'Bitwarden\'s unencrypted vault export format. High fidelity for every item type, and readable by Bitwarden\'s own importer. Not encrypted -- delete the file once you\'re done with it.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => true;

  @override
  bool get isEncrypted => false;

 @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) {
    if (!fileName.toLowerCase().endsWith('.json')) return false;
    if (bytes == null) return true;
    try {
      final text = utf8.decode(bytes.take(4096).toList(), allowMalformed: true);
      return text.contains('"items"');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) throw const FormatException('Root is not a JSON object.');
      root = decoded;
    } catch (e) {
      throw PasswordFileFormatException('Could not parse this file as JSON: $e');
    }
    if (root['encrypted'] == true) {
      throw const PasswordFileFormatException(
        'This is a password-protected Bitwarden export. Re-export from Bitwarden as an unencrypted (.json) export first.',
      );
    }
    final rawItems = root['items'];
    if (rawItems is! List) {
      throw const PasswordFileFormatException('This doesn\'t look like a Bitwarden vault export (no "items" array).');
    }

    final folderNames = <String, String>{};
    final rawFolders = root['folders'];
    if (rawFolders is List) {
      for (final f in rawFolders) {
        if (f is Map && f['id'] is String && f['name'] is String) {
          folderNames[f['id'] as String] = f['name'] as String;
        }
      }
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      try {
        final record = _itemToRecord(Map<String, dynamic>.from(raw), folderNames);
        if (record != null) records.add(record);
      } catch (e) {
        warnings.add('Skipped an item that could not be read: $e');
      }
    }
    if (records.isEmpty) {
      throw const PasswordFileFormatException('No usable items were found in this export.');
    }
    return DecodedExchange(records, warnings: warnings);
  }

  ExchangeRecord? _itemToRecord(Map<String, dynamic> item, Map<String, String> folderNames) {
    final bwType = (item['type'] as num?)?.toInt();
    final name = item['name'] as String? ?? '';
    final notes = item['notes'] as String? ?? '';
    final favorite = item['favorite'] == true;
    final folderId = item['folderId'] as String?;
    final folderPath = (folderId != null && folderNames.containsKey(folderId))
        ? folderNames[folderId]!.split('/').where((s) => s.isNotEmpty).toList()
        : const <String>[];

    final fields = <String, String>{};

    switch (bwType) {
      case _bwTypeLogin:
        final login = (item['login'] as Map?)?.cast<String, dynamic>() ?? const {};
        final uris = login['uris'];
        String firstUri = '';
        if (uris is List) {
          for (final u in uris) {
            if (u is Map && u['uri'] is String && (u['uri'] as String).isNotEmpty) {
              firstUri = u['uri'] as String;
              break;
            }
          }
        }
        fields['username'] = login['username'] as String? ?? '';
        fields['password'] = login['password'] as String? ?? '';
        fields['url'] = firstUri;
        final totp = login['totp'] as String?;
        if (totp != null && totp.isNotEmpty) fields['totp_secret'] = _extractTotpSecret(totp);
        fields['notes'] = notes;
        _mergeCustomFields(item, fields);
        return ExchangeRecord(
          type: VaultItemType.password,
          title: name,
          fields: fields,
          folderPath: folderPath,
          favorite: favorite,
        );

      case _bwTypeSecureNote:
        fields['content'] = notes;
        _mergeCustomFields(item, fields);
        return ExchangeRecord(
          type: VaultItemType.secureNote,
          title: name,
          fields: fields,
          folderPath: folderPath,
          favorite: favorite,
        );

      case _bwTypeCard:
        final card = (item['card'] as Map?)?.cast<String, dynamic>() ?? const {};
        final month = card['expMonth'] as String? ?? '';
        final year = card['expYear'] as String? ?? '';
        fields['cardholder'] = card['cardholderName'] as String? ?? '';
        fields['number'] = card['number'] as String? ?? '';
        fields['expiry'] = (month.isEmpty && year.isEmpty)
            ? ''
            : '${month.padLeft(2, '0')}/${year.length >= 2 ? year.substring(year.length - 2) : year}';
        fields['cvv'] = card['code'] as String? ?? '';
        fields['notes'] = notes;
        _mergeCustomFields(item, fields);
        return ExchangeRecord(
          type: VaultItemType.paymentCard,
          title: name,
          fields: fields,
          folderPath: folderPath,
          favorite: favorite,
        );

      case _bwTypeIdentity:
        final identity = (item['identity'] as Map?)?.cast<String, dynamic>() ?? const {};
        final first = identity['firstName'] as String? ?? '';
        final middle = identity['middleName'] as String? ?? '';
        final last = identity['lastName'] as String? ?? '';
        final fullName = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
        final addressParts = [
          identity['address1'],
          identity['address2'],
          identity['address3'],
          identity['city'],
          identity['state'],
          identity['postalCode'],
          identity['country'],
        ].whereType<String>().where((s) => s.isNotEmpty);
        fields['full_name'] = fullName;
        fields['national_id'] = identity['ssn'] as String? ?? '';
        fields['drivers_license'] = identity['licenseNumber'] as String? ?? '';
        fields['passport_no'] = identity['passportNumber'] as String? ?? '';
        fields['address'] = addressParts.join(', ');
        fields['phone'] = identity['phone'] as String? ?? '';
        fields['email'] = identity['email'] as String? ?? '';
        fields['notes'] = notes;
        _mergeCustomFields(item, fields);
        return ExchangeRecord(
          type: VaultItemType.identity,
          title: name,
          fields: fields,
          folderPath: folderPath,
          favorite: favorite,
        );

      default:
        // An org-collection item, or a Bitwarden item type added after this
        // codec was written -- keep everything as a secure note rather than
        // dropping it silently.
        fields['content'] = notes;
        _mergeCustomFields(item, fields);
        return ExchangeRecord(
          type: VaultItemType.secureNote,
          title: name.isEmpty ? '(imported item)' : name,
          fields: fields,
          folderPath: folderPath,
          favorite: favorite,
        );
    }
  }

  /// Bitwarden's `login.totp` is either a raw base32 secret or a full
  /// `otpauth://...` URI -- VaultExplorer's Item Vault only stores the raw
  /// secret, so pull it out of the URI's `secret=` parameter when present.
  String _extractTotpSecret(String totp) {
    if (!totp.startsWith('otpauth://')) return totp;
    try {
      final secret = Uri.parse(totp).queryParameters['secret'];
      return secret ?? totp;
    } catch (_) {
      return totp;
    }
  }

  void _mergeCustomFields(Map<String, dynamic> item, Map<String, String> fields) {
    final raw = item['fields'];
    if (raw is! List) return;
    for (final f in raw) {
      if (f is! Map) continue;
      final name = f['name'] as String?;
      final value = f['value'];
      if (name == null || name.isEmpty || value == null) continue;
      fields.putIfAbsent(name, () => '$value');
    }
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async {
    final folderIds = <String, String>{}; // folder path -> generated id
    final folders = <Map<String, String>>[];
    String folderIdFor(List<String> path) {
      if (path.isEmpty) return '';
      final key = path.join('/');
      return folderIds.putIfAbsent(key, () {
        final id = 'f-${folderIds.length + 1}';
        folders.add({'id': id, 'name': key});
        return id;
      });
    }

    final items = records.map((r) => _recordToItem(r, folderIdFor)).toList();

    final root = {
      'encrypted': false,
      'folders': folders,
      'items': items,
    };
    final text = const JsonEncoder.withIndent('  ').convert(root);
    return Uint8List.fromList(utf8.encode(text));
  }

  Map<String, dynamic> _recordToItem(ExchangeRecord r, String Function(List<String>) folderIdFor) {
    final f = Map<String, String>.from(r.fields);
    String take(String key) => f.remove(key) ?? '';
    final folderId = folderIdFor(r.folderPath);

    final base = <String, dynamic>{
      'id': null,
      'organizationId': null,
      'folderId': folderId.isEmpty ? null : folderId,
      'favorite': r.favorite,
      'name': r.title,
      'notes': null,
      'fields': const <dynamic>[],
      'reprompt': 0,
    };

    switch (r.type) {
      case VaultItemType.password:
        final username = take('username');
        final pwd = take('password');
        final url = take('url');
        final totp = take('totp_secret');
        base['notes'] = _emptyToNull(take('notes'));
        base['type'] = _bwTypeLogin;
        base['login'] = {
          'username': _emptyToNull(username),
          'password': _emptyToNull(pwd),
          'totp': _emptyToNull(totp),
          'uris': url.isEmpty ? const <dynamic>[] : [{'match': null, 'uri': url}],
        };
        break;
      case VaultItemType.secureNote:
        base['notes'] = _emptyToNull(take('content'));
        base['type'] = _bwTypeSecureNote;
        base['secureNote'] = {'type': 0};
        break;
      case VaultItemType.paymentCard:
        final expiry = take('expiry'); // "MM/YY"
        final parts = expiry.split('/');
        base['notes'] = _emptyToNull(take('notes'));
        base['type'] = _bwTypeCard;
        base['card'] = {
          'cardholderName': _emptyToNull(take('cardholder')),
          'brand': null,
          'number': _emptyToNull(take('number')),
          'expMonth': _emptyToNull(parts.isNotEmpty ? parts[0].trim() : ''),
          'expYear': _emptyToNull(parts.length > 1 ? parts[1].trim() : ''),
          'code': _emptyToNull(take('cvv')),
        };
        break;
      case VaultItemType.identity:
        final fullName = take('full_name');
        final spaceIdx = fullName.indexOf(' ');
        final first = spaceIdx == -1 ? fullName : fullName.substring(0, spaceIdx);
        final last = spaceIdx == -1 ? '' : fullName.substring(spaceIdx + 1);
        base['notes'] = _emptyToNull(take('notes'));
        base['type'] = _bwTypeIdentity;
        base['identity'] = {
          'title': null,
          'firstName': _emptyToNull(first),
          'middleName': null,
          'lastName': _emptyToNull(last),
          'address1': _emptyToNull(take('address')),
          'address2': null,
          'address3': null,
          'city': null,
          'state': null,
          'postalCode': null,
          'country': null,
          'company': null,
          'email': _emptyToNull(take('email')),
          'phone': _emptyToNull(take('phone')),
          'ssn': _emptyToNull(take('national_id')),
          'username': null,
          'passportNumber': _emptyToNull(take('passport_no')),
          'licenseNumber': _emptyToNull(take('drivers_license')),
        };
        break;
      case VaultItemType.bankAccount:
      case VaultItemType.softwareLicense:
        // No native Bitwarden item type for these -- a secure note with
        // every field preserved individually in `fields` (which Bitwarden
        // supports on every item type) keeps this lossless, unlike folding
        // everything into one notes blob.
        base['notes'] = _emptyToNull(take('notes'));
        base['type'] = _bwTypeSecureNote;
        base['secureNote'] = {'type': 0};
        break;
      case VaultItemType.authenticator:
        // Also no native Bitwarden type, but unlike bankAccount/
        // softwareLicense above, `login.totp` *is* a real Bitwarden slot
        // (it's exactly what Bitwarden itself uses for a login's 2FA) --
        // exporting as a login with just totp/username set (no password)
        // is a standalone-TOTP entry both Bitwarden's own app and its
        // importer already understand, rather than an inert secure note.
        // `issuer` has no matching slot; it rides along as a custom field
        // via the generic `f.isNotEmpty` block below, same as any
        // unmapped key.
        final account = take('account');
        final totp = take('totp_secret');
        base['notes'] = _emptyToNull(take('notes'));
        base['type'] = _bwTypeLogin;
        base['login'] = {
          'username': _emptyToNull(account),
          'password': null,
          'totp': _emptyToNull(totp),
          'uris': const <dynamic>[],
        };
        break;
    }

    if (f.isNotEmpty) {
      final existingFields = (base['fields'] as List).cast<dynamic>();
      base['fields'] = [
        ...existingFields,
        ...f.entries.map(
          (e) => {
            'name': e.key,
            'value': e.value,
            'type': kSecretExchangeFieldKeys.contains(e.key) ? 1 : 0,
            'linkedId': null,
          },
        ),
      ];
    }
    return base;
  }

  dynamic _emptyToNull(String s) => s.isEmpty ? null : s;
}
