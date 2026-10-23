import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';

void main() {
  group('VaultBookmark', () {
    test('name and folders come from the path', () {
      const file = VaultBookmark('Docs/Makefile', isDir: false);
      expect(file.name, 'Makefile');
      expect(file.parentPath, 'Docs');
      expect(file.containingFolder, 'Docs');

      const folder = VaultBookmark('Photos/v1.2', isDir: true);
      expect(folder.name, 'v1.2');
      expect(folder.containingFolder, 'Photos/v1.2');

      expect(const VaultBookmark('top', isDir: true).parentPath, '');
    });

    test('an extensionless file and a dotted folder keep their real kind', () {
      // The old "no dot means folder" guess got both of these wrong.
      final marks = VaultMarks().withBookmarks(const [
        VaultBookmark('README', isDir: false),
        VaultBookmark('archive.2024', isDir: true),
      ]);
      expect(marks.bookmarks[0].isDir, isFalse);
      expect(marks.bookmarks[1].isDir, isTrue);
    });
  });

  group('VaultMarks changes', () {
    const a = VaultBookmark('Docs/a.txt', isDir: false);
    const b = VaultBookmark('Photos', isDir: true);

    test('adding skips paths that are already bookmarked', () {
      final marks = VaultMarks().withBookmarks([a, b, a]);
      expect(marks.bookmarkPaths, ['Docs/a.txt', 'Photos']);
      expect(marks.isBookmarked('Photos'), isTrue);
      expect(marks.isBookmarked('Nope'), isFalse);
      expect(marks.withBookmarks([a]), marks);
    });

    test('removing keeps the rest in order and ignores unknown paths', () {
      final marks = VaultMarks().withBookmarks([a, b]);
      expect(marks.withoutBookmarks(['Docs/a.txt']).bookmarkPaths, ['Photos']);
      expect(marks.withoutBookmarks(['Nope']), marks);
    });

    test('reordering follows ReorderableListView.onReorderItem', () {
      final marks = VaultMarks().withBookmarks([a, b]);
      expect(marks.reordered(0, 1).bookmarkPaths, ['Photos', 'Docs/a.txt']);
      expect(marks.reordered(1, 0).bookmarkPaths, ['Photos', 'Docs/a.txt']);
      expect(marks.reordered(9, 0), marks);
    });

    test('pins are a set', () {
      final marks = VaultMarks().withPinned(['x', 'x', 'y']);
      expect(marks.pinnedPaths, {'x', 'y'});
      expect(marks.withoutPinned(['x']).pinnedPaths, {'y'});
    });
  });

  group('deleting', () {
    final tree = VaultMarks(
      bookmarks: const [
        VaultBookmark('Photos', isDir: true),
        VaultBookmark('Photos/2024/a.jpg', isDir: false),
        VaultBookmark('PhotosOld', isDir: true),
      ],
      pinnedPaths: const {'Photos/x.txt', 'PhotosOld/y.txt'},
    );

    test('a deleted folder takes its contents with it, and only those', () {
      final after = tree.withoutDeleted({'Photos'});
      expect(after.bookmarkPaths, ['PhotosOld']);
      expect(after.pinnedPaths, {'PhotosOld/y.txt'});
    });

    test('deleting something unmarked changes nothing', () {
      expect(tree.withoutDeleted({'Elsewhere'}), tree);
      expect(tree.withoutDeleted(const {}), tree);
    });
  });

  group('renaming and moving', () {
    final tree = VaultMarks(
      bookmarks: const [
        VaultBookmark('Photos', isDir: true),
        VaultBookmark('Photos/2024/a.jpg', isDir: false),
        VaultBookmark('PhotosOld', isDir: true),
      ],
      pinnedPaths: const {'Photos/x.txt'},
    );

    test('renaming a folder rewrites everything inside it', () {
      final after = tree.withMoves({'Photos': 'Pics'});
      expect(after.bookmarkPaths, ['Pics', 'Pics/2024/a.jpg', 'PhotosOld']);
      expect(after.pinnedPaths, {'Pics/x.txt'});
      expect(after.bookmarks.first.isDir, isTrue);
    });

    test('a swap of two names applies at once instead of chaining', () {
      final marks = VaultMarks().withBookmarks(const [
        VaultBookmark('a', isDir: false),
        VaultBookmark('b', isDir: false),
      ]);
      expect(marks.withMoves({'a': 'b', 'b': 'a'}).bookmarkPaths, ['b', 'a']);
    });

    test('the most specific move wins', () {
      final marks = VaultMarks().withBookmarks(const [
        VaultBookmark('d/f.txt', isDir: false),
      ]);
      final after = marks.withMoves({'d': 'x', 'd/f.txt': 'y/g.txt'});
      expect(after.bookmarkPaths, ['y/g.txt']);
    });

    test('moving onto an existing bookmark does not duplicate it', () {
      final marks = VaultMarks().withBookmarks(const [
        VaultBookmark('a', isDir: false),
        VaultBookmark('b', isDir: false),
      ]);
      expect(marks.withMoves({'a': 'b'}).bookmarkPaths, ['b']);
    });

    test('no moves changes nothing', () {
      expect(tree.withMoves(const {}), tree);
    });
  });

  group('JSON', () {
    test('round trips', () {
      final marks = VaultMarks(
        bookmarks: const [
          VaultBookmark('a', isDir: true),
          VaultBookmark('b/c.txt', isDir: false),
        ],
        pinnedPaths: const {'p', 'q'},
      );
      final json = jsonDecode(jsonEncode(marks.toJson()));
      expect(VaultMarks.fromJson(json), marks);
      expect(VaultMarks.fromJson(json).hashCode, marks.hashCode);
    });

    test('skips malformed entries instead of dropping the whole list', () {
      final marks = VaultMarks.fromJson({
        'bookmarks': [
          {'path': 'ok', 'dir': true},
          'junk',
          {'path': '', 'dir': true},
          {'path': 'no-kind'},
          {'path': 'ok', 'dir': false},
        ],
        'pinned': ['p', 3, ''],
      });
      expect(marks.bookmarks, [const VaultBookmark('ok', isDir: true)]);
      expect(marks.pinnedPaths, {'p'});
    });

    test('a root that is not an object is a FormatException', () {
      expect(() => VaultMarks.fromJson([1, 2]), throwsFormatException);
      expect(() => VaultMarks.fromJson('x'), throwsFormatException);
    });

    test('a missing list is just empty', () {
      expect(VaultMarks.fromJson(<String, Object?>{}).isEmpty, isTrue);
    });
  });
}
