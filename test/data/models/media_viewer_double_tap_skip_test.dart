import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';

void main() {
  group('MediaViewerToolbarConfig double-tap skip', () {
    test('is on and skips 5 seconds by default', () {
      const config = MediaViewerToolbarConfig();
      expect(config.doubleTapSkipEnabled, isTrue);
      expect(config.doubleTapSkipSeconds, 5);
      expect(MediaViewerToolbarConfig.defaults().doubleTapSkipSeconds, 5);
    });

    test('the offered skip times include the default and are ascending', () {
      const options = MediaViewerToolbarConfig.doubleTapSkipOptions;
      expect(options, contains(5));
      expect([...options]..sort(), options);
    });

    test('copyWith updates each setting independently', () {
      final config = MediaViewerToolbarConfig.defaults();
      final off = config.copyWith(doubleTapSkipEnabled: false);
      expect(off.doubleTapSkipEnabled, isFalse);
      expect(off.doubleTapSkipSeconds, 5);

      final ten = off.copyWith(doubleTapSkipSeconds: 10);
      expect(ten.doubleTapSkipEnabled, isFalse);
      expect(ten.doubleTapSkipSeconds, 10);
    });

    test('round-trips through JSON', () {
      final restored = MediaViewerToolbarConfig.fromJson(
        MediaViewerToolbarConfig.defaults()
            .copyWith(doubleTapSkipEnabled: false, doubleTapSkipSeconds: 30)
            .toJson(),
      );
      expect(restored.doubleTapSkipEnabled, isFalse);
      expect(restored.doubleTapSkipSeconds, 30);
    });

    test('a config saved before the setting existed keeps the old behavior', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
      });
      expect(parsed.doubleTapSkipEnabled, isTrue);
      expect(parsed.doubleTapSkipSeconds, 5);
    });

    test('an out-of-range saved skip time is clamped', () {
      MediaViewerToolbarConfig parse(num seconds) =>
          MediaViewerToolbarConfig.fromJson({'doubleTapSkipSeconds': seconds});
      expect(parse(0).doubleTapSkipSeconds, 1);
      expect(parse(-20).doubleTapSkipSeconds, 1);
      expect(parse(100000).doubleTapSkipSeconds, 600);
      expect(parse(12.0).doubleTapSkipSeconds, 12);
    });
  });
}
