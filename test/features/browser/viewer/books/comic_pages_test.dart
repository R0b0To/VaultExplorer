import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/features/browser/viewer/books/comic_pages.dart';

List<BookEntry> _entries(List<String> names) =>
    [for (final n in names) BookEntry(n, 1)];

void main() {
  group('naturalCompare', () {
    test('compares digit runs by value', () {
      final names = ['page10.jpg', 'page2.jpg', 'page1.jpg', 'page20.jpg'];
      names.sort(naturalCompare);
      expect(names, ['page1.jpg', 'page2.jpg', 'page10.jpg', 'page20.jpg']);
    });

    test('is not thrown by leading zeros or differing widths', () {
      final names = ['010.jpg', '002.jpg', '1.jpg', '0003.jpg'];
      names.sort(naturalCompare);
      expect(names, ['1.jpg', '002.jpg', '0003.jpg', '010.jpg']);
    });

    test('ignores case', () {
      final names = ['b.jpg', 'A.jpg', 'c.jpg'];
      names.sort(naturalCompare);
      expect(names, ['A.jpg', 'b.jpg', 'c.jpg']);
    });

    test('orders folders before their contents by path', () {
      final names = ['ch2/01.jpg', 'ch10/01.jpg', 'ch1/02.jpg', 'ch1/01.jpg'];
      names.sort(naturalCompare);
      expect(names, ['ch1/01.jpg', 'ch1/02.jpg', 'ch2/01.jpg', 'ch10/01.jpg']);
    });

    test('is a consistent total order (equal-looking names still differ)', () {
      expect(naturalCompare('a.jpg', 'a.jpg'), 0);
      expect(naturalCompare('A.jpg', 'a.jpg'), isNot(0));
    });
  });

  group('comicPageNames', () {
    test('keeps only images, in natural order', () {
      final pages = comicPageNames(_entries([
        '10.png',
        '2.jpg',
        'ComicInfo.xml',
        '1.webp',
        'notes.txt',
        'Thumbs.db',
      ]));
      expect(pages, ['1.webp', '2.jpg', '10.png']);
    });

    test('drops macOS resource forks and hidden files', () {
      final pages = comicPageNames(_entries([
        '__MACOSX/._001.jpg',
        '001.jpg',
        '.hidden/002.jpg',
        'dir/.DS_Store',
        'dir/003.jpg',
      ]));
      expect(pages, ['001.jpg', 'dir/003.jpg']);
    });

    test('an archive with no images has no pages', () {
      expect(comicPageNames(_entries(['readme.txt', 'a.xml'])), isEmpty);
    });
  });
}
