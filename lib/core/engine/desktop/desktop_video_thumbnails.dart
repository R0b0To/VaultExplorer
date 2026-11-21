// Video thumbnails for the desktop engine.
//
// Android answers `getVideoThumbnail[WithSize]` with MediaMetadataRetriever. Linux and Windows have no such
// thing in the engine, so this builds the same answer out of what the desktop already ships for playback:
// libmpv (through media_kit) reads the decrypted file from the loopback media server, decodes ONE frame, and that
// frame is scaled down to a PNG thumbnail.
//
//   request -> [this class: pick the frame(s)] -> grab (mpv, mpv_frame_grabber.dart) -> decode/scale/blank check
//              (video_frame_decoder.dart) -> PNG + the frame's true size
//
// Like the playback path, nothing decrypted touches storage: the source is a loopback URL (or, for a plain
// local-storage file, the file itself), see desktop_media_server.dart.
//
// This file is plain Dart on purpose (no Flutter, no media_kit): the player, the decoder and the vault are
// handed in, so the selection and lifecycle rules can be tested without any of them.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/thumbnail_generation_strategy.dart';

import 'video_thumbnail_logic.dart';

/// One frame out of a video: encoded (JPEG or PNG) at the video's own resolution, plus the video's length
/// ([Duration.zero] when the player does not know it).
class GrabbedFrame {
  const GrabbedFrame({required this.encoded, this.duration = Duration.zero});

  final Uint8List encoded;
  final Duration duration;
}

/// Opens [url] and returns the frame shown at [start] (the beginning when null), or null when the video cannot
/// be opened or shows no frame within [timeout]. [isLocalFile] says the URL is a `file:` one (otherwise it is the
/// loopback server's `http:` one); the implementation uses it to keep the player from reading anything else.
typedef FrameGrabber = Future<GrabbedFrame?> Function({
  required String url,
  required bool isLocalFile,
  Duration? start,
  required Duration timeout,
});

/// A frame ready to hand back: [png] fits the requested size, [sourceWidth] x [sourceHeight] are the frame's own
/// pixels, [isBlank] says it is a poor thumbnail (see [isLikelyBlankFrame]).
class DecodedFrame {
  const DecodedFrame({
    required this.png,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.isBlank,
  });

  final Uint8List png;
  final int sourceWidth;
  final int sourceHeight;
  final bool isBlank;
}

/// Scales [encoded] to fit [targetSize] and encodes it as PNG; null when it cannot be decoded.
typedef FrameDecoder = Future<DecodedFrame?> Function(Uint8List encoded, int targetSize);

/// Something a player can read: [url], and [close] to give it back (ends the media-server session).
class VideoSource {
  const VideoSource({required this.url, required this.close});

  final String url;
  final Future<void> Function() close;
}

/// Makes a vault file readable by a player; null when it is missing or empty.
typedef VaultVideoOpener = Future<VideoSource?> Function(int volId, String path);

/// A finished thumbnail. [width] x [height] are the SOURCE frame's size (callers use them for the aspect ratio).
class VideoThumbnail {
  const VideoThumbnail({required this.bytes, required this.width, required this.height});

  final Uint8List bytes;
  final int width;
  final int height;
}

class VideoThumbnailRequest {
  const VideoThumbnailRequest({
    this.volId,
    required this.path,
    this.isLocalFile = false,
    this.targetSize = 180,
    this.strategy = ThumbnailGenerationStrategy.hybrid,
    this.framePosition = 0.12,
    this.explicitTimeUs,
  }) : assert(isLocalFile || volId != null, 'a vault file needs its volume');

  /// The unlocked volume [path] lives in; unused for a local file.
  final int? volId;

  /// Path inside the vault, or the absolute path of a file on the host when [isLocalFile].
  final String path;
  final bool isLocalFile;
  final int targetSize;
  final ThumbnailGenerationStrategy strategy;
  final double framePosition;

  /// An exact timestamp (the video editor's film strip); wins over [strategy] and is never retried.
  final int? explicitTimeUs;
}

class _Candidate {
  const _Candidate(this.frame, this.duration);

  final DecodedFrame frame;
  final Duration duration;

  VideoThumbnail toThumbnail() =>
      VideoThumbnail(bytes: frame.png, width: frame.sourceWidth, height: frame.sourceHeight);
}

class _Run {
  _Run(this.volId);

  final int? volId;
  final Completer<bool> turn = Completer<bool>();
  bool cancelled = false;
}

class DesktopVideoThumbnails {
  DesktopVideoThumbnails({
    required this.openVaultFile,
    required this.grab,
    required this.decode,
    this.maxConcurrent = 2,
    this.grabTimeout = const Duration(seconds: 20),
    void Function(String message)? log,
  })  : assert(maxConcurrent > 0),
        _log = log ?? ((_) {});

