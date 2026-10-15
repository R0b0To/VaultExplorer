import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/case_collision.dart';

void main() {
  group('resolveCaseCollisionPaths', () {
    test('paths that do not collide are returned unchanged', () {
      const paths = ['a.txt', 'docs/b.txt', 'docs/c.txt'];
      expect(resolveCaseCollisionPaths(paths), paths);
      expect(resolveCaseCollisionPaths(const []), isEmpty);
    });

    test('the later of two names that differ only by case is renamed', () {
      expect(
        resolveCaseCollisionPaths(['Notes.txt', 'other.txt', 'notes.txt']),
        ['Notes.txt', 'other.txt', 'notes (1).txt'],
      );
    });

    test('a collision inside differently-cased directories is renamed there', () {
      expect(
        resolveCaseCollisionPaths(['Docs/a.txt', 'docs/A.txt']),
        ['Docs/a.txt', 'docs/A (1).txt'],
      );
    });

    test('directories that differ only by case merge without renaming', () {
      const paths = ['Docs/a.txt', 'docs/b.txt'];
      expect(resolveCaseCollisionPaths(paths), paths);
    });

    test('a file colliding with another entry\'s directory is renamed', () {
      expect(
        resolveCaseCollisionPaths(['docs', 'Docs/a.txt']),
        ['docs (1)', 'Docs/a.txt'],
      );
    });

    test('identical duplicate paths are left alone', () {
      const paths = ['a.txt', 'a.txt'];
      expect(resolveCaseCollisionPaths(paths), paths);
    });

    test('backslash separators are normalised', () {
      expect(
        resolveCaseCollisionPaths([r'Docs\a.txt', 'docs/a.txt']),
        ['Docs/a.txt', 'docs/a (1).txt'],
      );
    });

    test('three spellings each get their own name', () {
      expect(
        resolveCaseCollisionPaths(['README', 'x', 'readme', 'ReadMe']),
        ['README', 'x', 'readme (1)', 'ReadMe (2)'],
      );
    });

    test('a rename never lands on a name another entry really has', () {
      // "a (1)" is a real entry, so the renamed "A" must skip to "(2)".
      expect(
        resolveCaseCollisionPaths(['a', 'A', 'a (1)']),
        ['a', 'A (2)', 'a (1)'],
      );
    });

    test('extensions are kept and dotfiles are not split', () {
      expect(
        resolveCaseCollisionPaths(['x/.env', 'x/.ENV', 'x/a.tar.gz', 'x/A.TAR.GZ']),
        ['x/.env', 'x/.ENV (1)', 'x/a.tar.gz', 'x/A.TAR (1).GZ'],
      );
    });
  });
}
