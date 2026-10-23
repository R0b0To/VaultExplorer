import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/widgets/gated_page_scroll_physics.dart';

void main() {
  group('GatedPageScrollPhysics', () {
    late PagerSwipeGate gate;
    late PageController pager;

    setUp(() {
      gate = PagerSwipeGate();
      pager = PageController();
    });

    tearDown(() {
      pager.dispose();
    });

    Widget buildPager() {
      return MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: pager,
            pageSnapping: false,
            physics: GatedPageScrollPhysics(gate: gate),
            children: const [
              Center(child: Text('first')),
              Center(child: Text('second')),
            ],
          ),
        ),
      );
    }

    testWidgets('an open gate swipes between pages like a normal pager', (
      tester,
    ) async {
      await tester.pumpWidget(buildPager());

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(1.0, 0.001));
    });

    testWidgets('an open gate still snaps a slow drag to the nearest page', (
      tester,
    ) async {
      await tester.pumpWidget(buildPager());

      // Past halfway, let go without any speed.
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(1.0, 0.001));
    });

    testWidgets('a locked gate stops a fling from changing the page', (
      tester,
    ) async {
      await tester.pumpWidget(buildPager());
      gate.locked = true;

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(0.0, 0.001));
    });

    testWidgets('a locked gate stops a long drag from moving the pager', (
      tester,
    ) async {
      await tester.pumpWidget(buildPager());
      gate.locked = true;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      // Nothing followed the finger while it was down.
      expect(pager.page, closeTo(0.0, 0.001));

      await gesture.moveBy(const Offset(-300, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(0.0, 0.001));
    });

    testWidgets('unlocking the gate makes the next swipe work again', (
      tester,
    ) async {
      await tester.pumpWidget(buildPager());
      gate.locked = true;
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(pager.page, closeTo(0.0, 0.001));

      gate.locked = false;
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();

      expect(pager.page, closeTo(1.0, 0.001));
    });
  });
}
