import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';

void main() {
  group('formatBytes', () {
    test('delegates to the same table as FileSize.formatted', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(5 * 1024 * 1024), '5 MB');
    });
  });

  group('formatEntryDate', () {
    test('0 (unknown timestamp) formats as an em dash', () {
      expect(formatEntryDate(0), '—');
    });

    test('a negative timestamp also formats as an em dash', () {
      expect(formatEntryDate(-1), '—');
    });

    test('a timestamp from earlier today formats as zero-padded HH:MM', () {
      final now = DateTime.now();
      // A time earlier today, far enough back to be stable regardless of
      // when exactly this test runs, but never crossing midnight.
      final earlierToday = DateTime(now.year, now.month, now.day, 1, 5);
      final secs = earlierToday.millisecondsSinceEpoch ~/ 1000;

      expect(formatEntryDate(secs), '01:05');
    });

    test('a date in the same year but not today formats as "Mon D"', () {
      final now = DateTime.now();
      // Pick a day 40 days away that is guaranteed to still fall in the
      // current year: since a year is far longer than 80 days, at least
      // one of "40 days ago" / "40 days from now" must stay within it.
      var target = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 40));
      if (target.year != now.year) {
        target = DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 40));
      }
      final secs = target.millisecondsSinceEpoch ~/ 1000;

      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
      ];
      final expected = '${months[target.month - 1]} ${target.day}';

      expect(formatEntryDate(secs), expected);
    });

    test('a date in a previous year includes the year', () {
      final now = DateTime.now();
      final target = DateTime(now.year - 1, 6, 15);
      final secs = target.millisecondsSinceEpoch ~/ 1000;

      expect(formatEntryDate(secs), 'Jun 15, ${now.year - 1}');
    });
  });
}