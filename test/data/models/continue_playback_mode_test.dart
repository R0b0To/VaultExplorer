import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/continue_playback_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';

void main() {
  group('ContinuePlaybackMode.keepsPlaying', () {
    test('off keeps nothing playing', () {
      expect(ContinuePlaybackMode.off.keepsPlaying(isVideo: false), isFalse);
      expect(ContinuePlaybackMode.off.keepsPlaying(isVideo: true), isFalse);
    });

    test('audioOnly keeps audio but not video playing', () {
      expect(
        ContinuePlaybackMode.audioOnly.keepsPlaying(isVideo: false),
        isTrue,
      );
      expect(
        ContinuePlaybackMode.audioOnly.keepsPlaying(isVideo: true),
        isFalse,
      );
    });

    test('audioAndVideo keeps both playing', () {
      expect(
        ContinuePlaybackMode.audioAndVideo.keepsPlaying(isVideo: false),
        isTrue,
      );
      expect(
        ContinuePlaybackMode.audioAndVideo.keepsPlaying(isVideo: true),
        isTrue,
      );
    });
  });

  group('ContinuePlaybackMode.fromJson', () {
    test('reads every mode by name', () {
      for (final mode in ContinuePlaybackMode.values) {
        expect(ContinuePlaybackMode.fromJson(mode.name), mode);
      }
    });

    test('falls back to off for null or unknown values', () {
      expect(ContinuePlaybackMode.fromJson(null), ContinuePlaybackMode.off);
      expect(ContinuePlaybackMode.fromJson('nope'), ContinuePlaybackMode.off);
    });
  });

  group('MediaViewerToolbarConfig.continuePlaybackMode', () {
    test('defaults to off', () {
      expect(
        MediaViewerToolbarConfig.defaults().continuePlaybackMode,
        ContinuePlaybackMode.off,
      );
      expect(
        const MediaViewerToolbarConfig().continuePlaybackMode,
        ContinuePlaybackMode.off,
      );
    });

    test('copyWith updates it and leaves it alone otherwise', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        continuePlaybackMode: ContinuePlaybackMode.audioAndVideo,
      );
      expect(config.continuePlaybackMode, ContinuePlaybackMode.audioAndVideo);
      expect(
        config.copyWith(loopPlaylist: false).continuePlaybackMode,
        ContinuePlaybackMode.audioAndVideo,
      );
    });

    test('survives a toJson / fromJson round trip', () {
      final restored = MediaViewerToolbarConfig.fromJson(
        MediaViewerToolbarConfig.defaults()
            .copyWith(continuePlaybackMode: ContinuePlaybackMode.audioOnly)
            .toJson(),
      );
      expect(restored.continuePlaybackMode, ContinuePlaybackMode.audioOnly);
    });

    test('fromJson falls back to off when the key is missing', () {
      final restored = MediaViewerToolbarConfig.fromJson(<String, dynamic>{
        'showProgressBar': true,
      });
      expect(restored.continuePlaybackMode, ContinuePlaybackMode.off);
    });
  });

  group('MediaViewerToolbarConfig.pictureInPictureEnabled', () {
    test('defaults to off', () {
      expect(MediaViewerToolbarConfig.defaults().pictureInPictureEnabled, isFalse);
    });

    test('copyWith and the JSON round trip keep it', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        pictureInPictureEnabled: true,
      );
      expect(config.pictureInPictureEnabled, isTrue);
      final restored = MediaViewerToolbarConfig.fromJson(config.toJson());
      expect(restored.pictureInPictureEnabled, isTrue);
      expect(
        restored.copyWith(loopPlaylist: false).pictureInPictureEnabled,
        isTrue,
      );
    });

    test('fromJson falls back to off when the key is missing', () {
      final restored = MediaViewerToolbarConfig.fromJson(<String, dynamic>{
        'showProgressBar': true,
      });
      expect(restored.pictureInPictureEnabled, isFalse);
    });
  });
}
