import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('FilesystemType.label', () {
    test('technical filesystem names are left untranslated', () {
      expect(FilesystemType.fat32.label(l10n), 'FAT32');
      expect(FilesystemType.exfat.label(l10n), 'exFAT');
      expect(FilesystemType.ntfs.label(l10n), 'NTFS');
      expect(FilesystemType.ext.label(l10n), 'ext2/3/4');
    });

    test('the two generic fallbacks go through localized strings', () {
      expect(
        FilesystemType.encryptedVault.label(l10n),
        l10n.filesystemLabelEncryptedVault,
      );
      expect(
        FilesystemType.unknownConservative.label(l10n),
        l10n.filesystemLabelThisContainer,
      );
    });
  });

  group('FilesystemRules.of', () {
    test('maps each FilesystemType to its own rule table', () {
      expect(FilesystemRules.of(FilesystemType.fat32), same(FilesystemRules.fat32));
      expect(FilesystemRules.of(FilesystemType.exfat), same(FilesystemRules.exfat));
      expect(FilesystemRules.of(FilesystemType.ntfs), same(FilesystemRules.ntfs));
      expect(FilesystemRules.of(FilesystemType.ext), same(FilesystemRules.ext));
      expect(
        FilesystemRules.of(FilesystemType.encryptedVault),
        same(FilesystemRules.encryptedVault),
      );
      expect(
        FilesystemRules.of(FilesystemType.unknownConservative),
        same(FilesystemRules.unknownConservative),
      );
    });

    test('fat32 and exfat share the same rule values (both via FatFs)', () {
      final fat32 = FilesystemRules.fat32;
      final exfat = FilesystemRules.exfat;
      expect(fat32.illegalCharCodes, exfat.illegalCharCodes);
      expect(fat32.maxComponentLength, exfat.maxComponentLength);
      expect(fat32.maxPathLength, exfat.maxPathLength);
      expect(fat32.caseSensitive, exfat.caseSensitive);
    });

    test('ntfs shares fat32\'s character rules but allows a far longer '
        'path', () {
      expect(FilesystemRules.ntfs.illegalCharCodes, FilesystemRules.fat32.illegalCharCodes);
      expect(FilesystemRules.ntfs.maxPathLength, greaterThan(FilesystemRules.fat32.maxPathLength));
    });

    test('ext is the only case-sensitive filesystem among the four real '
        'ones', () {
      expect(FilesystemRules.fat32.caseSensitive, isFalse);
      expect(FilesystemRules.exfat.caseSensitive, isFalse);
      expect(FilesystemRules.ntfs.caseSensitive, isFalse);
      expect(FilesystemRules.ext.caseSensitive, isTrue);
    });

    test('ext only treats "/" as illegal, unlike the windows-family '
        'filesystems', () {
      expect(FilesystemRules.ext.illegalCharCodes, {0x2F});
    });

    test('ext measures component length in UTF-8 bytes; the others in '
        'UTF-16 code units', () {
      expect(FilesystemRules.ext.maxComponentLengthIsUtf8Bytes, isTrue);
      expect(FilesystemRules.fat32.maxComponentLengthIsUtf8Bytes, isFalse);
      expect(FilesystemRules.ntfs.maxComponentLengthIsUtf8Bytes, isFalse);
    });

    test('ext does not reject reserved device names or trailing space/dot '
        '— they are legal ext filenames', () {
      expect(FilesystemRules.ext.disallowReservedDeviceNames, isFalse);
      expect(FilesystemRules.ext.disallowTrailingSpaceOrDot, isFalse);
    });

    test('unknownConservative rejects every character any of the four '
        'real filesystems would reject (it is the union, not an '
        'intersection)', () {
      final union = FilesystemRules.unknownConservative;
      for (final rules in [
        FilesystemRules.fat32,
        FilesystemRules.exfat,
        FilesystemRules.ntfs,
        FilesystemRules.ext, // {'/'}  ⊂  windows-family set
      ]) {
        expect(union.illegalCharCodes.containsAll(rules.illegalCharCodes), isTrue);
      }
    });

    test('unknownConservative also disallows control chars, reserved '
        'device names, and trailing space/dot — the most restrictive '
        'choice for each boolean rule', () {
      final union = FilesystemRules.unknownConservative;
      expect(union.disallowControlChars, isTrue);
      expect(union.disallowReservedDeviceNames, isTrue);
      expect(union.disallowTrailingSpaceOrDot, isTrue);
    });

    test('unknownConservative uses the tightest length limits (fat32\'s '
        'path length, ext\'s byte-based component length)', () {
      final union = FilesystemRules.unknownConservative;
      expect(union.maxComponentLength, 255);
      expect(union.maxComponentLengthIsUtf8Bytes, isTrue);
      expect(union.maxPathLength, 260);
    });
  });

  group('isReservedDeviceName', () {
    test('matches every documented reserved base name, case-insensitively',
        () {
      for (final name in [
        'CON', 'con', 'Con', //
        'PRN', 'AUX', 'NUL', //
        'COM0', 'COM9', 'com5', //
        'LPT0', 'LPT9', 'lpt3', //
      ]) {
        expect(isReservedDeviceName(name), isTrue, reason: name);
      }
    });

    test('an extension does not exempt a reserved base name', () {
      expect(isReservedDeviceName('CON.txt'), isTrue);
      expect(isReservedDeviceName('lpt1.tar.gz'), isTrue);
    });

    test('a name that merely starts with a reserved word is not reserved',
        () {
      expect(isReservedDeviceName('CONTACT'), isFalse);
      expect(isReservedDeviceName('COMPANY'), isFalse);
      expect(isReservedDeviceName('AUXILIARY'), isFalse);
    });

    test('COM/LPT device numbers outside 0-9 are not reserved', () {
      expect(isReservedDeviceName('COM10'), isFalse);
      expect(isReservedDeviceName('LPT'), isFalse); // no digit at all
    });

    test('ordinary names are not reserved', () {
      expect(isReservedDeviceName('notes.txt'), isFalse);
      expect(isReservedDeviceName(''), isFalse);
    });
  });
}
