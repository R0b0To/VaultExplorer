import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/case_collision.dart';

void main() {
  group('findCaseCollisions', () {
    test('no collisions when every path is distinct', () {
      expect(
        findCaseCollisions(['a.txt', 'docs/b.txt', 'docs/c.txt']),
        isEmpty,
      );
      expect(findCaseCollisions(const []), isEmpty);
    });

    test('reports two files that differ only by case', () {
      final result = findCaseCollisions(['Notes.txt', 'other.txt', 'notes.txt']);
      expect(result, [
        ['Notes.txt', 'notes.txt'],
      ]);
    });

    test('collision inside differently-cased directories is still found', () {
      final result = findCaseCollisions(['Docs/a.txt', 'docs/A.txt']);
      expect(result, [
        ['Docs/a.txt', 'docs/A.txt'],
      ]);
    });

    test('directories that differ only by case merge harmlessly', () {
      expect(findCaseCollisions(['Docs/a.txt', 'docs/b.txt']), isEmpty);
    });

    test('a file colliding with another entry\'s implied directory', () {
      final result = findCaseCollisions(['docs', 'Docs/a.txt']);
      expect(result, [
        ['docs', 'Docs'],
      ]);
    });

    test('identical duplicate paths are not case collisions', () {
      expect(findCaseCollisions(['a.txt', 'a.txt']), isEmpty);
    });

    test('backslash separators are normalised', () {
      final result = findCaseCollisions([r'Docs\a.txt', 'docs/a.txt']);
      expect(result, hasLength(1));
    });

    test('three spellings land in one group in first-seen order', () {
      final result = findCaseCollisions(['README', 'x', 'readme', 'ReadMe']);
      expect(result, [
        ['README', 'readme', 'ReadMe'],
      ]);
    });
  });
}
