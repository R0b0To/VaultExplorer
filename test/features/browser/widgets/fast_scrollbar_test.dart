import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';

void main() {
  group('FastScrollbar', () {
    late ScrollController controller;

    setUp(() {
      controller = ScrollController();
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildTestApp({
      required int itemCount,
      List<RawEntry>? items,
      SortBy? sortBy,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: FastScrollbar(
              controller: controller,
              items: items,
              sortBy: sortBy,
              touchWidth: 32.0,
              child: ListView.builder(
                controller: controller,
                itemCount: itemCount,
                itemExtent: 50.0,
                itemBuilder: (context, index) {
                  return SizedBox(
                    height: 50.0,
                    child: Text('Item $index'),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders child content properly', (tester) async {
      await tester.pumpWidget(buildTestApp(itemCount: 100));
      await tester.pumpAndSettle();

      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(controller.offset, 0.0);
    });

    testWidgets('edge drag instantly grabs and scrolls even when thumb was hidden', (tester) async {
      await tester.pumpWidget(buildTestApp(itemCount: 100));
      await tester.pumpAndSettle();

      // Controller starts at 0
      expect(controller.offset, 0.0);

      // Total list height is 100 * 50 = 5000px, viewport is 600px, maxScrollExtent = 4400px.
      // Right edge is at X = 400. Start drag at X = 390 (within touchWidth: 32.0), Y = 300 (50% of 600px).
      final gesture = await tester.startGesture(const Offset(390, 300));
      // Move past kTouchSlop (18px) to activate vertical drag
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();

      // Should jump to around 50% of 4400 (~2200)
      expect(controller.offset, greaterThan(1500));
      expect(controller.offset, lessThan(3000));

      // Dragging down should immediately advance scroll offset
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();

      expect(controller.offset, greaterThan(2500));

      // Releasing gesture
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('displays popup bubble with item section letter during drag', (tester) async {
      final entries = List.generate(
        100,
        (i) => RawEntry(
          name: '${String.fromCharCode(65 + (i ~/ 4))}_file_$i.txt',
          isDir: false,
          sizeBytes: 1024 * (i + 1),
          modifiedSecs: 1700000000 + i * 100,
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          itemCount: entries.length,
          items: entries,
          sortBy: SortBy.name,
        ),
      );
      await tester.pumpAndSettle();

      // Drag near top of the track (Y = 20px)
      final gesture = await tester.startGesture(const Offset(390, 20));
      // Move past touch slop, staying in section 'A'
      await gesture.moveBy(const Offset(0, 19));
      await gesture.moveBy(const Offset(0, -9));
      await tester.pump();

      // Letter 'A' should be visible in popup
      expect(find.text('A'), findsOneWidget);

      // Drag to bottom
      await gesture.moveTo(const Offset(390, 580));
      await tester.pump();

      // Latter letter should be visible in popup
      expect(find.text('A'), findsNothing);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('does not intercept touches when list cannot scroll', (tester) async {
      // 3 items * 50 = 150px, viewport is 600px => maxScrollExtent = 0
      bool buttonTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: FastScrollbar(
                controller: controller,
                touchWidth: 32.0,
                child: ListView(
                  controller: controller,
                  children: [
                    SizedBox(
                      height: 50,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => buttonTapped = true,
                          child: const SizedBox(
                            width: 50,
                            height: 50,
                            child: Text('RightButton'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap at X = 390, Y = 25 (inside the right edge strip where RightButton is)
      await tester.tapAt(const Offset(390, 25));
      await tester.pump();

      // The button underneath should receive the tap because maxScrollExtent == 0
      expect(buttonTapped, isTrue);
    });

    testWidgets('displays modern folder icon for directory entries in popup', (tester) async {
      final entries = List.generate(
        100,
        (i) => RawEntry(
          name: 'Folder_$i',
          isDir: true,
          sizeBytes: 0,
          modifiedSecs: 1700000000 + i * 100,
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          itemCount: entries.length,
          items: entries,
          sortBy: SortBy.name,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(390, 20));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();

      // Modern folder icon should be displayed instead of an emoji
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
      expect(find.text('📁'), findsNothing);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('displays day number and month text for date sort in popup', (tester) async {
      final dateInstant = DateTime(2024, 9, 16, 12, 0);
      final secs = dateInstant.millisecondsSinceEpoch ~/ 1000;

      final entries = List.generate(
        100,
        (i) => RawEntry(
          name: 'file_$i.txt',
          isDir: false,
          sizeBytes: 1024,
          modifiedSecs: secs,
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          itemCount: entries.length,
          items: entries,
          sortBy: SortBy.date,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(390, 20));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();

      // Should display day number and month as text (e.g. contains '16' and 'Sep')
      final finder = find.textContaining('16 Sep');
      expect(finder, findsOneWidget);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
    });
  });
}