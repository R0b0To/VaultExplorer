import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart';

void main() {
  group('MediaViewerSession controller', () {
    test('initializes with expected default values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(mediaViewerSessionProvider('session-1'));
      expect(state.showUI, isFalse);
      expect(state.isCarouselVisible, isFalse);
      expect(state.enableCarousel, isTrue);
      expect(state.bookmarkPaths, isEmpty);
      expect(state.autoAdvance, isFalse);
      expect(state.isAutoAdvancing, isFalse);
      expect(state.slideshowDelaySeconds, 4);
      expect(state.videoPlaybackMode, VideoPlaybackMode.playOnce);
      expect(state.playbackSpeed, 1.0);
      expect(state.subtitlesEnabled, isTrue);
      expect(state.subtitleFontSize, 15.0);
      expect(state.subtitleVerticalPosition, 0.0);
      expect(state.imageFit, BoxFit.contain);
      expect(state.transitionEffect, PlaylistTransitionEffect.slide);
      expect(state.scrollMode, PlaylistScrollMode.horizontal);
      expect(state.isMuted, isFalse);
      expect(state.rotations, isEmpty);
      expect(state.imageReloadEpoch, isEmpty);
    });

    test('toggles and sets showUI correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.setShowUI(true);
      expect(
        container.read(mediaViewerSessionProvider('session-1')).showUI,
        isTrue,
      );

      notifier.toggleUI();
      expect(
        container.read(mediaViewerSessionProvider('session-1')).showUI,
        isFalse,
      );

      notifier.toggleUI();
      expect(
        container.read(mediaViewerSessionProvider('session-1')).showUI,
        isTrue,
      );
    });

    test('carousel and bookmark state management', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.setCarouselVisible(true);
      notifier.setEnableCarousel(false);
      var state = container.read(mediaViewerSessionProvider('session-1'));
      expect(state.isCarouselVisible, isTrue);
      expect(state.enableCarousel, isFalse);

      notifier.setBookmarkPaths(['photo1.jpg']);
      state = container.read(mediaViewerSessionProvider('session-1'));
      expect(state.bookmarkPaths, ['photo1.jpg']);

      notifier.toggleBookmark('photo2.jpg');
      state = container.read(mediaViewerSessionProvider('session-1'));
      expect(state.bookmarkPaths, ['photo1.jpg', 'photo2.jpg']);

      notifier.toggleBookmark('photo1.jpg');
      state = container.read(mediaViewerSessionProvider('session-1'));
      expect(state.bookmarkPaths, ['photo2.jpg']);
    });

    test('playback, subtitles, and layout options', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.setVideoPlaybackMode(VideoPlaybackMode.loop);
      notifier.setPlaybackSpeed(1.5);
      notifier.setSubtitlesEnabled(false);
      notifier.setSubtitleFontSize(18.0);
      notifier.setSubtitleVerticalPosition(0.2);
      notifier.setImageFit(BoxFit.cover);
      notifier.setTransitionEffect(PlaylistTransitionEffect.fade);
      notifier.setScrollMode(PlaylistScrollMode.verticalContinuous);
      notifier.setIsMuted(true);

      final state = container.read(mediaViewerSessionProvider('session-1'));
      expect(state.videoPlaybackMode, VideoPlaybackMode.loop);
      expect(state.playbackSpeed, 1.5);
      expect(state.subtitlesEnabled, isFalse);
      expect(state.subtitleFontSize, 18.0);
      expect(state.subtitleVerticalPosition, 0.2);
      expect(state.imageFit, BoxFit.cover);
      expect(state.transitionEffect, PlaylistTransitionEffect.fade);
      expect(state.scrollMode, PlaylistScrollMode.verticalContinuous);
      expect(state.isMuted, isTrue);
    });

    test('rotation and image reload epochs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.setRotation('img1.png', 90);
      expect(
        container
            .read(mediaViewerSessionProvider('session-1'))
            .rotations['img1.png'],
        90,
      );

      notifier.rotateClockwise('img1.png');
      expect(
        container
            .read(mediaViewerSessionProvider('session-1'))
            .rotations['img1.png'],
        180,
      );

      notifier.bumpImageReloadEpoch('img1.png');
      expect(
        container
            .read(mediaViewerSessionProvider('session-1'))
            .imageReloadEpoch['img1.png'],
        1,
      );

      notifier.bumpImageReloadEpoch('img1.png');
      expect(
        container
            .read(mediaViewerSessionProvider('session-1'))
            .imageReloadEpoch['img1.png'],
        2,
      );
    });

    test('keeps state isolated across session keys', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier1 =
          container.read(mediaViewerSessionProvider('sess-1').notifier);
      final notifier2 =
          container.read(mediaViewerSessionProvider('sess-2').notifier);

      notifier1.setShowUI(true);
      expect(
        container.read(mediaViewerSessionProvider('sess-1')).showUI,
        isTrue,
      );
      expect(
        container.read(mediaViewerSessionProvider('sess-2')).showUI,
        isFalse,
      );
    });
  });
}
