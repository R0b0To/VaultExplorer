import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

class _FakeAppSettingsService extends AppSettingsService {
  @override
  Future<AppSettings> loadSettings() async => AppSettings();
}

class _FakeContainerRepository implements ContainerRepository {
  @override
  Future<Map<String, ContainerRecord>> loadAll() async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileManagerToolbarService extends FileManagerToolbarService {
  @override
  Future<FileManagerToolbarConfig> load() async => FileManagerToolbarConfig.defaults();
}

MountedContainer _testContainer(int volId) => MountedContainer(
      volId: volId,
      uri: 'file:///vault$volId.hc',
      displayName: 'Vault $volId',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engineChannel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  List<String> dirListing = <String>[];

  setUp(() {
    dirListing = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (call) async {
      switch (call.method) {
        case 'listDirectory':
          return dirListing;
        case 'getSpaceInfo':
          return <int>[1000000, 500000];
        case 'getFreeSpace':
          return 500000;
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async {
      return '/test/path';
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.aeidolon.vaultexplorer/disguise_channel'), (call) async {
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.aeidolon.vaultexplorer/disguise_channel'), null);
  });

  Widget buildTestScreen(MountedContainer container) {
    return ProviderScope(
      overrides: [
        appSettingsServiceProvider.overrideWithValue(_FakeAppSettingsService()),
        containerRepositoryProvider.overrideWithValue(_FakeContainerRepository()),
        fileManagerToolbarServiceProvider.overrideWithValue(_FakeFileManagerToolbarService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FileBrowserScreen(
          container: container,
        ),
      ),
    );
  }

  testWidgets('App bar starts fully visible and expanded', (tester) async {
    final container = _testContainer(1);
    await tester.pumpWidget(buildTestScreen(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // App bar should be present in the widget tree with heightFactor 1.0
    final alignFinder = find.byKey(const Key('browser_app_bar_align'));
    expect(alignFinder, findsOneWidget);

    final Align align = tester.widget(alignFinder);
    expect(align.heightFactor, 1.0);
    expect(align.alignment, Alignment.bottomCenter);
  });

  testWidgets('Scrolling down collapses app bar and scrolling up reveals it', (tester) async {
    // Generate 60 entries so list is long and scrollable
    dirListing = List.generate(60, (i) => 'F|1024|1700000000|file_$i.txt');
    final container = _testContainer(2);

    await tester.pumpWidget(buildTestScreen(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final alignFinder = find.byKey(const Key('browser_app_bar_align'));
    // Verify initial state is fully expanded (1.0)
    expect(alignFinder, findsOneWidget);
    Align align = tester.widget(alignFinder);
    expect(align.heightFactor, 1.0);

    // Dispatch downward scroll (user scrolling down, list offset increases)
    final verticalListFinder = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    expect(verticalListFinder, findsOneWidget);
    await tester.drag(verticalListFinder, const Offset(0, -300));
    await tester.pump(); // Start collapse animation
    await tester.pump(const Duration(milliseconds: 250)); // Finish 200ms collapse animation

    // App bar should now be collapsed (either factor 0.0 with SizedBox.shrink, or <0.1)
    if (alignFinder.evaluate().isNotEmpty) {
      final Align collapsedAlign = tester.widget(alignFinder);
      expect(collapsedAlign.heightFactor, lessThan(0.1));
    } else {
      expect(alignFinder, findsNothing);
    }

    // Now scroll back up (drag downwards to move offset up)
    await tester.drag(verticalListFinder, const Offset(0, 150));
    await tester.pump(); // Start reveal animation
    await tester.pump(const Duration(milliseconds: 250)); // Finish 200ms expand animation

    // App bar should now be expanded again (heightFactor 1.0)
    expect(alignFinder, findsOneWidget);
    align = tester.widget(alignFinder);
    expect(align.heightFactor, 1.0);
  });

  testWidgets('App bar collapses when user scrolls down in folder with few items, and reveals when scrolling up', (tester) async {
    // Only 2 items - fits on screen, maxScrollExtent is 0
    dirListing = List.generate(2, (i) => 'F|1024|1700000000|file_$i.txt');
    final container = _testContainer(4);

    await tester.pumpWidget(buildTestScreen(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final alignFinder = find.byKey(const Key('browser_app_bar_align'));
    expect(alignFinder, findsOneWidget);

    // Try to drag up (scroll down)
    final verticalListFinder = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    expect(verticalListFinder, findsOneWidget);
    await tester.drag(verticalListFinder, const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // App bar should collapse even on short content
    if (alignFinder.evaluate().isNotEmpty) {
      final Align collapsedAlign = tester.widget(alignFinder);
      expect(collapsedAlign.heightFactor, lessThan(0.1));
    } else {
      expect(alignFinder, findsNothing);
    }

    // Now drag downwards (scroll up) - conscious action by user
    await tester.drag(verticalListFinder, const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // App bar should be revealed again
    expect(alignFinder, findsOneWidget);
    final Align align = tester.widget(alignFinder);
    expect(align.heightFactor, 1.0);
  });

  testWidgets('Selecting an item when app bar is collapsed overlays selection bar without shifting contents', (tester) async {
    dirListing = List.generate(60, (i) => 'F|1024|1700000000|file_$i.txt');
    final container = _testContainer(5);

    await tester.pumpWidget(buildTestScreen(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final alignFinder = find.byKey(const Key('browser_app_bar_align'));
    expect(alignFinder, findsOneWidget);

    // Scroll down to collapse
    final verticalListFinder = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalListFinder, const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(alignFinder, findsNothing);

    // Record position of the first visible file tile before selection
    final fileTileFinder = find.byType(FileTile).first;
    final Offset posBefore = tester.getTopLeft(fileTileFinder);

    // Long press on a file tile to enter selection mode
    await tester.longPress(fileTileFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Selection app bar must be displayed as an overlay
    final overlayFinder = find.byKey(const Key('browser_selection_app_bar_overlay'));
    expect(overlayFinder, findsOneWidget);

    // Normal app bar slot in the Column did NOT expand (stays collapsed)
    expect(alignFinder, findsNothing);

    // Content must NOT have shifted down (zero layout shift!)
    final Offset posAfter = tester.getTopLeft(fileTileFinder);
    expect(posAfter.dy, equals(posBefore.dy));

    // Exit selection mode via the close button
    final closeFinder = find.byIcon(Icons.close_rounded);
    expect(closeFinder, findsOneWidget);
    await tester.tap(closeFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Overlay is gone
    expect(overlayFinder, findsNothing);

    // Content still did not shift
    expect(tester.getTopLeft(fileTileFinder).dy, equals(posBefore.dy));
  });

  testWidgets('Selecting an item when app bar is visible overlays selection bar without shifting contents', (tester) async {
    dirListing = List.generate(60, (i) => 'F|1024|1700000000|file_$i.txt');
    final container = _testContainer(7);

    await tester.pumpWidget(buildTestScreen(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final alignFinder = find.byKey(const Key('browser_app_bar_align'));
    expect(alignFinder, findsOneWidget);

    final fileTileFinder = find.byType(FileTile).first;
    final Offset posBefore = tester.getTopLeft(fileTileFinder);

    // Long press to enter selection mode while app bar is visible
    await tester.longPress(fileTileFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Overlay selection bar appears
    final overlayFinder = find.byKey(const Key('browser_selection_app_bar_overlay'));
    expect(overlayFinder, findsOneWidget);

    // Position of file tile did not shift
    expect(tester.getTopLeft(fileTileFinder).dy, equals(posBefore.dy));

    // Exit selection mode
    final closeFinder = find.byIcon(Icons.close_rounded);
    await tester.tap(closeFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Overlay is gone, normal app bar is still visible
    expect(overlayFinder, findsNothing);
    expect(alignFinder, findsOneWidget);
    expect(tester.getTopLeft(fileTileFinder).dy, equals(posBefore.dy));
  });

  testWidgets('Navigating to child folder preserves collapsed app bar state', (tester) async {
    // Top-level has 1 folder 'subfolder' and some files
    dirListing = [
      'D|0|1700000000|subfolder',
      'F|1024|1700000000|file_1.txt',
      'F|1024|1700000000|file_2.txt',
    ];
    final container = _testContainer(6);

    await tester.pumpWidget(buildTestScreen(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final alignFinder = find.byKey(const Key('browser_app_bar_align'));
    expect(alignFinder, findsOneWidget);

    // Scroll down to collapse app bar
    final verticalListFinder = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalListFinder, const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(alignFinder, findsNothing);

    // Tap subfolder to navigate into it
    dirListing = [
      'F|1024|1700000000|child_file.txt',
    ];
    final folderFinder = find.text('subfolder');
    expect(folderFinder, findsOneWidget);
    await tester.tap(folderFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // App bar must STILL be collapsed (not reset to visible!)
    expect(alignFinder, findsNothing);

    // Navigate back to root via breadcrumb home button
    final homeFinder = find.byIcon(Icons.home_outlined);
    expect(homeFinder, findsOneWidget);
    await tester.tap(homeFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // App bar must STILL be collapsed after returning to parent folder
    expect(alignFinder, findsNothing);

    // Conscious action: user scrolls up to reveal it
    await tester.drag(verticalListFinder, const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // App bar is now revealed
    expect(alignFinder, findsOneWidget);
    final Align align = tester.widget(alignFinder);
    expect(align.heightFactor, 1.0);
  });
}
