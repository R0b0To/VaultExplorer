import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testItems = List.generate(
    10,
    (i) => RawEntry.parse(
      i % 2 == 0
          ? 'D|0|1690000000|folder_$i'
          : 'F|1024|1690000000|file_$i.txt',
    ),
  );

  Widget buildTestWidget({
    required List<RawEntry> items,
    required Set<RawEntry> selectedItems,
    required bool isSelectionMode,
    required ValueChanged<Set<RawEntry>> onSelectionChanged,
    void Function(RawEntry entry)? onLongPressSelect,
    ScrollController? scrollController,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: HoldRangeSelectContainer(
          items: items,
          selectedItems: selectedItems,
          isSelectionMode: isSelectionMode,
          onSelectionChanged: onSelectionChanged,
          onLongPressSelect: onLongPressSelect,
          child: ListView.builder(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final entry = items[index];
              return HoldSelectableItem(
                index: index,
                entry: entry,
                child: SizedBox(
                  height: 60,
                  child: Text(
                    entry.name,
                    key: ValueKey('item_$index'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  group('HoldRangeSelectContainer widget tests', () {
    testWidgets('HoldSelectableItem renders correctly with metadata',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          items: testItems,
          selectedItems: {},
          isSelectionMode: false,
          onSelectionChanged: (_) {},
        ),
      );

      expect(find.text('folder_0'), findsOneWidget);
      expect(find.text('file_1.txt'), findsOneWidget);
    });

    testWidgets('Long press starts selection when not in selection mode',
        (tester) async {
      RawEntry? longPressedEntry;
      Set<RawEntry> selection = {};

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return buildTestWidget(
              items: testItems,
              selectedItems: selection,
              isSelectionMode: false,
              onLongPressSelect: (entry) {
                longPressedEntry = entry;
                setState(() => selection = {entry});
              },
              onSelectionChanged: (newSelection) {
                setState(() => selection = newSelection);
              },
            );
          },
        ),
      );

      final itemFinder = find.byKey(const ValueKey('item_0'));
      expect(itemFinder, findsOneWidget);

      await tester.longPress(itemFinder);
      await tester.pumpAndSettle();

      expect(longPressedEntry, isNotNull);
      expect(longPressedEntry?.name, 'folder_0');
      expect(selection.contains(testItems[0]), isTrue);
    });

    testWidgets('Moving finger beyond threshold cancels hold timer and does not select items',
        (tester) async {
      Set<RawEntry> selection = {};

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return buildTestWidget(
              items: testItems,
              selectedItems: selection,
              isSelectionMode: false,
              onLongPressSelect: (entry) {
                setState(() => selection = {entry});
              },
              onSelectionChanged: (newSelection) {
                setState(() => selection = newSelection);
              },
            );
          },
        ),
      );

      final item1Center = tester.getCenter(find.byKey(const ValueKey('item_1')));
      final item4Center = tester.getCenter(find.byKey(const ValueKey('item_4')));

      // Drag from item 1 to item 4 without holding (fast scroll gesture)
      final gesture = await tester.startGesture(item1Center);
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.moveTo(item4Center);
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.up();
      await tester.pumpAndSettle();

      // Nothing should have been selected because moving cancelled the hold timer
      expect(selection.isEmpty, isTrue);
    });

    testWidgets('Works in multi-column GridView layout with hold to range-select',
        (tester) async {
      Set<RawEntry> selection = {};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return HoldRangeSelectContainer(
                  items: testItems,
                  selectedItems: selection,
                  isSelectionMode: selection.isNotEmpty,
                  onLongPressSelect: (entry) {
                    setState(() => selection = {entry});
                  },
                  onSelectionChanged: (newSelection) {
                    setState(() => selection = newSelection);
                  },
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 3.0,
                    ),
                    itemCount: testItems.length,
                    itemBuilder: (context, index) {
                      final entry = testItems[index];
                      return HoldSelectableItem(
                        index: index,
                        entry: entry,
                        child: Container(
                          key: ValueKey('grid_item_$index'),
                          color: selection.contains(entry)
                              ? Colors.blue
                              : Colors.grey,
                          child: Text(entry.name),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      final item0Center =
          tester.getCenter(find.byKey(const ValueKey('grid_item_0')));
      final item3Center =
          tester.getCenter(find.byKey(const ValueKey('grid_item_3')));

      // Hold item 0 to start selection mode
      var gesture = await tester.startGesture(item0Center);
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selection.contains(testItems[0]), isTrue);

      // Hold item 3 to range-select 0..3
      gesture = await tester.startGesture(item3Center);
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selection.contains(testItems[0]), isTrue);
      expect(selection.contains(testItems[1]), isTrue);
      expect(selection.contains(testItems[2]), isTrue);
      expect(selection.contains(testItems[3]), isTrue);
    });

    testWidgets('Holding another item when selection is enabled selects all items in range',
        (tester) async {
      // Start with item 1 selected
      Set<RawEntry> selection = {testItems[1]};

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return buildTestWidget(
              items: testItems,
              selectedItems: selection,
              isSelectionMode: true,
              onSelectionChanged: (newSelection) {
                setState(() => selection = newSelection);
              },
            );
          },
        ),
      );

      final item4Center = tester.getCenter(find.byKey(const ValueKey('item_4')));

      // Hold on item 4 for >= holdDelay (280ms)
      final gesture = await tester.startGesture(item4Center);
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();

      // All items between 1 and 4 should now be selected: 1, 2, 3, 4
      expect(selection.contains(testItems[0]), isFalse);
      expect(selection.contains(testItems[1]), isTrue);
      expect(selection.contains(testItems[2]), isTrue);
      expect(selection.contains(testItems[3]), isTrue);
      expect(selection.contains(testItems[4]), isTrue);
      expect(selection.contains(testItems[5]), isFalse);
    });

    testWidgets('Holding an earlier item backward range-selects in selection mode',
        (tester) async {
      // Start with item 4 selected
      Set<RawEntry> selection = {testItems[4]};

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return buildTestWidget(
              items: testItems,
              selectedItems: selection,
              isSelectionMode: true,
              onSelectionChanged: (newSelection) {
                setState(() => selection = newSelection);
              },
            );
          },
        ),
      );

      final item1Center = tester.getCenter(find.byKey(const ValueKey('item_1')));

      // Hold on earlier item 1 for >= holdDelay
      final gesture = await tester.startGesture(item1Center);
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();

      // Items 1..4 should all be selected
      expect(selection.contains(testItems[0]), isFalse);
      expect(selection.contains(testItems[1]), isTrue);
      expect(selection.contains(testItems[2]), isTrue);
      expect(selection.contains(testItems[3]), isTrue);
      expect(selection.contains(testItems[4]), isTrue);
      expect(selection.contains(testItems[5]), isFalse);
    });

    testWidgets('Multi-step: hold to select, hold another to range-select, tap another, hold another to range-select',
        (tester) async {
      Set<RawEntry> selection = {};

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return buildTestWidget(
              items: testItems,
              selectedItems: selection,
              isSelectionMode: selection.isNotEmpty,
              onLongPressSelect: (entry) {
                setState(() => selection = {entry});
              },
              onSelectionChanged: (newSelection) {
                setState(() => selection = newSelection);
              },
            );
          },
        ),
      );

      final item1Center = tester.getCenter(find.byKey(const ValueKey('item_1')));
      final item3Center = tester.getCenter(find.byKey(const ValueKey('item_3')));
      final item7Center = tester.getCenter(find.byKey(const ValueKey('item_7')));
      final item9Center = tester.getCenter(find.byKey(const ValueKey('item_9')));

      // Step 1: Hold item 1 to start selection mode
      var g = await tester.startGesture(item1Center);
      await tester.pump(const Duration(milliseconds: 350));
      await g.up();
      await tester.pumpAndSettle();
      expect(selection, {testItems[1]});

      // Step 2: Hold item 3 to range select 1..3
      g = await tester.startGesture(item3Center);
      await tester.pump(const Duration(milliseconds: 350));
      await g.up();
      await tester.pumpAndSettle();
      expect(selection, {testItems[1], testItems[2], testItems[3]});

      // Step 3: Tap item 7
      g = await tester.startGesture(item7Center);
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pumpAndSettle();
      // Simulate tap selection update
      selection.add(testItems[7]);
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return buildTestWidget(
              items: testItems,
              selectedItems: selection,
              isSelectionMode: true,
              onSelectionChanged: (newSelection) {
                setState(() => selection = newSelection);
              },
            );
          },
        ),
      );

      // Step 4: Hold item 9 to range select from 7 to 9
      g = await tester.startGesture(item9Center);
      await tester.pump(const Duration(milliseconds: 350));
      await g.up();
      await tester.pumpAndSettle();
      expect(selection, {
        testItems[1],
        testItems[2],
        testItems[3],
        testItems[7],
        testItems[8],
        testItems[9],
      });
    });

    testWidgets('Holding another item after scrolling offscreen selects all items in range',
        (tester) async {
      // 40 items
      final manyItems = List.generate(
        40,
        (i) => RawEntry.parse('F|1024|1690000000|file_$i.txt'),
      );
      Set<RawEntry> selection = {};
      final scrollController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return HoldRangeSelectContainer(
                  items: manyItems,
                  selectedItems: selection,
                  isSelectionMode: selection.isNotEmpty,
                  onLongPressSelect: (entry) {
                    setState(() => selection = {entry});
                  },
                  onSelectionChanged: (newSelection) {
                    setState(() => selection = newSelection);
                  },
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: manyItems.length,
                    itemBuilder: (context, index) {
                      final entry = manyItems[index];
                      return HoldSelectableItem(
                        index: index,
                        entry: entry,
                        child: SizedBox(
                          height: 60,
                          child: Text(
                            entry.name,
                            key: ValueKey('many_item_$index'),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Step 1: Hold item 0 to select it and enter selection mode
      final item0Finder = find.byKey(const ValueKey('many_item_0'));
      var gesture = await tester.startGesture(tester.getCenter(item0Finder));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selection, {manyItems[0]});

      // Step 2: Scroll down so item 0 is completely offscreen
      scrollController.jumpTo(1000.0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('many_item_0')), findsNothing);

      // Simulate a user touching the screen to scroll or stop scroll
      final visibleCenter = tester.getCenter(find.byKey(const ValueKey('many_item_20')));
      gesture = await tester.startGesture(visibleCenter);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, -30)); // scroll move
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      // Step 3: Now hold item 25 (which is visible)
      final item25Finder = find.byKey(const ValueKey('many_item_25'));
      expect(item25Finder, findsOneWidget);
      gesture = await tester.startGesture(tester.getCenter(item25Finder));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify that ALL items 0 through 25 are now selected!
      expect(selection.length, 26);
      for (int i = 0; i <= 25; i++) {
        expect(selection.contains(manyItems[i]), isTrue,
            reason: 'Item $i should be selected');
      }
      expect(selection.contains(manyItems[26]), isFalse);
    });

    testWidgets('FileTile replaces rightmost column with TileSelectionIndicator when selected without shifting layout',
        (tester) async {
      final fileEntry = testItems[1]; // file_1.txt
      Widget buildTile({required bool isSelected, required bool isSelectionMode}) {
        return MaterialApp(
          home: Scaffold(
            body: FileTile(
              entry: fileEntry,
              isSelectionMode: isSelectionMode,
              isSelected: isSelected,
              detailColumns: const [FileDetailColumn.date, FileDetailColumn.size],
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        );
      }

      // Unselected state
      await tester.pumpWidget(buildTile(isSelected: false, isSelectionMode: false));
      final unselectedNameRect = tester.getRect(find.text(fileEntry.name));
      expect(find.byType(TileSelectionIndicator), findsNothing);

      // Selected state
      await tester.pumpWidget(buildTile(isSelected: true, isSelectionMode: true));
      final selectedNameRect = tester.getRect(find.text(fileEntry.name));

      // Title position and width must be 100% identical (0px shift)
      expect(selectedNameRect.left, equals(unselectedNameRect.left));
      expect(selectedNameRect.width, equals(unselectedNameRect.width));
      expect(find.byType(TileSelectionIndicator), findsOneWidget);
    });

    testWidgets('DirectoryTile replaces rightmost column with TileSelectionIndicator when selected without shifting layout',
        (tester) async {
      final dirEntry = testItems[0]; // folder_0
      Widget buildTile({required bool isSelected, required bool isSelectionMode}) {
        return MaterialApp(
          home: Scaffold(
            body: DirectoryTile(
              entry: dirEntry,
              isSelectionMode: isSelectionMode,
              isSelected: isSelected,
              detailColumns: const [FileDetailColumn.date, FileDetailColumn.size],
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        );
      }

      // Unselected state
      await tester.pumpWidget(buildTile(isSelected: false, isSelectionMode: false));
      final unselectedNameRect = tester.getRect(find.text(dirEntry.name));
      expect(find.byType(TileSelectionIndicator), findsNothing);

      // Selected state
      await tester.pumpWidget(buildTile(isSelected: true, isSelectionMode: true));
      final selectedNameRect = tester.getRect(find.text(dirEntry.name));

      // Title position and width must be 100% identical (0px shift)
      expect(selectedNameRect.left, equals(unselectedNameRect.left));
      expect(selectedNameRect.width, equals(unselectedNameRect.width));
      expect(find.byType(TileSelectionIndicator), findsOneWidget);
    });
  });
}
