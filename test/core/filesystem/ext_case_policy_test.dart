import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/volume_filesystem_registry.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

/// Pins what an ext volume gets from [FilesystemType.extPortable]. These
/// tests use the type directly (not the switch), so they describe the
/// behaviour that turning `kAllowCaseDistinctNamesInExtContainers` on
/// selects, and keep passing if the switch is turned off again.
void main() {
  final l10n = AppLocalizationsEn();
  final portableRules = FilesystemRules.of(FilesystemType.extPortable);

  const fileNotes = RawEntry(
    name: 'Notes',
    isDir: false,
    sizeBytes: 10,
    modifiedSecs: 1000,
  );

  NameValidationResult validate(String name, FilesystemType type) =>
      validateEntryName(name, type, entryType: EntryType.file, l10n: l10n);

  tearDown(VolumeFilesystemRegistry.clearForTesting);

  group('conflict checks on extPortable', () {
    test('"Notes" and "notes" coexist', () {
      final result = checkEntryConflict(
        candidateName: 'notes',
        candidateIsDir: false,
        existingEntries: const [fileNotes],
        caseSensitive: portableRules.caseSensitive,
      );
      expect(result.isConflict, isFalse);
    });

    test('an exact-name match is still a conflict', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: const [fileNotes],
        caseSensitive: portableRules.caseSensitive,
      );
      expect(result.kind, EntryConflictKind.sameType);
    });

    test('an exact-name match of the other type is still cross-type', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: true,
        existingEntries: const [fileNotes],
        caseSensitive: portableRules.caseSensitive,
      );
      expect(result.kind, EntryConflictKind.crossType);
    });
  });

  group('name rules on extPortable', () {
    const names = [
      'ok.txt',
      'Notes',
      'notes',
      'a:b',
      'what?.txt',
      'CON',
      'con.txt',
      'NUL.log',
      'trailing.',
      'trailing ',
      ' leading',
      'tab\there',
      'x*y',
      'pipe|name',
    ];

    test('rejects exactly what the conservative rules reject', () {
      for (final name in names) {
        expect(
          validate(name, FilesystemType.extPortable).issues.map((i) => i.reason),
          validate(name, FilesystemType.unknownConservative)
              .issues
              .map((i) => i.reason),
          reason: 'name: ${name.replaceAll('\t', r'\t')}',
        );
      }
    });

    test('a portable name that the full ext rules would accept is refused', () {
      // The point of extPortable: ext itself allows these, but they can't be
      // copied to FAT/exFAT/NTFS or Android shared storage.
      for (final name in ['a:b', 'CON', 'trailing.']) {
        expect(validate(name, FilesystemType.ext).isValid, isTrue, reason: name);
        expect(
          validate(name, FilesystemType.extPortable).isValid,
          isFalse,
          reason: name,
        );
      }
    });

    test('capitalization is the only difference from unknownConservative', () {
      expect(portableRules.caseSensitive, isTrue);
      expect(
        FilesystemRules.of(FilesystemType.unknownConservative).caseSensitive,
        isFalse,
      );
    });
  });

  group('resolution for an ext volume', () {
    MountedContainer ext(int volId) => MountedContainer(
      uri: 'content://test/$volId',
      displayName: 'ext-$volId',
      volId: volId,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 0,
      freeSpace: 0,
      containerFormat: 'veracrypt',
    );

    test('a recorded ext volume gets case-distinct names while the switch is on', () {
      VolumeFilesystemRegistry.record(1, FilesystemType.ext);
      expect(
        resolveFilesystemType(ext(1)),
        FilesystemType.extPortable,
      );
      expect(namesAreCaseSensitive(ext(1)), isTrue);
    }, skip: kAllowCaseDistinctNamesInExtContainers ? false : 'switch is off');

    test('an ext volume that was never recorded stays conservative', () {
      expect(resolveFilesystemType(ext(2)), FilesystemType.unknownConservative);
      expect(namesAreCaseSensitive(ext(2)), isFalse);
    });

    test('FAT, exFAT and NTFS volumes stay conservative and case-insensitive', () {
      VolumeFilesystemRegistry.record(3, FilesystemType.fat32);
      VolumeFilesystemRegistry.record(4, FilesystemType.exfat);
      VolumeFilesystemRegistry.record(5, FilesystemType.ntfs);
      for (final id in [3, 4, 5]) {
        expect(
          resolveFilesystemType(ext(id)),
          FilesystemType.unknownConservative,
          reason: '$id',
        );
        expect(namesAreCaseSensitive(ext(id)), isFalse, reason: '$id');
      }
    });
  });
}
