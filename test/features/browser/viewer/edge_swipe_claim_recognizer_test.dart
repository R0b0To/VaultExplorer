import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/edge_swipe_claim_recognizer.dart';

class _Harness {
  final controller = ScrollController();
  int rawStripMoves = 0;
  int taps = 0;
  EdgeSwipeClaimRecognizer? recognizer;
  bool claimAllowed = true;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            SizedBox(
              height: 300,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => taps++,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 80,
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      gestures: <Type, GestureRecognizerFactory>{
                        EdgeSwipeClaimRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              EdgeSwipeClaimRecognizer
                            >(() {
                              recognizer = EdgeSwipeClaimRecognizer(
                                canClaim: () => claimAllowed,
                              );
                              return recognizer!;
                            }, (_) {}),
                      },
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerMove: (_) => rawStripMoves++,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3000),
          ],
        ),
      ),
    );
  }
}

void main() {
  const onStrip = Offset(40, 150);
  const offStrip = Offset(400, 150);
  const dragUp = Offset(0, -120);

  testWidgets(
    'a vertical drag that starts on the strip does not scroll the list, '
    'while the strip still sees the pointer moves',
    (tester) async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(h.build());

      await tester.dragFrom(onStrip, dragUp);
      await tester.pump();

      expect(h.rawStripMoves, greaterThan(0));
      expect(h.controller.offset, 0.0);
    },
  );

  testWidgets('the same drag off the strip still scrolls the list', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.build());

    await tester.dragFrom(offStrip, dragUp);
    await tester.pump();

    expect(h.controller.offset, greaterThan(0.0));
  });

  testWidgets(
    'when the strip would not act (canClaim is false) the list scrolls even '
    'from the strip',
    (tester) async {
      final h = _Harness()..claimAllowed = false;
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(h.build());

      await tester.dragFrom(onStrip, dragUp);
      await tester.pump();

      expect(h.controller.offset, greaterThan(0.0));
    },
  );

  testWidgets('a plain tap on the strip still reaches the tap target below', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.build());

    await tester.tapAt(onStrip);
    await tester.pump();

    expect(h.taps, 1);
    expect(h.controller.offset, 0.0);
  });

  testWidgets(
    'abort() hands a touch that has not become a drag yet back to the list '
    '(second finger landing)',
    (tester) async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(h.build());

      final gesture = await tester.startGesture(onStrip);
      h.recognizer!.abort();
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pump();

      expect(h.controller.offset, greaterThan(0.0));
    },
  );

  testWidgets('only touch is claimed: a stylus drag on the strip still '
      'scrolls (the strip handlers ignore non-touch pointers too)', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.build());

    final gesture = await tester.startGesture(
      onStrip,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -100));
    await gesture.up();
    await tester.pump();

    expect(h.controller.offset, greaterThan(0.0));
  });
}