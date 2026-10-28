import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_swipe_physics.dart';

/// Metrics of a three-page pager (800 px per page) resting at [pixels].
ScrollMetrics _metrics({
  required double pixels,
  AxisDirection axisDirection = AxisDirection.right,
}) {
  return FixedScrollMetrics(
    minScrollExtent: 0.0,
    maxScrollExtent: 1600.0,
    pixels: pixels,
    viewportDimension: 800.0,
    axisDirection: axisDirection,
    devicePixelRatio: 1.0,
  );
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

    test('only the net movement counts, not the path taken', () {
      // A finger that went out 60 px, then hooked back 18 and down 24, has
      // the same net movement as one short diagonal stroke.
      const net = Offset(-42.0, 24.0);
      expect(playlistSwipeDirection(net, AxisDirection.right), 1);
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
      expect(
        playlistSwipeDirection(const Offset(-40, -90), AxisDirection.right),
        0,
      );
    });

    test('right-to-left pagers read the direction the other way round', () {
      expect(
        playlistSwipeDirection(const Offset(40, 0), AxisDirection.left),
        1,
      );
      expect(
        playlistSwipeDirection(const Offset(-40, 0), AxisDirection.left),
        -1,
      );
    });

    test('vertical pagers use the vertical movement', () {
      expect(
        playlistSwipeDirection(const Offset(8, -50), AxisDirection.down),
        1,
      );
      expect(
        playlistSwipeDirection(const Offset(8, 50), AxisDirection.down),
        -1,
      );
      // A sideways movement is across a vertical pager's axis.
      expect(
        playlistSwipeDirection(const Offset(-120, 10), AxisDirection.down),
        0,
      );
    });

    test('the distance and the slope limit can be tightened', () {
      const swipe = Offset(-40, 40);
      expect(playlistSwipeDirection(swipe, AxisDirection.right), 1);
      expect(
        playlistSwipeDirection(
          swipe,
          AxisDirection.right,
          maxCrossRatio: 0.5,
        ),
        0,
      );
      expect(
        playlistSwipeDirection(
          swipe,
          AxisDirection.right,
          minDistance: 80,
        ),
        0,
      );
    });
  });

  group('PlaylistSwipeTracker', () {
    test('hands over the finished touch once, with its start page', () {
      final tracker = PlaylistSwipeTracker();
      tracker.begin(const Offset(400, 300), 2);
      tracker.release(const Offset(360, 330));

      final summary = tracker.take();
      expect(summary, isNotNull);
      expect(summary!.delta, const Offset(-40, 30));
      expect(summary.startPage, 2);
      expect(tracker.take(), isNull);
    });

    test('a release with no touch-down is ignored', () {
      final tracker = PlaylistSwipeTracker();
      tracker.release(const Offset(10, 10));
      expect(tracker.take(), isNull);
    });

    test('a cancelled touch leaves nothing behind', () {
      final tracker = PlaylistSwipeTracker();
      tracker.begin(const Offset(400, 300), 0);
      tracker.cancel();
      tracker.release(const Offset(300, 300));
      expect(tracker.take(), isNull);

      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(300, 300));
      tracker.cancel();
      expect(tracker.take(), isNull);
    });

    test('a new touch-down discards a summary nobody took', () {
      final tracker = PlaylistSwipeTracker();
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(300, 300));
      tracker.begin(const Offset(10, 10), 1);
      expect(tracker.take(), isNull);
    });

    test('a summary does not outlive the event it was recorded in', () async {
      final tracker = PlaylistSwipeTracker();
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(300, 300));

      await Future<void>.delayed(Duration.zero);

      expect(tracker.take(), isNull);
    });
  });

  group('PlaylistSwipePageScrollPhysics', () {
    late PlaylistSwipeTracker tracker;
    late PlaylistSwipePageScrollPhysics physics;

    setUp(() {
      tracker = PlaylistSwipeTracker();
      physics = PlaylistSwipePageScrollPhysics(
        parent: const BouncingScrollPhysics(),
        tracker: tracker,
      );
    });

    /// Where the page settles, in scroll pixels, or null for no movement.
    double? settlesAt(ScrollMetrics metrics, double velocity) =>
        physics.createBallisticSimulation(metrics, velocity)?.x(10.0);

    test('a short diagonal swipe goes on to the next page', () {
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(364, 330));

      expect(settlesAt(_metrics(pixels: 15), 0.0), closeTo(800.0, 0.01));
    });

    test('a short diagonal swipe goes back to the previous page', () {
      tracker.begin(const Offset(400, 300), 1);
      tracker.release(const Offset(440, 320));

      expect(settlesAt(_metrics(pixels: 785), 0.0), closeTo(0.0, 0.01));
    });

    test('without a recorded touch the stock page physics decide', () {
      expect(settlesAt(_metrics(pixels: 15), 0.0), closeTo(0.0, 0.01));
    });

    test('a swipe that is too short or too steep leaves the page alone', () {
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(376, 300));
      expect(settlesAt(_metrics(pixels: 6), 0.0), closeTo(0.0, 0.01));

      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(360, 400));
      expect(settlesAt(_metrics(pixels: 20), 0.0), closeTo(0.0, 0.01));
    });

    test('a hard throw back against the swipe cancels it', () {
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(364, 300));

      expect(settlesAt(_metrics(pixels: 15), -800.0), closeTo(0.0, 0.01));
    });

    test('a gentle backward tail does not cancel a curved swipe', () {
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(364, 300));

      expect(settlesAt(_metrics(pixels: 15), -100.0), closeTo(800.0, 0.01));
    });

    test('a swipe that already went further is not cut short', () {
      // Dragged to the middle of the second page and thrown forward: the stock
      // physics carry it on to the third page, and so do these.
      tracker.begin(const Offset(700, 300), 0);
      tracker.release(const Offset(0, 300));

      expect(settlesAt(_metrics(pixels: 1200), 1000.0), closeTo(1600.0, 0.01));
    });

    test('there is no page past the last one to swipe to', () {
      tracker.begin(const Offset(400, 300), 2);
      tracker.release(const Offset(360, 300));

      expect(settlesAt(_metrics(pixels: 1590), 0.0), closeTo(1600.0, 0.01));
    });

    test('reads right-to-left and vertical pagers by their own axis', () {
      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(440, 300));
      expect(
        settlesAt(
          _metrics(pixels: 15, axisDirection: AxisDirection.left),
          0.0,
        ),
        closeTo(800.0, 0.01),
      );

      tracker.begin(const Offset(400, 300), 0);
      tracker.release(const Offset(396, 260));
      expect(
        settlesAt(
          _metrics(pixels: 15, axisDirection: AxisDirection.down),
          0.0,
        ),
        closeTo(800.0, 0.01),
      );
    });

    test('keeps its tracker when applied on top of another physics', () {
      final applied = physics.applyTo(const ClampingScrollPhysics());
      expect(applied.tracker, same(tracker));
    });
  });

  group('in a PageView', () {
    late PlaylistSwipeTracker tracker;
    late PageController pager;

    setUp(() {
      tracker = PlaylistSwipeTracker();
      pager = PageController();
    });

    tearDown(() {
      pager.dispose();
    });

    List<Widget> pages() => const [
      Center(child: Text('first')),
      Center(child: Text('second')),
      Center(child: Text('third')),
    ];

    /// The pager as the viewer builds it: a raw pointer [Listener] feeds the
    /// tracker, and the pager uses the overall-movement physics.
    Widget buildSwipePager() {
      return MaterialApp(
        home: Scaffold(
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) =>
                tracker.begin(event.position, pager.page!.round()),
            onPointerUp: (event) => tracker.release(event.position),
            onPointerCancel: (_) => tracker.cancel(),
            child: PageView(
              controller: pager,
              pageSnapping: false,
              physics: PlaylistSwipePageScrollPhysics(
                parent: const BouncingScrollPhysics(),
                tracker: tracker,
              ),
              children: pages(),
            ),
          ),
        ),
      );
    }

    testWidgets('the stock pager snaps a short diagonal swipe back', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pager,
              physics: const BouncingScrollPhysics(),
              children: pages(),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(PageView), const Offset(-36, 30));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(0.0, 0.001));
    });

    testWidgets('a short diagonal swipe changes to the next page', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipePager());

      await tester.drag(find.byType(PageView), const Offset(-36, 30));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(1.0, 0.001));
    });

    testWidgets('a short diagonal swipe changes back to the previous page', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipePager());
      pager.jumpToPage(1);
      await tester.pump();

      await tester.drag(find.byType(PageView), const Offset(40, 20));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(0.0, 0.001));
    });

    testWidgets('a curved swipe is judged by where it ended up', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipePager());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-30, 0));
      // The finger hooks back and down before lifting.
      await gesture.moveBy(const Offset(18, 24));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(1.0, 0.001));
    });

    testWidgets('a nudge that is too short does not change the page', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipePager());

      await tester.drag(find.byType(PageView), const Offset(-24, 0));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(0.0, 0.001));
    });

    testWidgets('a mostly vertical drag does not change the page', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipePager());

      await tester.drag(find.byType(PageView), const Offset(-40, 100));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(0.0, 0.001));
    });

    testWidgets('a swipe on the last page settles back on it', (tester) async {
      await tester.pumpWidget(buildSwipePager());
      pager.jumpToPage(2);
      await tester.pump();

      await tester.drag(find.byType(PageView), const Offset(-40, 10));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(2.0, 0.001));
    });

    testWidgets('a long swipe and a fling still work as before', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipePager());

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(pager.page, closeTo(1.0, 0.001));

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(pager.page, closeTo(2.0, 0.001));
    });
  });
}
