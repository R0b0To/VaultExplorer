import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

// ── Item type enum ─────────────────────────────────────────────────────────────

enum VaultItemType {
  password,
  paymentCard,
  identity,
  secureNote,
  bankAccount,
  softwareLicense;

  String label(AppLocalizations l10n) => switch (this) {
        VaultItemType.password => l10n.vaultItemTypePassword,
        VaultItemType.paymentCard => l10n.vaultItemTypePaymentCard,
        VaultItemType.identity => l10n.vaultItemTypeIdentity,
        VaultItemType.secureNote => l10n.vaultItemTypeSecureNote,
        VaultItemType.bankAccount => l10n.vaultItemTypeBankAccount,
        VaultItemType.softwareLicense => l10n.vaultItemTypeSoftwareLicense,
      };

  String get icon => switch (this) {
        VaultItemType.password => 'key',
        VaultItemType.paymentCard => 'credit_card',
        VaultItemType.identity => 'badge',
        VaultItemType.secureNote => 'note',
        VaultItemType.bankAccount => 'account_balance',
        VaultItemType.softwareLicense => 'computer',
      };

  String toJson() => name;

  static VaultItemType fromJson(String? value) => switch (value) {
        'password' => VaultItemType.password,
        'paymentCard' => VaultItemType.paymentCard,
        'identity' => VaultItemType.identity,
        'secureNote' => VaultItemType.secureNote,
        'bankAccount' => VaultItemType.bankAccount,
        'softwareLicense' => VaultItemType.softwareLicense,
        _ => VaultItemType.secureNote,
      };
}

// ── Field definition ───────────────────────────────────────────────────────────

enum FieldType { text, secret, multiline, date, phone, email, url, number }

class VaultField {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  String value;

  VaultField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.value = '',
  });

  VaultField copyWith({String? value}) =>
      VaultField(
        key: key,
        label: label,
        type: type,
        required: required,
        value: value ?? this.value,
      );

  Map<String, dynamic> toJson() => {'key': key, 'value': value};

  static VaultField fromTemplate(
    Map<String, dynamic> template,
    Map<String, dynamic> values,
  ) =>
      VaultField(
        key: template['key'] as String,
        label: template['label'] as String,
        type: FieldType.values.firstWhere(
          (t) => t.name == (template['type'] as String? ?? 'text'),
          orElse: () => FieldType.text,
        ),
        required: template['required'] as bool? ?? false,
        value: values[template['key']] as String? ?? '',
      );
}

// ── Item templates ─────────────────────────────────────────────────────────────

