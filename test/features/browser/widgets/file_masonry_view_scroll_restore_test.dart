import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/file_masonry_view.dart';

/// Going back to a folder rebuilds its masonry grid (the browser body is keyed
/// by the folder path) with a controller whose `initialScrollOffset` is where
/// the folder was left (issue #85).
void main() {
  final container = MountedContainer(
    uri: 'content://test-container',
    displayName: 'Test Vault',
    volId: 1,
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 100000000,
    freeSpace: 50000000,
  );
  final parentItems = [
    for (var i = 0; i < 6; i++)
      RawEntry(name: 'dir$i', isDir: true, sizeBytes: 0, modifiedSecs: 0),
    for (var i = 0; i < 120; i++)
      RawEntry(name: 'f$i.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0),
  ];
  final childItems = [
    for (var i = 0; i < 10; i++)
      RawEntry(name: 'c$i.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0),
  ];

  /// Opens the parent folder, scrolls it to [scrollTo] (or its end), enters a
  /// sub-folder and goes back, the way DirectoryContentView does. Returns the
  /// offset the parent was left at and the controller it came back with.
  Future<(double, ScrollController)> leaveAndReturn(
    WidgetTester tester, {
    required int columns,
    double? scrollTo,
  }) async {
    late StateSetter setOuter;
    var path = '';
    var controller = ScrollController();
    addTearDown(() => controller.dispose());
    // A phone held upright: the layout menu allows 1 to 3 columns there.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return KeyedSubtree(
                  key: ValueKey(path),
                  child: FileMasonryView(
                    container: container,
                    items: path.isEmpty ? parentItems : childItems,
                    isSelectionMode: false,
                    selectedItems: const {},
                    currentDirPath: path,
                    thumbnailCacheMode: ThumbnailCacheMode.disabled,
                    thumbnailQuality: ThumbnailQuality.defaultQuality,
                    initialColumns: columns,
                    onDirTap: (_) {},
                    onFileTap: (_) {},
                    onItemLongPress: (_) {},
                    scrollController: controller,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.jumpTo(scrollTo ?? controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final left = controller.offset;
    expect(left, greaterThan(0));

    setOuter(() {
      path = 'dir3';
      controller = ScrollController();
    });
    await tester.pumpAndSettle();

    setOuter(() {
      path = '';
      controller = ScrollController(initialScrollOffset: left);
    });
    await tester.pumpAndSettle();
    return (left, controller);
  }

  testWidgets('two columns: lands where the folder was left', (tester) async {
    final (left, controller) = await leaveAndReturn(
      tester,
      columns: 2,
      scrollTo: 3000,
    );
    expect(controller.offset, left);
  });

  testWidgets('two columns: a folder left near its end comes back there', (
    tester,
  ) async {
    // Beyond the children laid out on the first frame the grid only
    // estimates its extent, so this offset is reached over several frames.
    final (left, controller) = await leaveAndReturn(tester, columns: 2);
    expect(controller.offset, left);
  });

  testWidgets('three columns: lands where the folder was left', (tester) async {
    final (left, controller) = await leaveAndReturn(
      tester,
      columns: 3,
      scrollTo: 1500,
    );
    expect(controller.offset, left);
  });

  testWidgets('one column: lands where the folder was left', (tester) async {
    final (left, controller) = await leaveAndReturn(
      tester,
      columns: 1,
      scrollTo: 3000,
    );
    expect(controller.offset, left);
  });
}
