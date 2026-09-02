import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

void main() {
  group('FileManagerToolbarConfig autoStartPlaylistMode', () {
    test('defaults to false in defaults() factory', () {
      final config = FileManagerToolbarConfig.defaults();
      expect(config.autoStartPlaylistMode, isTrue);
    });

    test('defaults to false when unassigned in constructor', () {
      final config = const FileManagerToolbarConfig(
        order: [],
        hidden: {},
      );
      expect(config.autoStartPlaylistMode, isTrue);
    });

    test('copyWith updates autoStartPlaylistMode', () {
      final config = FileManagerToolbarConfig.defaults();
      final updated = config.copyWith(autoStartPlaylistMode: true);
      expect(updated.autoStartPlaylistMode, isTrue);

      final reset = updated.copyWith(autoStartPlaylistMode: false);
      expect(reset.autoStartPlaylistMode, isFalse);
    });

    test('serializes and deserializes autoStartPlaylistMode correctly in JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        autoStartPlaylistMode: true,
      );
      final json = config.toJson();
      expect(json['autoStartPlaylistMode'], isTrue);

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.autoStartPlaylistMode, isTrue);
    });

    test('fromJson falls back to false when key is missing', () {
      final json = <String, dynamic>{
        'showBreadcrumbBar': true,
      };
      final config = FileManagerToolbarConfig.fromJson(json);
      expect(config.autoStartPlaylistMode, isTrue);
    });
  });

  group('FileManagerToolbarConfig thumbnail settings', () {
    test('defaults in defaults() factory and constructor', () {
      final def = FileManagerToolbarConfig.defaults();
      expect(def.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(def.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);

      const unassigned = FileManagerToolbarConfig(order: [], hidden: {});
      expect(unassigned.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(unassigned.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);
    });

    test('copyWith updates thumbnail settings', () {
      final config = FileManagerToolbarConfig.defaults();
      final updated = config.copyWith(
        defaultThumbnailCacheMode: ThumbnailCacheMode.inContainer,
        defaultThumbnailQuality: const ThumbnailQuality(quality: 85, size: 240),
      );
      expect(updated.defaultThumbnailCacheMode, ThumbnailCacheMode.inContainer);
      expect(updated.defaultThumbnailQuality.quality, 85);
      expect(updated.defaultThumbnailQuality.size, 240);
    });

    test('serializes and deserializes correctly in JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        defaultThumbnailCacheMode: ThumbnailCacheMode.appCache,
        defaultThumbnailQuality: const ThumbnailQuality(quality: 70, size: 300),
      );
      final json = config.toJson();
      expect(json['defaultThumbnailCacheMode'], 'appCache');
      expect(json['defaultThumbnailQuality'], {'quality': 70, 'size': 300});

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.defaultThumbnailCacheMode, ThumbnailCacheMode.appCache);
      expect(restored.defaultThumbnailQuality.quality, 70);
      expect(restored.defaultThumbnailQuality.size, 300);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final config = FileManagerToolbarConfig.fromJson({});
      expect(config.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(config.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);
    });
  });
}
