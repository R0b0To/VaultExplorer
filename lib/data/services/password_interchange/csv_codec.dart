library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

enum _Canon {
  title,
  username,
  password,
  url,
  notes,
  totp,
  type,
  folder,
  favorite,
  cardholder,
  cardNumber,
  cardCvv,
  cardExpiry,
  fullName,
  phone,
  email,
  extraJson,
}

/// Header names (lower-cased, spaces/underscores stripped for comparison)
/// this codec recognizes for each canonical field, ordered by priority.
/// Covers this codec's own export plus Bitwarden, LastPass, Chrome,
/// 1Password, Dashlane, NordPass, and Apple Passwords/iCloud Keychain CSV
/// exports -- between them, a superset of the column names those tools use
/// for a straightforward login row.
const Map<_Canon, List<String>> _kCandidates = {
  _Canon.title: ['name', 'title', 'itemname', 'accountname'],
  _Canon.username: ['username', 'loginusername', 'username1', 'account', 'loginname'],
  _Canon.password: ['password', 'loginpassword', 'password1'],
  _Canon.url: ['url', 'loginuri', 'website', 'site', 'additionalurls'],
  _Canon.notes: ['notes', 'note', 'comments'],
  _Canon.totp: ['totp', 'logintotp', 'otpauth', 'otpsecret', 'otp'],
  _Canon.type: ['type', 'category'],
  _Canon.folder: ['folder', 'grouping', 'group'],
  _Canon.favorite: ['favorite', 'fav'],
  _Canon.cardholder: ['cardholdername', 'cardholder'],
  _Canon.cardNumber: ['cardnumber', 'number'],
  _Canon.cardCvv: ['cvc', 'cvv', 'securitycode', 'code'],
  _Canon.cardExpiry: ['expirydate', 'expiration', 'expiry'],
  _Canon.fullName: ['fullname'],
  _Canon.phone: ['phonenumber', 'phone'],
  _Canon.email: ['email'],
  _Canon.extraJson: ['extra', 'extrajson', 'vaultexplorerextra'],
};

