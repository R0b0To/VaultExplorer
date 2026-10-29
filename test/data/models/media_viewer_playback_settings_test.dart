import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';

void main() {
  group('MediaViewerToolbarConfig.keepAudioPlayingAfterClose', () {
    test('defaults to off', () {
      expect(
        MediaViewerToolbarConfig.defaults().keepAudioPlayingAfterClose,
        isFalse,
      );
      expect(
        const MediaViewerToolbarConfig().keepAudioPlayingAfterClose,
        isFalse,
      );
    });

    test('copyWith updates it and leaves it alone otherwise', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        keepAudioPlayingAfterClose: true,
      );
      expect(config.keepAudioPlayingAfterClose, isTrue);
      expect(
        config.copyWith(loopPlaylist: false).keepAudioPlayingAfterClose,
        isTrue,
      );
    });

    test('survives a toJson / fromJson round trip', () {
      final restored = MediaViewerToolbarConfig.fromJson(
        MediaViewerToolbarConfig.defaults()
            .copyWith(keepAudioPlayingAfterClose: true)
            .toJson(),
      );
      expect(restored.keepAudioPlayingAfterClose, isTrue);
    });

    test('fromJson falls back to off when the key is missing', () {
      final restored = MediaViewerToolbarConfig.fromJson(<String, dynamic>{
        'showProgressBar': true,
      });
      expect(restored.keepAudioPlayingAfterClose, isFalse);
    });
  });

  group('MediaViewerToolbarConfig.pictureInPictureEnabled', () {
    test('defaults to off (the viewer button enters it on demand)', () {
      expect(
        MediaViewerToolbarConfig.defaults().pictureInPictureEnabled,
        isFalse,
      );
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

  group('MediaViewerToolbarConfig.floatingPlayerEnabled', () {
    test('defaults to on (closing a playing video floats it)', () {
      expect(
        MediaViewerToolbarConfig.defaults().floatingPlayerEnabled,
        isTrue,
      );
      expect(const MediaViewerToolbarConfig().floatingPlayerEnabled, isTrue);
    });

    test('copyWith and the JSON round trip keep it', () {
      final off = MediaViewerToolbarConfig.defaults().copyWith(
        floatingPlayerEnabled: false,
      );
      expect(off.floatingPlayerEnabled, isFalse);
      final restored = MediaViewerToolbarConfig.fromJson(off.toJson());
      expect(restored.floatingPlayerEnabled, isFalse);
      expect(
        restored.copyWith(loopPlaylist: false).floatingPlayerEnabled,
        isFalse,
      );
    });

    test('is independent of the automatic picture-in-picture setting', () {
      final config = MediaViewerToolbarConfig.defaults().copyWith(
        pictureInPictureEnabled: true,
      );
      expect(config.floatingPlayerEnabled, isTrue);
      expect(
        config.copyWith(floatingPlayerEnabled: false).pictureInPictureEnabled,
        isTrue,
      );
    });

    test('fromJson falls back to on when the key is missing', () {
      final restored = MediaViewerToolbarConfig.fromJson(<String, dynamic>{
        'showProgressBar': true,
      });
      expect(restored.floatingPlayerEnabled, isTrue);
    });
  });

  group('MediaViewerAction.pictureInPicture', () {
    test('is only applicable to video', () {
      const action = MediaViewerAction.pictureInPicture;
      expect(
        action.isApplicable(
          isImage: false,
          isAudio: false,
          isPlaylistMode: false,
        ),
        isTrue,
      );
      expect(
        action.isApplicable(
          isImage: true,
          isAudio: false,
          isPlaylistMode: false,
        ),
        isFalse,
      );
      expect(
        action.isApplicable(
          isImage: false,
          isAudio: true,
          isPlaylistMode: false,
        ),
        isFalse,
      );
    });

    test('is on the default top bar', () {
      expect(
        MediaViewerToolbarConfig.defaults().topBarActions,
        contains(MediaViewerAction.pictureInPicture),
      );
    });

    test('joins the More menu of a layout saved before it existed', () {
      final saved = MediaViewerToolbarConfig.defaults().toJson();
      for (final key in [
        'topBarActions',
        'bottomBarActions',
        'moreMenuActions',
        'advancedSettingsActions',
        'hiddenActions',
      ]) {
        saved[key] = (saved[key] as List)
            .where((name) => name != MediaViewerAction.pictureInPicture.name)
            .toList();
      }
      final restored = MediaViewerToolbarConfig.fromJson(saved);
      expect(
        restored.moreMenuActions,
        contains(MediaViewerAction.pictureInPicture),
      );
      expect(
        restored.topBarActions,
        isNot(contains(MediaViewerAction.pictureInPicture)),
      );
    });
  });
}
