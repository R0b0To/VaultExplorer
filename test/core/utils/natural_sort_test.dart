import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/natural_sort.dart';

void main() {
  group('naturalCompare', () {
    test('orders single-digit-vs-multi-digit names by numeric value', () {
      final input = ['f1', 'f10', 'f2'];
      input.sort(naturalCompare);
      expect(input, ['f1', 'f2', 'f10']);
    });

    test('orders a realistic file listing the way a person expects', () {
      final input = [
        'image10.png',
        'image1.png',
        'image2.png',
        'image20.png',
      ];
      input.sort(naturalCompare);
      expect(
        input,
        ['image1.png', 'image2.png', 'image10.png', 'image20.png'],
      );
    });

    test('falls back to plain character order when there are no digits', () {
      final input = ['banana', 'apple', 'cherry'];
      input.sort(naturalCompare);
      expect(input, ['apple', 'banana', 'cherry']);
    });

    test('a shorter name that is a prefix of a longer one sorts first', () {
      final input = ['a', 'aa', 'b'];
      input.sort(naturalCompare);
      expect(input, ['a', 'aa', 'b']);
    });

    test('purely numeric names sort by value, not by string length', () {
      final input = ['100', '20', '3'];
      input.sort(naturalCompare);
      expect(input, ['3', '20', '100']);
    });

    test('leading zeros do not change a digit run\'s numeric value', () {
      // "007" and "07" and "7" are all the numeric value 7; the exact
      // tie-break order isn't meaningful, but it must be stable/total.
      final input = ['007', '7', '07'];
      input.sort(naturalCompare);
      expect(input, ['7', '07', '007']);
    });

    test('multiple digit runs in one name are each compared numerically', () {
      final input = ['a10b10', 'a10b1', 'a10b2'];
      input.sort(naturalCompare);
      expect(input, ['a10b1', 'a10b2', 'a10b10']);
    });

    test('is stable for equal strings', () {
      expect(naturalCompare('same.txt', 'same.txt'), 0);
    });

    test('handles an empty string as always sorting first', () {
      final input = ['a', ''];
      input.sort(naturalCompare);
      expect(input, ['', 'a']);
    });

    test('mirrors the exact bug report: f1, f2, f10 not f1, f10, f2', () {
      // Sanity check against plain String.compareTo to document the bug
      // this comparator fixes: without it, "f10" sorts before "f2".
      final broken = ['f1', 'f10', 'f2']..sort((a, b) => a.compareTo(b));
      expect(broken, ['f1', 'f10', 'f2']); // the old, wrong behavior

      final fixed = ['f1', 'f10', 'f2']..sort(naturalCompare);
      expect(fixed, ['f1', 'f2', 'f10']); // the fixed, natural behavior
    });
  });
}
