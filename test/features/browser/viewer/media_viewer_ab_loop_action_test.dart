import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('MediaViewerAction.abLoop', () {
    test('has an icon of its own, distinct from the playback mode button', () {
      expect(MediaViewerAction.abLoop.icon, Icons.repeat_on_rounded);
      expect(
        MediaViewerAction.abLoop.icon,
        isNot(MediaViewerAction.playbackMode.icon),
      );
    });

    test('has an English label', () {
      expect(
        MediaViewerAction.abLoop.getLocalizedLabel(AppLocalizationsEn()),
        'A-B repeat',
      );
    });

    test('applies to video and audio but not images', () {
      bool applicable({required bool isImage, required bool isAudio}) =>
          MediaViewerAction.abLoop.isApplicable(
            isImage: isImage,
            isAudio: isAudio,
            isPlaylistMode: false,
          );
      expect(applicable(isImage: false, isAudio: false), isTrue);
      expect(applicable(isImage: false, isAudio: true), isTrue);
      expect(applicable(isImage: true, isAudio: false), isFalse);
    });

    test('round-trips through JSON', () {
      expect(
        MediaViewerAction.fromJson(MediaViewerAction.abLoop.toJson()),
        MediaViewerAction.abLoop,
      );
    });

    test('is available in the default More menu, not the bottom bar', () {
      const config = MediaViewerToolbarConfig();
      expect(config.bottomBarActions, isNot(contains(MediaViewerAction.abLoop)));
      expect(config.moreMenuActions, contains(MediaViewerAction.abLoop));
    });

    test('an old saved layout gets it in the More menu, not the bottom bar', () {
      final config = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
      });
      expect(config.moreMenuActions, contains(MediaViewerAction.abLoop));
      expect(
        config.moreMenuActions.where((a) => a == MediaViewerAction.abLoop).length,
        1,
      );
      expect(config.bottomBarActions, isNot(contains(MediaViewerAction.abLoop)));
    });

    test('a user placement is respected, not duplicated', () {
      final defaults = MediaViewerToolbarConfig.defaults();
      final saved = defaults.copyWith(
        topBarActions: [MediaViewerAction.bookmark, MediaViewerAction.abLoop],
        bottomBarActions: [MediaViewerAction.playPause],
        moreMenuActions: defaults.moreMenuActions
            .where((action) => action != MediaViewerAction.abLoop)
            .toList(),
      );
      final restored = MediaViewerToolbarConfig.fromJson(saved.toJson());
      expect(restored.topBarActions, contains(MediaViewerAction.abLoop));
      expect(restored.moreMenuActions, isNot(contains(MediaViewerAction.abLoop)));
    });

    test('a hidden placement is respected too', () {
      final defaults = MediaViewerToolbarConfig.defaults();
      final saved = defaults.copyWith(
        bottomBarActions: [MediaViewerAction.playPause],
        hiddenActions: {MediaViewerAction.abLoop},
        moreMenuActions: defaults.moreMenuActions
            .where((action) => action != MediaViewerAction.abLoop)
            .toList(),
      );
      final restored = MediaViewerToolbarConfig.fromJson(saved.toJson());
      expect(restored.hiddenActions, contains(MediaViewerAction.abLoop));
      expect(restored.moreMenuActions, isNot(contains(MediaViewerAction.abLoop)));
      expect(restored.bottomBarActions, isNot(contains(MediaViewerAction.abLoop)));
    });
  });
}
