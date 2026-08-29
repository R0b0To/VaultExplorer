import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

class NativeMedia3PlayerView extends StatelessWidget {
  final NativeMedia3Controller media3Controller;

  const NativeMedia3PlayerView({
    super.key,
    required this.media3Controller,
  });

  @override
  Widget build(BuildContext context) {
    final textureId = media3Controller.textureId;
    if (textureId == null || media3Controller.isDisposed) {
      return const SizedBox.shrink();
    }
    return SizedBox.expand(
      child: Texture(textureId: textureId),
    );
  }
}