import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';

void main() {
  group('FileSize construction', () {
    test('FileSize.bytes stores the raw value', () {
      expect(const FileSize.bytes(1234).bytes, 1234);
    });

    test('a negative byte count is rejected by the constructor assert', () {
      expect(() => FileSize.bytes(-1), throwsA(isA<AssertionError>()));
    });

    test('FileSize.kilobytes converts using a 1000 multiplier (decimal, '
        'not binary)', () {
      expect(FileSize.kilobytes(2).bytes, 2000);
    });

    test('FileSize.megabytes converts using a 1,000,000 multiplier', () {
      expect(FileSize.megabytes(3).bytes, 3000000);
    });

    test('FileSize.gibibytes converts using a 1024-based multiplier', () {
      expect(FileSize.gibibytes(1).bytes, 1024 * 1024 * 1024);
    });

    test('fractional factory inputs round to the nearest byte', () {
      expect(FileSize.kilobytes(1.5).bytes, 1500);
    });

    test('zero is the canonical zero-byte constant', () {
      expect(FileSize.zero.bytes, 0);
      expect(FileSize.zero, const FileSize.bytes(0));
    });
  });

  group('comparison operators', () {
    test('> and < compare byte counts', () {
      expect(FileSize.kilobytes(2) > FileSize.kilobytes(1), isTrue);
      expect(FileSize.kilobytes(1) < FileSize.kilobytes(2), isTrue);
      expect(FileSize.kilobytes(1) > FileSize.kilobytes(2), isFalse);
    });

    test('>= and <= include the equal case', () {
      final a = FileSize.kilobytes(5);
      final b = FileSize.kilobytes(5);
      expect(a >= b, isTrue);
      expect(a <= b, isTrue);
    });
  });

  group('equality and hashCode', () {
    test('two FileSize with the same byte count are equal', () {
      expect(const FileSize.bytes(500), const FileSize.bytes(500));
      expect(
        const FileSize.bytes(500).hashCode,
        const FileSize.bytes(500).hashCode,
      );
    });

    test('different byte counts are not equal', () {
      expect(const FileSize.bytes(500), isNot(const FileSize.bytes(501)));
    });
  });

  group('formatByteCount / FileSize.formatted', () {
    final cases = <int, String>{
      0: '0 B',
      1: '1 B',
      500: '500 B',
      1024: '1.0 KB',
      1500: '1.5 KB',
      10 * 1024: '10 KB', // >= 10: no decimal
      5 * 1024 * 1024 * 1024: '5.0 GB',
    };

    cases.forEach((bytes, expected) {
      test('$bytes bytes formats as "$expected"', () {
        expect(formatByteCount(bytes), expected);
        expect(FileSize.bytes(bytes).formatted, expected);
      });
    });

    test('zero or negative bytes both format as "0 B"', () {
      expect(formatByteCount(0), '0 B');
      expect(formatByteCount(-5), '0 B');
    });

    test('values are capped at the TB unit rather than inventing a PB '
        'suffix', () {
      final onePetabyte = 1024 * 1024 * 1024 * 1024 * 1024; // 1024 TB
      expect(formatByteCount(onePetabyte), '1024 TB');
    });

    test('the "B" unit never shows a decimal, even for values that would '
        'otherwise qualify', () {
      expect(formatByteCount(7), '7 B');
    });
  });
}
