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

      // Rotations are clockwise quarter-turns, not degrees.
      notifier.setRotation('img1.png', 1);
      expect(
        container
            .read(mediaViewerSessionProvider('session-1'))
            .rotations['img1.png'],
        1,
      );

      notifier.rotateClockwise('img1.png');
      expect(
        container
            .read(mediaViewerSessionProvider('session-1'))
            .rotations['img1.png'],
        2,
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

  group('rotation units (regression: the toolbar button turned 180 degrees)', () {
    int? rotationOf(ProviderContainer c, String path) =>
        c.read(mediaViewerSessionProvider('session-1')).rotations[path];

    test('each rotateClockwise is exactly one quarter-turn and wraps after four',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      // It was 90 -> 180 -> 270 -> 0 (degrees) fed into RotatedBox's
      // quarterTurns, which renders as 180 -> 0 -> 180 -> 0 degrees.
      final seen = <int?>[];
      for (var i = 0; i < 5; i++) {
        notifier.rotateClockwise('a.mp4');
        seen.add(rotationOf(container, 'a.mp4'));
      }

      expect(seen, [1, 2, 3, 0, 1]);
    });

    test('stays within RotatedBox range, so the % 2 sideways check is right', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.rotateClockwise('a.mp4');

      final quarterTurns = rotationOf(container, 'a.mp4')!;
      // After one 90-degree turn the video is sideways...
      expect(quarterTurns % 2 != 0, isTrue);
      // ...and a value in degrees (90) would have looked upright here.
      expect(quarterTurns, lessThan(4));
    });

    test('toolbar button and settings-sheet row share one scale', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      // The sheet stores (rotation + 1) % 4 via setRotation.
      notifier.setRotation('a.mp4', 2);
      notifier.rotateClockwise('a.mp4');

      expect(rotationOf(container, 'a.mp4'), 3);
    });

    test('setRotation wraps out-of-range values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.setRotation('a.mp4', 4);
      expect(rotationOf(container, 'a.mp4'), 0);
      notifier.setRotation('a.mp4', 5);
      expect(rotationOf(container, 'a.mp4'), 1);
      notifier.setRotation('a.mp4', -1);
      expect(rotationOf(container, 'a.mp4'), 3);
    });

    test('files rotate independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier =
          container.read(mediaViewerSessionProvider('session-1').notifier);

      notifier.rotateClockwise('a.mp4');
      notifier.rotateClockwise('a.mp4');
      notifier.rotateClockwise('b.png');

      expect(rotationOf(container, 'a.mp4'), 2);
      expect(rotationOf(container, 'b.png'), 1);
    });
  });
}
