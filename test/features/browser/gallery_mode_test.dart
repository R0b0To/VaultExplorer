import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/widgets/file_masonry_view.dart';
import 'package:vaultexplorer/features/browser/widgets/gallery_date_header.dart';

void main() {
  group('Gallery Mode Model Tests', () {
    test('matchesFilter matches both images and videos for gallery key', () {
      expect(matchesFilter('photo.jpg', 'gallery'), isTrue);
      expect(matchesFilter('photo.png', 'gallery'), isTrue);
      expect(matchesFilter('image.webp', 'gallery'), isTrue);
      expect(matchesFilter('video.mp4', 'gallery'), isTrue);
      expect(matchesFilter('clip.mkv', 'gallery'), isTrue);
      expect(matchesFilter('movie.avi', 'gallery'), isTrue);

      expect(matchesFilter('song.mp3', 'gallery'), isFalse);
      expect(matchesFilter('document.pdf', 'gallery'), isFalse);
      expect(matchesFilter('archive.zip', 'gallery'), isFalse);
      expect(matchesFilter('app.apk', 'gallery'), isFalse);
    });

    test('FileCategory gallery enum values and mappings', () {
      expect(FileCategory.gallery.filterKey, 'gallery');
      expect(FileCategory.fromFilterKey('gallery'), FileCategory.gallery);
      expect(FileCategory.fromStorageKey('gallery'), FileCategory.gallery);

      // Gallery is excluded from drawer categories
      expect(FileCategory.drawerCategories.contains(FileCategory.gallery), isFalse);
      expect(FileCategory.orderedFrom(['gallery', 'images']).contains(FileCategory.gallery), isFalse);
    });

    test('FileManagerAction gallery and options enum are present and in default order', () {
      expect(FileManagerAction.values.contains(FileManagerAction.gallery), isTrue);
      expect(FileManagerAction.values.contains(FileManagerAction.options), isTrue);
      final defaults = FileManagerToolbarConfig.defaults();
      expect(defaults.order.contains(FileManagerAction.gallery), isTrue);
      expect(defaults.order.contains(FileManagerAction.options), isTrue);
    });

    test('FileManagerToolbarConfig galleryModeStorageUris persistence', () {
      var config = FileManagerToolbarConfig.defaults();
      const vaultUri = 'vault://test-vault-id';

      expect(config.isGalleryModeForStorage(vaultUri), isFalse);

      config = config.withGalleryModeForStorage(vaultUri, true);
      expect(config.isGalleryModeForStorage(vaultUri), isTrue);

      final json = config.toJson();
      expect(json['galleryModeStorageUris'], contains(vaultUri));

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.isGalleryModeForStorage(vaultUri), isTrue);

      final toggledOff = restored.withGalleryModeForStorage(vaultUri, false);
      expect(toggledOff.isGalleryModeForStorage(vaultUri), isFalse);
    });

    test('computeDateGroups groups items by day in descending order', () {
      final nowSecs = DateTime(2026, 11, 4, 14, 30).millisecondsSinceEpoch ~/ 1000;
      final yesterdaySecs = DateTime(2026, 11, 3, 10, 0).millisecondsSinceEpoch ~/ 1000;
      final items = [
        RawEntry(name: 'photo1.jpg', sizeBytes: 1024, modifiedSecs: nowSecs, isDir: false),
        RawEntry(name: 'photo2.jpg', sizeBytes: 2048, modifiedSecs: nowSecs, isDir: false),
        RawEntry(name: 'photo3.jpg', sizeBytes: 4096, modifiedSecs: yesterdaySecs, isDir: false),
        RawEntry(name: 'photo4.jpg', sizeBytes: 512, modifiedSecs: 0, isDir: false),
      ];

      final groups = computeDateGroups(items);
      expect(groups.length, 3);
      expect(groups[0].items.length, 2);
      expect(groups[0].globalIndices, [0, 1]);
      expect(groups[1].items.length, 1);
      expect(groups[1].globalIndices, [2]);
      expect(groups[2].items.length, 1);
      expect(groups[2].date, isNull);
      expect(groups[2].globalIndices, [3]);
    });

    testWidgets('FileMasonryView with groupByDate scrolls past groups with single items without truncating', (tester) async {
      final container = MountedContainer(
        uri: 'content://test-vault',
        displayName: 'Test Vault',
        volId: 1,
        rootFiles: const [],
        mountedAt: DateTime(2026, 1, 1),
        totalSpace: 100000000,
        freeSpace: 50000000,
      );

      // Create groups mimicking the user's scenario:
      // Group 1 (day 10): 1 item
      // Group 2 (day 9): 3 items
      // Group 3 (day 8): 3 items
      // Group 4 (day 7): 10 items
      // Group 5 (day 6): 20 items
      final items = <RawEntry>[];
      final base = DateTime(2026, 10, 30, 12, 0);
      // Group 1: 1 item
      items.add(RawEntry(name: 'day10_0.jpg', isDir: false, sizeBytes: 100, modifiedSecs: base.millisecondsSinceEpoch ~/ 1000));
      // Group 2: 3 items
      final day9 = base.subtract(const Duration(days: 3));
      for (var i = 0; i < 3; i++) {
        items.add(RawEntry(name: 'day9_$i.jpg', isDir: false, sizeBytes: 100, modifiedSecs: day9.millisecondsSinceEpoch ~/ 1000));
      }
      // Group 3: 3 items
      final day8 = base.subtract(const Duration(days: 6));
      for (var i = 0; i < 3; i++) {
        items.add(RawEntry(name: 'day8_$i.jpg', isDir: false, sizeBytes: 100, modifiedSecs: day8.millisecondsSinceEpoch ~/ 1000));
      }
      // Group 4: 20 items
      final day7 = base.subtract(const Duration(days: 9));
      for (var i = 0; i < 20; i++) {
        items.add(RawEntry(name: 'day7_$i.jpg', isDir: false, sizeBytes: 100, modifiedSecs: day7.millisecondsSinceEpoch ~/ 1000));
      }

      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FileMasonryView(
                container: container,
                items: items,
                isSelectionMode: false,
                selectedItems: const {},
                currentDirPath: '',
                thumbnailCacheMode: ThumbnailCacheMode.disabled,
                thumbnailQuality: ThumbnailQuality.defaultQuality,
                initialColumns: 2,
                groupByDate: true,
                onDirTap: (_) {},
                onFileTap: (_) {},
                onItemLongPress: (_) {},
                scrollController: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialMax = controller.position.maxScrollExtent;
      expect(initialMax, greaterThan(200));

      // Scroll down by 500
      controller.jumpTo(500);
      await tester.pumpAndSettle();
      expect(controller.offset, equals(500));

      // Scroll all the way down
      final maxScroll = controller.position.maxScrollExtent;
      controller.jumpTo(maxScroll);
      await tester.pumpAndSettle();
      expect(controller.offset, equals(controller.position.maxScrollExtent));
      expect(controller.offset, greaterThan(500));
    });

    testWidgets('GalleryDateHeader text color in dark and light themes', (tester) async {
      final darkTheme = buildDarkTheme();
      final lightTheme = buildLightTheme();

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('dark_app'),
          theme: darkTheme,
          home: Scaffold(
            body: SkinAreaScope(
              key: const ValueKey('dark_scope'),
              area: SkinArea.files,
              child: const GalleryDateHeader(
                title: 'Friday, October 30',
                count: 1,
              ),
            ),
          ),
        ),
      );

      final darkTitleText = tester.widget<Text>(find.text('Friday, October 30'));
      expect(darkTitleText.style?.color, equals(Colors.white));

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('light_app'),
          theme: lightTheme,
          home: Scaffold(
            body: SkinAreaScope(
              key: const ValueKey('light_scope'),
              area: SkinArea.files,
              child: const GalleryDateHeader(
                title: 'Friday, October 30',
                count: 1,
              ),
            ),
          ),
        ),
      );

      final lightTitleText = tester.widget<Text>(find.text('Friday, October 30'));
      expect(lightTitleText.style?.color, equals(const Color(0xFF1F1F1F)));
    });
  });
}
