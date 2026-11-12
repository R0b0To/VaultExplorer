import 'package:flutter_test/flutter_test.dart';

void main() {
  test('precision math verification', () {
    const double itemExtent = 420.43793279060685;
    const double scrollExtent = 17143356.70955434;
    const double precisionErrorTolerance = 1e-10;

    final double count = scrollExtent / itemExtent;
    final double diff = (count.roundToDouble() - count).abs();

    expect(diff, greaterThan(precisionErrorTolerance));
    expect(diff * itemExtent, greaterThan(precisionErrorTolerance));

    // With integer itemExtent (e.g. floorToDouble())
    final double fixedItemExtent = itemExtent.floorToDouble(); // 420.0
    final double fixedScrollExtent = 40775 * fixedItemExtent; // 17125500.0
    final double fixedCount = fixedScrollExtent / fixedItemExtent;
    final double fixedDiff = (fixedCount.roundToDouble() - fixedCount).abs();

    expect(fixedDiff, equals(0.0));
    expect(fixedDiff, lessThanOrEqualTo(precisionErrorTolerance));
  });
}
