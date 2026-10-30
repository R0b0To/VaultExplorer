import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
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

  group('edgeSwipeClaimsMovement', () {
    // The default slop is Flutter's fallback of 18 px, so a claim needs 13.5 px
    // of vertical travel (0.75 of a slop).
    test('a clearly vertical drag is claimed once it has travelled far enough',
        () {
      expect(edgeSwipeClaimsMovement(const Offset(0, 14)), isTrue);
      expect(edgeSwipeClaimsMovement(const Offset(4, -15)), isTrue);
      expect(edgeSwipeClaimsMovement(const Offset(-8, 60)), isTrue);
    });

    test('a drag that has not travelled far enough yet is not claimed', () {
      expect(edgeSwipeClaimsMovement(Offset.zero), isFalse);
      expect(edgeSwipeClaimsMovement(const Offset(0, 13.4)), isFalse);
    });

    test('the travel needed follows the device touch slop', () {
      // Android reports a slop of about 8 px, so the claim comes at 6 px,
      // still before a vertical scrollable's own 8 px.
      expect(edgeSwipeClaimsMovement(const Offset(0, 6), touchSlop: 8), isTrue);
      expect(
        edgeSwipeClaimsMovement(const Offset(0, 5.9), touchSlop: 8),
        isFalse,
      );
      expect(edgeSwipeClaimsMovement(const Offset(0, 6)), isFalse);
    });

    test('a diagonal or curved start is left to the swipe', () {
      expect(edgeSwipeClaimsMovement(const Offset(-14, 14)), isFalse);
      expect(edgeSwipeClaimsMovement(const Offset(-14, 24)), isFalse);
      expect(edgeSwipeClaimsMovement(const Offset(-30, 20)), isFalse);
      expect(
        edgeSwipeClaimsMovement(const Offset(-5, 7), touchSlop: 8),
        isFalse,
      );
    });

    test('a horizontal movement is never claimed', () {
      expect(edgeSwipeClaimsMovement(const Offset(-80, 3)), isFalse);
    });
  });

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

  testWidgets(
    'a diagonal drag that leans downward is left to the list instead of '
    'being claimed by the strip',
    (tester) async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(h.build());

      // Moves sideways as much as it moves up, like the start of a curved
      // swipe. The strip used to claim any single move that leaned vertical.
      final gesture = await tester.startGesture(onStrip);
      await gesture.moveBy(const Offset(-10, -12));
      await gesture.moveBy(const Offset(-10, -12));
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
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