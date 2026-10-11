import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_swipe_to_seek_area.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_seek_hud.dart';

void main() {
  group('SwipeSeekHud', () {
    testWidgets('renders bold white position and total text without distracting elements', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SwipeSeekHud(
              targetPosition: Duration(seconds: 45),
              totalDuration: Duration(minutes: 2),
              delta: Duration(seconds: 15),
            ),
          ),
        ),
      );

      expect(find.text('00:45 / 02:00'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(Icon), findsNothing);

      final textWidget = tester.widget<Text>(find.text('00:45 / 02:00'));
      expect(textWidget.style?.color, equals(Colors.white));
      expect(textWidget.style?.fontWeight, equals(FontWeight.bold));
      expect(textWidget.style?.shadows, isNotEmpty);
    });

    testWidgets('renders milliseconds on target position when showMilliseconds is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SwipeSeekHud(
              targetPosition: Duration(milliseconds: 30250),
              totalDuration: Duration(minutes: 5),
              showMilliseconds: true,
            ),
          ),
        ),
      );

      expect(find.text('00:30.250 / 05:00'), findsOneWidget);
    });
  });

  group('EditorSwipeToSeekArea', () {
    testWidgets('tap triggers onTap and does not show HUD', (tester) async {
      var tapped = false;
      var seekStarted = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: EditorSwipeToSeekArea(
                    totalDuration: const Duration(minutes: 2),
                    currentPosition: () => const Duration(seconds: 30),
                    onTap: () => tapped = true,
                    onSeekStart: () => seekStarted = true,
                    onSeekUpdate: (_) {},
                    onSeekEnd: (_) {},
                    child: Container(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EditorSwipeToSeekArea));
      await tester.pump();

      expect(tapped, isTrue);
      expect(seekStarted, isFalse);
      expect(find.byType(SwipeSeekHud), findsNothing);
    });

    testWidgets('horizontal drag initiates seek, displays HUD and calls callbacks', (
      tester,
    ) async {
      var seekStarted = false;
      Duration? latestUpdate;
      Duration? endedPosition;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: EditorSwipeToSeekArea(
                    totalDuration: const Duration(seconds: 120),
                    currentPosition: () => const Duration(seconds: 30),
                    seekSensitivity: 1.0,
                    onTap: () {},
                    onSeekStart: () => seekStarted = true,
                    onSeekUpdate: (pos) => latestUpdate = pos,
                    onSeekEnd: (pos) => endedPosition = pos,
                    child: Container(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(EditorSwipeToSeekArea));
      final gesture = await tester.startGesture(center);
      // Drag right by 100 pixels horizontally
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      expect(seekStarted, isTrue);
      expect(latestUpdate, isNotNull);
      expect(latestUpdate!.inMilliseconds, greaterThan(30000));
      expect(find.byType(SwipeSeekHud), findsOneWidget);

      await gesture.up();
      await tester.pump();

      expect(endedPosition, isNotNull);
      expect(endedPosition, equals(latestUpdate));

      // HUD remains visible immediately after lift
      expect(find.byType(SwipeSeekHud), findsOneWidget);

      // HUD hides after delay
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byType(SwipeSeekHud), findsNothing);
    });

    testWidgets('when enabled is false, horizontal drag does not claim seek', (
      tester,
    ) async {
      var seekStarted = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: EditorSwipeToSeekArea(
                    totalDuration: const Duration(seconds: 120),
                    currentPosition: () => const Duration(seconds: 30),
                    enabled: false,
                    onTap: () {},
                    onSeekStart: () => seekStarted = true,
                    onSeekUpdate: (_) {},
                    onSeekEnd: (_) {},
                    child: Container(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(EditorSwipeToSeekArea));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      expect(seekStarted, isFalse);
      expect(find.byType(SwipeSeekHud), findsNothing);
      await gesture.up();
    });

    testWidgets('multi-pointer touch cancels seek and calls onSeekCancel', (
      tester,
    ) async {
      var seekStarted = false;
      Duration? canceledTo;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: EditorSwipeToSeekArea(
                    totalDuration: const Duration(seconds: 120),
                    currentPosition: () => const Duration(seconds: 30),
                    onTap: () {},
                    onSeekStart: () => seekStarted = true,
                    onSeekUpdate: (_) {},
                    onSeekEnd: (_) {},
                    onSeekCancel: (pos) => canceledTo = pos,
                    child: Container(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(EditorSwipeToSeekArea));
      final gesture1 = await tester.startGesture(center);
      await gesture1.moveBy(const Offset(60, 0));
      await tester.pump();

      expect(seekStarted, isTrue);

      // Second pointer touches down
      final gesture2 = await tester.startGesture(center + const Offset(0, 50));
      await gesture1.moveBy(const Offset(10, 0));
      await tester.pump();

      // Canceled back to starting position (30 seconds)
      expect(canceledTo, equals(const Duration(seconds: 30)));

      await gesture1.up();
      await gesture2.up();
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets(
      'when visibleDuration is 2 seconds, sensitivity decreases so seek does not skip whole seconds and shows milliseconds',
      (tester) async {
        Duration? latestUpdate;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    height: 300,
                    child: EditorSwipeToSeekArea(
                      totalDuration: const Duration(minutes: 10),
                      visibleDuration: () => const Duration(seconds: 2),
                      currentPosition: () => const Duration(seconds: 30),
                      seekSensitivity: 1.0,
                      onTap: () {},
                      onSeekStart: () {},
                      onSeekUpdate: (pos) => latestUpdate = pos,
                      onSeekEnd: (_) {},
                      child: Container(color: Colors.blue),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final center = tester.getCenter(find.byType(EditorSwipeToSeekArea));
        final gesture = await tester.startGesture(center);
        // Drag right by 50 pixels horizontally on a 400px wide box
        // Fraction is 50/400 = 0.125.
        // For a 2s visible window, 0.125 * 2s = 0.25s = 250ms!
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump();

        expect(latestUpdate, isNotNull);
        // Position was 30.000s, with a 250ms delta it is ~30.250s, NOT skipping seconds (e.g. not 40s or 52s)!
        final deltaMs = latestUpdate!.inMilliseconds - 30000;
        expect(deltaMs, closeTo(250, 15));

        // When visible range is < 10s, HUD renders milliseconds
        expect(find.byType(SwipeSeekHud), findsOneWidget);
        expect(find.text('00:30.250 / 10:00'), findsOneWidget);

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
  });
}
