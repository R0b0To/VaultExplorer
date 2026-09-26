library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';

class ProtonJsonCodec implements PasswordFormatCodec {
  const ProtonJsonCodec();

  @override
  String get id => 'proton_json';

  @override
  String get displayName => 'Proton (.json)';

  @override
  String get description =>
      'Unencrypted JSON export from Proton Authenticator or Proton Pass.';

  @override
  bool get supportsImport => true;

  @override
  bool get supportsExport => true;

  @override
  bool get isEncrypted => false;

  @override
  bool looksLikeThisFormat({required String fileName, Uint8List? bytes}) {
    if (!fileName.toLowerCase().endsWith('.json')) return false;
    if (bytes == null) return false;
    try {
      final text = utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
      return text.contains('"entries"') || text.contains('"vaults"');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DecodedExchange> decode(Uint8List bytes, {String? password}) async {
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Root is not a JSON object.');
      }
      root = decoded;
    } catch (e) {
      throw PasswordFileFormatException('Could not parse this file as JSON: $e');
    }

    final records = <ExchangeRecord>[];
    final warnings = <String>[];

    // Format 1: Proton Authenticator {"version": 1, "entries": [...]}
    if (root.containsKey('entries') && root['entries'] is List) {
      final entries = root['entries'] as List;
      for (final raw in entries) {
        if (raw is! Map) continue;
        try {
          final record = _authenticatorEntryToRecord(Map<String, dynamic>.from(raw));
          if (record != null) records.add(record);
        } catch (e) {
          warnings.add('Skipped entry: $e');
        }
      }
    }
    // Format 2: Proton Pass {"vaults": {...} or [...]}
    else if (root.containsKey('vaults')) {
      _decodeProtonPassVaults(root['vaults'], records, warnings);
    } else {
      throw const PasswordFileFormatException(
        'This doesn\'t look like a Proton export (no "entries" or "vaults" found).',
      );
    }

    if (records.isEmpty) {
      throw const PasswordFileFormatException('No usable items were found in this Proton export.');
    }

    return DecodedExchange(records, warnings: warnings);
  }

  ExchangeRecord? _authenticatorEntryToRecord(Map<String, dynamic> raw) {
    final content = raw['content'] as Map<String, dynamic>? ?? {};
    final uriStr = (content['uri'] as String? ?? '').trim();
    final name = (content['name'] as String? ?? '').trim();
    final note = (raw['note'] as String? ?? '').trim();

    final fields = <String, String>{};
    String title = name;

    if (uriStr.isNotEmpty) {
      try {
        final uri = Uri.parse(uriStr);
        final qp = uri.queryParameters;

        if (qp.containsKey('secret')) {
          fields['totp_secret'] = qp['secret']!;
        } else {
          fields['totp_secret'] = uriStr;
        }

        String issuer = qp['issuer'] ?? '';
        final pathLabel = Uri.decodeComponent(uri.path.replaceFirst(RegExp(r'^/'), ''));
        String account = name;

        if (pathLabel.contains(':')) {
          final parts = pathLabel.split(':');
          if (issuer.isEmpty) issuer = parts.first.trim();
          if (account.isEmpty) account = parts.sublist(1).join(':').trim();
        } else if (account.isEmpty) {
          account = pathLabel.trim();
        }

        if (issuer.isNotEmpty) fields['issuer'] = issuer;
        if (account.isNotEmpty) fields['account'] = account;

        if (qp.containsKey('algorithm')) fields['totp_algorithm'] = qp['algorithm']!;
        if (qp.containsKey('digits')) fields['totp_digits'] = qp['digits']!;
        if (qp.containsKey('period')) fields['totp_period'] = qp['period']!;

        if (title.isEmpty) {
          title = issuer.isNotEmpty ? issuer : account;
        }
      } catch (_) {
        fields['totp_secret'] = uriStr;
      }
    }

    if (note.isNotEmpty) fields['notes'] = note;

    return ExchangeRecord(
      type: VaultItemType.authenticator,
      title: title.isNotEmpty ? title : 'Authenticator',
      fields: fields,
    );
  }

