import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_to_dismiss_layer.dart';

const _contentKey = ValueKey<String>('dismiss-content');

class _Harness {
  int dismissed = 0;
  bool canStart = true;
  bool enabled = true;
  Axis axis = Axis.vertical;
  bool bothDirections = false;
  final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  Widget build({Widget? child}) {
    return MaterialApp(
      home: Scaffold(
        body: MediaSwipeDismissLayer(
          enabled: enabled,
          axis: axis,
          bothDirections: bothDirections,
          canStart: () => canStart,
          onDismiss: () => dismissed++,
          progress: progress,
          // The production viewer content has its own gesture recognizers
          // (zoom, paging, seek). Keep one in the harness so Flutter does not
          // give the dismiss recognizer the arena on pointer-down, before it
          // can tell a tap from a drag.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child:
                child ??
                const SizedBox.expand(
                  key: _contentKey,
                  child: ColoredBox(color: Colors.red),
                ),
          ),
        ),
      ),
    );
  }
}

/// onDismiss in these tests does not pop anything, so after a dismissal the
/// layer's "the pop was swallowed" fallback brings the content back. Letting
/// that timer run keeps the test from ending with a pending timer.
Future<void> _letDismissalSettle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('vertical axis (swipe down)', () {
    testWidgets('a long drag down dismisses once', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());

      await tester.drag(find.byKey(_contentKey), const Offset(0, 300));
      await tester.pump();
      expect(h.dismissed, 1);

      await _letDismissalSettle(tester);
      expect(h.dismissed, 1);
    });

    testWidgets('a short, slow drag springs back without dismissing', (
      tester,
    ) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());
      final start = tester.getTopLeft(find.byKey(_contentKey));

      await tester.drag(find.byKey(_contentKey), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
      expect(tester.getTopLeft(find.byKey(_contentKey)), start);
      expect(h.progress.value, 0.0);
    });

    testWidgets('a short but fast flick dismisses', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());

      await tester.fling(find.byKey(_contentKey), const Offset(0, 100), 2500);
      await tester.pump();
      expect(h.dismissed, 1);
      await _letDismissalSettle(tester);
    });

    testWidgets('dragging up does nothing in one-way mode', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());
      final start = tester.getTopLeft(find.byKey(_contentKey));

      await tester.drag(find.byKey(_contentKey), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
      expect(tester.getTopLeft(find.byKey(_contentKey)), start);
    });

    testWidgets('a sideways drag is not a dismiss', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());

      await tester.drag(find.byKey(_contentKey), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
    });

    testWidgets('the content follows the finger and progress is reported', (
      tester,
    ) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());
      final start = tester.getTopLeft(find.byKey(_contentKey));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_contentKey)),
      );
      // The fade reaches full progress at 10% of the viewport; stay below the
      // 20% dismissal threshold so this remains a follow-the-finger check.
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();

      expect(tester.getTopLeft(find.byKey(_contentKey)).dy, greaterThan(start.dy));
      expect(h.progress.value, greaterThan(0.0));
      expect(h.progress.value, lessThanOrEqualTo(1.0));
      expect(h.dismissed, 0);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a plain tap neither dismisses nor eats the child\'s tap', (
      tester,
    ) async {
      final h = _Harness();
      var taps = 0;
      await tester.pumpWidget(
        h.build(
          child: GestureDetector(
            key: _contentKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      );

      await tester.tap(find.byKey(_contentKey));
      await tester.pump();

      expect(taps, 1);
      expect(h.dismissed, 0);
    });
  });

  group('horizontal axis (swipe sideways)', () {
    testWidgets('dismisses in both directions', (tester) async {
      for (final dx in [300.0, -300.0]) {
        final h = _Harness()
          ..axis = Axis.horizontal
          ..bothDirections = true;
        await tester.pumpWidget(h.build());

        await tester.drag(find.byKey(_contentKey), Offset(dx, 0));
        await tester.pump();
        expect(h.dismissed, 1, reason: 'drag of $dx');
        await _letDismissalSettle(tester);
      }
    });

    testWidgets('a vertical drag is not a dismiss', (tester) async {
      final h = _Harness()
        ..axis = Axis.horizontal
        ..bothDirections = true;
      await tester.pumpWidget(h.build());

      await tester.drag(find.byKey(_contentKey), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
    });
  });

  group('gating', () {
    testWidgets('does nothing when disabled', (tester) async {
      final h = _Harness()..enabled = false;
      await tester.pumpWidget(h.build());

      await tester.drag(find.byKey(_contentKey), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
    });

    testWidgets('does nothing while canStart says no (zoomed, pinching, ...)', (
      tester,
    ) async {
      final h = _Harness()..canStart = false;
      await tester.pumpWidget(h.build());

      await tester.drag(find.byKey(_contentKey), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
    });

    testWidgets('a second finger turns the drag into a cancel', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());
      final center = tester.getCenter(find.byKey(_contentKey));

      final first = await tester.startGesture(center, pointer: 1);
      await first.moveBy(const Offset(0, 30));
      await first.moveBy(const Offset(0, 200));
      await tester.pump();

      final second = await tester.startGesture(
        center + const Offset(120, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
    });

    testWidgets('turning the option off mid-drag puts the content back', (
      tester,
    ) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());
      final start = tester.getTopLeft(find.byKey(_contentKey));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_contentKey)),
      );
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();

      h.enabled = false;
      await tester.pumpWidget(h.build());
      await gesture.up();
      await tester.pumpAndSettle();

      expect(h.dismissed, 0);
      expect(tester.getTopLeft(find.byKey(_contentKey)), start);
    });
  });

  group('next to a horizontal PageView (the playlist pager)', () {
    testWidgets('sideways drags still page, downward drags dismiss', (
      tester,
    ) async {
      final h = _Harness();
      final pages = PageController();
      addTearDown(pages.dispose);
      await tester.pumpWidget(
        h.build(
          child: PageView(
            key: _contentKey,
            controller: pages,
            children: const [
              ColoredBox(color: Colors.red),
              ColoredBox(color: Colors.blue),
            ],
          ),
        ),
      );

      await tester.drag(find.byKey(_contentKey), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(pages.page, 1.0);
      expect(h.dismissed, 0);

      await tester.drag(find.byKey(_contentKey), const Offset(0, 300));
      await tester.pump();
      expect(h.dismissed, 1);
      expect(pages.page, 1.0);
      await _letDismissalSettle(tester);
    });
  });
}
