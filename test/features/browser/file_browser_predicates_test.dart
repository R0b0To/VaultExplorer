import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';

RawEntry _file(String name) => RawEntry(name: name, isDir: false, sizeBytes: 100, modifiedSecs: 0);
RawEntry _dir(String name) => RawEntry(name: name, isDir: true, sizeBytes: 0, modifiedSecs: 0);

void main() {
  group('fullPathOf', () {
    test('a root-level entry is just its own name', () {
      expect(fullPathOf(_file('photo.jpg'), ''), 'photo.jpg');
    });

    test('a nested entry is prefixed with the current directory', () {
      expect(fullPathOf(_file('photo.jpg'), 'Vacation/2026'), 'Vacation/2026/photo.jpg');
    });
  });

  group('isFolderMounted', () {
    test('true for a directory whose full path is in the mounted set', () {
      final entry = _dir('Documents');
      expect(isFolderMounted(entry, '', {'Documents'}), isTrue);
    });

    test('false for a directory not in the mounted set', () {
      final entry = _dir('Documents');
      expect(isFolderMounted(entry, '', {'Photos'}), isFalse);
    });

    test('false for a file even if its path happens to be in the mounted set', () {
      // A file can never be SAF-mounted -- the set only ever holds
      // directory paths in practice, but this pins down that the
      // isDir check isn't skippable as an optimization.
      final entry = _file('Documents');
      expect(isFolderMounted(entry, '', {'Documents'}), isFalse);
    });

    test('resolves against the current directory, not just the bare name', () {
      final entry = _dir('2026');
      expect(isFolderMounted(entry, 'Vacation', {'Vacation/2026'}), isTrue);
      expect(isFolderMounted(entry, 'Work', {'Vacation/2026'}), isFalse);
    });
  });

  group('isPinned', () {
    test('true when the full path is pinned', () {
      expect(isPinned(_file('notes.txt'), 'Docs', {'Docs/notes.txt'}), isTrue);
    });

    test('false when it is not', () {
      expect(isPinned(_file('notes.txt'), 'Docs', {'Docs/other.txt'}), isFalse);
    });
  });

  group('isBookmark', () {
    test('true when the full path is bookmarked', () {
      expect(isBookmark(_file('notes.txt'), 'Docs', ['Docs/notes.txt']), isTrue);
    });

    test('false when it is not', () {
      expect(isBookmark(_file('notes.txt'), 'Docs', ['Docs/other.txt']), isFalse);
    });
  });

  group('matchesFilter', () {
    test('null filter matches everything', () {
      expect(matchesFilter('photo.jpg', null), isTrue);
      expect(matchesFilter('report.pdf', null), isTrue);
      expect(matchesFilter('archive.zip', null), isTrue);
    });

    test('an unrecognized filter string matches everything, same as null', () {
      expect(matchesFilter('photo.jpg', 'not_a_real_filter'), isTrue);
    });

    test('image filter matches known image extensions only', () {
      expect(matchesFilter('photo.jpg', 'image'), isTrue);
      expect(matchesFilter('photo.PNG', 'image'), isTrue, reason: 'extension matching is case-insensitive');
      expect(matchesFilter('clip.mp4', 'image'), isFalse);
    });

    test('video filter matches known video extensions only', () {
      expect(matchesFilter('clip.mp4', 'video'), isTrue);
      expect(matchesFilter('photo.jpg', 'video'), isFalse);
    });

    test('audio filter matches known audio extensions only', () {
      expect(matchesFilter('song.mp3', 'audio'), isTrue);
      expect(matchesFilter('photo.jpg', 'audio'), isFalse);
    });

    test('document filter matches office/text/archive extensions, case-insensitively', () {
      expect(matchesFilter('report.pdf', 'document'), isTrue);
      expect(matchesFilter('report.PDF', 'document'), isTrue);
      expect(matchesFilter('notes.docx', 'document'), isTrue);
      expect(matchesFilter('photo.jpg', 'document'), isFalse);
    });

    group('secure filter (vault-item pseudo-extensions)', () {
      // Regression coverage for a real bug found while extracting this
      // function: the original _matchesFilter lowercased the extension
      // before this check, but vaultIconForExt()'s switch is
      // case-sensitive over VaultItemType.name values like 'paymentCard'
      // -- so this filter matched 'password' items (no uppercase letters
      // to lose) but silently matched none of the other five vault item
      // types. Every other call site in the app (file_tile.dart,
      // bookmark_bar.dart, file_grid_view.dart, file_masonry_view.dart)
      // already passed the extension un-lowercased.
      test('matches every VaultItemType pseudo-extension, not just password', () {
        expect(matchesFilter('Login.password', 'secure'), isTrue);
        expect(matchesFilter('Visa.paymentCard', 'secure'), isTrue);
        expect(matchesFilter('Passport.identity', 'secure'), isTrue);
        expect(matchesFilter('Wifi.secureNote', 'secure'), isTrue);
        expect(matchesFilter('Checking.bankAccount', 'secure'), isTrue);
        expect(matchesFilter('IDE.softwareLicense', 'secure'), isTrue);
      });

      test('an all-lowercase vault extension does NOT match (case matters, by design)', () {
        // This is the exact failure mode the old bug produced for every
        // *other* type: confirms the match is genuinely case-sensitive
        // rather than this test accidentally being case-insensitive too.
        expect(matchesFilter('Visa.paymentcard', 'secure'), isFalse);
      });

      test('does not match ordinary file extensions', () {
        expect(matchesFilter('photo.jpg', 'secure'), isFalse);
        expect(matchesFilter('report.pdf', 'secure'), isFalse);
      });
    });
  });
}