  void _decodeProtonPassVaults(
    dynamic vaultsData,
    List<ExchangeRecord> records,
    List<String> warnings,
  ) {
    final vaultsList = <Map<String, dynamic>>[];
    if (vaultsData is Map) {
      for (final v in vaultsData.values) {
        if (v is Map) vaultsList.add(Map<String, dynamic>.from(v));
      }
    } else if (vaultsData is List) {
      for (final v in vaultsData) {
        if (v is Map) vaultsList.add(Map<String, dynamic>.from(v));
      }
    }

    for (final vault in vaultsList) {
      final vaultName = (vault['name'] as String? ?? '').trim();
      final items = vault['items'];
      if (items is! List) continue;

      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        try {
          final record = _passItemToRecord(Map<String, dynamic>.from(rawItem), vaultName);
          if (record != null) records.add(record);
        } catch (e) {
          warnings.add('Skipped item: $e');
        }
      }
    }
  }

  ExchangeRecord? _passItemToRecord(Map<String, dynamic> raw, String vaultName) {
    final data = raw['data'] as Map<String, dynamic>? ?? {};
    final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
    final content = data['content'] as Map<String, dynamic>? ?? {};
    final itemType = (data['type'] as String? ?? 'login').toLowerCase();

    final title = (metadata['name'] as String? ?? '').trim();
    final note = (metadata['note'] as String? ?? '').trim();
    final folderPath = vaultName.isNotEmpty ? [vaultName] : const <String>[];

    final fields = <String, String>{};
    if (note.isNotEmpty) fields['notes'] = note;

    switch (itemType) {
      case 'login':
        final username = (content['itemEmail'] as String? ??
                content['itemUsername'] as String? ??
                content['username'] as String? ??
                '')
            .trim();
        final password = (content['password'] as String? ?? '').trim();
        final urls = content['urls'];
        String url = '';
        if (urls is List && urls.isNotEmpty) {
          url = (urls.first as String? ?? '').trim();
        }

        if (username.isNotEmpty) fields['username'] = username;
        if (password.isNotEmpty) fields['password'] = password;
        if (url.isNotEmpty) fields['url'] = url;

        final totpUri = (content['totpUri'] as String? ?? '').trim();
        if (totpUri.isNotEmpty) {
          _parseAndApplyTotpUri(totpUri, fields);
        }

        return ExchangeRecord(
          type: VaultItemType.password,
          title: title.isNotEmpty ? title : (username.isNotEmpty ? username : 'Login'),
          fields: fields,
          folderPath: folderPath,
        );

      case 'creditcard':
      case 'card':
        fields['cardholder'] = (content['cardholderName'] as String? ?? '').trim();
        fields['number'] = (content['number'] as String? ?? '').trim();
        final expMonth = (content['expMonth'] as String? ?? '').trim();
        final expYear = (content['expYear'] as String? ?? '').trim();
        if (expMonth.isNotEmpty || expYear.isNotEmpty) {
          fields['expiry'] =
              '${expMonth.padLeft(2, '0')}/${expYear.length >= 2 ? expYear.substring(expYear.length - 2) : expYear}';
        }
        fields['cvv'] = (content['verificationNumber'] as String? ?? '').trim();
        if (content['pin'] != null) fields['pin'] = content['pin'].toString();

        return ExchangeRecord(
          type: VaultItemType.paymentCard,
          title: title.isNotEmpty ? title : 'Card',
          fields: fields,
          folderPath: folderPath,
        );

      case 'note':
        fields['content'] = (content['note'] as String? ?? note).trim();
        return ExchangeRecord(
          type: VaultItemType.secureNote,
          title: title.isNotEmpty ? title : 'Note',
          fields: fields,
          folderPath: folderPath,
        );

      default:
        final totpUri = (content['totpUri'] as String? ?? '').trim();
        if (totpUri.isNotEmpty) {
          _parseAndApplyTotpUri(totpUri, fields);
          return ExchangeRecord(
            type: VaultItemType.authenticator,
            title: title.isNotEmpty ? title : 'Authenticator',
            fields: fields,
            folderPath: folderPath,
          );
        }
        fields['content'] = note;
        return ExchangeRecord(
          type: VaultItemType.secureNote,
          title: title.isNotEmpty ? title : 'Item',
          fields: fields,
          folderPath: folderPath,
        );
    }
  }

  void _parseAndApplyTotpUri(String totpUri, Map<String, String> fields) {
    try {
      final uri = Uri.parse(totpUri);
      final qp = uri.queryParameters;
      if (qp.containsKey('secret')) {
        fields['totp_secret'] = qp['secret']!;
      } else {
        fields['totp_secret'] = totpUri;
      }
      if (qp.containsKey('issuer') && !fields.containsKey('issuer')) {
        fields['issuer'] = qp['issuer']!;
      }
      if (qp.containsKey('algorithm')) fields['totp_algorithm'] = qp['algorithm']!;
      if (qp.containsKey('digits')) fields['totp_digits'] = qp['digits']!;
      if (qp.containsKey('period')) fields['totp_period'] = qp['period']!;
    } catch (_) {
      fields['totp_secret'] = totpUri;
    }
  }

  @override
  Future<Uint8List> encode(List<ExchangeRecord> records, {String? password}) async {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final secret = r.fields['totp_secret'] ?? '';
      if (secret.isEmpty && r.type != VaultItemType.password) continue;

      final issuer = r.fields['issuer'] ?? r.title;
      final account = r.fields['account'] ?? r.fields['username'] ?? '';
      final algorithm = r.fields['totp_algorithm'] ?? 'SHA1';
      final digits = r.fields['totp_digits'] ?? '6';
      final period = r.fields['totp_period'] ?? '30';

      String label = issuer;
      if (account.isNotEmpty) {
        label = '$issuer:$account';
      }

      final uri = Uri(
        scheme: 'otpauth',
        host: 'totp',
        path: label,
        queryParameters: {
          'secret': secret,
          if (issuer.isNotEmpty) 'issuer': issuer,
          'algorithm': algorithm,
          'digits': digits,
          'period': period,
        },
      );

      entries.add({
        'id': 'entry-$i',
        'content': {
          'uri': uri.toString(),
          'entry_type': 'Totp',
          'name': account.isNotEmpty ? account : r.title,
        },
        'note': r.fields['notes'],
      });
    }

    final root = {
      'version': 1,
      'entries': entries,
    };

    final text = const JsonEncoder.withIndent('    ').convert(root);
    return Uint8List.fromList(utf8.encode(text));
  }
}