class VaultItemTemplate {
  static List<Map<String, dynamic>> fieldsFor(VaultItemType type, AppLocalizations l10n) =>
      switch (type) {
        VaultItemType.password => [
            {'key': 'username', 'label': l10n.fieldUsernameEmail, 'type': 'text', 'required': true},
            {'key': 'password', 'label': l10n.fieldPassword, 'type': 'secret', 'required': true},
            {'key': 'url', 'label': l10n.fieldWebsiteUrl, 'type': 'url'},
            {'key': 'totp_secret', 'label': l10n.fieldTotpSecret, 'type': 'secret'},
            {'key': 'notes', 'label': l10n.fieldNotes, 'type': 'multiline'},
          ],
        VaultItemType.paymentCard => [
            {'key': 'cardholder', 'label': l10n.fieldCardholderName, 'type': 'text', 'required': true},
            {'key': 'number', 'label': l10n.fieldCardNumber, 'type': 'secret', 'required': true},
            {'key': 'expiry', 'label': l10n.fieldExpiryMMYY, 'type': 'text', 'required': true},
            {'key': 'cvv', 'label': l10n.fieldCvvCvc, 'type': 'secret', 'required': true},
            {'key': 'pin', 'label': l10n.fieldPin, 'type': 'secret'},
            {'key': 'bank', 'label': l10n.fieldIssuingBank, 'type': 'text'},
            {'key': 'notes', 'label': l10n.fieldNotes, 'type': 'multiline'},
          ],
        VaultItemType.identity => [
            {'key': 'full_name', 'label': l10n.fieldFullName, 'type': 'text', 'required': true},
            {'key': 'dob', 'label': l10n.fieldDateOfBirth, 'type': 'date'},
            {'key': 'nationality', 'label': l10n.fieldNationality, 'type': 'text'},
            {'key': 'passport_no', 'label': l10n.fieldPassportNumber, 'type': 'secret'},
            {'key': 'passport_expiry', 'label': l10n.fieldPassportExpiry, 'type': 'date'},
            {'key': 'national_id', 'label': l10n.fieldNationalIdSsn, 'type': 'secret'},
            {'key': 'drivers_license', 'label': l10n.fieldDriversLicense, 'type': 'text'},
            {'key': 'address', 'label': l10n.fieldAddress, 'type': 'multiline'},
            {'key': 'phone', 'label': l10n.fieldPhone, 'type': 'phone'},
            {'key': 'email', 'label': l10n.fieldEmail, 'type': 'email'},
            {'key': 'notes', 'label': l10n.fieldNotes, 'type': 'multiline'},
          ],
        VaultItemType.secureNote => [
            {'key': 'content', 'label': l10n.fieldNote, 'type': 'multiline', 'required': true},
          ],
        VaultItemType.bankAccount => [
            {'key': 'bank_name', 'label': l10n.fieldBankName, 'type': 'text', 'required': true},
            {'key': 'account_holder', 'label': l10n.fieldAccountHolder, 'type': 'text', 'required': true},
            {'key': 'account_number', 'label': l10n.fieldAccountNumber, 'type': 'secret', 'required': true},
            {'key': 'routing_number', 'label': l10n.fieldRoutingSortCode, 'type': 'secret'},
            {'key': 'iban', 'label': l10n.fieldIban, 'type': 'secret'},
            {'key': 'swift', 'label': l10n.fieldSwiftBic, 'type': 'text'},
            {'key': 'account_type', 'label': l10n.fieldAccountType, 'type': 'text'},
            {'key': 'pin', 'label': l10n.fieldPin, 'type': 'secret'},
            {'key': 'notes', 'label': l10n.fieldNotes, 'type': 'multiline'},
          ],
        VaultItemType.softwareLicense => [
            {'key': 'product', 'label': l10n.fieldProductName, 'type': 'text', 'required': true},
            {'key': 'license_key', 'label': l10n.fieldLicenseKey, 'type': 'secret', 'required': true},
            {'key': 'registered_to', 'label': l10n.fieldRegisteredTo, 'type': 'text'},
            {'key': 'email', 'label': l10n.fieldRegistrationEmail, 'type': 'email'},
            {'key': 'purchase_date', 'label': l10n.fieldPurchaseDate, 'type': 'date'},
            {'key': 'expiry_date', 'label': l10n.fieldExpiryRenewalDate, 'type': 'date'},
            {'key': 'download_url', 'label': l10n.fieldDownloadUrl, 'type': 'url'},
            {'key': 'notes', 'label': l10n.fieldNotes, 'type': 'multiline'},
          ],
      };
}

// ── VaultItem ─────────────────────────────────────────────────────────────────

class VaultItem {
  final String id;
  final VaultItemType type;
  String title;
  final Map<String, String> fields;
  final DateTime createdAt;
  DateTime updatedAt;
  bool bookmark;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
    this.bookmark = false,
  });

  /// Returns the primary display subtitle (first non-empty non-secret field).
  String subtitle(AppLocalizations l10n) {
    final template = VaultItemTemplate.fieldsFor(type, l10n);
    for (final t in template) {
      final fieldType = FieldType.values.firstWhere(
        (ft) => ft.name == (t['type'] as String? ?? 'text'),
        orElse: () => FieldType.text,
      );
      if (fieldType == FieldType.secret) continue;
      if (fieldType == FieldType.multiline) continue;
      final v = fields[t['key'] as String] ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  List<VaultField> vaultFields(AppLocalizations l10n) {
    final template = VaultItemTemplate.fieldsFor(type, l10n);
    return template
        .map((t) => VaultField.fromTemplate(t, fields))
        .toList();
  }

  VaultItem copyWithFields(Map<String, String> newFields, String newTitle) =>
      VaultItem(
        id: id,
        type: type,
        title: newTitle,
        fields: Map.from(newFields),
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        bookmark: bookmark,
      );

  VaultItem copyWithBookmark(bool fav) => VaultItem(
        id: id,
        type: type,
        title: title,
        fields: fields,
        createdAt: createdAt,
        updatedAt: updatedAt,
        bookmark: fav,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toJson(),
        'title': title,
        'fields': fields,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'bookmark': bookmark,
      };

  factory VaultItem.fromJson(Map<String, dynamic> j) => VaultItem(
        id: j['id'] as String,
        type: VaultItemType.fromJson(j['type'] as String?),
        title: j['title'] as String? ?? '',
        fields: (j['fields'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        // Falls back to the legacy 'favourite' key so items saved before the
        // favourite->bookmark rename still load with their state intact.
        bookmark: j['bookmark'] as bool? ?? j['favourite'] as bool? ?? false,
      );

  static VaultItem create(VaultItemType type, String title) => VaultItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        title: title,
        fields: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}


