import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ProviderSubscription subscription;
  final provider = fileManagerToolbarSettingsProvider(null);

  setUp(() {
    container = ProviderContainer();
    subscription = container.listen(provider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  group('FileManagerToolbarSettingsController Tests', () {
    test('initializes and loads toolbar config state', () async {
      final controller = container.read(provider.notifier);
      await controller.load(null);

      final state = container.read(provider);
      expect(state.loading, isFalse);
      expect(state.config, isA<FileManagerToolbarConfig>());
    });

    test('switch mutators update config state', () async {
      final controller = container.read(provider.notifier);
      await controller.load(null);

      await controller.setShowHiddenFiles(true);
      expect(container.read(provider).config.showHiddenFiles, isTrue);

      await controller.setShowBreadcrumbBar(false);
      expect(container.read(provider).config.showBreadcrumbBar, isFalse);

      expect(container.read(provider).config.selectByIcon, isTrue);
      await controller.setSelectByIcon(false);
      expect(container.read(provider).config.selectByIcon, isFalse);

      expect(container.read(provider).config.showFileExtensions, isTrue);
      await controller.setShowFileExtensions(false);
      expect(container.read(provider).config.showFileExtensions, isFalse);

      await controller.setPlaylistTransitionEffect(PlaylistTransitionEffect.fade);
      expect(container.read(provider).config.playlistTransitionEffect, PlaylistTransitionEffect.fade);

      await controller.setDefaultThumbnailCacheMode(ThumbnailCacheMode.inContainer);
      expect(container.read(provider).config.defaultThumbnailCacheMode, ThumbnailCacheMode.inContainer);

      await controller.setDefaultThumbnailQuality(const ThumbnailQuality(quality: 80, size: 240));
      expect(container.read(provider).config.defaultThumbnailQuality.quality, 80);
      expect(container.read(provider).config.defaultThumbnailQuality.size, 240);
    });

    test('toggleActionVisible hides and reveals actions', () async {
      final controller = container.read(provider.notifier);
      await controller.load(null);

      await controller.toggleActionVisible(FileManagerAction.search, false);
      expect(container.read(provider).config.hidden, contains(FileManagerAction.search));

      await controller.toggleActionVisible(FileManagerAction.search, true);
      expect(container.read(provider).config.hidden, isNot(contains(FileManagerAction.search)));
    });

    test('setSkin updates the skin and leaves other settings alone', () async {
      final controller = container.read(provider.notifier);
      await controller.load(null);

      await controller.setShowHiddenFiles(true);
      await controller.setSkin(SkinPreset.minimalOutline.skin);

      final config = container.read(provider).config;
      expect(config.skin, SkinPreset.minimalOutline.skin);
      expect(config.showHiddenFiles, isTrue);

      // Tweaking one option makes it a custom skin rather than a preset.
      final tweaked = config.skin.copyWith(monospaceNames: true);
      await controller.setSkin(tweaked);
      expect(container.read(provider).config.skin, tweaked);
      expect(container.read(provider).config.skin.matchingPreset, isNull);

      await controller.setSkin(FileManagerSkin.classic);
      expect(container.read(provider).config.skin, FileManagerSkin.classic);
    });

    test('toggleDetailColumnVisible hides and reveals detail columns', () async {
      final controller = container.read(provider.notifier);
      await controller.load(null);

      await controller.toggleDetailColumnVisible(FileDetailColumn.size, false);
      expect(container.read(provider).config.hiddenDetailColumns, contains(FileDetailColumn.size));

      await controller.toggleDetailColumnVisible(FileDetailColumn.size, true);
      expect(container.read(provider).config.hiddenDetailColumns, isNot(contains(FileDetailColumn.size)));
    });

    test('setMediaViewerSwipeToSeekEnabled updates mediaViewerToolbarConfig', () async {
      final controller = container.read(provider.notifier);
      await controller.load(null);

      expect(container.read(provider).config.mediaViewerToolbarConfig.swipeToSeekEnabled, isFalse);

      await controller.setMediaViewerSwipeToSeekEnabled(true);
      expect(container.read(provider).config.mediaViewerToolbarConfig.swipeToSeekEnabled, isTrue);

      await controller.setMediaViewerSwipeToSeekEnabled(false);
      expect(container.read(provider).config.mediaViewerToolbarConfig.swipeToSeekEnabled, isFalse);
    });
  });
}