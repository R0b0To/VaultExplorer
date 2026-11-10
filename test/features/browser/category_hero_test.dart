import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/file_grid_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_masonry_view.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  final container = MountedContainer(
    volId: 42,
    displayName: 'Test Storage',
    uri: '/storage/test',
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 100000000,
    freeSpace: 50000000,
  );

  final nestedPhoto = CategoryEntry(
    name: 'Camera/IMG_001.jpg',
    sourceVolId: 42,
    path: 'DCIM/Camera/IMG_001.jpg',
    isDir: false,
    sizeBytes: 1024,
    modifiedSecs: 1000,
  );

  testWidgets('FileGridView uses CategoryEntry.path for Hero tag and executes flight',
      (tester) async {
    late BuildContext savedContext;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return SizedBox(
                  width: 500,
                  height: 500,
                  child: FileGridView(
                    container: container,
                    containerFor: (e) => container,
                    items: [nestedPhoto],
                    isSelectionMode: false,
                    selectedItems: const {},
                    currentDirPath: '',
                    thumbnailCacheMode: ThumbnailCacheMode.disabled,
                    thumbnailQuality: ThumbnailQuality.defaultQuality,
                    onDirTap: (_) {},
                    onFileTap: (_) {},
                    onItemLongPress: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gridHero = tester.widget<Hero>(find.byType(Hero));
    expect(gridHero.tag, equals('media_hero_42_DCIM/Camera/IMG_001.jpg'));

    Navigator.push(
      savedContext,
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => MediaViewerScreen(
          container: container,
          mediaFiles: [nestedPhoto.path],
          initialIndex: 0,
          thumbnailCacheMode: ThumbnailCacheMode.disabled,
          thumbnailQuality: ThumbnailQuality.defaultQuality,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Pop MediaViewerScreen
    Navigator.of(savedContext).pop();
    await tester.pump(); // Start reverse transition

    final heroesDuringPop = tester.widgetList<Hero>(find.byType(Hero)).toList();
    expect(heroesDuringPop.length, greaterThanOrEqualTo(2));
    for (final h in heroesDuringPop) {
      expect(h.tag, equals('media_hero_42_DCIM/Camera/IMG_001.jpg'));
    }

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 50));
  });

  testWidgets('FileMasonryView uses CategoryEntry.path for Hero tag and executes flight',
      (tester) async {
    late BuildContext savedContext;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return SizedBox(
                  width: 500,
                  height: 500,
                  child: FileMasonryView(
                    container: container,
                    containerFor: (e) => container,
                    items: [nestedPhoto],
                    isSelectionMode: false,
                    selectedItems: const {},
                    currentDirPath: '',
                    thumbnailCacheMode: ThumbnailCacheMode.disabled,
                    thumbnailQuality: ThumbnailQuality.defaultQuality,
                    onDirTap: (_) {},
                    onFileTap: (_) {},
                    onItemLongPress: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    // Allow masonry initial timeout/render
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final masonryHero = tester.widget<Hero>(find.byType(Hero));
    expect(masonryHero.tag, equals('media_hero_42_DCIM/Camera/IMG_001.jpg'));

    Navigator.push(
      savedContext,
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => MediaViewerScreen(
          container: container,
          mediaFiles: [nestedPhoto.path],
          initialIndex: 0,
          thumbnailCacheMode: ThumbnailCacheMode.disabled,
          thumbnailQuality: ThumbnailQuality.defaultQuality,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Pop MediaViewerScreen
    Navigator.of(savedContext).pop();
    await tester.pump();

    final heroesDuringPop = tester.widgetList<Hero>(find.byType(Hero)).toList();
    expect(heroesDuringPop.length, greaterThanOrEqualTo(2));
    for (final h in heroesDuringPop) {
      expect(h.tag, equals('media_hero_42_DCIM/Camera/IMG_001.jpg'));
    }

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 50));
  });

  testWidgets('FileListView uses CategoryEntry.path for Hero tag and executes flight',
      (tester) async {
    late BuildContext savedContext;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return SizedBox(
                  width: 500,
                  height: 500,
                  child: FileListView(
                    container: container,
                    containerFor: (e) => container,
                    items: [nestedPhoto],
                    isSelectionMode: false,
                    selectedItems: const {},
                    currentDirPath: '',
                    showThumbnails: true,
                    thumbnailCacheMode: ThumbnailCacheMode.disabled,
                    thumbnailQuality: ThumbnailQuality.defaultQuality,
                    onDirTap: (_) {},
                    onFileTap: (_) {},
                    onItemLongPress: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listHero = tester.widget<Hero>(find.byType(Hero));
    expect(listHero.tag, equals('media_hero_42_DCIM/Camera/IMG_001.jpg'));

    Navigator.push(
      savedContext,
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => MediaViewerScreen(
          container: container,
          mediaFiles: [nestedPhoto.path],
          initialIndex: 0,
          thumbnailCacheMode: ThumbnailCacheMode.disabled,
          thumbnailQuality: ThumbnailQuality.defaultQuality,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Pop MediaViewerScreen
    Navigator.of(savedContext).pop();
    await tester.pump();

    final heroesDuringPop = tester.widgetList<Hero>(find.byType(Hero)).toList();
    expect(heroesDuringPop.length, greaterThanOrEqualTo(2));
    for (final h in heroesDuringPop) {
      expect(h.tag, equals('media_hero_42_DCIM/Camera/IMG_001.jpg'));
    }

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 50));
  });
}
