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
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MediaViewerToolbarSettingsScreen(),
    ),
  );
}

void main() {
  testWidgets(
      'renders Swipe to Seek setting toggle and toggles state on wide landscape layout',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
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
    await tester.scrollUntilVisible(
      finder,
      100.0,
      scrollable: find.byType(Scrollable).last,
    );
    expect(finder, findsOneWidget);

    final switchTile = tester.widget<SwitchListTile>(finder);
    expect(switchTile.value, isFalse);

    await tester.tap(find.text('Swipe to Seek'));
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

  testWidgets(
      'shows playback and advanced settings together on a wide layout',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
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

    final playbackSetting = find.widgetWithText(SwitchListTile, 'Swipe to Seek');
    await tester.scrollUntilVisible(
      playbackSetting,
      100.0,
      scrollable: find.byType(Scrollable).last,
    );
    expect(playbackSetting, findsOneWidget);

    final advancedSetting = find.widgetWithText(
      SwitchListTile,
      'Enable volume boost',
    );
    await tester.scrollUntilVisible(
      advancedSetting,
      100.0,
      scrollable: find.byType(Scrollable).last,
    );
    expect(advancedSetting, findsOneWidget);
    expect(find.text('Thumbnail Generation'), findsOneWidget);
  });

  testWidgets(
      'renders the consolidated settings screen directly on a narrow layout',
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

    await tester.pumpWidget(_buildTestApp(container: container));
    await tester.pumpAndSettle();

    expect(find.text('Media Player Controls'), findsOneWidget);
    final finder = find.widgetWithText(SwitchListTile, 'Swipe to Seek');
    await tester.scrollUntilVisible(
      finder,
      100.0,
      scrollable: find.byType(Scrollable).last,
    );
    expect(finder, findsOneWidget);
  });

  testWidgets('filters settings with instant search', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
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

    expect(find.widgetWithText(SwitchListTile, 'Brightness Swipe Gesture'),
        findsOneWidget);
  });
}
