import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_swipe_claim.dart';

/// A three-page pager whose pages are built like the viewer's: a zoom viewer
/// with the claim layer stacked on top of it.
///
/// [touchSlop] sets the device's touch slop the way a platform reports it. A
/// real Android phone reports about 8 px, which halves every threshold the
/// pager, the taps and the zoom viewer use; null leaves Flutter's fallback.
class _Pager {
  _Pager({
    this.axis = Axis.horizontal,
    this.withClaim = true,
    this.touchSlop,
  });

  final Axis axis;
  final bool withClaim;
  final double? touchSlop;
  final controller = PageController();
  bool swipeAllowed = true;

  late final drag = PlaylistSwipeDrag(
    positionOf: () => controller.hasClients ? controller.position : null,
    canClaim: () => swipeAllowed,
  );

  Widget _page(int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          panEnabled: false,
          child: SizedBox.expand(child: Center(child: Text('page $index'))),
        ),
        if (withClaim) const Positioned.fill(child: PlaylistSwipeClaimLayer()),
      ],
    );
  }

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final Widget pager = PlaylistSwipeScope(
              drag: drag,
              axis: axis,
              enabled: true,
              child: PageView(
                controller: controller,
                scrollDirection: axis,
                physics: const BouncingScrollPhysics(),
                children: [for (var i = 0; i < 3; i++) _page(i)],
              ),
            );
            final slop = touchSlop;
            if (slop == null) return pager;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(gestureSettings: DeviceGestureSettings(touchSlop: slop)),
              child: pager,
            );
          },
        ),
      ),
    );
  }
}

/// Moves a finger by [total] in small steps, as a real touch reports it. A
/// single huge jump would let the zoom viewer's deeper recognizer win on the
/// very event that crosses its distance, which no finger does.
Future<void> _moveInSteps(
  TestGesture gesture,
  Offset total, {
  double step = 4.0,
}) async {
  final steps = (total.distance / step).ceil();
  final each = total / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(each);
  }
}

void main() {
  group('playlistSwipeDirection', () {
    test('a plain swipe along the axis points to the next or previous item', () {
      expect(
        playlistSwipeDirection(const Offset(-120, 0), AxisDirection.right),
        1,
      );
      expect(
        playlistSwipeDirection(const Offset(120, 0), AxisDirection.right),
        -1,
      );
    });

    test('a short swipe that slopes up to a diagonal still counts', () {
      expect(
        playlistSwipeDirection(const Offset(-36, 30), AxisDirection.right),
        1,
      );
      expect(
        playlistSwipeDirection(const Offset(-40, -40), AxisDirection.right),
        1,
      );
    });

    test('too little travel along the axis is not a swipe', () {
      expect(
        playlistSwipeDirection(const Offset(-24, 0), AxisDirection.right),
        0,
      );
      expect(
        playlistSwipeDirection(const Offset(-31.9, 4), AxisDirection.right),
        0,
      );
    });

    test('a movement that points mostly across the axis is not a swipe', () {
      expect(
        playlistSwipeDirection(const Offset(-40, 100), AxisDirection.right),
        0,
      );
    });

    test('right-to-left and vertical pagers read their own axis', () {
      expect(
        playlistSwipeDirection(const Offset(40, 0), AxisDirection.left),
        1,
      );
      expect(
        playlistSwipeDirection(const Offset(8, -50), AxisDirection.down),
        1,
      );
      expect(
        playlistSwipeDirection(const Offset(-120, 10), AxisDirection.down),
        0,
      );
    });

    test('the distance and the slope limit can be tightened', () {
      const swipe = Offset(-40, 40);
      expect(playlistSwipeDirection(swipe, AxisDirection.right), 1);
      expect(
        playlistSwipeDirection(swipe, AxisDirection.right, maxCrossRatio: 0.5),
        0,
      );
      expect(
        playlistSwipeDirection(swipe, AxisDirection.right, minDistance: 80),
        0,
      );
    });
  });

  defineClaimTests(null);
  defineClaimTests(8.0);
}

