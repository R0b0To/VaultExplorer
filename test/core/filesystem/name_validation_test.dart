import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  NameValidationResult validate(
    String name,
    FilesystemType fsType, {
    EntryType entryType = EntryType.file,
  }) =>
      validateEntryName(name, fsType, entryType: entryType, l10n: l10n);

  group('valid names', () {
    test('an ordinary name has no issues on fat32', () {
      final result = validate('vacation-photo.jpg', FilesystemType.fat32);
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
      expect(result.name, 'vacation-photo.jpg');
    });

    test('a name containing ":" is fine on ext (only "/" is illegal there)',
        () {
      final result = validate('10:30 meeting notes', FilesystemType.ext);
      expect(result.isValid, isTrue);
    });

    test('"CON" is a legal ext filename (device names are not reserved '
        'there)', () {
      final result = validate('CON', FilesystemType.ext);
      expect(result.isValid, isTrue);
    });

    test('a trailing dot is legal on ext', () {
      final result = validate('archive.', FilesystemType.ext);
      expect(result.isValid, isTrue);
    });
  });

  group('empty name', () {
    test('reports exactly one issue and checks nothing else', () {
      final result = validate('', FilesystemType.fat32);
      expect(result.isValid, isFalse);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.reason, NameValidationReason.empty);
      expect(result.issues.single.message, l10n.validationEmptyName);
    });
  });

  group('"." and ".."', () {
    test('"." is rejected as a reserved navigation name', () {
      final result = validate('.', FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.isDotOrDotDot),
      );
    });

    test('".." is rejected on every filesystem, including ext', () {
      final result = validate('..', FilesystemType.ext);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.isDotOrDotDot),
      );
    });

    test('a name that merely starts with "." is fine', () {
      final result = validate('.gitignore', FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.isDotOrDotDot)),
      );
    });
  });

  group('illegal characters', () {
    test('colon is illegal on fat32, with a 0-indexed charIndex', () {
      final result = validate('10:30.txt', FilesystemType.fat32);
      final issue = result.issues.singleWhere(
        (i) => i.reason == NameValidationReason.illegalCharacter,
      );
      expect(issue.charIndex, 2); // the ':' is the 3rd character, index 2
      expect(issue.message, contains('":"'));
    });

    test('every windows-family illegal character is individually reported '
        'on ntfs', () {
      for (final ch in [
        '"', '*', '/', ':', '<', '>', '?', '\\', '|', //
      ]) {
        final result = validate('a${ch}b', FilesystemType.ntfs);
        expect(
          result.issues.map((i) => i.reason),
          contains(NameValidationReason.illegalCharacter),
          reason: '"$ch" should be illegal on ntfs',
        );
      }
    });

    test('only "/" is illegal on ext', () {
      final result = validate('weird*name?.txt', FilesystemType.ext);
      expect(
        result.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.illegalCharacter)),
      );

      final slash = validate('has/slash', FilesystemType.ext);
      expect(
        slash.issues.map((i) => i.reason),
        contains(NameValidationReason.illegalCharacter),
      );
    });

    test('a name with two illegal characters reports both, not just the '
        'first', () {
      final result = validate('a:b*c', FilesystemType.fat32);
      final illegal = result.issues
          .where((i) => i.reason == NameValidationReason.illegalCharacter)
          .toList();
      expect(illegal, hasLength(2));
      expect(illegal[0].charIndex, 1); // ':'
      expect(illegal[1].charIndex, 3); // '*'
    });
  });

  group('control characters', () {
    test('a NUL-range control character is rejected on fat32', () {
      final result = validate('bad\x01name', FilesystemType.fat32);
      final issue = result.issues.singleWhere(
        (i) => i.reason == NameValidationReason.controlCharacter,
      );
      expect(issue.charIndex, 3);
    });

    test('DEL (0x7F) is treated as a control character', () {
      final result = validate('name\x7F', FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.controlCharacter),
      );
    });

    test('control characters are rejected on ext too, even though the '
        'illegal-character set there is minimal', () {
      final result = validate('bad\x01name', FilesystemType.ext);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.controlCharacter),
      );
    });

    test('a single control character produces exactly one issue', () {
      final result = validate('a\x01b', FilesystemType.fat32);
      final controlIssues = result.issues
          .where((i) => i.reason == NameValidationReason.controlCharacter)
          .toList();
      expect(controlIssues, hasLength(1));
    });
  });

  group('reserved device names', () {
    test('"CON" is rejected on fat32/ntfs/exfat', () {
      for (final fs in [
        FilesystemType.fat32,
        FilesystemType.ntfs,
        FilesystemType.exfat,
      ]) {
        final result = validate('CON', fs);
        expect(
          result.issues.map((i) => i.reason),
          contains(NameValidationReason.reservedDeviceName),
          reason: 'CON should be reserved on $fs',
        );
      }
    });

    test('"con.txt" is rejected case-insensitively, extension and all', () {
      final result = validate('con.txt', FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.reservedDeviceName),
      );
    });

    test('"CONTACT" is not reserved — only an exact base-name match counts',
        () {
      final result = validate('CONTACT', FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.reservedDeviceName)),
      );
    });

    test('reserved names are not flagged on ext', () {
      final result = validate('LPT1', FilesystemType.ext);
      expect(
        result.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.reservedDeviceName)),
      );
    });
  });

  group('trailing space / dot', () {
    test('a trailing space is rejected on fat32, charIndex at the last '
        'character', () {
      final result = validate('notes ', FilesystemType.fat32);
      final issue = result.issues.singleWhere(
        (i) => i.reason == NameValidationReason.trailingSpace,
      );
      expect(issue.charIndex, 5);
      expect(issue.message, contains('File')); // nounCapitalized default
    });

    test('a trailing dot is rejected on fat32', () {
      final result = validate('notes.', FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.trailingDot),
      );
    });

    test('EntryType.folder is reflected in the trailing-space message', () {
      final result =
          validate('My Folder ', FilesystemType.fat32, entryType: EntryType.folder);
      final issue = result.issues.singleWhere(
        (i) => i.reason == NameValidationReason.trailingSpace,
      );
      expect(issue.message, contains('Folder'));
    });

    test('trailing space and dot are both legal on ext', () {
      final space = validate('notes ', FilesystemType.ext);
      final dot = validate('notes.', FilesystemType.ext);
      expect(
        space.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.trailingSpace)),
      );
      expect(
        dot.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.trailingDot)),
      );
    });
  });

  group('component length', () {
    test('exactly at the fat32 limit (255 UTF-16 units) is valid', () {
      final name = 'a' * 255;
      final result = validate(name, FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.componentTooLong)),
      );
    });

    test('one over the fat32 limit is rejected', () {
      final name = 'a' * 256;
      final result = validate(name, FilesystemType.fat32);
      expect(
        result.issues.map((i) => i.reason),
        contains(NameValidationReason.componentTooLong),
      );
    });

    test('ext measures UTF-8 bytes, not UTF-16 code units — 200 "é" '
        'characters is 200 code units but 400 bytes', () {
      final name = 'é' * 200;
      expect(name.length, 200); // sanity check: 200 UTF-16 code units

      final onExt = validate(name, FilesystemType.ext);
      expect(
        onExt.issues.map((i) => i.reason),
        contains(NameValidationReason.componentTooLong),
        reason: '400 UTF-8 bytes exceeds the 255-byte ext limit',
      );

      final onFat32 = validate(name, FilesystemType.fat32);
      expect(
        onFat32.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.componentTooLong)),
        reason: '200 UTF-16 code units is under the fat32 255 limit',
      );
    });

    test('the too-long message reports the measured length and correct '
        'unit', () {
      final result = validate('a' * 256, FilesystemType.fat32);
      final issue = result.issues.singleWhere(
        (i) => i.reason == NameValidationReason.componentTooLong,
      );
      expect(issue.message, contains('256'));
      expect(issue.message, contains(l10n.unitCharacters));
    });

    test('encryptedVault allows a much longer component (1024 bytes)', () {
      final name = 'a' * 500;
      final result = validate(name, FilesystemType.encryptedVault);
      expect(
        result.issues.map((i) => i.reason),
        isNot(contains(NameValidationReason.componentTooLong)),
      );
    });
  });

  group('multiple simultaneous issues', () {
    test('collects every violated rule instead of stopping at the first',
        () {
      // Reserved device name (base before the first "." is exactly "CON")
      // + an illegal ":" later in the string + a trailing space, all in
      // one fat32 name.
      final result = validate('CON.tx:t ', FilesystemType.fat32);
      final reasons = result.issues.map((i) => i.reason).toSet();
      expect(reasons, contains(NameValidationReason.illegalCharacter));
      expect(reasons, contains(NameValidationReason.trailingSpace));
      expect(reasons, contains(NameValidationReason.reservedDeviceName));
    });
  });

  group('unknownConservative', () {
    test('applies the union of restrictions — rejects what any concrete '
        'filesystem would reject', () {
      final result = validate('CON.tmp ', FilesystemType.unknownConservative);
      final reasons = result.issues.map((i) => i.reason).toSet();
      expect(reasons, contains(NameValidationReason.reservedDeviceName));
      expect(reasons, contains(NameValidationReason.trailingSpace));
    });
  });
}
