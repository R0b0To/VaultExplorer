import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_background_context_menu.dart';

Widget _app({
  required List<Widget> Function(BuildContext) menuBuilder,
  bool enabled = true,
  VoidCallback? onItemSecondaryTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 400,
        child: FolderBackgroundContextMenu(
          enabled: enabled,
          menuBuilder: menuBuilder,
          // A tall list with one tile at the top, like a folder with a single
          // item and empty space under it.
          child: ListView(
            children: [
              InkWell(
                key: const Key('tile'),
                onTap: () {},
                onSecondaryTap: onItemSecondaryTap,
                child: const SizedBox(height: 48, child: Text('file.txt')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right click on the empty area opens the menu', (tester) async {
    await tester.pumpWidget(
      _app(
        menuBuilder: (_) => [
          MenuItemButton(onPressed: () {}, child: const Text('Paste')),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(onPressed: () {}, child: const Text('Folder')),
            ],
            child: const Text('New item'),
          ),
        ],
      ),
    );
    expect(find.text('Paste'), findsNothing);

    // Far below the only tile.
    await _rightClick(tester, const Offset(200, 350));

    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('New item'), findsOneWidget);
  });

  testWidgets('right click on an item leaves the menu to the item', (
    tester,
  ) async {
    var itemMenuOpened = 0;
    await tester.pumpWidget(
      _app(
        onItemSecondaryTap: () => itemMenuOpened++,
        menuBuilder: (_) => [
          MenuItemButton(onPressed: () {}, child: const Text('Paste')),
        ],
      ),
    );

    await _rightClick(tester, tester.getCenter(find.byKey(const Key('tile'))));

    expect(itemMenuOpened, 1);
    expect(find.text('Paste'), findsNothing);
  });

  testWidgets('a disabled pane does not open a menu', (tester) async {
    await tester.pumpWidget(
      _app(
        enabled: false,
        menuBuilder: (_) => [
          MenuItemButton(onPressed: () {}, child: const Text('Paste')),
        ],
      ),
    );

    await _rightClick(tester, const Offset(200, 350));

    expect(find.text('Paste'), findsNothing);
  });

  testWidgets('menu is rebuilt from current state on every click', (
    tester,
  ) async {
    var label = 'First';
    await tester.pumpWidget(
      _app(
        menuBuilder: (_) => [
          MenuItemButton(onPressed: () {}, child: Text(label)),
        ],
      ),
    );

    await _rightClick(tester, const Offset(200, 350));
    expect(find.text('First'), findsOneWidget);

    // Dismiss, change state, click again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    label = 'Second';
    await _rightClick(tester, const Offset(200, 350));

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('a left click anywhere on the listing closes the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        menuBuilder: (_) => [
          MenuItemButton(onPressed: () {}, child: const Text('Paste')),
        ],
      ),
    );

    // Empty part of the listing.
    await _rightClick(tester, const Offset(200, 350));
    expect(find.text('Paste'), findsOneWidget);
    await tester.tapAt(const Offset(300, 380));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);

    // On a tile: also closes it.
    await _rightClick(tester, const Offset(200, 350));
    expect(find.text('Paste'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);
  });

  testWidgets('the click that closes the menu does not open the tile', (
    tester,
  ) async {
    var tileTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: FolderBackgroundContextMenu(
              menuBuilder: (_) => [
                MenuItemButton(onPressed: () {}, child: const Text('Paste')),
              ],
              child: ListView(
                children: [
                  InkWell(
                    key: const Key('tile'),
                    onTap: () => tileTaps++,
                    child: const SizedBox(height: 48, child: Text('file.txt')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await _rightClick(tester, const Offset(200, 350));
    expect(find.text('Paste'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tile')));
    await tester.pumpAndSettle();

    expect(find.text('Paste'), findsNothing);
    expect(tileTaps, 0);
  });
}