/// The scenarios that matter for a swipe claimed for the pager, at one device
/// touch slop. Both slops are exercised because the claim has to win against
/// the zoom viewer at either: the viewer accepts at twice the slop.
void defineClaimTests(double? touchSlop) {
  final slopName = touchSlop == null
      ? 'the fallback touch slop'
      : 'a touch slop of ${touchSlop.toStringAsFixed(0)} px';
  group('a swipe claimed for the pager, with $slopName', () {
    testWidgets(
      'without the claim layer the zoom viewer swallows an L-shaped swipe',
      (tester) async {
        final pager = _Pager(withClaim: false, touchSlop: touchSlop);
        addTearDown(pager.controller.dispose);
        await tester.pumpWidget(pager.build());

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        await _moveInSteps(gesture, const Offset(0, 60));
        await _moveInSteps(gesture, const Offset(-500, 0));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(pager.controller.page, closeTo(0.0, 0.001));
      },
    );

    testWidgets('an L-shaped swipe drags the page along with the finger', (
      tester,
    ) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      // Down first, then across.
      await _moveInSteps(gesture, const Offset(0, 60));
      await _moveInSteps(gesture, const Offset(-500, 0));

      // The page is following the finger, 500 px of an 800 px page.
      expect(pager.controller.page, closeTo(0.625, 0.03));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pager.controller.page, closeTo(1.0, 0.001));
    });

    testWidgets('a curved swipe that starts steeply drags and commits', (
      tester,
    ) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      // Starts mostly downward, then bends toward the paging axis.
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-2, 6));
      }
      for (var i = 0; i < 100; i++) {
        await gesture.moveBy(const Offset(-5, 2));
      }
      expect(pager.controller.page, greaterThan(0.5));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pager.controller.page, closeTo(1.0, 0.001));
    });

    testWidgets('a short drag is cancelled and the page snaps back', (
      tester,
    ) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await _moveInSteps(gesture, const Offset(0, 60));
      await _moveInSteps(gesture, const Offset(-200, 0));
      expect(pager.controller.page, greaterThan(0.2));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pager.controller.page, closeTo(0.0, 0.001));
    });

    testWidgets('dragging back before letting go cancels the swipe', (
      tester,
    ) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await _moveInSteps(gesture, const Offset(0, 60));
      await _moveInSteps(gesture, const Offset(-400, 0));
      expect(pager.controller.page, greaterThan(0.4));
      await _moveInSteps(gesture, const Offset(300, 0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pager.controller.page, closeTo(0.0, 0.001));
    });

    testWidgets('a straight swipe still works as before', (tester) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await _moveInSteps(gesture, const Offset(-500, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pager.controller.page, closeTo(1.0, 0.001));
    });

    testWidgets('a purely vertical drag leaves the page where it is', (
      tester,
    ) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await _moveInSteps(gesture, const Offset(0, 120));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pager.controller.page, closeTo(0.0, 0.001));
    });

    testWidgets('a vertical pager follows an L-shaped swipe the other way', (
      tester,
    ) async {
      final pager = _Pager(axis: Axis.vertical, touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      // Across first, then up: 450 px of a 600 px page.
      await _moveInSteps(gesture, const Offset(-60, 0));
      await _moveInSteps(gesture, const Offset(0, -450));
      expect(pager.controller.page, closeTo(0.75, 0.03));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pager.controller.page, closeTo(1.0, 0.001));
    });

    testWidgets('locking swipes mid-drag cancels the drag', (tester) async {
      final pager = _Pager(touchSlop: touchSlop);
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await _moveInSteps(gesture, const Offset(0, 60));
      await _moveInSteps(gesture, const Offset(-300, 0));
      expect(pager.controller.page, greaterThan(0.3));

      // A second finger lands, a brightness drag starts, a zoom begins, ...
      pager.swipeAllowed = false;
      await gesture.moveBy(const Offset(-4, 0));
      await tester.pumpAndSettle();

      // The page has already settled back, with the finger still down.
      expect(pager.controller.page, closeTo(0.0, 0.001));
      await gesture.up();
    });

    testWidgets('nothing is claimed while swipes are locked', (tester) async {
      final pager = _Pager(touchSlop: touchSlop)..swipeAllowed = false;
      addTearDown(pager.controller.dispose);
      await tester.pumpWidget(pager.build());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await _moveInSteps(gesture, const Offset(0, 60));
      await _moveInSteps(gesture, const Offset(-500, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pager.controller.page, closeTo(0.0, 0.001));
    });

    testWidgets('the layer builds nothing outside a scope', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [Positioned.fill(child: PlaylistSwipeClaimLayer())],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(RawGestureDetector), findsNothing);
    });
  });
}
