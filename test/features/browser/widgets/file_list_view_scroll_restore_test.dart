import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';

/// Going back to a folder opens its list with a controller whose
/// `initialScrollOffset` is where the folder was left. DirectoryContentView
/// gives every folder its own list key (a GlobalKey kept across folders would
/// keep the old scroll position), so the list has to be on that offset on its
/// very first frame, with no jump afterwards.
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
    for (var i = 0; i < 200; i++)
      RawEntry(name: 'f$i.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0),
  ];
  final childItems = [
    for (var i = 0; i < 10; i++)
      RawEntry(name: 'c$i.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0),
  ];

  testWidgets('lands on the offset the folder was left at on the first frame', (
    tester,
  ) async {
    late StateSetter setOuter;
    var path = '';
    var controller = ScrollController();
    var listKey = GlobalKey<FileListViewState>();
    addTearDown(() => controller.dispose());
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
                  child: FileListView(
                    key: listKey,
                    container: container,
                    items: path.isEmpty ? parentItems : childItems,
                    isSelectionMode: false,
                    selectedItems: const {},
                    currentDirPath: path,
                    thumbnailCacheMode: ThumbnailCacheMode.disabled,
                    thumbnailQuality: ThumbnailQuality.defaultQuality,
                    showThumbnails: false,
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

    controller.jumpTo(3000);
    await tester.pumpAndSettle();
    final left = controller.offset;
    expect(left, greaterThan(0));

    // Into a sub-folder: new controller at the top, new list key.
    setOuter(() {
      path = 'dir3';
      controller = ScrollController();
      listKey = GlobalKey<FileListViewState>();
    });
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    // Back: a new controller at the saved offset, new list key.
    setOuter(() {
      path = '';
      controller = ScrollController(initialScrollOffset: left);
      listKey = GlobalKey<FileListViewState>();
    });
    await tester.pump();
    expect(controller.offset, left);
  });
}
