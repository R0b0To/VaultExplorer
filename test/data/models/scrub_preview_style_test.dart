import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';

void main() {
  group('ScrubPreviewStyle JSON', () {
    test('round-trips every value', () {
      for (final style in ScrubPreviewStyle.values) {
        expect(ScrubPreviewStyle.fromJson(style.toJson()), style);
      }
    });

    test('missing or unrecognised values fall back to the mini box', () {
      // A settings file from before this option existed, or from a newer
      // build that has a style this one doesn't know.
      expect(ScrubPreviewStyle.fromJson(null), ScrubPreviewStyle.miniBox);
      expect(ScrubPreviewStyle.fromJson(''), ScrubPreviewStyle.miniBox);
      expect(ScrubPreviewStyle.fromJson('hologram'), ScrubPreviewStyle.miniBox);
    });
  });

  group('MediaViewerToolbarConfig.scrubPreviewStyle', () {
    test('defaults to the mini box, i.e. the pre-existing behaviour', () {
      expect(
        MediaViewerToolbarConfig.defaults().scrubPreviewStyle,
        ScrubPreviewStyle.miniBox,
      );
    });

    test('copyWith changes only the style', () {
      const before = MediaViewerToolbarConfig(showProgressBar: false);
      final after = before.copyWith(scrubPreviewStyle: ScrubPreviewStyle.fullscreen);

      expect(after.scrubPreviewStyle, ScrubPreviewStyle.fullscreen);
      expect(after.showProgressBar, isFalse);
      expect(after.bottomBarActions, before.bottomBarActions);
      // ...and leaves it alone when not asked to change it.
      expect(after.copyWith(showStatusBadge: false).scrubPreviewStyle,
          ScrubPreviewStyle.fullscreen);
    });

    test('survives a toJson/fromJson round trip', () {
      final config = const MediaViewerToolbarConfig()
          .copyWith(scrubPreviewStyle: ScrubPreviewStyle.fullscreen);

      final restored = MediaViewerToolbarConfig.fromJson(config.toJson());

      expect(restored.scrubPreviewStyle, ScrubPreviewStyle.fullscreen);
    });

    test('a config saved before the option existed loads as the mini box', () {
      final legacy = const MediaViewerToolbarConfig().toJson()
        ..remove('scrubPreviewStyle');

      expect(
        MediaViewerToolbarConfig.fromJson(legacy).scrubPreviewStyle,
        ScrubPreviewStyle.miniBox,
      );
    });

    test('is persisted through the enclosing FileManagerToolbarConfig', () {
      // The settings backup/restore path serialises the whole file-manager
      // config, so the style has to make it through that wrapper too.
      final config = FileManagerToolbarConfig.defaults().copyWith(
        mediaViewerToolbarConfig: const MediaViewerToolbarConfig(
          scrubPreviewStyle: ScrubPreviewStyle.fullscreen,
        ),
      );

      final restored = FileManagerToolbarConfig.fromJson(config.toJson());

      expect(
        restored.mediaViewerToolbarConfig.scrubPreviewStyle,
        ScrubPreviewStyle.fullscreen,
      );
    });
  });
}
