import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/grid_corner_style.dart';

void main() {
  group('GridCornerStyle', () {
    test('rounded keeps the original 12px radius, square is 0', () {
      expect(GridCornerStyle.rounded.radius, 12.0);
      expect(GridCornerStyle.square.radius, 0.0);
    });

    test('JSON round-trips every value', () {
      for (final style in GridCornerStyle.values) {
        expect(GridCornerStyle.fromJson(style.toJson()), style);
      }
    });

    test('unknown or missing JSON falls back to rounded', () {
      expect(GridCornerStyle.fromJson(null), GridCornerStyle.rounded);
      expect(GridCornerStyle.fromJson('hexagon'), GridCornerStyle.rounded);
    });
  });
}
