import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';

/// Session-lived cache of each video file's embedded rotation, expressed
/// as quarter-turns clockwise (0-3), as read from the container's rotation
/// metadata (`MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION` on the
/// native side, surfaced through `NativeFFmpegController.getDiagnostics()`'s
/// `rotationDegrees` field).
///
/// This exists because nothing in the native FFmpeg decode pipeline applies
/// that metadata to the actual decoded/rendered frames (see
/// ffmpeg_player.cpp / FFmpegPlayerEngine.kt) -- a vertically-shot video
/// decodes to a landscape buffer, and the player widget has to compensate
/// with a RotatedBox using this value, instead of the rotation staying
/// purely informational the way it did when it was only ever read for the
/// diagnostics sheet.
///
/// Keyed the same way as [MediaAspectRatioCache] so a new container session
/// never serves a stale rotation left over from a previous mount into the
/// same slot.
class MediaRotationCache {
  MediaRotationCache._();
  static final _cache = LruCache<String, int>(2000);

  static String _key(MountedContainer container, String filePath) =>
      '${container.uri}:$filePath';

  static int? get(MountedContainer container, String filePath) =>
      _cache[_key(container, filePath)];

  static void put(MountedContainer container, String filePath, int quarterTurns) {
    _cache[_key(container, filePath)] = quarterTurns % 4;
  }

  static void clear() => _cache.clear();
}
