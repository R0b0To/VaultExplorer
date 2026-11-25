import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_drag_session.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

const _a = RawEntry(name: 'a.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0);
const _b = RawEntry(name: 'b.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0);
const _c = RawEntry(name: 'c.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0);

final _volume = MountedContainer(
  volId: 1,
  uri: 'file:///vault1.hc',
  displayName: 'Vault 1',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: 'veracrypt',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => PlatformFeatures.debugIsDesktopOverride = true);
  tearDownAll(() => PlatformFeatures.debugIsDesktopOverride = null);

  group('browserEntriesToDrag with aloneIfUnselected', () {
    test('an unselected tile is dragged alone, the selection stays out', () {
      expect(
        browserEntriesToDrag(
          _c,
          {_a, _b},
          [_a, _b, _c],
          aloneIfUnselected: true,
        ),
        {_c},
      );
    });

    test('a selected tile still takes the whole selection along', () {
      expect(
        browserEntriesToDrag(
          _a,
          {_a, _b},
          [_a, _b, _c],
          aloneIfUnselected: true,
        ),
        {_a, _b},
      );
    });

    test('the default keeps joining the dragged tile to the selection', () {
      expect(browserEntriesToDrag(_c, {_a, _b}, [_a, _b, _c]), {_a, _b, _c});
    });
  });

  group('mouse and touch dragging of a tile', () {
    late List<RawEntry> longPressed;

    Widget app({
      required Set<RawEntry> selected,
      required bool selectionMode,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            // The same wrapper the real file views use: its recognizers share
            // the gesture arena with the tiles' drag.
            body: HoldRangeSelectContainer(
              items: const [_a, _b, _c],
              selectedItems: selected,
              isSelectionMode: selectionMode,
              onSelectionChanged: (_) {},
              enableHoldDrag: true,
              enableMouseMarquee: true,
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    HoldSelectableItem(
                      index: i,
                      entry: [_a, _b, _c][i],
                      child: BrowserItemDragItem(
                        entry: [_a, _b, _c][i],
                        container: _volume,
                        currentDirectory: '',
                        visibleItems: const [_a, _b, _c],
                        selectedItems: selected,
                        isSelectionMode: selectionMode,
                        enabled: true,
                        onItemLongPress: longPressed.add,
                        onDrop: (_, _, _, _) async {},
                        child: Container(
                          key: ValueKey([_a, _b, _c][i].name),
                          height: 60,
                          width: 300,
                          color: Colors.grey,
                          alignment: Alignment.centerLeft,
                          child: Text([_a, _b, _c][i].name),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    bool dragActive(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('a.txt'))),
    ).read(browserDragSessionProvider).isActive;

    setUp(() => longPressed = []);

    testWidgets('pressing and moving drags at once, without selecting', (
      tester,
    ) async {
      await tester.pumpWidget(app(selected: {}, selectionMode: false));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('b.txt'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();

      expect(dragActive(tester), isTrue);
      expect(longPressed, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(dragActive(tester), isFalse);
      expect(longPressed, isEmpty);
    });

    testWidgets('holding the button still does nothing', (tester) async {
      await tester.pumpWidget(app(selected: {}, selectionMode: false));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('b.txt'))),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(dragActive(tester), isFalse);
      expect(longPressed, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a click-sized wobble is not a drag', (tester) async {
      await tester.pumpWidget(app(selected: {}, selectionMode: false));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('b.txt'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump();
      expect(dragActive(tester), isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('an unselected tile drags alone even in selection mode', (
      tester,
    ) async {
      await tester.pumpWidget(app(selected: {_a, _b}, selectionMode: true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('c.txt'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();

      expect(dragActive(tester), isTrue);
      // No count badge: only c.txt is carried.
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
      expect(longPressed, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a selected tile drags the whole selection', (tester) async {
      await tester.pumpWidget(app(selected: {_a, _b}, selectionMode: true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('a.txt'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();

      expect(dragActive(tester), isTrue);
      expect(find.text('2'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('touch still needs a hold, and selects the tile first', (
      tester,
    ) async {
      await tester.pumpWidget(app(selected: {}, selectionMode: false));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('b.txt'))),
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      // Moving before the hold hands the touch to scrolling.
      expect(dragActive(tester), isFalse);
      await gesture.up();
      await tester.pumpAndSettle();

      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('b.txt'))),
      );
      await tester.pump(kItemDragHoldDelay + const Duration(milliseconds: 50));
      expect(longPressed, [_b]);
      await tester.pump(
        kItemDragAfterSelectDelay + const Duration(milliseconds: 50),
      );
      expect(dragActive(tester), isTrue);
      await hold.up();
      await tester.pumpAndSettle();
    });

    testWidgets('touch cannot grab an unselected tile in selection mode', (
      tester,
    ) async {
      await tester.pumpWidget(app(selected: {_a}, selectionMode: true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('c.txt'))),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(dragActive(tester), isFalse);
      expect(longPressed, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
