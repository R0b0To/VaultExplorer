import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_edit_logic.dart';

void main() {
  group('mergeKeywords', () {
    test('adds and removes without regard to case', () {
      expect(mergeKeywords(['Sun', 'sea'], ['SEA', 'Sand'], ['sun']), ['sea', 'Sand']);
    });

    test('trims and drops duplicates', () {
      expect(mergeKeywords([], ['a', ' a ', 'b'], []), ['a', 'b']);
    });
  });

  group('dateFromFileName', () {
    test('reads camera and messenger stamps', () {
      final want = DateTime.utc(2023, 7, 14, 18, 32, 5);
      expect(dateFromFileName('IMG_20230714_183205.jpg'), want);
      expect(dateFromFileName('2023-07-14 18.32.05.png'), want);
      expect(dateFromFileName('PXL_20230714_183205123.jpg'), want);
    });

    test('a name with only a date gives midnight', () {
      expect(dateFromFileName('IMG-20230714-WA0001.jpg'), DateTime.utc(2023, 7, 14));
    });

    test('rejects names without a plausible date', () {
      expect(dateFromFileName('holiday.jpg'), isNull);
      expect(dateFromFileName('IMG_20231345_183205.jpg'), isNull);
      expect(dateFromFileName('1234567890123.jpg'), isNull);
    });
  });

  group('wall clock helpers', () {
    test('shift crosses a year boundary', () {
      expect(
        shiftWallClock(DateTime.utc(2020, 12, 31, 23), const Duration(hours: 2)),
        DateTime.utc(2021, 1, 1, 1),
      );
    });

    test('epoch conversion round-trips', () {
      final w = DateTime.utc(2022, 6, 1, 10, 20, 30);
      expect(wallClockOfEpochSecs(epochSecsOfWallClock(w)), w);
    });
  });
}
