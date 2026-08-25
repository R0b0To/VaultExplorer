import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('VaultItemType JSON', () {
    test('every value round-trips through toJson/fromJson', () {
      for (final type in VaultItemType.values) {
        expect(VaultItemType.fromJson(type.toJson()), type);
      }
    });

    test('fromJson falls back to secureNote for an unknown or null string',
        () {
      // Deliberate choice, not an oversight: an item whose type can't be
      // recognized (corrupted data, or a type added in a newer app version)
      // still loads as *something* editable rather than being dropped.
      expect(VaultItemType.fromJson('not_a_real_type'), VaultItemType.secureNote);
      expect(VaultItemType.fromJson(null), VaultItemType.secureNote);
      expect(VaultItemType.fromJson(''), VaultItemType.secureNote);
    });
  });

  group('VaultItemTemplate.fieldsFor', () {
    test('every item type has a non-empty template with unique field keys',
        () {
      for (final type in VaultItemType.values) {
        final template = VaultItemTemplate.fieldsFor(type, l10n);
        expect(template, isNotEmpty, reason: 'for $type');

        final keys = template.map((f) => f['key'] as String).toList();
        expect(
          keys.toSet().length,
          keys.length,
          reason: 'duplicate field key within $type\'s template: $keys',
        );

        for (final field in template) {
          expect(field['key'], isNotEmpty, reason: 'for $type');
          expect(field['label'], isNotEmpty, reason: 'for $type');
          // 'type' is optional in the template map (VaultField.fromTemplate
          // defaults a missing one to 'text'), but if present it must be a
          // real FieldType name -- a typo here would silently fall back to
          // FieldType.text rather than failing loudly.
          if (field['type'] != null) {
            expect(
              FieldType.values.map((t) => t.name),
              contains(field['type']),
              reason: 'unrecognized field type "${field['type']}" for $type',
            );
          }
        }
      }
    });

    test('password template marks username and password as required, '
        'and includes a TOTP secret field', () {
      final fields = VaultItemTemplate.fieldsFor(VaultItemType.password, l10n);
      final byKey = {for (final f in fields) f['key'] as String: f};

      expect(byKey['username']?['required'], isTrue);
      expect(byKey['password']?['required'], isTrue);
      expect(byKey['password']?['type'], 'secret');
      expect(byKey.containsKey('totp_secret'), isTrue);
      expect(byKey['totp_secret']?['type'], 'secret');
    });

    test('secure note template is just a single required multiline field',
        () {
      final fields =
          VaultItemTemplate.fieldsFor(VaultItemType.secureNote, l10n);
      expect(fields, hasLength(1));
      expect(fields.single['key'], 'content');
      expect(fields.single['type'], 'multiline');
      expect(fields.single['required'], isTrue);
    });
  });

  group('VaultField.fromTemplate', () {
    test('reads the value for its key out of the supplied values map', () {
      final field = VaultField.fromTemplate(
        {'key': 'username', 'label': 'Username', 'type': 'text', 'required': true},
        {'username': 'alice', 'password': 'hunter2'},
      );
      expect(field.key, 'username');
      expect(field.label, 'Username');
      expect(field.type, FieldType.text);
      expect(field.required, isTrue);
      expect(field.value, 'alice');
    });

    test('defaults value to empty string when the key is absent', () {
      final field = VaultField.fromTemplate(
        {'key': 'notes', 'label': 'Notes', 'type': 'multiline'},
        {},
      );
      expect(field.value, '');
      expect(field.required, isFalse);
    });

    test('an unrecognized type string falls back to FieldType.text', () {
      final field = VaultField.fromTemplate(
        {'key': 'x', 'label': 'X', 'type': 'not_a_real_field_type'},
        {},
      );
      expect(field.type, FieldType.text);
    });

    test('a missing type in the template also falls back to FieldType.text',
        () {
      final field = VaultField.fromTemplate({'key': 'x', 'label': 'X'}, {});
      expect(field.type, FieldType.text);
    });
  });

  group('VaultField.copyWith', () {
    test('changes only value, leaving key/label/type/required untouched', () {
      final original = VaultField(
        key: 'password',
        label: 'Password',
        type: FieldType.secret,
        required: true,
        value: 'old',
      );
      final updated = original.copyWith(value: 'new');

      expect(updated.value, 'new');
      expect(updated.key, original.key);
      expect(updated.label, original.label);
      expect(updated.type, original.type);
      expect(updated.required, original.required);
      // The original is untouched -- copyWith doesn't mutate in place.
      expect(original.value, 'old');
    });

    test('omitting value keeps the current one', () {
      final original =
          VaultField(key: 'k', label: 'L', type: FieldType.text, value: 'kept');
      expect(original.copyWith().value, 'kept');
    });
  });

  group('VaultField.toJson', () {
    test('only serializes key and value -- not label/type/required', () {
      final field = VaultField(
        key: 'password',
        label: 'Password',
        type: FieldType.secret,
        required: true,
        value: 'hunter2',
      );
      // label/type/required are re-derived from VaultItemTemplate every
      // time the item is loaded (see VaultItem.vaultFields), not persisted
      // per-field -- so if a template's label or required-ness changes in
      // a future app version, existing saved items pick up the new
      // definition automatically instead of being stuck with whatever was
      // true when they were first saved.
      expect(field.toJson(), {'key': 'password', 'value': 'hunter2'});
    });
  });

  group('VaultItem.create', () {
    test('starts with empty fields, no bookmark, and equal timestamps', () {
      final item = VaultItem.create(VaultItemType.password, 'My Bank');
      expect(item.type, VaultItemType.password);
      expect(item.title, 'My Bank');
      expect(item.fields, isEmpty);
      expect(item.bookmark, isFalse);
      expect(item.id, isNotEmpty);
      // createdAt and updatedAt are set from the same DateTime.now() call
      // sequence, so they should be identical or differ by an
      // imperceptible amount, never meaningfully apart.
      expect(
        item.updatedAt.difference(item.createdAt).inSeconds.abs(),
        lessThan(1),
      );
    });

    test('two items created back-to-back get different ids', () {
      // Relies on DateTime.now() having finer-than-one-microsecond
      // real-world granularity between two sequential constructor calls,
      // which holds in practice on the Dart VM (this is not a fake clock
      // that could tick backwards or stay frozen -- see VaultItem.create).
      // If this ever flakes, that's worth investigating rather than just
      // adding a delay, since it would mean two rapid "New Item" taps
      // really can collide on id.
      final a = VaultItem.create(VaultItemType.secureNote, 'A');
      final b = VaultItem.create(VaultItemType.secureNote, 'B');
      expect(a.id, isNot(b.id));
    });
  });

  group('VaultItem JSON round-trip', () {
    test('a fully-populated item survives toJson -> fromJson unchanged', () {
      final original = VaultItem(
        id: 'abc123',
        type: VaultItemType.paymentCard,
        title: 'Work Visa',
        fields: {
          'cardholder': 'Alice Example',
          'number': '4111111111111111',
          'expiry': '12/29',
          'cvv': '123',
        },
        createdAt: DateTime.utc(2024, 3, 1, 10, 30),
        updatedAt: DateTime.utc(2024, 6, 15, 8, 0),
        bookmark: true,
      );

      final roundTripped = VaultItem.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.type, original.type);
      expect(roundTripped.title, original.title);
      expect(roundTripped.fields, original.fields);
      expect(roundTripped.createdAt, original.createdAt);
      expect(roundTripped.updatedAt, original.updatedAt);
      expect(roundTripped.bookmark, original.bookmark);
    });

    test('fromJson falls back to the legacy "favourite" key when "bookmark" '
        'is absent, so items saved before the favourite->bookmark rename '
        'still load with their state intact', () {
      final json = {
        'id': '1',
        'type': 'password',
        'title': 'Old Item',
        'fields': <String, dynamic>{},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
        'favourite': true,
        // no 'bookmark' key at all
      };
      expect(VaultItem.fromJson(json).bookmark, isTrue);
    });

    test('"bookmark" takes priority over "favourite" when both are present',
        () {
      final json = {
        'id': '1',
        'type': 'password',
        'title': 'T',
        'fields': <String, dynamic>{},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
        'bookmark': false,
        'favourite': true,
      };
      expect(VaultItem.fromJson(json).bookmark, isFalse);
    });

    test('missing bookmark/favourite defaults to false', () {
      final json = {
        'id': '1',
        'type': 'password',
        'title': 'T',
        'fields': <String, dynamic>{},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
      };
      expect(VaultItem.fromJson(json).bookmark, isFalse);
    });

    test('an unrecognized type string loads as secureNote rather than '
        'throwing', () {
      final json = {
        'id': '1',
        'type': 'some_future_type_this_app_version_does_not_know',
        'title': 'T',
        'fields': <String, dynamic>{},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
      };
      expect(VaultItem.fromJson(json).type, VaultItemType.secureNote);
    });

    test('missing or unparseable timestamps fall back to "now" rather than '
        'throwing', () {
      final json = {
        'id': '1',
        'type': 'password',
        'title': 'T',
        'fields': <String, dynamic>{},
        'createdAt': 'not a date',
        'updatedAt': null,
      };
      final before = DateTime.now();
      final item = VaultItem.fromJson(json);
      final after = DateTime.now();

      expect(
        item.createdAt.isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(item.createdAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
      expect(
        item.updatedAt.isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
      );
    });

    test('missing title defaults to an empty string rather than throwing',
        () {
      final json = {
        'id': '1',
        'type': 'password',
        'fields': <String, dynamic>{},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
      };
      expect(VaultItem.fromJson(json).title, '');
    });

    test('non-string field values are coerced to strings rather than '
        'throwing (defends against a hand-edited or foreign JSON file)',
        () {
      final json = {
        'id': '1',
        'type': 'password',
        'title': 'T',
        'fields': {'weird_number_field': 42, 'weird_bool_field': true},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
      };
      final item = VaultItem.fromJson(json);
      expect(item.fields['weird_number_field'], '42');
      expect(item.fields['weird_bool_field'], 'true');
    });

    test('a missing "id" throws rather than silently generating one -- '
        'unlike every other field, id has no fallback, so a caller relying '
        'on this working for a malformed file will find out immediately',
        () {
      final json = {
        'type': 'password',
        'title': 'T',
        'fields': <String, dynamic>{},
        'createdAt': DateTime.utc(2023).toIso8601String(),
        'updatedAt': DateTime.utc(2023).toIso8601String(),
      };
      expect(() => VaultItem.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  group('VaultItem.subtitle', () {
    test('for a password item, shows the username -- never the password',
        () {
      final item = VaultItem(
        id: '1',
        type: VaultItemType.password,
        title: 'Email',
        fields: {'username': 'alice@example.com', 'password': 'hunter2'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(item.subtitle(l10n), 'alice@example.com');
    });

    test('falls through to the next non-secret field when the first is '
        'empty (username blank -> shows the URL instead)', () {
      final item = VaultItem(
        id: '1',
        type: VaultItemType.password,
        title: 'Email',
        fields: {'username': '', 'password': 'hunter2', 'url': 'example.com'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(item.subtitle(l10n), 'example.com');
    });

    test('a secure note (whose only field is multiline) has no subtitle',
        () {
      final item = VaultItem(
        id: '1',
        type: VaultItemType.secureNote,
        title: 'My Note',
        fields: {'content': 'Some private content'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // The note's content is both the only field and a multiline field,
      // so it's deliberately excluded -- a list view showing this item
      // should never preview secret-note content as if it were a subtitle.
      expect(item.subtitle(l10n), '');
    });

    test('with every eligible field empty, returns an empty string rather '
        'than throwing', () {
      final item = VaultItem(
        id: '1',
        type: VaultItemType.password,
        title: 'Empty',
        fields: const {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(item.subtitle(l10n), '');
    });
  });

  group('VaultItem.vaultFields', () {
    test('produces one VaultField per template entry, populated from '
        'this item\'s fields map', () {
      final item = VaultItem(
        id: '1',
        type: VaultItemType.password,
        title: 'Email',
        fields: {'username': 'alice', 'password': 'hunter2'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final fields = item.vaultFields(l10n);
      final byKey = {for (final f in fields) f.key: f};

      expect(
        fields.length,
        VaultItemTemplate.fieldsFor(VaultItemType.password, l10n).length,
      );
      expect(byKey['username']?.value, 'alice');
      expect(byKey['password']?.value, 'hunter2');
      // A template field with no corresponding entry in item.fields (e.g.
      // this item never had a URL saved) still appears, just empty --
      // vaultFields always reflects the full template, not just whichever
      // keys happen to be present.
      expect(byKey['url']?.value, '');
    });
  });

  group('VaultItem.copyWithFields', () {
    test('replaces fields and title, bumps updatedAt, keeps id/type/'
        'createdAt/bookmark', () {
      final original = VaultItem(
        id: 'abc',
        type: VaultItemType.secureNote,
        title: 'Old Title',
        fields: {'content': 'old content'},
        createdAt: DateTime.utc(2020),
        updatedAt: DateTime.utc(2020),
        bookmark: true,
      );

      final updated =
          original.copyWithFields({'content': 'new content'}, 'New Title');

      expect(updated.id, original.id);
      expect(updated.type, original.type);
      expect(updated.createdAt, original.createdAt);
      expect(updated.bookmark, original.bookmark);
      expect(updated.title, 'New Title');
      expect(updated.fields, {'content': 'new content'});
      expect(updated.updatedAt.isAfter(original.updatedAt), isTrue);
    });

    test('the new fields map is an independent copy, not a shared '
        'reference -- mutating the map passed in afterward does not '
        'retroactively change the item', () {
      final original = VaultItem(
        id: '1',
        type: VaultItemType.secureNote,
        title: 'T',
        fields: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final sourceMap = {'content': 'v1'};
      final updated = original.copyWithFields(sourceMap, 'T');

      sourceMap['content'] = 'mutated after the fact';

      expect(updated.fields['content'], 'v1');
    });
  });

  group('VaultItem.copyWithBookmark', () {
    test('flips only the bookmark flag, keeping everything else', () {
      final original = VaultItem(
        id: '1',
        type: VaultItemType.password,
        title: 'T',
        fields: {'username': 'alice'},
        createdAt: DateTime.utc(2020),
        updatedAt: DateTime.utc(2020),
        bookmark: false,
      );

      final updated = original.copyWithBookmark(true);

      expect(updated.bookmark, isTrue);
      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.createdAt, original.createdAt);
      // Unlike copyWithFields, copyWithBookmark passes `fields` straight
      // through rather than `Map.from(fields)` -- the two items share the
      // same underlying fields map. That's exercised explicitly here so a
      // future change to one copyWith* method's cloning behavior doesn't
      // silently change the other's; worth confirming with whoever wrote
      // it whether the shared reference is intentional (bookmark-only
      // toggles never touch fields, so it's likely harmless in practice)
      // or should be Map.from(fields) for consistency with copyWithFields.
      expect(identical(updated.fields, original.fields), isTrue);
    });
  });
}
