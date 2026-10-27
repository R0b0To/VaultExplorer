import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';

void main() {
  group('MediaViewerToolbarConfig swipeToSeekEnabled', () {
    test('defaults to false in defaults() factory', () {
      final config = MediaViewerToolbarConfig.defaults();
      expect(config.swipeToSeekEnabled, isFalse);
    });

    test('defaults to false when unassigned in constructor', () {
      const config = MediaViewerToolbarConfig();
      expect(config.swipeToSeekEnabled, isFalse);
    });

    test('copyWith updates swipeToSeekEnabled', () {
      final config = MediaViewerToolbarConfig.defaults();
      final updated = config.copyWith(swipeToSeekEnabled: true);
      expect(updated.swipeToSeekEnabled, isTrue);

      final reset = updated.copyWith(swipeToSeekEnabled: false);
      expect(reset.swipeToSeekEnabled, isFalse);
    });

    test('serializes and deserializes swipeToSeekEnabled in JSON', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        swipeToSeekEnabled: true,
      );
      final json = config.toJson();
      expect(json['swipeToSeekEnabled'], isTrue);

      final restored = MediaViewerToolbarConfig.fromJson(json);
      expect(restored.swipeToSeekEnabled, isTrue);
    });

    test('fromJson falls back to false when key is missing', () {
      final json = <String, dynamic>{
        'showProgressBar': true,
      };
      final config = MediaViewerToolbarConfig.fromJson(json);
      expect(config.swipeToSeekEnabled, isFalse);
    });
  });

  group('MediaViewerToolbarConfig swipeToDismissEnabled', () {
    test('is off by default', () {
      expect(MediaViewerToolbarConfig.defaults().swipeToDismissEnabled, isFalse);
      expect(const MediaViewerToolbarConfig().swipeToDismissEnabled, isFalse);
    });

    test('copyWith updates it without touching swipeToSeekEnabled', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        swipeToSeekEnabled: true,
      );
      final updated = config.copyWith(swipeToDismissEnabled: true);
      expect(updated.swipeToDismissEnabled, isTrue);
      expect(updated.swipeToSeekEnabled, isTrue);

      final reset = updated.copyWith(swipeToDismissEnabled: false);
      expect(reset.swipeToDismissEnabled, isFalse);
      expect(reset.swipeToSeekEnabled, isTrue);
    });

    test('round-trips through JSON', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        swipeToDismissEnabled: true,
      );
      final json = config.toJson();
      expect(json['swipeToDismissEnabled'], isTrue);
      expect(
        MediaViewerToolbarConfig.fromJson(json).swipeToDismissEnabled,
        isTrue,
      );
    });

    test('fromJson falls back to false for configs saved before it existed', () {
      final config = MediaViewerToolbarConfig.fromJson(<String, dynamic>{
        'showProgressBar': true,
      });
      expect(config.swipeToDismissEnabled, isFalse);
    });
  });

  group('editAudio action', () {
    test('is in the default More menu, next to editVideo', () {
      const config = MediaViewerToolbarConfig();
      expect(config.moreMenuActions, contains(MediaViewerAction.editAudio));
      expect(
        config.moreMenuActions.indexOf(MediaViewerAction.editAudio),
        config.moreMenuActions.indexOf(MediaViewerAction.editVideo) + 1,
      );
    });

    test('only applies to audio files', () {
      bool applies({required bool isImage, required bool isAudio}) =>
          MediaViewerAction.editAudio.isApplicable(
            isImage: isImage,
            isAudio: isAudio,
            isPlaylistMode: false,
          );
      expect(applies(isImage: false, isAudio: true), isTrue);
      expect(applies(isImage: false, isAudio: false), isFalse); // video
      expect(applies(isImage: true, isAudio: false), isFalse);
    });

    test('editVideo still does not apply to audio, and still applies to video', () {
      expect(
        MediaViewerAction.editVideo.isApplicable(
          isImage: false,
          isAudio: true,
          isPlaylistMode: false,
        ),
        isFalse,
      );
      expect(
        MediaViewerAction.editVideo.isApplicable(
          isImage: false,
          isAudio: false,
          isPlaylistMode: false,
        ),
        isTrue,
      );
    });

    test('fromJson adds it to the More menu of a config saved before it existed', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo', 'editVideo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': <String>[],
      });
      expect(parsed.moreMenuActions, contains(MediaViewerAction.editAudio));
      expect(parsed.moreMenuActions, contains(MediaViewerAction.editVideo));
    });

    test('fromJson keeps it where the person put it', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark', 'editAudio'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': <String>[],
      });
      expect(parsed.topBarActions, contains(MediaViewerAction.editAudio));
      expect(parsed.moreMenuActions, isNot(contains(MediaViewerAction.editAudio)));
    });

    test('fromJson does not bring it back once hidden', () {
      final parsed = MediaViewerToolbarConfig.fromJson({
        'topBarActions': ['bookmark'],
        'bottomBarActions': ['playPause'],
        'moreMenuActions': ['fileInfo'],
        'advancedSettingsActions': ['rotate90'],
        'hiddenActions': ['editAudio'],
      });
      expect(parsed.hiddenActions, contains(MediaViewerAction.editAudio));
      expect(parsed.moreMenuActions, isNot(contains(MediaViewerAction.editAudio)));
    });

    test('survives a toJson / fromJson round trip', () {
      final restored = MediaViewerToolbarConfig.fromJson(
        MediaViewerToolbarConfig.defaults().toJson(),
      );
      expect(restored.moreMenuActions, contains(MediaViewerAction.editAudio));
    });
  });
}
