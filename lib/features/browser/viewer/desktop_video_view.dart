import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_video_backend.dart';

/// Renders a [DesktopVideoBackend]'s frames (the desktop counterpart of `NativeMedia3PlayerView`).
///
/// The viewer already sizes and fits the video itself (see `_buildVideoTexture` in the media player widget)
/// and draws its own controls and captions, so this only fills the box it is given: no media_kit controls,
/// no media_kit subtitle layer (captions arrive through `NativeVideoValue.captionText`).
class DesktopVideoView extends StatelessWidget {
  const DesktopVideoView({super.key, required this.backend});

  final DesktopVideoBackend backend;

  @override
  Widget build(BuildContext context) {
    // The media_kit controller is created inside initialize(), after the widget may first be built.
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final controller = backend.videoController;
        if (controller == null || backend.isDisposed) return const SizedBox.shrink();
        return SizedBox.expand(
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.fill,
            fill: const Color(0x00000000),
            pauseUponEnteringBackgroundMode: false,
            subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
          ),
        );
      },
    );
  }
}
