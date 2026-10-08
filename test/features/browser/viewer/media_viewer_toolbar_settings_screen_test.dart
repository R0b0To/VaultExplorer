import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_toolbar_settings_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

class _FakeFileManagerToolbarService extends FileManagerToolbarService {
  FileManagerToolbarConfig _config = FileManagerToolbarConfig.defaults();

  @override
  Future<FileManagerToolbarConfig> load() async => _config;

  @override
  Future<void> save(FileManagerToolbarConfig config) async {
    _config = config;
  }
}

Widget _buildTestApp({
  required ProviderContainer container,
  int initialTab = 0,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaViewerToolbarSettingsScreen(initialTab: initialTab),
    ),
  );
}

void main() {
  testWidgets('renders Swipe to Seek setting toggle and toggles state on Tab 0',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeService = _FakeFileManagerToolbarService();
    final container = ProviderContainer(
      overrides: [
        fileManagerToolbarServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildTestApp(container: container));
    await tester.pumpAndSettle();

    final finder = find.widgetWithText(SwitchListTile, 'Swipe to Seek');
    expect(finder, findsOneWidget);

    final switchTile = tester.widget<SwitchListTile>(finder);
    expect(switchTile.value, isFalse);

    await tester.tap(finder);
    await tester.pumpAndSettle();

    final updatedTile = tester.widget<SwitchListTile>(finder);
    expect(updatedTile.value, isTrue);
    expect(
      container
          .read(fileManagerToolbarSettingsProvider(null))
          .config
          .mediaViewerToolbarConfig
          .swipeToSeekEnabled,
      isTrue,
    );
  });

  testWidgets('switches between tabs and displays Toolbar Layout & Mockup',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeService = _FakeFileManagerToolbarService();
    final container = ProviderContainer(
      overrides: [
        fileManagerToolbarServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildTestApp(container: container));
    await tester.pumpAndSettle();

    // Tab 1: Toolbar Layout
    final toolbarTab = find.text('Toolbar Layout');
    expect(toolbarTab, findsOneWidget);
    await tester.tap(toolbarTab);
    await tester.pumpAndSettle();

    // Mockup and section headers should be visible
    expect(find.text('video_01.mp4'), findsOneWidget);
    expect(find.textContaining('All Sections'), findsOneWidget);
    expect(find.text('Top Bar Actions'), findsWidgets);

    // Tab 2: Advanced Options
    final advancedTab = find.text('Advanced Options');
    expect(advancedTab, findsOneWidget);
    await tester.tap(advancedTab);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SwitchListTile, 'Enable volume boost'), findsOneWidget);
    expect(find.text('Thumbnail Generation'), findsOneWidget);
  });

  testWidgets('opens directly to Toolbar Layout tab when initialTab is 1',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeService = _FakeFileManagerToolbarService();
    final container = ProviderContainer(
      overrides: [
        fileManagerToolbarServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildTestApp(container: container, initialTab: 1));
    await tester.pumpAndSettle();

    // Should immediately display the Toolbar mockup on Tab 1
    expect(find.text('video_01.mp4'), findsOneWidget);

    // Tap on Top Bar filter chip
    final topBarChip = find.widgetWithText(FilterChip, 'Top Bar Actions (2)');
    expect(topBarChip, findsOneWidget);
    await tester.ensureVisible(topBarChip);
    await tester.tap(topBarChip);
    await tester.pumpAndSettle();

    // Scroll down to reveal availableToAdd
    final addButton = find.byTooltip('Add').first;
    await tester.scrollUntilVisible(
      addButton,
      100.0,
      scrollable: find.byType(Scrollable).first,
    );
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
  });

  testWidgets('filters settings with instant search', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeService = _FakeFileManagerToolbarService();
    final container = ProviderContainer(
      overrides: [
        fileManagerToolbarServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildTestApp(container: container));
    await tester.pumpAndSettle();

    // Tap search button
    final searchButton = find.byTooltip('Search settings');
    expect(searchButton, findsOneWidget);
    await tester.tap(searchButton);
    await tester.pumpAndSettle();

    // Enter query in search textfield
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'brightness');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SwitchListTile, 'Brightness Swipe Gesture'), findsOneWidget);
  });
}
