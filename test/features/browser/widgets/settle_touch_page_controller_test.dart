import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/widgets/settle_touch_page_controller.dart';

void main() {
  group('SettleTouchPageController', () {
    /// Flings the pager from the first page to the second, then drags the
    /// second page's list upwards while the pager is still settling. Returns
    /// how far that list scrolled.
    Future<double> scrollListWhileSettling(
      WidgetTester tester,
      PageController pager,
    ) async {
      final list = ScrollController();
      addTearDown(list.dispose);
      addTearDown(pager.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pager,
              children: [
                const SizedBox.expand(),
                ListView.builder(
                  controller: list,
                  itemCount: 200,
                  itemExtent: 50,
                  itemBuilder: (context, index) => Text('Item $index'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      // The first frame only starts the settle; the second one moves it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Precondition: the swipe is over, but the pager has not come to rest.
      expect(pager.position.isScrollingNotifier.value, isTrue);
      expect(pager.page, allOf(greaterThan(0.5), lessThan(1.0)));

      await tester.drag(
        find.byType(ListView),
        const Offset(0, -300),
        warnIfMissed: false,
      );
      final scrolled = list.offset;

      await tester.pumpAndSettle();
      return scrolled;
    }

    testWidgets('a vertical drag during the settle scrolls the page', (
      tester,
    ) async {
      final pager = SettleTouchPageController();

      final scrolled = await scrollListWhileSettling(tester, pager);

      expect(scrolled, greaterThan(100));
      // The touch did not cost the swipe: the pager still ends on the new page.
      expect(pager.page, closeTo(1.0, 0.001));
    });

    testWidgets('a stock PageController ignores that drag', (tester) async {
      // Documents the framework behaviour this controller exists to work
      // around. If this starts failing, Flutter no longer mutes a settling
      // pager's pages and the controller is not needed any more.
      final pager = PageController();

      final scrolled = await scrollListWhileSettling(tester, pager);

      expect(scrolled, 0.0);
    });
  });
}
