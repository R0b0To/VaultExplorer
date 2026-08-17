import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  const fileNotes = RawEntry(
    name: 'Notes',
    isDir: false,
    sizeBytes: 10,
    modifiedSecs: 1000,
  );
  const folderNotes = RawEntry(
    name: 'Notes',
    isDir: true,
    sizeBytes: 0,
    modifiedSecs: 1000,
  );
  const fileOther = RawEntry(
    name: 'Budget',
    isDir: false,
    sizeBytes: 5,
    modifiedSecs: 900,
  );

  group('no conflict', () {
    test('an empty directory never conflicts', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: const [],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.none);
      expect(result.isConflict, isFalse);
      expect(result.existing, isNull);
    });

    test('a differently-named entry does not conflict', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: [fileOther],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.none);
    });
  });

  group('same-type conflict', () {
    test('creating a file with the same name as an existing file', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: [fileNotes, fileOther],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.sameType);
      expect(result.existing, same(fileNotes));
      expect(result.isConflict, isTrue);
    });

    test('creating a folder with the same name as an existing folder', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: true,
        existingEntries: [folderNotes],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.sameType);
    });
  });

  group('cross-type conflict', () {
    test('creating a folder where a same-named file already exists', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: true,
        existingEntries: [fileNotes],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.crossType);
      expect(result.existing, same(fileNotes));
    });

    test('creating a file where a same-named folder already exists', () {
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: [folderNotes],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.crossType);
    });
  });

  group('case sensitivity', () {
    test('case-insensitive (FAT/exFAT/NTFS) treats "notes" and "Notes" as '
        'the same name', () {
      final result = checkEntryConflict(
        candidateName: 'notes',
        candidateIsDir: false,
        existingEntries: [fileNotes],
        caseSensitive: false,
      );
      expect(result.kind, EntryConflictKind.sameType);
    });

    test('case-sensitive (ext) treats "notes" and "Notes" as different '
        'names', () {
      final result = checkEntryConflict(
        candidateName: 'notes',
        candidateIsDir: false,
        existingEntries: [fileNotes],
        caseSensitive: true,
      );
      expect(result.kind, EntryConflictKind.none);
    });
  });

  group('excluding', () {
    test('excluding the entry being renamed avoids a false self-conflict',
        () {
      // Renaming fileNotes to a name it already has (i.e. no-op rename, or
      // only a case change) should not conflict with itself.
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: [fileNotes, fileOther],
        caseSensitive: false,
        excluding: fileNotes,
      );
      expect(result.kind, EntryConflictKind.none);
    });

    test('excluding one entry still catches a conflict with a different '
        'entry of the same name', () {
      const duplicateNotes = RawEntry(
        name: 'Notes',
        isDir: false,
        sizeBytes: 99,
        modifiedSecs: 2000,
      );
      final result = checkEntryConflict(
        candidateName: 'Notes',
        candidateIsDir: false,
        existingEntries: [fileNotes, duplicateNotes],
        caseSensitive: false,
        excluding: fileNotes,
      );
      expect(result.kind, EntryConflictKind.sameType);
      expect(result.existing, same(duplicateNotes));
    });
  });

  group('message', () {
    test('kind.none has no message', () {
      const result = EntryConflictResult(EntryConflictKind.none, null);
      expect(result.message(l10n, 'Notes'), isNull);
    });

    test('sameType message names the noun of the existing (file) entry', () {
      final result = EntryConflictResult(EntryConflictKind.sameType, fileNotes);
      expect(result.message(l10n, 'Notes'), l10n.conflictSameType('file', 'Notes'));
    });

    test('sameType message names the noun of the existing (folder) entry',
        () {
      final result =
          EntryConflictResult(EntryConflictKind.sameType, folderNotes);
      expect(
        result.message(l10n, 'Notes'),
        l10n.conflictSameType('folder', 'Notes'),
      );
    });

    test('crossType message names both the existing and candidate noun',
        () {
      final result =
          EntryConflictResult(EntryConflictKind.crossType, fileNotes);
      expect(
        result.message(l10n, 'Notes'),
        l10n.conflictCrossType('file', 'Notes', 'folder'),
      );
    });
  });
}