String _normalizeHeader(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

class CsvCodec implements PasswordFormatCodec {
  const CsvCodec();

  @override
  String get id => 'csv';

  @override
  String get displayName => 'CSV';

  @override
  String get description =>
      'Reads exports from Bitwarden, LastPass, Chrome, 1Password, Dashlane, NordPass, Apple Passwords and generic CSV. Plain text -- not encrypted, and less complete than KDBX for anything beyond logins. Delete the file once you\'re done with it.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => true;

  @override
  bool get isEncrypted => false;

  @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) => fileName.toLowerCase().endsWith('.csv');

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      throw PasswordFileFormatException('Could not read this file as text: $e');
    }

 final List<List<dynamic>> rows;
    try {
      rows = csv.decode(text);
    } catch (e) {
      throw PasswordFileFormatException('Could not parse this file as CSV: $e');
    }
    if (rows.isEmpty) {
      throw const PasswordFileFormatException('This CSV file has no rows.');
    }

    final header = rows.first.map((h) => _normalizeHeader('$h')).toList();
    final colIndex = <_Canon, int>{};
    for (final entry in _kCandidates.entries) {
      for (final candidate in entry.value) {
        final idx = header.indexOf(candidate);
        if (idx != -1) {
          colIndex[entry.key] = idx;
          break;
        }
      }
    }
    if (!colIndex.containsKey(_Canon.title) &&
        !colIndex.containsKey(_Canon.username) &&
        !colIndex.containsKey(_Canon.password)) {
      throw const PasswordFileFormatException(
        'None of this CSV\'s columns look like a password manager export (expected at least a name, username, or password column).',
      );
    }

    String cell(List<dynamic> row, _Canon c) {
      final idx = colIndex[c];
      if (idx == null || idx >= row.length) return '';
      return '${row[idx] ?? ''}'.trim();
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length == 1 && '${row.first}'.trim().isEmpty) continue; // trailing blank line
      try {
        records.add(_rowToRecord(row, cell));
      } catch (e) {
        warnings.add('Skipped row ${i + 1}: $e');
      }
    }
    if (records.isEmpty) {
      throw const PasswordFileFormatException('No usable rows were found in this CSV file.');
    }
    return DecodedExchange(records, warnings: warnings);
  }

  ExchangeRecord _rowToRecord(List<dynamic> row, String Function(List<dynamic>, _Canon) cell) {
    final title = cell(row, _Canon.title);
    final username = cell(row, _Canon.username);
    final password = cell(row, _Canon.password);
    final url = cell(row, _Canon.url);
    final notes = cell(row, _Canon.notes);
    final totp = cell(row, _Canon.totp);
    final typeRaw = cell(row, _Canon.type);
    final folderRaw = cell(row, _Canon.folder);
    final favoriteRaw = cell(row, _Canon.favorite).toLowerCase();

    final type = _resolveType(
      typeRaw: typeRaw,
      hasUsernameOrPassword: username.isNotEmpty || password.isNotEmpty,
      hasCardNumber: cell(row, _Canon.cardNumber).isNotEmpty,
      hasIdentityHints: cell(row, _Canon.fullName).isNotEmpty || cell(row, _Canon.phone).isNotEmpty,
    );

    final fields = <String, String>{};
    // Anything from a previous VaultExplorer export round-trips first, since
    // it's unambiguous -- generic per-column extraction below only fills in
    // whatever this didn't already cover.
    final extraJsonRaw = cell(row, _Canon.extraJson);
    if (extraJsonRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(extraJsonRaw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (k is String) fields[k] = '$v';
          });
        }
      } catch (_) {
        // Not our own `extra` JSON -- just a column named similarly. Ignore.
      }
    }

    switch (type) {
      case VaultItemType.password:
        fields.putIfAbsent('username', () => username);
        fields.putIfAbsent('password', () => password);
        fields.putIfAbsent('url', () => url);
        fields.putIfAbsent('notes', () => notes);
        if (totp.isNotEmpty) fields.putIfAbsent('totp_secret', () => totp);
        break;
      case VaultItemType.paymentCard:
        fields.putIfAbsent('cardholder', () => cell(row, _Canon.cardholder).isNotEmpty ? cell(row, _Canon.cardholder) : username);
        fields.putIfAbsent('number', () => cell(row, _Canon.cardNumber));
        fields.putIfAbsent('expiry', () => cell(row, _Canon.cardExpiry));
        fields.putIfAbsent('cvv', () => cell(row, _Canon.cardCvv));
        fields.putIfAbsent('notes', () => notes);
        break;
      case VaultItemType.identity:
        fields.putIfAbsent('full_name', () => cell(row, _Canon.fullName).isNotEmpty ? cell(row, _Canon.fullName) : title);
        fields.putIfAbsent('phone', () => cell(row, _Canon.phone));
        fields.putIfAbsent('email', () => cell(row, _Canon.email).isNotEmpty ? cell(row, _Canon.email) : username);
        fields.putIfAbsent('notes', () => notes);
        break;
      case VaultItemType.bankAccount:
        fields.putIfAbsent('bank_name', () => title);
        fields.putIfAbsent('account_holder', () => username);
        fields.putIfAbsent('notes', () => notes);
        break;
      case VaultItemType.softwareLicense:
        fields.putIfAbsent('product', () => title);
        fields.putIfAbsent('license_key', () => password.isNotEmpty ? password : cell(row, _Canon.cardNumber));
        fields.putIfAbsent('notes', () => notes);
        break;
      case VaultItemType.secureNote:
        final content = notes.isNotEmpty ? notes : (extraJsonRaw.isNotEmpty && fields.isEmpty ? extraJsonRaw : '');
        fields.putIfAbsent('content', () => content);
        if (username.isNotEmpty) fields.putIfAbsent('_imported_username', () => username);
        if (url.isNotEmpty) fields.putIfAbsent('_imported_url', () => url);
        break;
    }

    return ExchangeRecord(
      type: type,
      title: title.isNotEmpty ? title : (username.isNotEmpty ? username : url),
      fields: fields,
      folderPath: folderRaw.isEmpty ? const [] : folderRaw.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList(),
      favorite: favoriteRaw == '1' || favoriteRaw == 'true' || favoriteRaw == 'yes',
    );
  }

  VaultItemType _resolveType({
    required String typeRaw,
    required bool hasUsernameOrPassword,
    required bool hasCardNumber,
    required bool hasIdentityHints,
  }) {
    final t = typeRaw.toLowerCase().trim();
    if (t.isNotEmpty) {
      for (final vt in VaultItemType.values) {
        if (vt.name.toLowerCase() == t) return vt; // our own export, exact enum name
      }
      if (t.contains('card')) return VaultItemType.paymentCard;
      if (t.contains('ident')) return VaultItemType.identity;
      if (t.contains('bank')) return VaultItemType.bankAccount;
      if (t.contains('licen')) return VaultItemType.softwareLicense;
      if (t.contains('note') && !hasUsernameOrPassword) return VaultItemType.secureNote;
      if (t.contains('login') || t.contains('password')) return VaultItemType.password;
    }
    if (hasUsernameOrPassword) return VaultItemType.password;
    if (hasCardNumber) return VaultItemType.paymentCard;
    if (hasIdentityHints) return VaultItemType.identity;
    return VaultItemType.secureNote;
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async {
    const header = ['title', 'type', 'folder', 'favorite', 'username', 'password', 'url', 'totp', 'notes', 'extra'];
    final rows = <List<String>>[header];

    for (final r in records) {
      final f = Map<String, String>.from(r.fields);
      String take(String key) => f.remove(key) ?? '';

      String username = '';
      String pwd = '';
      String url = '';
      String totp = '';
      String notes = '';
      switch (r.type) {
        case VaultItemType.password:
          username = take('username');
          pwd = take('password');
          url = take('url');
          totp = take('totp_secret');
          notes = take('notes');
          break;
        case VaultItemType.softwareLicense:
          pwd = take('license_key');
          url = take('download_url');
          notes = take('notes');
          break;
        default:
          notes = take('notes');
          if (r.type == VaultItemType.secureNote) notes = take('content');
          break;
      }

      rows.add([
        r.title,
        r.type.name,
        r.folderPath.join('/'),
        r.favorite ? 'true' : 'false',
        username,
        pwd,
        url,
        totp,
        notes,
        f.isEmpty ? '' : jsonEncode(f),
      ]);
    }

    final csvText = Csv(lineDelimiter: '\n').encode(rows);
    return Uint8List.fromList(utf8.encode(csvText));
  }
}
