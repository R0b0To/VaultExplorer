import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';

/// Wraps the whole app (put it outermost in `MaterialApp.builder`). While
/// Android's picture-in-picture window is up, the app is hidden and only the
/// playing video is shown, so the small window isn't a squashed copy of
/// whatever screen the person was on.
///
/// The app stays mounted underneath ([Offstage]), so nothing is rebuilt or
/// reset when the person returns to the full screen.
class PictureInPictureLayer extends StatelessWidget {
  final Widget child;

  const PictureInPictureLayer({super.key, required this.child});

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
              child: Offstage(offstage: inPictureInPicture, child: child),
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
