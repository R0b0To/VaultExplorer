import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/file_masonry_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('FileMasonryViewState.geometriesForGlobalIndices returns exact item positions',
      (tester) async {
    final container = MountedContainer(
      volId: 1,
      displayName: 'test_vault',
      uri: 'content://test',
      rootFiles: const [],
      mountedAt: DateTime.now(),
      totalSpace: 1024,
      freeSpace: 512,
    );

    final entries = List<RawEntry>.generate(
      50,
      (i) => RawEntry(
        name: 'file_${i.toString().padLeft(4, '0')}.txt',
        isDir: false,
        sizeBytes: 1024,
        modifiedSecs: 1000,
      ),
    );

    final masonryKey = GlobalKey<FileMasonryViewState>();
    final scrollController = ScrollController();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FileMasonryView(
                key: masonryKey,
                container: container,
                items: entries,
                isSelectionMode: false,
                selectedItems: const {},
                currentDirPath: 'photos',
                thumbnailCacheMode: ThumbnailCacheMode.disabled,
                thumbnailQuality: ThumbnailQuality.defaultQuality,
                scrollController: scrollController,
                onDirTap: (_) {},
                onFileTap: (_) {},
                onItemLongPress: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final state = masonryKey.currentState;
    expect(state, isNotNull);

    // Query geometry for item 0, item 10, item 25
    final targets = {0, 10, 25};
    final geometries = state!.geometriesForGlobalIndices(targets);

    expect(geometries.containsKey(0), isTrue);
    expect(geometries.containsKey(10), isTrue);
    expect(geometries.containsKey(25), isTrue);

    // First item is at top inset (12.0)
    expect(geometries[0]!.top, equals(12.0));
    expect(geometries[0]!.height, greaterThan(0));

    // Later items have strictly increasing or equal row tops
    expect(geometries[10]!.top, greaterThanOrEqualTo(geometries[0]!.top));
    expect(geometries[25]!.top, greaterThan(geometries[10]!.top));

    scrollController.dispose();
  });

  testWidgets('FileMasonryViewState.geometriesForGlobalIndices works with groupByDate',
      (tester) async {
    final container = MountedContainer(
      volId: 1,
      displayName: 'test_vault',
      uri: 'content://test',
      rootFiles: const [],
      mountedAt: DateTime.now(),
      totalSpace: 1024,
      freeSpace: 512,
    );

    final entries = List<RawEntry>.generate(
      30,
      (i) => RawEntry(
        name: 'file_${i.toString().padLeft(4, '0')}.txt',
        isDir: false,
        sizeBytes: 1024,
        modifiedSecs: 1700000000 + (i ~/ 10) * 86400 * 30, // 3 different date buckets
      ),
    );

    final masonryKey = GlobalKey<FileMasonryViewState>();
    final scrollController = ScrollController();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FileMasonryView(
                key: masonryKey,
                container: container,
                items: entries,
                isSelectionMode: false,
                selectedItems: const {},
                currentDirPath: 'photos',
                thumbnailCacheMode: ThumbnailCacheMode.disabled,
                thumbnailQuality: ThumbnailQuality.defaultQuality,
                scrollController: scrollController,
                groupByDate: true,
                onDirTap: (_) {},
                onFileTap: (_) {},
                onItemLongPress: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final state = masonryKey.currentState;
    expect(state, isNotNull);

    final targets = {0, 15, 29};
    final geometries = state!.geometriesForGlobalIndices(targets);

    expect(geometries.containsKey(0), isTrue);
    expect(geometries.containsKey(15), isTrue);
    expect(geometries.containsKey(29), isTrue);

    expect(geometries[0]!.height, greaterThan(0));
    // In date grouping, newest items (higher modifiedSecs, e.g. item 29)
    // appear first, while older items (e.g. item 0) appear lower.
    expect(geometries[29]!.top, lessThan(geometries[15]!.top));
    expect(geometries[15]!.top, lessThan(geometries[0]!.top));

    scrollController.dispose();
  });
}
