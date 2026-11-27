import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_tear_off_zone.dart';

void main() {
  // A 32 px strip at the top of a 1000 px wide window.
  bool torn(double x, double y, {bool was = false}) => TabTearOffZone.isTornOut(
    pointerX: x,
    pointerY: y,
    stripTop: 0,
    stripBottom: 32,
    windowWidth: 1000,
    wasTornOut: was,
  );

  group('TabTearOffZone', () {
    test('a pointer inside the strip is not pulled out', () {
      expect(torn(500, 16), isFalse);
      expect(torn(0, 0), isFalse);
      expect(torn(1000, 32), isFalse);
    });

    test('sideways and vertical wobble of a reorder stays in', () {
      expect(torn(500, 32 + 27), isFalse);
      expect(torn(-27, 16), isFalse);
      expect(torn(1000 + 27, 16), isFalse);
    });

    test('pulling down past the margin tears the tab out', () {
      expect(torn(500, 32 + 29), isTrue);
      expect(torn(500, 400), isTrue);
    });

    test('pulling up above the window tears the tab out', () {
      expect(torn(500, -29), isTrue);
    });

    test('leaving through either side of the window tears the tab out', () {
      expect(torn(-29, 16), isTrue);
      expect(torn(1000 + 29, 16), isTrue);
    });

    test('a held-out tab needs to come back further to rejoin the strip', () {
      // 32 + 22 is inside the margin when entering, but not when already out.
      expect(torn(500, 32 + 22), isFalse);
      expect(torn(500, 32 + 22, was: true), isTrue);
      expect(torn(500, 32 + 19, was: true), isFalse);
    });
  });
}
