import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/features/browser/paste_conflict_detection.dart';

void main() {
  group('detectPasteConflicts', () {
    test('no conflicts when nothing pasted collides with an existing name', () {
      final result = detectPasteConflicts(
        items: [const ClipboardItem(path: 'Docs/report.pdf', isDir: false)],
        existingNamesLower: {'photo.jpg'},
        existingDirsLower: {},
        isCrossContainer: false,
        currentDirPath: '',
      );

      expect(result, isEmpty);
    });

    test('a colliding file name is reported as a conflict', () {
      final result = detectPasteConflicts(
        items: [const ClipboardItem(path: 'Downloads/report.pdf', isDir: false)],
        existingNamesLower: {'report.pdf'},
        existingDirsLower: {},
        isCrossContainer: false,
        currentDirPath: 'Docs',
      );

      expect(result, hasLength(1));
      expect(result.single.item.path, 'Downloads/report.pdf');
      expect(result.single.destIsDir, isFalse);
    });

    test('name matching is case-insensitive', () {
      final result = detectPasteConflicts(
        items: [const ClipboardItem(path: 'Downloads/Report.PDF', isDir: false)],
        existingNamesLower: {'report.pdf'},
        existingDirsLower: {},
        isCrossContainer: false,
        currentDirPath: '',
      );

      expect(result, hasLength(1));
    });

    test('destIsDir reflects whether the colliding destination entry is a directory', () {
      final result = detectPasteConflicts(
        items: [const ClipboardItem(path: 'Backup/Photos', isDir: true)],
        existingNamesLower: {'photos'},
        existingDirsLower: {'photos'},
        isCrossContainer: false,
        currentDirPath: '',
      );

      expect(result.single.destIsDir, isTrue);
    });

    test('a name that matches but is not in existingDirsLower reports destIsDir false', () {
      // e.g. pasting a folder named the same as an existing *file*.
      final result = detectPasteConflicts(
        items: [const ClipboardItem(path: 'Backup/notes.txt', isDir: true)],
        existingNamesLower: {'notes.txt'},
        existingDirsLower: {},
        isCrossContainer: false,
        currentDirPath: '',
      );

      expect(result.single.destIsDir, isFalse);
    });

    group('same-path-as-current-location is not a conflict', () {
      test('pasting a file back onto its own current path (same container) is skipped', () {
        // e.g. copying without moving, then immediately pasting into the
        // same folder it was copied from -- a no-op, not a collision.
        final result = detectPasteConflicts(
          items: [const ClipboardItem(path: 'Docs/report.pdf', isDir: false)],
          existingNamesLower: {'report.pdf'},
          existingDirsLower: {},
          isCrossContainer: false,
          currentDirPath: 'Docs',
        );

        expect(result, isEmpty);
      });

      test(
        'the same-name exemption requires the *exact* same path, not just the same leaf name',
        () {
          // Same file name, but the source item actually lives in a
          // different folder than the one being pasted into -- this is a
          // genuine collision, not a same-location no-op.
          final result = detectPasteConflicts(
            items: [const ClipboardItem(path: 'Other/report.pdf', isDir: false)],
            existingNamesLower: {'report.pdf'},
            existingDirsLower: {},
            isCrossContainer: false,
            currentDirPath: 'Docs',
          );

          expect(result, hasLength(1));
        },
      );

      test(
        'the same-path exemption does NOT apply across containers, even with an identical path string',
        () {
          // Cross-container paste: the source and destination are
          // different vaults, so an identical path string is a
          // coincidence, not "pasting onto itself" -- must still be
          // flagged as a conflict so the user can choose how to resolve it.
          final result = detectPasteConflicts(
            items: [const ClipboardItem(path: 'Docs/report.pdf', isDir: false)],
            existingNamesLower: {'report.pdf'},
            existingDirsLower: {},
            isCrossContainer: true,
            currentDirPath: 'Docs',
          );

          expect(result, hasLength(1));
        },
      );

      test('the exemption resolves the current directory correctly at the root', () {
        final result = detectPasteConflicts(
          items: [const ClipboardItem(path: 'report.pdf', isDir: false)],
          existingNamesLower: {'report.pdf'},
          existingDirsLower: {},
          isCrossContainer: false,
          currentDirPath: '',
        );

        expect(result, isEmpty);
      });
    });

    test('multiple items are each checked independently', () {
      final result = detectPasteConflicts(
        items: const [
          ClipboardItem(path: 'Src/a.txt', isDir: false),
          ClipboardItem(path: 'Src/b.txt', isDir: false),
          ClipboardItem(path: 'Src/c.txt', isDir: false),
        ],
        existingNamesLower: {'a.txt', 'c.txt'},
        existingDirsLower: {},
        isCrossContainer: false,
        currentDirPath: 'Dest',
      );

      expect(result.map((c) => c.item.path), ['Src/a.txt', 'Src/c.txt']);
    });
  });
}
