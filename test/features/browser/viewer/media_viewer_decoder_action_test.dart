import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('MediaViewerAction.decoder', () {
    test('has correct icon and properties', () {
      expect(MediaViewerAction.decoder.icon, Icons.memory_rounded);
      expect(
        MediaViewerAction.decoder.getLocalizedLabel(AppLocalizationsEn()),
        'Video decoder',
      );
    });

    test('is not applicable for images, but applicable for video and audio', () {
      expect(
        MediaViewerAction.decoder.isApplicable(
          isImage: true,
          isAudio: false,
          isPlaylistMode: false,
        ),
        isFalse,
      );
      expect(
        MediaViewerAction.decoder.isApplicable(
          isImage: false,
          isAudio: false,
          isPlaylistMode: false,
        ),
        isTrue,
      );
      expect(
        MediaViewerAction.decoder.isApplicable(
          isImage: false,
          isAudio: true,
          isPlaylistMode: false,
        ),
        isTrue,
      );
    });

    test('is present in default advancedSettingsActions', () {
      const config = MediaViewerToolbarConfig();
      expect(
        config.advancedSettingsActions.contains(MediaViewerAction.decoder),
        isTrue,
      );
    });

    test('fromJson migrates old configs without decoder into advancedSettingsActions', () {
      final oldJson = {
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90', 'playbackSpeed'],
        'hiddenActions': <String>[],
      };

      final parsed = MediaViewerToolbarConfig.fromJson(oldJson);
      expect(
        parsed.advancedSettingsActions.contains(MediaViewerAction.decoder),
        isTrue,
      );
    });

    test('fromJson preserves existing location when decoder was placed in topBarActions', () {
      final customJson = {
        'topBarActions': ['bookmark', 'decoder'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': <String>[],
      };

      final parsed = MediaViewerToolbarConfig.fromJson(customJson);
      expect(
        parsed.topBarActions.contains(MediaViewerAction.decoder),
        isTrue,
      );
      expect(
        parsed.advancedSettingsActions.contains(MediaViewerAction.decoder),
        isFalse,
      );
    });
  });

  group('Playback pause on entering settings', () {
    test('session autoAdvance can be paused cleanly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(mediaViewerSessionProvider('test-session').notifier);

      notifier.setAutoAdvance(true);
      expect(
        container.read(mediaViewerSessionProvider('test-session')).autoAdvance,
        isTrue,
      );

      notifier.setAutoAdvance(false);
      expect(
        container.read(mediaViewerSessionProvider('test-session')).autoAdvance,
        isFalse,
      );
    });
  });
}

