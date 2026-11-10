import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('MediaViewerAction.lockControls', () {
    test('has a lock icon and an English label', () {
      expect(MediaViewerAction.lockControls.icon, Icons.lock_outline_rounded);
      expect(
        MediaViewerAction.lockControls.getLocalizedLabel(AppLocalizationsEn()),
        'Lock controls',
      );
    });

    test('applies to video, audio and images alike', () {
      for (final isImage in [true, false]) {
        for (final isAudio in [true, false]) {
          if (isImage && isAudio) continue;
          for (final isPlaylistMode in [true, false]) {
            expect(
              MediaViewerAction.lockControls.isApplicable(
                isImage: isImage,
                isAudio: isAudio,
                isPlaylistMode: isPlaylistMode,
              ),
              isTrue,
              reason: 'image=$isImage audio=$isAudio playlist=$isPlaylistMode',
            );
          }
        }
      }
    });

    test('round-trips through JSON', () {
      expect(
        MediaViewerAction.fromJson(MediaViewerAction.lockControls.toJson()),
        MediaViewerAction.lockControls,
      );
    });

    test('is in the default More menu, above rename and delete', () {
      const config = MediaViewerToolbarConfig();
      expect(
        config.topBarActions,
        isNot(contains(MediaViewerAction.lockControls)),
      );
      final more = config.moreMenuActions;
      expect(more, contains(MediaViewerAction.lockControls));
      expect(
        more.indexOf(MediaViewerAction.lockControls),
        lessThan(more.indexOf(MediaViewerAction.rename)),
      );
      expect(more.last, MediaViewerAction.delete);
    });

    test('a layout that is the previous default moves it to the More menu', () {
      final config = MediaViewerToolbarConfig.fromJson({
        'topBarActions': [
          'bookmark',
          'playlistMenu',
          'pictureInPicture',
          'lockControls',
        ],
        'bottomBarActions': [
          'mute',
          'playbackMode',
          'previous',
          'playPause',
          'next',
          'thumbnailCarousel',
          'advancedSettings',
        ],
        'moreMenuActions': [
          'fileInfo',
          'openWithApp',
          'editImage',
          'editVideo',
          'editAudio',
          'abLoop',
          'rename',
          'delete',
        ],
        'advancedSettingsActions': const MediaViewerToolbarConfig()
            .advancedSettingsActions
            .map((a) => a.toJson())
            .toList(),
      });

      expect(config.topBarActions, const MediaViewerToolbarConfig().topBarActions);
      expect(
        config.moreMenuActions,
        const MediaViewerToolbarConfig().moreMenuActions,
      );
    });

    test('a customised layout keeps the lock button in the top bar', () {
      final config = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark', 'lockControls'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
      });

      expect(config.topBarActions, contains(MediaViewerAction.lockControls));
      expect(
        config.moreMenuActions,
        isNot(contains(MediaViewerAction.lockControls)),
      );
    });

    test('an old saved layout gets it once, in the More menu', () {
      final config = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
      });
      expect(
        config.moreMenuActions
            .where((a) => a == MediaViewerAction.lockControls)
            .length,
        1,
      );
      expect(
        config.topBarActions,
        isNot(contains(MediaViewerAction.lockControls)),
      );
      expect(
        config.bottomBarActions,
        isNot(contains(MediaViewerAction.lockControls)),
      );
    });

    test('a saved layout keeps it where the person put it', () {
      final config = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause', 'lockControls'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
      });
      expect(
        config.bottomBarActions,
        contains(MediaViewerAction.lockControls),
      );
      expect(
        config.moreMenuActions,
        isNot(contains(MediaViewerAction.lockControls)),
      );
    });

    test('is not brought back once the person hid it', () {
      final config = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': ['lockControls'],
      });
      expect(config.hiddenActions, contains(MediaViewerAction.lockControls));
      expect(
        config.moreMenuActions,
        isNot(contains(MediaViewerAction.lockControls)),
      );
    });

    test('survives a toJson / fromJson round trip', () {
      final restored = MediaViewerToolbarConfig.fromJson(
        MediaViewerToolbarConfig.defaults().toJson(),
      );
      expect(
        restored.topBarActions,
        contains(MediaViewerAction.lockControls),
      );
    });
  });
}
