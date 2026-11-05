import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/predictive_back_preference.dart';

// What the "Predictive back animations" preference does to a back gesture, run
// through the same page transition the app's theme installs on Android.
//
// A gesture the app claims makes the route follow the finger and marks the
// navigator as being in a user gesture. A gesture it leaves alone must behave
// like a plain back: nothing moves while dragging, cancelling changes nothing,
// and committing pops the page. Android's own Predictive Back is not part of
// the Dart side, so it is not (and cannot be) exercised here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The preference is process-wide; every test starts from, and leaves, "on".
  setUp(() => appPredictiveBackNotifier.value = true);
  tearDown(() => appPredictiveBackNotifier.value = true);

  // The same registration as in buildLightTheme / buildDarkTheme.
  final theme = ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: CrossfadePageTransitionsBuilder()},
    ),
  );

  Future<void> pumpAtPageB(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        routes: {
          '/': (context) => Material(
            child: TextButton(
              child: const Text('page a'),
              onPressed: () => Navigator.of(context).pushNamed('/b'),
            ),
          ),
          '/b': (context) => const Material(child: Text('page b')),
        },
      ),
    );
    await tester.tap(find.text('page a'));
    await tester.pumpAndSettle();
    expect(find.text('page b'), findsOneWidget);
  }

  Future<void> send(
    WidgetTester tester,
    String method, [
    Map<String, Object?>? arguments,
  ]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );

  Future<void> startGesture(WidgetTester tester) async {
    await send(tester, 'startBackGesture', {
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0, // left
    });
    await tester.pump();
  }

  Future<void> dragGesture(WidgetTester tester, double progress) async {
    await send(tester, 'updateBackGestureProgress', {
      'touchOffset': <double>[100.0, 300.0],
      'progress': progress,
      'swipeEdge': 0, // left
    });
    await tester.pump();
  }

  Future<void> cancelGesture(WidgetTester tester) async {
    await send(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
  }

  Future<void> commitGesture(WidgetTester tester) async {
    await send(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
  }

  NavigatorState navigatorOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator));

  /// How far page B is "in": 1.0 at rest, lower while a gesture drags it out.
  double pageBProgress(WidgetTester tester) =>
      ModalRoute.of(tester.element(find.text('page b')))!.animation!.value;

  final onAndroid = TargetPlatformVariant.only(TargetPlatform.android);

  group('preference on (the default)', () {
    testWidgets('the page follows the finger and a cancel leaves it in place', (
      tester,
    ) async {
      await pumpAtPageB(tester);

      await startGesture(tester);
      expect(navigatorOf(tester).userGestureInProgress, isTrue);

      await dragGesture(tester, 0.35);
      expect(pageBProgress(tester), closeTo(0.65, 0.001));

      await cancelGesture(tester);
      expect(find.text('page b'), findsOneWidget);
      expect(find.text('page a'), findsNothing);
      expect(pageBProgress(tester), 1.0);
      expect(navigatorOf(tester).userGestureInProgress, isFalse);
    }, variant: onAndroid);

    testWidgets('a committed gesture goes back', (tester) async {
      await pumpAtPageB(tester);

      await startGesture(tester);
      await dragGesture(tester, 0.6);
      await commitGesture(tester);

      expect(find.text('page b'), findsNothing);
      expect(find.text('page a'), findsOneWidget);
      expect(navigatorOf(tester).userGestureInProgress, isFalse);
    }, variant: onAndroid);
  });

  group('preference off', () {
    setUp(() => appPredictiveBackNotifier.value = false);

    testWidgets('the page stays put while dragging; a cancel changes nothing', (
      tester,
    ) async {
      await pumpAtPageB(tester);

      await startGesture(tester);
      expect(navigatorOf(tester).userGestureInProgress, isFalse);

      await dragGesture(tester, 0.35);
      expect(pageBProgress(tester), 1.0);

      await cancelGesture(tester);
      expect(find.text('page b'), findsOneWidget);
      expect(find.text('page a'), findsNothing);
      expect(pageBProgress(tester), 1.0);
      expect(navigatorOf(tester).userGestureInProgress, isFalse);
    }, variant: onAndroid);

    testWidgets('a committed gesture still goes back, as a normal pop', (
      tester,
    ) async {
      await pumpAtPageB(tester);

      await startGesture(tester);
      await dragGesture(tester, 0.6);
      expect(find.text('page b'), findsOneWidget); // nothing moved yet
      await commitGesture(tester);

      expect(find.text('page b'), findsNothing);
      expect(find.text('page a'), findsOneWidget);
      expect(navigatorOf(tester).canPop(), isFalse);
    }, variant: onAndroid);

    testWidgets('repeated cancelled gestures never navigate away', (
      tester,
    ) async {
      await pumpAtPageB(tester);

      // Two cancelled gestures in a row: neither may leave the page.
      for (var i = 0; i < 2; i++) {
        await startGesture(tester);
        await dragGesture(tester, 0.9);
        await cancelGesture(tester);
        expect(find.text('page b'), findsOneWidget);
      }
      expect(navigatorOf(tester).canPop(), isTrue);
    }, variant: onAndroid);
  });

  group('changing the preference', () {
    testWidgets('applies to the very next gesture, with no restart', (
      tester,
    ) async {
      await pumpAtPageB(tester);

      // On: the gesture is followed.
      await startGesture(tester);
      expect(navigatorOf(tester).userGestureInProgress, isTrue);
      await cancelGesture(tester);

      // Off: the same page, the next gesture is left alone.
      appPredictiveBackNotifier.value = false;
      await startGesture(tester);
      expect(navigatorOf(tester).userGestureInProgress, isFalse);
      await cancelGesture(tester);

      // On again.
      appPredictiveBackNotifier.value = true;
      await startGesture(tester);
      expect(navigatorOf(tester).userGestureInProgress, isTrue);
      await cancelGesture(tester);

      expect(find.text('page b'), findsOneWidget);
    }, variant: onAndroid);

    testWidgets('a gesture already under way still finishes cleanly', (
      tester,
    ) async {
      await pumpAtPageB(tester);

      await startGesture(tester);
      appPredictiveBackNotifier.value = false; // flipped mid-gesture
      await dragGesture(tester, 0.5);
      expect(pageBProgress(tester), closeTo(0.5, 0.001));
      await commitGesture(tester);

      expect(find.text('page a'), findsOneWidget);
      expect(navigatorOf(tester).userGestureInProgress, isFalse);
    }, variant: onAndroid);
  });
}
