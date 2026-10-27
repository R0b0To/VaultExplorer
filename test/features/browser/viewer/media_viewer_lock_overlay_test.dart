import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_lock_overlay.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The overlay gives haptic feedback; swallow the platform call.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  late int unlocks;
  late int underlyingTaps;
  late ValueNotifier<int> nudge;

  Future<void> pumpOverlay(WidgetTester tester) async {
    unlocks = 0;
    underlyingTaps = 0;
    nudge = ValueNotifier<int>(0);
    addTearDown(nudge.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => underlyingTaps++,
                  onDoubleTap: () => underlyingTaps++,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              Positioned.fill(
                child: MediaViewerLockOverlay(
                  nudge: nudge,
                  onUnlock: () => unlocks++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double buttonOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(MediaViewerLockOverlay),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  Future<void> letHintFade(WidgetTester tester) async {
    await tester.pump(MediaViewerLockOverlay.hintDuration);
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('MediaViewerLockOverlay', () {
    testWidgets('shows the unlock hint right away', (tester) async {
      await pumpOverlay(tester);
      expect(find.text('Hold to unlock'), findsOneWidget);
      expect(buttonOpacity(tester), 1.0);
    });

    testWidgets('hides the lock button after a few seconds', (tester) async {
      await pumpOverlay(tester);
      await letHintFade(tester);
      expect(buttonOpacity(tester), 0.0);
    });

    testWidgets('swallows taps so nothing underneath reacts', (tester) async {
      await pumpOverlay(tester);
      await letHintFade(tester);

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 600));

      expect(underlyingTaps, 0);
      expect(unlocks, 0);
    });

    testWidgets('swallows drags and swipes', (tester) async {
      await pumpOverlay(tester);
      await tester.dragFrom(const Offset(100, 300), const Offset(400, 0));
      await tester.pump();
      expect(underlyingTaps, 0);
      expect(unlocks, 0);
    });

    testWidgets('a touch brings the lock button back', (tester) async {
      await pumpOverlay(tester);
      await letHintFade(tester);
      expect(buttonOpacity(tester), 0.0);

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(buttonOpacity(tester), 1.0);
    });

    testWidgets('a hidden lock button cannot be pressed', (tester) async {
      await pumpOverlay(tester);
      final buttonCenter = tester.getCenter(find.byIcon(Icons.lock_rounded));
      await letHintFade(tester);

      final gesture = await tester.startGesture(buttonCenter);
      await tester.pump(MediaViewerLockOverlay.holdDuration * 2);
      await gesture.up();
      await tester.pump();

      expect(unlocks, 0);
    });

    testWidgets('a plain tap on the lock button does not unlock',
        (tester) async {
      await pumpOverlay(tester);
      await tester.tap(find.byIcon(Icons.lock_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(unlocks, 0);
    });

    testWidgets('releasing the lock button early does not unlock',
        (tester) async {
      await pumpOverlay(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.lock_rounded)),
      );
      await tester.pump(MediaViewerLockOverlay.holdDuration * 0.6);
      await gesture.up();
      await tester.pump(MediaViewerLockOverlay.holdDuration);
      expect(unlocks, 0);
    });

    testWidgets('holding the lock button unlocks exactly once',
        (tester) async {
      await pumpOverlay(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.lock_rounded)),
      );
      await tester.pump(MediaViewerLockOverlay.holdDuration);
      await tester.pump(const Duration(milliseconds: 50));
      expect(unlocks, 1);

      await gesture.up();
      await tester.pump(MediaViewerLockOverlay.holdDuration);
      expect(unlocks, 1);
    });

    testWidgets('the lock button does not fade while it is held',
        (tester) async {
      await pumpOverlay(tester);
      // Press just before the hint would fade, and keep holding past that
      // moment (but short of the unlock time).
      await tester.pump(
        MediaViewerLockOverlay.hintDuration - const Duration(milliseconds: 200),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.lock_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(unlocks, 0);
      expect(buttonOpacity(tester), 1.0);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('the nudge reveals the lock button', (tester) async {
      await pumpOverlay(tester);
      await letHintFade(tester);
      expect(buttonOpacity(tester), 0.0);

      nudge.value++;
      await tester.pump(const Duration(milliseconds: 300));
      expect(buttonOpacity(tester), 1.0);
    });
  });
}
