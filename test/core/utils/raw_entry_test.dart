import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

void main() {
  group('RawEntry.parse — files', () {
    test('parses a well-formed file entry', () {
      final entry = RawEntry.parse('F|1234|1690000000|photo.png');
      expect(entry.name, 'photo.png');
      expect(entry.isDir, isFalse);
      expect(entry.sizeBytes, 1234);
      expect(entry.modifiedSecs, 1690000000);
    });

    test('an unrecognized type tag is treated as not-a-directory (file)',
        () {
      // Only 'D' means directory; anything else is a file, per isDir:
      // typeTag == 'D'.
      final entry = RawEntry.parse('X|1|1|weird.tag');
      expect(entry.isDir, isFalse);
    });
  });

  group('RawEntry.parse — directories', () {
    test('parses a well-formed directory entry, always with sizeBytes 0',
        () {
      final entry = RawEntry.parse('D|0|1690000000|MyFolder');
      expect(entry.name, 'MyFolder');
      expect(entry.isDir, isTrue);
      expect(entry.modifiedSecs, 1690000000);
    });
  });

  group('RawEntry.parse — name field', () {
    test('the name is everything after the third "|", including further '
        '"|" characters, so a legal ext filename containing "|" round-'
        'trips exactly', () {
      final entry = RawEntry.parse('F|10|100|weird|name|with|pipes');
      expect(entry.name, 'weird|name|with|pipes');
    });

    test('an empty name is preserved as an empty string', () {
      final entry = RawEntry.parse('F|10|100|');
      expect(entry.name, '');
    });
  });

  group('RawEntry.parse — malformed input', () {
    test('fewer than three separators throws FormatException', () {
      expect(() => RawEntry.parse('F|10|100'), throwsFormatException);
      expect(() => RawEntry.parse('F|10'), throwsFormatException);
      expect(() => RawEntry.parse('F'), throwsFormatException);
      expect(() => RawEntry.parse(''), throwsFormatException);
    });

    test('a non-numeric size or mtime falls back to 0 rather than '
        'throwing', () {
      final entry = RawEntry.parse('F|not-a-number|also-bad|name.txt');
      expect(entry.sizeBytes, 0);
      expect(entry.modifiedSecs, 0);
    });
  });

  group('RawEntry.parseAll', () {
    test('parses every entry and skips "System:*" sentinel lines', () {
      final entries = RawEntry.parseAll([
        'F|10|100|a.txt',
        'System:TRUNCATED',
        'D|0|200|folder',
      ]);

      expect(entries, hasLength(2));
      expect(entries[0].name, 'a.txt');
      expect(entries[1].name, 'folder');
    });

    test('an empty list produces an empty result', () {
      expect(RawEntry.parseAll(const []), isEmpty);
    });

    test('a list of only sentinel lines produces an empty result without '
        'attempting to parse them', () {
      expect(
        RawEntry.parseAll(const ['System:TRUNCATED', 'System:OTHER']),
        isEmpty,
      );
    });
  });

  group('raw (round-trip)', () {
    test('reconstructs the canonical wire string for a file', () {
      const entry = RawEntry(
        name: 'photo.png',
        isDir: false,
        sizeBytes: 1234,
        modifiedSecs: 1690000000,
      );
      expect(entry.raw, 'F|1234|1690000000|photo.png');
    });

    test('reconstructs the canonical wire string for a directory', () {
      const entry = RawEntry(
        name: 'MyFolder',
        isDir: true,
        sizeBytes: 0,
        modifiedSecs: 1690000000,
      );
      expect(entry.raw, 'D|0|1690000000|MyFolder');
    });

    test('parse(entry.raw) round-trips back to an equal entry', () {
      const entry = RawEntry(
        name: 'a|weird|name.txt',
        isDir: false,
        sizeBytes: 42,
        modifiedSecs: 99,
      );
      expect(RawEntry.parse(entry.raw), entry);
    });
  });

  group('modifiedAt', () {
    test('0 means unknown and maps to null', () {
      const entry = RawEntry(
        name: 'a',
        isDir: false,
        sizeBytes: 0,
        modifiedSecs: 0,
      );
      expect(entry.modifiedAt, isNull);
    });

    test('a positive value maps to the corresponding UTC-seconds instant',
        () {
      const entry = RawEntry(
        name: 'a',
        isDir: false,
        sizeBytes: 0,
        modifiedSecs: 1690000000,
      );
      expect(
        entry.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1690000000 * 1000),
      );
    });
  });

  group('equality and hashCode', () {
    test('two entries with identical fields are equal', () {
      const a = RawEntry(name: 'x', isDir: false, sizeBytes: 1, modifiedSecs: 2);
      const b = RawEntry(name: 'x', isDir: false, sizeBytes: 1, modifiedSecs: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('entries differing in any single field are not equal', () {
      const base = RawEntry(name: 'x', isDir: false, sizeBytes: 1, modifiedSecs: 2);
      expect(base, isNot(const RawEntry(name: 'y', isDir: false, sizeBytes: 1, modifiedSecs: 2)));
      expect(base, isNot(const RawEntry(name: 'x', isDir: true, sizeBytes: 1, modifiedSecs: 2)));
      expect(base, isNot(const RawEntry(name: 'x', isDir: false, sizeBytes: 9, modifiedSecs: 2)));
      expect(base, isNot(const RawEntry(name: 'x', isDir: false, sizeBytes: 1, modifiedSecs: 9)));
    });

    test('a RawEntry can be used as a Set element for de-duplication', () {
      const a = RawEntry(name: 'x', isDir: false, sizeBytes: 1, modifiedSecs: 2);
      const b = RawEntry(name: 'x', isDir: false, sizeBytes: 1, modifiedSecs: 2);
      expect({a, b}, hasLength(1));
    });
  });

  group('toString', () {
    test('mentions the type, name, size, and timestamp', () {
      const entry = RawEntry(
        name: 'photo.png',
        isDir: false,
        sizeBytes: 1234,
        modifiedSecs: 99,
      );
      final str = entry.toString();
      expect(str, contains('FILE'));
      expect(str, contains('photo.png'));
      expect(str, contains('1234'));
    });

    test('directories are labeled DIR', () {
      const entry = RawEntry(
        name: 'folder',
        isDir: true,
        sizeBytes: 0,
        modifiedSecs: 0,
      );
      expect(entry.toString(), contains('DIR'));
    });
  });
}