  final VaultVideoOpener openVaultFile;
  final FrameGrabber grab;
  final FrameDecoder decode;

  /// Players alive at once. Each one is a whole libmpv instance, so this stays small however many tiles are
  /// waiting for a thumbnail.
  final int maxConcurrent;

  /// How long one frame may take (open, decode, first picture) before it is given up on.
  final Duration grabTimeout;

  final void Function(String message) _log;

  int _slotsInUse = 0;
  final List<_Run> _waiting = [];
  final Set<_Run> _active = {};
  bool _disposed = false;

  /// Frames are generated one request at a time per slot, in the order asked. Resolves to null for anything that
  /// cannot be shown: a missing or locked file, a format libmpv cannot decode, a timeout.
  Future<VideoThumbnail?> thumbnail(VideoThumbnailRequest request) async {
    if (_disposed) return null;
    final run = _Run(request.volId);
    if (!await _acquire(run)) return null;
    _active.add(run);
    try {
      return await _extract(request, run);
    } on Object catch (e) {
      _log('video thumbnail for ${request.path} failed: $e');
      return null;
    } finally {
      _active.remove(run);
      _release();
    }
  }

  /// The vault [volId] is going away: queued requests for it are dropped and running ones stop at their next
  /// step (the media server has already cut their stream off).
  void cancelVolume(int volId) {
    for (final run in _waiting.where((r) => r.volId == volId).toList()) {
      _waiting.remove(run);
      run.cancelled = true;
      run.turn.complete(false);
    }
    for (final run in _active) {
      if (run.volId == volId) run.cancelled = true;
    }
  }

  /// Drops everything queued and stops accepting requests (app exit).
  void dispose() {
    _disposed = true;
    for (final run in _waiting) {
      run.cancelled = true;
      run.turn.complete(false);
    }
    _waiting.clear();
    for (final run in _active) {
      run.cancelled = true;
    }
  }

  // ── slots ───────────────────────────────────────────────────────────────

  Future<bool> _acquire(_Run run) {
    if (_slotsInUse < maxConcurrent) {
      _slotsInUse++;
      return Future.value(true);
    }
    _waiting.add(run);
    return run.turn.future; // true: handed a slot by [_release]; false: cancelled while queued
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).turn.complete(true); // the slot passes on without being given back
    } else {
      _slotsInUse--;
    }
  }

  // ── extraction ──────────────────────────────────────────────────────────

  Future<VideoThumbnail?> _extract(VideoThumbnailRequest r, _Run run) async {
    final source = r.isLocalFile ? await _openLocalFile(r.path) : await openVaultFile(r.volId!, r.path);
    if (source == null) return null;
    try {
      Future<_Candidate?> frameAt(Duration? start) async {
        if (run.cancelled || _disposed) return null;
        try {
          final frame = await grab(url: source.url, isLocalFile: r.isLocalFile, start: start, timeout: grabTimeout);
          if (frame == null || frame.encoded.isEmpty || run.cancelled) return null;
          final decoded = await decode(frame.encoded, r.targetSize);
          return decoded == null ? null : _Candidate(decoded, frame.duration);
        } on Object catch (e) {
          _log('video frame at ${start ?? Duration.zero} of ${r.path} failed: $e');
          return null;
        }
      }

      final explicitUs = r.explicitTimeUs;
      if (explicitUs != null) {
        final c = await frameAt(explicitUs <= 0 ? null : Duration(microseconds: explicitUs));
        return c?.toThumbnail();
      }

      // The start of the video always comes first: it needs no seek, and it is what 'firstFrame' and 'hybrid'
      // want. It also tells us how long the video is, which the other strategies need to know.
      final first = await frameAt(null);
      if (first == null) return null;
      var best = first;
      final duration = first.duration;

      switch (r.strategy) {
        case ThumbnailGenerationStrategy.firstFrame:
          break;
        case ThumbnailGenerationStrategy.frameAtPercentage:
          if (duration > Duration.zero) {
            // A frame at the wanted position beats the first one; if it fails the first one is still a thumbnail.
            final c = await frameAt(timeAtFraction(duration, r.framePosition));
            if (c != null) best = c;
          }
        case ThumbnailGenerationStrategy.hybrid:
          if (first.frame.isBlank && duration > Duration.zero) {
            for (final fraction in blankFrameRetryFractions(r.framePosition)) {
              final c = await frameAt(timeAtFraction(duration, fraction));
              if (c == null) continue;
              if (!c.frame.isBlank) {
                best = c;
                break;
              }
            }
          }
      }
      return best.toThumbnail();
    } finally {
      try {
        await source.close();
      } on Object catch (e) {
        _log('closing the video source of ${r.path} failed: $e');
      }
    }
  }

  Future<VideoSource?> _openLocalFile(String path) async {
    if (!await File(path).exists()) return null;
    return VideoSource(url: Uri.file(path).toString(), close: () async {});
  }
}
