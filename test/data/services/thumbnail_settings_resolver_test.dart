import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/thumbnail_settings_resolver.dart';

void main() {
  const globalQuality = ThumbnailQuality(quality: 60, size: 150);
  const localQuality = ThumbnailQuality(quality: 95, size: 320);
  const vaultQuality = ThumbnailQuality(quality: 90, size: 280);

  // Three different values so a test can tell which scope answered.
  final config = FileManagerToolbarConfig.defaults().copyWith(
    defaultThumbnailCacheMode: ThumbnailCacheMode.appCache,
    defaultThumbnailQuality: globalQuality,
    localStorageThumbnailCacheMode: ThumbnailCacheMode.inContainer,
    localStorageThumbnailQuality: localQuality,
  );

  const follower = ContainerRecord(uri: 'file:///a.hc', label: 'A');
  const custom = ContainerRecord(
    uri: 'file:///b.hc',
    label: 'B',
    thumbnailCacheMode: ThumbnailCacheMode.disabled,
    thumbnailQuality: vaultQuality,
  );

  group('resolveThumbnailSettings', () {
    test('a vault that follows the default gets the global values', () {
      final r = resolveThumbnailSettings(
        config: config,
        isLocalStorage: false,
        record: follower,
      );
      expect(r.cacheMode, ThumbnailCacheMode.appCache);
      expect(r.quality, globalQuality);
    });

    test('a vault with no record at all also follows the default', () {
      final r = resolveThumbnailSettings(config: config, isLocalStorage: false);
      expect(r.cacheMode, ThumbnailCacheMode.appCache);
      expect(r.quality, globalQuality);
    });

    test('a vault with its own settings ignores the global values', () {
      final r = resolveThumbnailSettings(
        config: config,
        isLocalStorage: false,
        record: custom,
      );
      expect(r.cacheMode, ThumbnailCacheMode.disabled);
      expect(r.quality, vaultQuality);
    });

    test('changing the default reaches a following vault but not a custom one', () {
      final changed = config.copyWith(
        defaultThumbnailCacheMode: ThumbnailCacheMode.inContainer,
      );
      expect(
        resolveThumbnailSettings(
          config: changed,
          isLocalStorage: false,
          record: follower,
        ).cacheMode,
        ThumbnailCacheMode.inContainer,
      );
      expect(
        resolveThumbnailSettings(
          config: changed,
          isLocalStorage: false,
          record: custom,
        ).cacheMode,
        ThumbnailCacheMode.disabled,
      );
    });

    test('a record that predates quality keeps its mode, takes the global quality', () {
      const modeOnly = ContainerRecord(
        uri: 'file:///c.hc',
        label: 'C',
        thumbnailCacheMode: ThumbnailCacheMode.disabled,
      );
      final r = resolveThumbnailSettings(
        config: config,
        isLocalStorage: false,
        record: modeOnly,
      );
      expect(r.cacheMode, ThumbnailCacheMode.disabled);
      expect(r.quality, globalQuality);
    });

    test('Local Storage and the decoy use the shared slot, never the vault default', () {
      final r = resolveThumbnailSettings(config: config, isLocalStorage: true);
      expect(r.cacheMode, ThumbnailCacheMode.inContainer);
      expect(r.quality, localQuality);

      // Even a stray record cannot pull Local Storage off its own slot.
      final withRecord = resolveThumbnailSettings(
        config: config,
        isLocalStorage: true,
        record: custom,
      );
      expect(withRecord.cacheMode, ThumbnailCacheMode.inContainer);
      expect(withRecord.quality, localQuality);
    });

    test('an explicit override wins, each half independently', () {
      final r = resolveThumbnailSettings(
        config: config,
        isLocalStorage: false,
        record: custom,
        overrideCacheMode: ThumbnailCacheMode.inContainer,
      );
      expect(r.cacheMode, ThumbnailCacheMode.inContainer);
      expect(r.quality, vaultQuality);

      final q = resolveThumbnailSettings(
        config: config,
        isLocalStorage: true,
        overrideQuality: globalQuality,
      );
      expect(q.cacheMode, ThumbnailCacheMode.inContainer);
      expect(q.quality, globalQuality);
    });
  });
}
