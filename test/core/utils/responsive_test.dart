import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/layout/adaptive_page_route.dart';
import 'package:vaultexplorer/core/widgets/layout/adaptive_route_frame.dart';
import 'package:vaultexplorer/core/widgets/sheets/adaptive_sheet.dart';

/// Pumps a [MaterialApp] in a window of [size] logical pixels and returns the
/// [ScreenInfo] seen from inside it.
Future<ScreenInfo> _screenInfoFor(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late ScreenInfo info;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          info = context.screen;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return info;
}

void main() {
  group('AppBreakpoints.useDockedSidebarFor', () {
    test('phones and portrait tablets keep the modal drawer', () {
      expect(AppBreakpoints.useDockedSidebarFor(const Size(411, 891)), isFalse);
      // A landscape phone is wide enough but far too short.
      expect(AppBreakpoints.useDockedSidebarFor(const Size(891, 411)), isFalse);
      expect(
        AppBreakpoints.useDockedSidebarFor(const Size(800, 1280)),
        isFalse,
      );
    });

    test('tablet landscape and desktop windows dock the sidebar', () {
      expect(
        AppBreakpoints.useDockedSidebarFor(const Size(1280, 800)),
        isTrue,
      );
      expect(AppBreakpoints.useDockedSidebarFor(const Size(840, 480)), isTrue);
      expect(
        AppBreakpoints.useDockedSidebarFor(const Size(839, 800)),
        isFalse,
      );
      expect(
        AppBreakpoints.useDockedSidebarFor(const Size(1280, 479)),
        isFalse,
      );
    });
  });

  group('ScreenInfo.cardColumnsFor', () {
    test('never goes below one column', () {
      expect(ScreenInfo.cardColumnsFor(0), 1);
      expect(ScreenInfo.cardColumnsFor(-50), 1);
      expect(ScreenInfo.cardColumnsFor(double.nan), 1);
      expect(ScreenInfo.cardColumnsFor(200), 1);
    });

    test('adds a column for every full tile width that fits', () {
      expect(ScreenInfo.cardColumnsFor(339), 1);
      expect(ScreenInfo.cardColumnsFor(340), 1);
      expect(ScreenInfo.cardColumnsFor(680), 2);
      expect(ScreenInfo.cardColumnsFor(1020), 3);
    });

    test('is capped by maxColumns', () {
      expect(ScreenInfo.cardColumnsFor(5000), 3);
      expect(ScreenInfo.cardColumnsFor(5000, maxColumns: 4), 4);
    });
  });

  group('ScreenInfo layout decisions', () {
    testWidgets('a phone in portrait gets the compact layouts', (tester) async {
      final info = await _screenInfoFor(tester, const Size(411, 891));
      expect(info.useWideLayout, isFalse);
      expect(info.useLandscapeLayout, isFalse);
      expect(info.useDockedSidebar, isFalse);
      expect(info.maxGridColumns, 4);
      expect(info.maxMasonryColumns, 3);
    });

    testWidgets('a portrait tablet is a wide layout, not a phone', (
      tester,
    ) async {
      final info = await _screenInfoFor(tester, const Size(800, 1280));
      expect(info.isLandscape, isFalse);
      expect(info.useWideLayout, isTrue);
      expect(info.useLandscapeLayout, isTrue);
      expect(info.layoutOrientation, Orientation.landscape);
      expect(info.useDockedSidebar, isFalse);
      expect(info.maxGridColumns, 7);
    });

    testWidgets('a landscape phone is landscape but not docked', (
      tester,
    ) async {
      final info = await _screenInfoFor(tester, const Size(891, 411));
      expect(info.useLandscapeLayout, isTrue);
      expect(info.useDockedSidebar, isFalse);
      expect(info.maxGridColumns, 7);
    });

    testWidgets('a desktop window docks the sidebar and allows more columns', (
      tester,
    ) async {
      final info = await _screenInfoFor(tester, const Size(1280, 800));
      expect(info.useDockedSidebar, isTrue);
      expect(info.maxGridColumns, 10);
      expect(info.maxMasonryColumns, 9);
    });
  });

  group('DockedSidebarScope', () {
    testWidgets('is only visible to descendants', (tester) async {
      bool? outside;
      bool? inside;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Builder(
                builder: (context) {
                  outside = DockedSidebarScope.of(context);
                  return const SizedBox.shrink();
                },
              ),
              DockedSidebarScope(
                child: Builder(
                  builder: (context) {
                    inside = DockedSidebarScope.of(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      expect(outside, isFalse);
      expect(inside, isTrue);
    });
  });

  group('AdaptiveRouteFrame', () {
    Future<Size> childSizeIn(WidgetTester tester, Size window) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late Size seen;
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveRouteFrame(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // What the page inside believes the window to be.
                seen = MediaQuery.sizeOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return seen;
    }

    testWidgets('leaves a phone-sized window full screen', (tester) async {
      expect(
        await childSizeIn(tester, const Size(411, 891)),
        const Size(411, 891),
      );
    });

    testWidgets('leaves a small tablet window full screen', (tester) async {
      expect(
        await childSizeIn(tester, const Size(800, 1280)),
        const Size(800, 1280),
      );
    });

    testWidgets('frames a large window as a panel and sizes the page to it', (
      tester,
    ) async {
      // 880 wide at most; 800 - 2 * 24 margin = 752 tall.
      expect(
        await childSizeIn(tester, const Size(1280, 800)),
        const Size(880, 752),
      );
    });

    testWidgets('caps the panel on a very large window', (tester) async {
      expect(
        await childSizeIn(tester, const Size(2560, 1440)),
        const Size(880, 760),
      );
    });
  });

  group('dialogs instead of pages and sheets on large windows', () {
    Future<void> useWindow(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('prefersDialogs follows the window and the sidebar scope', (
      tester,
    ) async {
      bool? phone;
      bool? tablet;
      bool? desktop;
      bool? beside;

      Widget probe(void Function(BuildContext) read) => MaterialApp(
        home: Builder(
          builder: (context) {
            read(context);
            return const SizedBox.shrink();
          },
        ),
      );

      await useWindow(tester, const Size(411, 891));
      await tester.pumpWidget(probe((c) => phone = c.prefersDialogs));
      await useWindow(tester, const Size(800, 1280));
      await tester.pumpWidget(probe((c) => tablet = c.prefersDialogs));
      await useWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(probe((c) => desktop = c.prefersDialogs));
      // Inside the sidebar's content area the window may look narrow, but the
      // scope says a sidebar is docked.
      await useWindow(tester, const Size(700, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: DockedSidebarScope(
            child: Builder(
              builder: (context) {
                beside = context.prefersDialogs;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(phone, isFalse);
      expect(tablet, isFalse);
      expect(desktop, isTrue);
      expect(beside, isTrue);
    });

    testWidgets('adaptivePageRoute: full-screen page on a portrait tablet', (
      tester,
    ) async {
      await useWindow(tester, const Size(800, 1280));
      late Route<void> route;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              route = adaptivePageRoute<void>(
                context,
                builder: (_) => const SizedBox.shrink(),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
    });

    testWidgets('adaptivePageRoute: a sized dialog panel on a large window', (
      tester,
    ) async {
      await useWindow(tester, const Size(1280, 800));
      late BuildContext appContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              appContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      Size? seen;
      final route = adaptivePageRoute<void>(
        appContext,
        builder: (context) {
          seen = MediaQuery.sizeOf(context);
          return const SizedBox.expand();
        },
      );
      expect(route, isA<DialogRoute<void>>());
      unawaited(Navigator.of(appContext).push(route));
      await tester.pumpAndSettle();
      expect(seen, const Size(520, 640));
    });

    testWidgets('showAdaptiveSheet: bottom sheet below, dialog on large', (
      tester,
    ) async {
      Future<void> open(Size window) async {
        await useWindow(tester, window);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAdaptiveSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('sheet body')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await open(const Size(411, 891));
      expect(find.text('sheet body'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      // Replace the phone-sized app (and its open sheet) with a large one.
      await tester.pumpWidget(const SizedBox.shrink());
      await open(const Size(1280, 800));
      expect(find.text('sheet body'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
