import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/carousel_geometry.dart';

void main() {
  group('CarouselGeometry.visibleCenterShift', () {
    const h = 400.0;

    double shift(double top, double bottom) =>
        CarouselGeometry.visibleCenterShift(
          viewportHeight: h,
          sceneTop: top,
          sceneBottom: bottom,
        );

    test('is zero at 1x', () {
      expect(shift(0, 400), 0);
    });

    test('zoomed in 2x on the top half: visible middle is above centre', () {
      expect(shift(0, 200), -100);
    });

    test('zoomed in 2x on the bottom half: visible middle is below centre', () {
      expect(shift(200, 400), 100);
    });

    test('zoomed in 2x on the middle: no shift', () {
      expect(shift(100, 300), 0);
    });

    test('zoomed out, list centred on screen: no shift', () {
      // 0.5x with the list in the middle of the screen.
      expect(shift(-200, 600), 0);
    });

    test('zoomed out, list sitting at the top or bottom: no shift', () {
      // The screen shows more than the whole list, so its middle is the
      // middle of what's visible whichever side it's pushed to.
      expect(shift(0, 800), 0);
      expect(shift(-400, 400), 0);
    });

    test('degenerate inputs return zero instead of NaN or negative ranges', () {
      expect(
        CarouselGeometry.visibleCenterShift(
          viewportHeight: 0,
          sceneTop: 0,
          sceneBottom: 0,
        ),
        0,
      );
      // Screen window entirely outside the list.
      expect(shift(500, 900), 0);
    });
  });

  group('current index while zoomed', () {
    const w = 400.0;
    const h = 400.0;

    // Four square items, each exactly one viewport tall, so item i starts at
    // list offset 400 * i and has no padding.
    final geometry = CarouselGeometry(
      playlist: const ['a.png', 'b.png', 'c.png', 'd.png'],
      rotations: const {},
      isAudio: (_) => false,
      aspectRatioFor: (_) => 1.0,
    );

    test('without a shift the centre of the viewport decides', () {
      // Sanity check of the layout the cases below rely on.
      expect(geometry.itemHeight(0, w, h), 400);
      expect(geometry.indexForOffset(400, w, h), 1);
      expect(geometry.indexForOffset(650, w, h), 2);
    });

    test(
      'zoomed on the top of the viewport, the item on screen wins, not the '
      'item at the viewport centre',
      () {
        // List scrolled to 650, zoomed 2x onto the top half of the viewport:
        // the screen shows list offsets 650..850, i.e. mostly item b.
        const offset = 650.0;
        final shift = CarouselGeometry.visibleCenterShift(
          viewportHeight: h,
          sceneTop: 0,
          sceneBottom: 200,
        );

        expect(geometry.indexForOffset(offset, w, h), 2); // what used to happen
        expect(geometry.indexForOffset(offset + shift, w, h), 1);
      },
    );

    test('zoomed on the bottom of the viewport, the lower item wins', () {
      final shift = CarouselGeometry.visibleCenterShift(
        viewportHeight: h,
        sceneTop: 200,
        sceneBottom: 400,
      );
      expect(shift, 100);

      // Scrolled to 350: the screen shows list offsets 550..750, all of it
      // inside item b (400..800).
      expect(geometry.indexForOffset(350 + shift, w, h), 1);
      // Scrolled to 650: the screen shows 850..1050, all of it inside item c
      // (800..1200).
      expect(geometry.indexForOffset(650 + shift, w, h), 2);
    });
  });
}
