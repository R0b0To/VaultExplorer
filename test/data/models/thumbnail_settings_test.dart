import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';

void main() {
  group('ThumbnailSettings', () {
    test('defaults are the out-of-the-box mode and quality', () {
      expect(ThumbnailSettings.defaults.cacheMode, ThumbnailCacheMode.disabled);
      expect(ThumbnailSettings.defaults.quality, ThumbnailQuality.defaultQuality);
    });

    test('equality and hashCode compare both fields', () {
      const a = ThumbnailSettings(
        cacheMode: ThumbnailCacheMode.appCache,
        quality: ThumbnailQuality(quality: 70, size: 200),
      );
      const same = ThumbnailSettings(
        cacheMode: ThumbnailCacheMode.appCache,
        quality: ThumbnailQuality(quality: 70, size: 200),
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a == a.copyWith(cacheMode: ThumbnailCacheMode.inContainer), isFalse);
      expect(
        a == a.copyWith(quality: const ThumbnailQuality(quality: 71, size: 200)),
        isFalse,
      );
    });

    test('copyWith replaces only what is given', () {
      const base = ThumbnailSettings.defaults;
      final changed = base.copyWith(cacheMode: ThumbnailCacheMode.appCache);
      expect(changed.cacheMode, ThumbnailCacheMode.appCache);
      expect(changed.quality, base.quality);
    });
  });
}
