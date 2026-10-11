import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';

/// Helper reproducing the swipe physics calculation in [MediaViewerScreen].
ScrollPhysics computeSwipePhysics({
  required PlaylistScrollMode scrollMode,
  required bool isCurrentItemSwipeToSeekEnabled,
  bool multiTouchLock = false,
  bool zoomInteractionLock = false,
  bool isProgrammaticScrolling = false,
}) {
  final swipeToSeekActive =
      scrollMode == PlaylistScrollMode.horizontal &&
      isCurrentItemSwipeToSeekEnabled;
  final shouldLock =
      multiTouchLock ||
      zoomInteractionLock ||
      isProgrammaticScrolling ||
      swipeToSeekActive;
  return shouldLock
      ? const NeverScrollableScrollPhysics()
      : const BouncingScrollPhysics();
}

void main() {
  group('MediaViewer swipe physics across playlist scroll modes', () {
    test(
      'in horizontal mode with swipe-to-seek video, disables page swipe to prevent interference',
      () {
        final physics = computeSwipePhysics(
          scrollMode: PlaylistScrollMode.horizontal,
          isCurrentItemSwipeToSeekEnabled: true,
        );
        expect(physics, isA<NeverScrollableScrollPhysics>());
      },
    );

    test(
      'in verticalPage mode with swipe-to-seek video, leaves item-change gesture enabled',
      () {
        final physics = computeSwipePhysics(
          scrollMode: PlaylistScrollMode.verticalPage,
          isCurrentItemSwipeToSeekEnabled: true,
        );
        expect(physics, isA<BouncingScrollPhysics>());
      },
    );

    test(
      'in verticalContinuous mode with swipe-to-seek video, leaves list scroll enabled',
      () {
        final physics = computeSwipePhysics(
          scrollMode: PlaylistScrollMode.verticalContinuous,
          isCurrentItemSwipeToSeekEnabled: true,
        );
        expect(physics, isA<BouncingScrollPhysics>());
      },
    );

    test(
      'in verticalPage mode, zoom or multi-touch still locks physics as expected',
      () {
        final zoomed = computeSwipePhysics(
          scrollMode: PlaylistScrollMode.verticalPage,
          isCurrentItemSwipeToSeekEnabled: true,
          zoomInteractionLock: true,
        );
        expect(zoomed, isA<NeverScrollableScrollPhysics>());

        final multiTouch = computeSwipePhysics(
          scrollMode: PlaylistScrollMode.verticalPage,
          isCurrentItemSwipeToSeekEnabled: true,
          multiTouchLock: true,
        );
        expect(multiTouch, isA<NeverScrollableScrollPhysics>());
      },
    );

    test(
      'switching scrollMode from horizontal to verticalPage unblocks item-change gesture',
      () {
        var mode = PlaylistScrollMode.horizontal;
        var physics = computeSwipePhysics(
          scrollMode: mode,
          isCurrentItemSwipeToSeekEnabled: true,
        );
        expect(physics, isA<NeverScrollableScrollPhysics>());

        mode = PlaylistScrollMode.verticalPage;
        physics = computeSwipePhysics(
          scrollMode: mode,
          isCurrentItemSwipeToSeekEnabled: true,
        );
        expect(physics, isA<BouncingScrollPhysics>());
      },
    );
  });
}
