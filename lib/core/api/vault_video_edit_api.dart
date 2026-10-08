import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// What the native side learned about a video: its length, tracks and
/// keyframe positions. See `LosslessVideoCutter.probe` in Kotlin.
class VideoProbe {
  final int durationUs;
  final int width;
  final int height;
  final int rotationDegrees;
  final bool hasVideo;
  final bool hasAudio;
  final String? videoMime;
  final String? audioMime;
  final int? videoBitrate;
  final int? audioBitrate;
  final double? frameRate;
  final int? audioSampleRate;
  final int? audioChannels;

  /// Sync-sample times of the video track, ascending, in microseconds.
  final List<int> keyframesUs;

  /// False when the keyframe scan stopped early (very long or unusual file);
  /// cuts still work, the editor just can't preview every snap.
  final bool keyframesComplete;

  /// `mp4` or `webm` -- the container the lossless cut will write.
  final String outputExtension;

  /// True if the video contains embedded subtitle/text tracks that cannot be preserved in lossless cut.
  final bool hasSubtitles;

  /// Number of detected subtitle tracks.
  final int subtitleTracks;

  const VideoProbe({
    required this.durationUs,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.hasVideo,
    required this.hasAudio,
    required this.videoMime,
    required this.audioMime,
    this.videoBitrate,
    this.audioBitrate,
    this.frameRate,
    this.audioSampleRate,
    this.audioChannels,
    required this.keyframesUs,
    required this.keyframesComplete,
    required this.outputExtension,
    this.hasSubtitles = false,
    this.subtitleTracks = 0,
  });

  factory VideoProbe.fromMap(Map<Object?, Object?> m) => VideoProbe(
    durationUs: (m['durationUs'] as num?)?.toInt() ?? 0,
    width: (m['width'] as num?)?.toInt() ?? 0,
    height: (m['height'] as num?)?.toInt() ?? 0,
    rotationDegrees: (m['rotationDegrees'] as num?)?.toInt() ?? 0,
    hasVideo: m['hasVideo'] as bool? ?? false,
    hasAudio: m['hasAudio'] as bool? ?? false,
    videoMime: m['videoMime'] as String?,
    audioMime: m['audioMime'] as String?,
    videoBitrate: (m['videoBitrate'] as num?)?.toInt(),
    audioBitrate: (m['audioBitrate'] as num?)?.toInt(),
    frameRate: (m['frameRate'] as num?)?.toDouble(),
    audioSampleRate: (m['audioSampleRate'] as num?)?.toInt(),
    audioChannels: (m['audioChannels'] as num?)?.toInt(),
    keyframesUs: [
      for (final k in (m['keyframesUs'] as List<Object?>? ?? const []))
        (k as num).toInt(),
    ],
    keyframesComplete: m['keyframesComplete'] as bool? ?? false,
    outputExtension: m['outputExtension'] as String? ?? 'mp4',
    hasSubtitles: m['hasSubtitles'] as bool? ?? false,
    subtitleTracks: (m['subtitleTracks'] as num?)?.toInt() ?? 0,
  );
}

class VideoExportResult {
  final List<String> outputPaths;

  /// Audio tracks the muxer couldn't take (the video is still exported).
  final int droppedAudioTracks;

  const VideoExportResult({
    required this.outputPaths,
    required this.droppedAudioTracks,
  });
}

/// A failed video probe/export. [cancelled] is true when the user cancelled.
class VideoEditException implements Exception {
  final String code;
  final String message;
  const VideoEditException(this.code, this.message);

  bool get cancelled => code == 'CANCELLED';

  @override
  String toString() => 'VideoEditException($code): $message';
}

/// Lossless video trimming/cutting on the native side (MediaExtractor +
/// MediaMuxer stream copy -- no re-encode). Paths follow the player's rule:
/// container-relative for a vault, absolute for local storage.
class VaultVideoEditApi {
  final MethodChannel _channel;
  const VaultVideoEditApi(this._channel);

  Future<VideoProbe> probe({
    required int volId,
    required String filePath,
    required bool isLocalStorage,
    bool includeKeyframes = true,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(ChannelMethods.videoEditProbe, {
            'volId': volId,
            'filePath': filePath,
            'isLocalStorage': isLocalStorage,
            'includeKeyframes': includeKeyframes,
          });
      if (raw == null) {
        throw const VideoEditException('PROBE_FAILED', 'No response');
      }
      return VideoProbe.fromMap(raw);
    } on PlatformException catch (e) {
      throw VideoEditException(
        e.code,
        e.message ?? 'Could not read this video',
      );
    }
  }

  /// Cuts [segmentsUs] (`[startUs, endUs]` pairs) out of the source. With
  /// [merge] they are joined into the single file [outputPaths] names;
  /// otherwise each becomes its own file, in order.
  Future<VideoExportResult> export({
    required int volId,
    required String filePath,
    required bool isLocalStorage,
    required List<({int startUs, int endUs})> segmentsUs,
    required bool merge,
    required List<String> outputPaths,
    required int opId,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.videoEditExport,
        {
          'volId': volId,
          'filePath': filePath,
          'isLocalStorage': isLocalStorage,
          'segments': [
            for (final s in segmentsUs) [s.startUs, s.endUs],
          ],
          'merge': merge,
          'outputPaths': outputPaths,
          'opId': opId,
        },
      );
      return VideoExportResult(
        outputPaths: [
          for (final p
              in (raw?['outputPaths'] as List<Object?>? ?? outputPaths))
            p as String,
        ],
        droppedAudioTracks: (raw?['droppedAudioTracks'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw VideoEditException(e.code, e.message ?? 'Export failed');
    }
  }

  Future<void> cancel(int opId) async {
    try {
      await _channel.invokeMethod<void>(ChannelMethods.cancelVideoEdit, {
        'opId': opId,
      });
    } on PlatformException {
      // Best effort: if the call fails the export simply runs to completion.
    }
  }
}
