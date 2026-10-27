import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';

/// Wraps the whole app (put it outermost in `MaterialApp.builder`) and owns the
/// two app-level pieces of picture-in-picture:
///
///  * While Android's PiP window is the *app itself* (the "automatic
///    picture-in-picture" mode, entered when the app is left), the app is
///    hidden and only the playing video is shown, so the small window isn't a
///    squashed copy of whatever screen the person was on. The app stays
///    mounted underneath ([Offstage]), so nothing is rebuilt or reset when
///    they return to the full screen.
///  * When the person taps the separate PiP window (the viewer's button) to go
///    back to full screen, the media viewer is reopened on the video it was
///    playing, taking the running player back.
class PictureInPictureLayer extends StatefulWidget {
  final Widget child;

  const PictureInPictureLayer({super.key, required this.child});

  @override
  State<PictureInPictureLayer> createState() => _PictureInPictureLayerState();
}

class _PictureInPictureLayerState extends State<PictureInPictureLayer> {
  @override
  void initState() {
    super.initState();
    BackgroundPlaybackHost.instance.expandHandler = _reopenViewer;
  }

  @override
  void dispose() {
    final host = BackgroundPlaybackHost.instance;
    if (host.expandHandler == _reopenViewer) host.expandHandler = null;
    super.dispose();
  }

  void _reopenViewer() {
    final host = BackgroundPlaybackHost.instance;
    final session = host.session;
    final navigator = appNavigatorKey.currentState;
    if (session == null || navigator == null) {
      unawaited(host.closeAndWait());
      return;
    }
    // The viewer takes the running player back on its own (see
    // BackgroundPlaybackHost.takeMatching), as it does for any item that is
    // still playing.
    navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaViewerScreen(
              container: session.container,
              mediaFiles: List<String>.of(session.playlist.playlist),
              initialIndex: session.playlist.currentIndex,
              startingFolder: session.startingFolder,
              thumbnailQuality: session.thumbnailQuality,
              thumbnailCacheMode: session.thumbnailCacheMode,
              mediaFilter: session.mediaFilter,
              sortBy: session.sortBy,
              sortAscending: session.sortAscending,
              pinnedPaths: session.pinnedPaths,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Touching the coordinator installs the platform event handler.
    final coordinator = PictureInPictureCoordinator.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: PictureInPictureBridge.isInPictureInPicture,
      builder: (context, inPictureInPicture, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: Offstage(
                offstage: inPictureInPicture,
                child: widget.child,
              ),
            ),
            if (inPictureInPicture)
              Positioned.fill(
                child: _PictureInPictureVideo(coordinator: coordinator),
              ),
          ],
        );
      },
    );
  }
}

class _PictureInPictureVideo extends StatelessWidget {
  final PictureInPictureCoordinator coordinator;

  const _PictureInPictureVideo({required this.coordinator});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<NativeVideoController?>(
        valueListenable: coordinator.source,
        builder: (context, controller, _) {
          if (controller == null || controller.isDisposed) {
            return const SizedBox.shrink();
          }
          return ValueListenableBuilder<NativeVideoValue>(
            valueListenable: controller,
            builder: (context, value, _) => Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: NativeVideoPlayerView(controller: controller),
              ),
            ),
          );
        },
      ),
    );
  }
}
