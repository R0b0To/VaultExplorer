import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/sidebar_drop_target.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

const _file = RawEntry(
  name: 'a.txt',
  isDir: false,
  sizeBytes: 1,
  modifiedSecs: 0,
);

MountedContainer _volume(int volId, {bool readOnly = false}) =>
    MountedContainer(
      volId: volId,
      uri: 'file:///vault$volId.hc',
      displayName: 'Vault $volId',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
      readOnly: readOnly,
    );

typedef _Drop = ({
  MountedContainer destination,
  String path,
  BrowserDropMode mode,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => PlatformFeatures.debugIsDesktopOverride = true);
  tearDownAll(() => PlatformFeatures.debugIsDesktopOverride = null);

  const sourceKey = ValueKey('source');
  const targetKey = ValueKey('target');
  late List<_Drop> drops;

  /// A draggable file (in volume 1) above one sidebar entry.
  Widget app({required MountedContainer? container, String path = ''}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              BrowserItemDragItem(
                entry: _file,
                container: _volume(1),
                currentDirectory: '',
                visibleItems: const [_file],
                selectedItems: const {},
                isSelectionMode: false,
                enabled: true,
                onItemLongPress: (_) {},
                onDrop: (data, destination, destinationPath, mode) async {
                  drops.add((
                    destination: destination,
                    path: destinationPath,
                    mode: mode,
                  ));
                },
                child: Container(
                  key: sourceKey,
                  height: 60,
                  width: 300,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),
              SidebarDropTarget(
                container: container,
                path: path,
                child: Container(
                  key: targetKey,
                  height: 60,
                  width: 300,
                  color: Colors.blueGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Picks the file up with the mouse and carries it over the target.
  Future<TestGesture> dragOverTarget(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(sourceKey)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(targetKey)));
    await tester.pump();
    return gesture;
  }

  double frameOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(SidebarDropTarget),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  setUp(() => drops = []);

  testWidgets('dropping on another container offers copy and move', (
    tester,
  ) async {
    final dest = _volume(2);
    await tester.pumpWidget(app(container: dest, path: 'Docs/Reports'));

    final gesture = await dragOverTarget(tester);
    expect(frameOpacity(tester), 1.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.drive_file_move_rounded), findsOneWidget);
    expect(drops, isEmpty);

    await tester.tap(find.byIcon(Icons.drive_file_move_rounded));
    await tester.pumpAndSettle();
    expect(drops, hasLength(1));
    expect(drops.single.destination.volId, 2);
    expect(drops.single.path, 'Docs/Reports');
    expect(drops.single.mode, BrowserDropMode.move);
  });

  testWidgets('choosing copy hands copy to the source pane', (tester) async {
    await tester.pumpWidget(app(container: _volume(2)));

    final gesture = await dragOverTarget(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(drops.single.path, '');
    expect(drops.single.mode, BrowserDropMode.copy);
  });

  testWidgets('an entry without a container (locked vault, file) refuses', (
    tester,
  ) async {
    await tester.pumpWidget(app(container: null));

    final gesture = await dragOverTarget(tester);
    expect(frameOpacity(tester), 0.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(drops, isEmpty);
  });

  testWidgets('a read-only container refuses', (tester) async {
    await tester.pumpWidget(app(container: _volume(2, readOnly: true)));

    final gesture = await dragOverTarget(tester);
    expect(frameOpacity(tester), 0.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(drops, isEmpty);
  });

  testWidgets('the frame goes away when the drag leaves the entry', (
    tester,
  ) async {
    await tester.pumpWidget(app(container: _volume(2)));

    final gesture = await dragOverTarget(tester);
    expect(frameOpacity(tester), 1.0);

    await gesture.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(frameOpacity(tester), 0.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(drops, isEmpty);
  });
}
