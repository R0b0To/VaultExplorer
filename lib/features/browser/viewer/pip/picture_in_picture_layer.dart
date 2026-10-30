import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_session_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/floating_video_player.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';

/// Wraps the whole app (put it outermost in `MaterialApp.builder`) and owns the
/// app-level pieces of picture-in-picture and the floating player:
///
///  * While Android's PiP window is the *app itself* (entered when the app is
///    left with the floating player or the "automatic picture-in-picture"
///    setting, or right away with the viewer's button), the app is
///    hidden and only the playing video is shown, so the small window isn't a
///    squashed copy of whatever screen the person was on. The app stays
///    mounted underneath ([Offstage]), so nothing is rebuilt or reset when
///    they return to the full screen.
///  * When the person taps the separate PiP window (the fallback of the
///    viewer's button) to go back to full screen, the media viewer is reopened on the video it was
///    playing, taking the running player back.
///  * The in-app floating player ([FloatingVideoPlayer]) is drawn here, above
///    the navigator, while [BackgroundPlaybackHost] has a floating session.
///    Leaving the app then turns the app into the PiP window above, with the
///    same video.
class PictureInPictureLayer extends StatefulWidget {
  final Widget child;

  const PictureInPictureLayer({super.key, required this.child});

  @override
  State<PictureInPictureLayer> createState() => _PictureInPictureLayerState();
}

class _PictureInPictureLayerState extends State<PictureInPictureLayer> {
  StreamSubscription<void>? _openPlayerSubscription;

  @override
  void initState() {
    super.initState();
    BackgroundPlaybackHost.instance.expandHandler = _reopenViewer;
    _openPlayerSubscription = MediaSessionBridge.openPlayerRequests.listen(
      (_) => _onOpenPlayerRequest(),
    );
    unawaited(_initializeMediaSessionBridge());
  }

  Future<void> _initializeMediaSessionBridge() async {
    await MediaSessionBridge.ensureInitialized();
    if (mounted) _onOpenPlayerRequest();
  }

  void _onOpenPlayerRequest() {
    if (!MediaSessionBridge.takePendingOpenPlayerRequest()) return;
    BackgroundPlaybackHost.instance.openFromNotification();
  }

  @override
  void dispose() {
    unawaited(_openPlayerSubscription?.cancel());
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
            // Kept mounted (just not painted) while the app is the PiP window,
            // so the corner the person parked it in is still there afterwards.
            Positioned.fill(
              child: Offstage(
                offstage: inPictureInPicture,
                // Three sources for one window: the video flying in while the
                // viewer is still closing (an entry), the session that takes
                // over once the viewer is gone, and the player the viewer has
                // just taken back, which the window stays up over until the
                // viewer has drawn the video where it was (an exit). The
                // constant key keeps it the same window throughout, so none of
                // the hand-overs is seen.
                child: ListenableBuilder(
                  listenable: Listenable.merge(<Listenable>[
                    BackgroundPlaybackHost.instance.floatingSession,
                    BackgroundPlaybackHost.instance.floatingEntry,
                    BackgroundPlaybackHost.instance.floatingExit,
                  ]),
                  builder: (context, _) {
                    final host = BackgroundPlaybackHost.instance;
                    final entry = host.floatingEntry.value;
                    final manager =
                        host.floatingSession.value?.playbackManager ??
                        entry?.playbackManager ??
                        host.floatingExit.value?.playbackManager;
                    if (manager == null) return const SizedBox.shrink();
                    return FloatingVideoPlayer(
                      key: const ValueKey<String>('floating_video_player'),
                      playbackManager: manager,
                      flyFrom: entry?.from,
                      onExpand: host.expand,
                    );
                  },
                ),
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
