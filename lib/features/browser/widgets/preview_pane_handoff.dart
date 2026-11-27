import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/video_playback_mode.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';

/// Hands the player that a preview pane is playing over to
/// [BackgroundPlaybackHost], so it keeps playing after the selection moves on.
///
///  * [floating] (video): the in-app floating player. The window takes off from
///    where the video is on screen ([renderBox] is the pane's own box, and the
///    video is fitted into it by its aspect ratio).
///  * otherwise (audio): a background audio session, steered from the music mini
///    player and the system media controls.
///
/// Returns false, with the player left to the caller, when the host refuses
/// (the app is locked). On true the caller must neither drive nor dispose
/// [manager] any more.
bool handOffPreviewPlayback({
  required BuildContext context,
  required MountedContainer container,
  required String filePath,
  required VideoPlaybackManager manager,
  required NativeVideoController controller,
  required ThumbnailQuality quality,
  required ThumbnailCacheMode cacheMode,
  required bool floating,
  String? startingFolder,
}) {
  if (controller.isDisposed || controller.value.hasError) return false;
  final host = BackgroundPlaybackHost.instance;
  final providers = ProviderScope.containerOf(context, listen: false);

  Rect? from;
  if (floating) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && controller.value.isInitialized) {
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(controller.value.aspectRatio, 1),
        box.size,
      ).destination;
      final origin = box.localToGlobal(
        Offset(
          (box.size.width - fitted.width) / 2,
          (box.size.height - fitted.height) / 2,
        ),
      );
      from = origin & fitted;
    }
  }

  final session = BackgroundPlaybackSession(
    providers: providers,
    container: container,
    playlist: PlaylistController(
      container: container,
      fileIoApi: providers.read(vaultFileIoApiProvider),
      initialMediaFiles: <String>[filePath],
      initialIndex: 0,
      startingFolder: startingFolder,
    ),
    playbackManager: manager,
    playbackMode: VideoPlaybackMode.playOnce,
    playbackSpeed: 1,
    isMuted: false,
    thumbnailQuality: quality,
    thumbnailCacheMode: cacheMode,
    startingFolder: startingFolder,
    mediaFilter: null,
    sortBy: SortBy.name,
    sortAscending: true,
    pinnedPaths: null,
    floatingPlayer: floating,
  );

  if (from != null && !from.isEmpty) {
    host.beginFloatingEntry(
      FloatingPlayerEntry(playbackManager: manager, from: from),
    );
  }
  if (!host.adopt(session)) {
    host.endFloatingEntry();
    return false;
  }
  // The window takes off from the entry's rectangle when it is created, which
  // happens in the next frame; the entry may only end after that.
  if (from != null) {
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => host.endFloatingEntry(),
    );
  }
  return true;
}
