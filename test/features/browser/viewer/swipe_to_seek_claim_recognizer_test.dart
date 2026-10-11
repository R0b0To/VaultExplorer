import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_to_seek_claim_recognizer.dart';

class _Harness {
  final pageController = PageController();
  final Axis scrollDirection;
  int rawStripMoves = 0;
  int taps = 0;
  SwipeToSeekClaimRecognizer? recognizer;
  bool claimAllowed = true;

  _Harness({this.scrollDirection = Axis.horizontal});

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: PageView(
          controller: pageController,
          scrollDirection: scrollDirection,
          children: [
            Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => taps++,
                  ),
                ),
                Positioned.fill(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    gestures: <Type, GestureRecognizerFactory>{
                      SwipeToSeekClaimRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            SwipeToSeekClaimRecognizer
                          >(() {
                            recognizer = SwipeToSeekClaimRecognizer(
                              canClaim: () => claimAllowed,
                            );
                            return recognizer!;
                          }, (instance) {
                            instance.onStart = (_) {};
                          }),
                    },
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerMove: (_) => rawStripMoves++,
                    ),
                  ),
                ),
              ],
            ),
            const Scaffold(body: Center(child: Text('Page 2'))),
          ],
        ),
      ),
    );
  }
}

void main() {
  const center = Offset(200, 200);
  const dragLeft = Offset(-100, 0);

  testWidgets(
    'a horizontal drag does not change page when SwipeToSeek claims it',
    (tester) async {
      final h = _Harness();
      addTearDown(h.pageController.dispose);
      await tester.pumpWidget(h.build());

      await tester.dragFrom(center, dragLeft);
      await tester.pump();

      expect(h.rawStripMoves, greaterThan(0));
      expect(h.pageController.page, 0.0);
    },
  );

  testWidgets(
    'when canClaim is false, the PageView scrolls',
    (tester) async {
      final h = _Harness()..claimAllowed = false;
      addTearDown(h.pageController.dispose);
      await tester.pumpWidget(h.build());

      await tester.dragFrom(center, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(h.pageController.page, 1.0);
    },
  );

  testWidgets('a tap still reaches the tap target below', (tester) async {
    final h = _Harness();
    addTearDown(h.pageController.dispose);
    await tester.pumpWidget(h.build());

    await tester.tapAt(center);
    await tester.pump();

    expect(h.taps, 1);
    expect(h.pageController.page, 0.0);
  });

  testWidgets(
    'abort() hands a touch that has not become a drag yet back to the pager',
    (tester) async {
      final h = _Harness();
      addTearDown(h.pageController.dispose);
      await tester.pumpWidget(h.build());

      final gesture = await tester.startGesture(center);
      h.recognizer!.abort();
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-500, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(h.pageController.page, 1.0);
    },
  );

  testWidgets(
    'when PageView is vertical, vertical drag changes page while horizontal drag claims seek without interfering',
    (tester) async {
      final h = _Harness(scrollDirection: Axis.vertical);
      addTearDown(h.pageController.dispose);
      await tester.pumpWidget(h.build());

      // Horizontal drag claims seek without changing vertical page
      await tester.dragFrom(center, dragLeft);
      await tester.pump();
      expect(h.rawStripMoves, greaterThan(0));
      expect(h.pageController.page, 0.0);

      // Vertical drag changes page smoothly
      await tester.dragFrom(center, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(h.pageController.page, 1.0);
    },
  );
}
