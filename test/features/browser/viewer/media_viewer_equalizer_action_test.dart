import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('MediaViewerAction.equalizer', () {
    test('has the right icon and label', () {
      expect(MediaViewerAction.equalizer.icon, Icons.equalizer_rounded);
      expect(
        MediaViewerAction.equalizer.getLocalizedLabel(AppLocalizationsEn()),
        'Equalizer',
      );
    });

    test('is for video and audio, not images', () {
      bool applicable({required bool image, required bool audio}) =>
          MediaViewerAction.equalizer.isApplicable(
            isImage: image,
            isAudio: audio,
            isPlaylistMode: false,
          );
      expect(applicable(image: true, audio: false), isFalse);
      expect(applicable(image: false, audio: false), isTrue);
      expect(applicable(image: false, audio: true), isTrue);
    });

    test('is in the default Advanced settings list', () {
      const config = MediaViewerToolbarConfig();
      expect(config.advancedSettingsActions, contains(MediaViewerAction.equalizer));
    });

    test('fromJson adds it to Advanced settings of a config saved before it existed', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90', 'playbackSpeed'],
        'hiddenActions': <String>[],
      });
      expect(parsed.advancedSettingsActions, contains(MediaViewerAction.equalizer));
    });

    test('fromJson keeps it where the person put it', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark', 'equalizer'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': <String>[],
      });
      expect(parsed.topBarActions, contains(MediaViewerAction.equalizer));
      expect(
        parsed.advancedSettingsActions,
        isNot(contains(MediaViewerAction.equalizer)),
      );
    });

    test('fromJson does not bring it back once hidden', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': ['equalizer'],
      });
      expect(parsed.hiddenActions, contains(MediaViewerAction.equalizer));
      expect(
        parsed.advancedSettingsActions,
        isNot(contains(MediaViewerAction.equalizer)),
      );
    });

    test('appears only once after a round trip', () {
      final restored = MediaViewerToolbarConfig.fromJson(
        const MediaViewerToolbarConfig().toJson(),
      );
      final all = [
        ...restored.topBarActions,
        ...restored.bottomBarActions,
        ...restored.moreMenuActions,
        ...restored.advancedSettingsActions,
        ...restored.hiddenActions,
      ];
      expect(all.where((a) => a == MediaViewerAction.equalizer), hasLength(1));
    });
  });

  group('equalizer settings in the media viewer config', () {
    test('default to off and flat', () {
      expect(
        const MediaViewerToolbarConfig().equalizer,
        AudioEqualizerSettings.defaults,
      );
    });

    test('configs saved before the equalizer existed load with the default', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': <String>[],
      });
      expect(parsed.equalizer, AudioEqualizerSettings.defaults);
    });

    test('are saved and restored', () {
      final eq = AudioEqualizerSettings(
        enabled: true,
        preampDb: -3,
        bandGainsDb: EqualizerPreset.electronic.bandGainsDb,
        preventClipping: false,
      );
      final restored = MediaViewerToolbarConfig.fromJson(
        const MediaViewerToolbarConfig().copyWith(equalizer: eq).toJson(),
      );
      expect(restored.equalizer, eq);
    });

    test('copyWith of something else keeps them', () {
      final eq = AudioEqualizerSettings(enabled: true, bandGainsDb: [3, 2, 1]);
      final config = const MediaViewerToolbarConfig().copyWith(equalizer: eq);
      expect(config.copyWith(showProgressBar: false).equalizer, eq);
    });
  });
}
