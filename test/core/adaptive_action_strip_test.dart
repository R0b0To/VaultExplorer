import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/adaptive_action_strip.dart';

AdaptiveActionItem _item(Object id, {bool pinned = false, int priority = 0}) =>
    AdaptiveActionItem(
      id: id,
      builder: (_) => IconButton(
        key: ValueKey<String>('inline-$id'),
        icon: const Icon(Icons.circle),
        onPressed: () {},
      ),
      menuBuilder: pinned
          ? null
          : (_) => MenuItemButton(
              key: ValueKey<String>('menu-$id'),
              onPressed: () {},
              child: Text('item $id'),
            ),
      priority: priority,
    );

void main() {
  group('planAdaptiveActionLayout', () {
    final items = [for (var i = 0; i < 6; i++) _item(i)];

    List<int> inlineFor(double width, [List<AdaptiveActionItem>? list]) =>
        planAdaptiveActionLayout(
          items: list ?? items,
          available: width,
          itemExtent: 48,
          separatorExtent: 9,
        ).inline;

    test('shows everything when it fits', () {
      final plan = planAdaptiveActionLayout(
        items: items,
        available: 6 * 48,
        itemExtent: 48,
        separatorExtent: 9,
      );
      expect(plan.inline, [0, 1, 2, 3, 4, 5]);
      expect(plan.overflow, isEmpty);
    });

    test('collapses from the end and reserves room for the menu button', () {
      final plan = planAdaptiveActionLayout(
        items: items,
        available: 4 * 48,
        itemExtent: 48,
        separatorExtent: 9,
      );
      // Three inline plus the overflow button fill four slots.
      expect(plan.inline, [0, 1, 2]);
      expect(plan.overflow, [3, 4, 5]);
    });

    test('never collapses a single action on its own', () {
      for (var slots = 1; slots < 6; slots++) {
        final plan = planAdaptiveActionLayout(
          items: items,
          available: slots * 48.0,
          itemExtent: 48,
          separatorExtent: 9,
        );
        expect(plan.overflow.length == 1, isFalse, reason: 'slots=$slots');
      }
    });

    test('pinned items stay inline however narrow it gets', () {
      final mixed = [
        _item('add', pinned: true),
        _item('a'),
        _item('b'),
        _item('c'),
      ];
      final plan = planAdaptiveActionLayout(
        items: mixed,
        available: 48,
        itemExtent: 48,
        separatorExtent: 9,
      );
      expect(plan.inline, [0]);
      expect(plan.overflow, [1, 2, 3]);
    });

    test('lower priority collapses first, ties collapse from the end', () {
      final prioritized = [
        _item('x', priority: 1),
        _item('y', priority: 2),
        _item('z', priority: 1),
        _item('w', priority: 2),
      ];
      final plan = planAdaptiveActionLayout(
        items: prioritized,
        available: 3 * 48,
        itemExtent: 48,
        separatorExtent: 9,
      );
      // Two slots of actions plus the button: x and z (priority 1) go.
      expect(plan.inline, [1, 3]);
      expect(plan.overflow, [0, 2]);
    });

    test('drops a separator whose group collapsed away', () {
      final grouped = [
        _item('a', priority: 2),
        _item('b', priority: 2),
        const AdaptiveActionItem.separator(id: 'sep'),
        _item('c', priority: 1),
        _item('d', priority: 1),
      ];
      final plan = planAdaptiveActionLayout(
        items: grouped,
        available: 3 * 48,
        itemExtent: 48,
        separatorExtent: 9,
      );
      expect(plan.inline, [0, 1]);
      expect(plan.overflow, [3, 4]);
      expect(inlineFor(10000, grouped), [0, 1, 2, 3, 4]);
    });
  });

  group('AdaptiveActionStrip', () {
    Future<void> pumpStrip(WidgetTester tester, double width) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AdaptiveActionStrip(
                  items: [for (var i = 0; i < 6; i++) _item(i)],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('wide: every action inline, no menu button', (tester) async {
      await pumpStrip(tester, 400);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey<String>('inline-$i')), findsOneWidget);
      }
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    });

    testWidgets('narrow: extra actions move into the menu', (tester) async {
      await pumpStrip(tester, 4 * 48);
      expect(find.byKey(const ValueKey<String>('inline-2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('inline-3')), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      for (final i in [3, 4, 5]) {
        expect(find.byKey(ValueKey<String>('menu-$i')), findsOneWidget);
      }
    });

    testWidgets('resizing back brings the actions inline again', (
      tester,
    ) async {
      await pumpStrip(tester, 4 * 48);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      await pumpStrip(tester, 400);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byKey(const ValueKey<String>('inline-5')), findsOneWidget);
    });
  });
}
