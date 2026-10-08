import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('MediaViewerAction.adjustments', () {
    test('has its own icon (tune_rounded belongs to advanced settings)', () {
      expect(MediaViewerAction.adjustments.icon, Icons.brightness_6_rounded);
      expect(
        MediaViewerAction.adjustments.icon,
        isNot(MediaViewerAction.advancedSettings.icon),
      );
    });

    test('has an English label', () {
      expect(
        MediaViewerAction.adjustments.getLocalizedLabel(AppLocalizationsEn()),
        'Adjustments',
      );
    });

    test('applies to images and video but not audio', () {
      bool applicable({required bool isImage, required bool isAudio}) =>
          MediaViewerAction.adjustments.isApplicable(
            isImage: isImage,
            isAudio: isAudio,
            isPlaylistMode: false,
          );
      expect(applicable(isImage: true, isAudio: false), isTrue);
      expect(applicable(isImage: false, isAudio: false), isTrue);
      expect(applicable(isImage: false, isAudio: true), isFalse);
    });

    test('round-trips through JSON', () {
      expect(
        MediaViewerAction.fromJson(MediaViewerAction.adjustments.toJson()),
        MediaViewerAction.adjustments,
      );
    });

    test('is in the default advanced settings list only', () {
      const config = MediaViewerToolbarConfig();
      expect(config.advancedSettingsActions, contains(MediaViewerAction.adjustments));
      expect(config.topBarActions, isNot(contains(MediaViewerAction.adjustments)));
      expect(config.bottomBarActions, isNot(contains(MediaViewerAction.adjustments)));
      expect(config.moreMenuActions, isNot(contains(MediaViewerAction.adjustments)));
    });

    test('old saved configs get it appended to advanced settings', () {
      final old = {
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
      };
      final config = MediaViewerToolbarConfig.fromJson(old);
      expect(config.advancedSettingsActions, contains(MediaViewerAction.adjustments));
      expect(
        config.advancedSettingsActions.where((a) => a == MediaViewerAction.adjustments).length,
        1,
      );
    });

    test('a user placement is respected, not duplicated', () {
      final saved = MediaViewerToolbarConfig.defaults().copyWith(
        bottomBarActions: [
          MediaViewerAction.playPause,
          MediaViewerAction.adjustments,
        ],
        advancedSettingsActions: [MediaViewerAction.rotate90],
      );
      final restored = MediaViewerToolbarConfig.fromJson(saved.toJson());
      expect(restored.bottomBarActions, contains(MediaViewerAction.adjustments));
      expect(restored.advancedSettingsActions, isNot(contains(MediaViewerAction.adjustments)));
    });

    test('a hidden placement is respected too', () {
      final saved = MediaViewerToolbarConfig.defaults().copyWith(
        advancedSettingsActions: [MediaViewerAction.rotate90],
        hiddenActions: {MediaViewerAction.adjustments},
      );
      final restored = MediaViewerToolbarConfig.fromJson(saved.toJson());
      expect(restored.hiddenActions, contains(MediaViewerAction.adjustments));
      expect(restored.advancedSettingsActions, isNot(contains(MediaViewerAction.adjustments)));
    });
  });
}
