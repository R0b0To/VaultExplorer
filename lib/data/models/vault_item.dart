// ── Item type enum ─────────────────────────────────────────────────────────────

enum VaultItemType {
  password,
  paymentCard,
  identity,
  secureNote,
  bankAccount,
  softwareLicense;

  String get label => switch (this) {
        VaultItemType.password => 'Password',
        VaultItemType.paymentCard => 'Payment Card',
        VaultItemType.identity => 'Identity',
        VaultItemType.secureNote => 'Secure Note',
        VaultItemType.bankAccount => 'Bank Account',
        VaultItemType.softwareLicense => 'Software License',
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
  static List<Map<String, dynamic>> fieldsFor(VaultItemType type) =>
      switch (type) {
        VaultItemType.password => [
            {'key': 'username', 'label': 'Username / Email', 'type': 'text', 'required': true},
            {'key': 'password', 'label': 'Password', 'type': 'secret', 'required': true},
            {'key': 'url', 'label': 'Website URL', 'type': 'url'},
            {'key': 'totp_secret', 'label': 'TOTP Secret (2FA)', 'type': 'secret'},
            {'key': 'notes', 'label': 'Notes', 'type': 'multiline'},
          ],
        VaultItemType.paymentCard => [
            {'key': 'cardholder', 'label': 'Cardholder Name', 'type': 'text', 'required': true},
            {'key': 'number', 'label': 'Card Number', 'type': 'secret', 'required': true},
            {'key': 'expiry', 'label': 'Expiry (MM/YY)', 'type': 'text', 'required': true},
            {'key': 'cvv', 'label': 'CVV / CVC', 'type': 'secret', 'required': true},
            {'key': 'pin', 'label': 'PIN', 'type': 'secret'},
            {'key': 'bank', 'label': 'Issuing Bank', 'type': 'text'},
            {'key': 'notes', 'label': 'Notes', 'type': 'multiline'},
          ],
        VaultItemType.identity => [
            {'key': 'full_name', 'label': 'Full Name', 'type': 'text', 'required': true},
            {'key': 'dob', 'label': 'Date of Birth', 'type': 'date'},
            {'key': 'nationality', 'label': 'Nationality', 'type': 'text'},
            {'key': 'passport_no', 'label': 'Passport Number', 'type': 'secret'},
            {'key': 'passport_expiry', 'label': 'Passport Expiry', 'type': 'date'},
            {'key': 'national_id', 'label': 'National ID / SSN', 'type': 'secret'},
            {'key': 'drivers_license', 'label': "Driver's License", 'type': 'text'},
            {'key': 'address', 'label': 'Address', 'type': 'multiline'},
            {'key': 'phone', 'label': 'Phone', 'type': 'phone'},
            {'key': 'email', 'label': 'Email', 'type': 'email'},
            {'key': 'notes', 'label': 'Notes', 'type': 'multiline'},
          ],
        VaultItemType.secureNote => [
            {'key': 'content', 'label': 'Note', 'type': 'multiline', 'required': true},
          ],
        VaultItemType.bankAccount => [
            {'key': 'bank_name', 'label': 'Bank Name', 'type': 'text', 'required': true},
            {'key': 'account_holder', 'label': 'Account Holder', 'type': 'text', 'required': true},
            {'key': 'account_number', 'label': 'Account Number', 'type': 'secret', 'required': true},
            {'key': 'routing_number', 'label': 'Routing / Sort Code', 'type': 'secret'},
            {'key': 'iban', 'label': 'IBAN', 'type': 'secret'},
            {'key': 'swift', 'label': 'SWIFT / BIC', 'type': 'text'},
            {'key': 'account_type', 'label': 'Account Type', 'type': 'text'},
            {'key': 'pin', 'label': 'PIN', 'type': 'secret'},
            {'key': 'notes', 'label': 'Notes', 'type': 'multiline'},
          ],
        VaultItemType.softwareLicense => [
            {'key': 'product', 'label': 'Product Name', 'type': 'text', 'required': true},
            {'key': 'license_key', 'label': 'License Key', 'type': 'secret', 'required': true},
            {'key': 'registered_to', 'label': 'Registered To', 'type': 'text'},
            {'key': 'email', 'label': 'Registration Email', 'type': 'email'},
            {'key': 'purchase_date', 'label': 'Purchase Date', 'type': 'date'},
            {'key': 'expiry_date', 'label': 'Expiry / Renewal Date', 'type': 'date'},
            {'key': 'download_url', 'label': 'Download URL', 'type': 'url'},
            {'key': 'notes', 'label': 'Notes', 'type': 'multiline'},
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
  bool favourite;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
    this.favourite = false,
  });

  /// Returns the primary display subtitle (first non-empty non-secret field).
  String get subtitle {
    final template = VaultItemTemplate.fieldsFor(type);
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

  List<VaultField> get vaultFields {
    final template = VaultItemTemplate.fieldsFor(type);
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
        favourite: favourite,
      );

  VaultItem copyWithFavourite(bool fav) => VaultItem(
        id: id,
        type: type,
        title: title,
        fields: fields,
        createdAt: createdAt,
        updatedAt: updatedAt,
        favourite: fav,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toJson(),
        'title': title,
        'fields': fields,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'favourite': favourite,
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
        favourite: j['favourite'] as bool? ?? false,
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


