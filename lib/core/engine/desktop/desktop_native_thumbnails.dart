// Image thumbnails made by the engine itself (ve_image_thumbnail*, ABI 15; the decoding is imaging/thumb.cpp).
//
// Why this exists: the Flutter route reads the whole file into Dart (copied across an isolate boundary in 8 MiB
// pieces), hands it to dart:ui, and gets the thumbnail back through a GPU read-back encoded as PNG -- all of it
// queued behind one UI isolate. Here ONE blocking native call on a worker isolate reads the file through a small
// read-ahead buffer, decodes it at reduced size (a JPEG straight out of its DCT), and answers a few kilobytes of
// JPEG. Android makes thumbnails the same way (BitmapFactory with a sample size, JPEG out).
//
// Thumbnails run in a pool of their own, never next to unlocks, listings and file reads: a screen full of tiles
// must not queue a directory listing behind a hundred decodes, and a long unlock must not stall the tiles.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'engine_worker_pool.dart';
import 've_native.dart';

/// Opt-in tracing of every thumbnail: set the environment variable VE_THUMB_TRACE to `1` (lines go to stdout, and the
/// engine's own to stderr) or to a file path (every line, Dart's and the engine's, is appended to it). A line says
/// which route made the thumbnail, the outcome and the milliseconds, and for a video the container and codec -- never
/// a file name or a path. It exists to answer "why is this slow / why is there no thumbnail" on a real machine.
final String? _traceTarget = () {
  final v = Platform.environment['VE_THUMB_TRACE'];
  return (v == null || v.isEmpty || v == '0') ? null : v;
}();

bool get thumbnailTraceEnabled => _traceTarget != null;

void traceThumbnail(String line) {
  final target = _traceTarget;
  if (target == null) return;
  if (target == '1') {
    stdout.writeln(line);
    return;
  }
  try {
    File(target).writeAsStringSync('$line\n', mode: FileMode.append);
  } on FileSystemException catch (e) {
    stderr.writeln('VE_THUMB_TRACE: cannot write $target: ${e.message}');
  }
}

/// What a native thumbnail attempt came to.
sealed class NativeImageOutcome {
  const NativeImageOutcome();
}

/// A thumbnail: [bytes] is a JPEG, or a PNG when [isPng] (the picture really has transparency).
class NativeImageThumb extends NativeImageOutcome {
  const NativeImageThumb({
    required this.bytes,
    required this.isPng,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
    required this.hasAlpha,
    required this.isBlank,
  });

  final Uint8List bytes;
  final bool isPng;

  /// The picture's own size as a viewer shows it (EXIF orientation applied).
  final int sourceWidth;
  final int sourceHeight;

  /// The thumbnail's size.
  final int width;
  final int height;
  final bool hasAlpha;

  /// Flat, near-black, blown-out or low-contrast: a poor thumbnail for a video frame.
  final bool isBlank;
}

/// The engine cannot make this one (not a JPEG / PNG / WebP, an animated WebP, a CMYK JPEG, or the native call
/// could not run): the caller should try another decoder.
class NativeImageUnsupported extends NativeImageOutcome {
  const NativeImageUnsupported();
}

/// The picture cannot be thumbnailed at all (missing, unreadable, corrupt): no thumbnail, and another decoder
/// would only read the whole file again to fail the same way.
class NativeImageFailed extends NativeImageOutcome {
  const NativeImageFailed();
}

/// Refused by a size guard (the picture is too large to decode) or the machine ran out of memory.
class NativeImageRefused extends NativeImageOutcome {
  const NativeImageRefused({required this.outOfMemory});
  final bool outOfMemory;
}

/// Decoders running at once. A decode is one CPU-bound native call, so more than the machine has cores only
/// queues them in the OS scheduler; fewer than the tiles on screen asks for leaves cores idle.
int nativeThumbnailWorkers({int? cores}) => math.max(2, math.min((cores ?? Platform.numberOfProcessors) - 1, 8));

class DesktopNativeThumbnails {
  /// [call] runs an engine op ([veExecute]) in the thumbnail pool; [onDispose] stops that pool.
  DesktopNativeThumbnails({required this.call, this.onDispose});

  /// The production setup: a pool of [nativeThumbnailWorkers] isolates, started on the first request.
  factory DesktopNativeThumbnails.withOwnPool({String? libraryPath}) {
    final pool = EngineWorkerPool(size: nativeThumbnailWorkers(), libraryPath: libraryPath);
    return DesktopNativeThumbnails(call: pool.call, onDispose: pool.dispose);
  }

  final Future<Object?> Function(String op, [List<Object?> args]) call;
  final Future<void> Function()? onDispose;

  Future<void> dispose() async => onDispose?.call();

  /// A picture inside the unlocked slot [vol].
  Future<NativeImageOutcome> vaultFile(
    int vol,
    String path, {
    required int targetSize,
    required int quality,
    required bool preserveAlpha,
    required int maxSourceBytes,
  }) =>
      _run('imageThumbnail', [vol, path, targetSize, quality, preserveAlpha, maxSourceBytes]);

  /// A picture file on this machine.
  Future<NativeImageOutcome> hostFile(
    String path, {
    required int targetSize,
    required int quality,
    required bool preserveAlpha,
    required int maxSourceBytes,
  }) =>
      _run('imageThumbnailFile', [path, targetSize, quality, preserveAlpha, maxSourceBytes]);

  /// A picture already in memory (a video frame). The bytes are copied once into the worker isolate.
  Future<NativeImageOutcome> memory(
    Uint8List data, {
    required int targetSize,
    required int quality,
    bool preserveAlpha = false,
  }) =>
      _run('imageThumbnailMem', [data, targetSize, quality, preserveAlpha]);

  /// One picture of the video at [path] inside the unlocked slot [vol] (see ve_video_thumbnail in ve_engine.h):
  /// [strategy] is a ThumbnailGenerationStrategy index, [explicitTimeUs] (>= 0) an exact point that wins over it.
  /// [NativeImageUnsupported] means this engine cannot open or decode that video: use another route.
  Future<NativeImageOutcome> videoVaultFile(
    int vol,
    String path, {
    required int targetSize,
    required int quality,
    required int strategy,
    required double framePosition,
    int? explicitTimeUs,
    required Duration timeout,
  }) =>
      _run('videoThumbnail',
          [vol, path, targetSize, quality, strategy, framePosition, explicitTimeUs ?? -1, timeout.inMilliseconds]);

  /// The same for a video file on this machine.
  Future<NativeImageOutcome> videoHostFile(
    String path, {
    required int targetSize,
    required int quality,
    required int strategy,
    required double framePosition,
    int? explicitTimeUs,
    required Duration timeout,
  }) =>
      _run('videoThumbnailFile',
          [path, targetSize, quality, strategy, framePosition, explicitTimeUs ?? -1, timeout.inMilliseconds]);

  /// What has already been reported as broken (printed once each, so a broken route does not flood the console).
  static final Set<String> _reportedBroken = {};

  Future<NativeImageOutcome> _run(String op, List<Object?> args) async {
    final timer = Stopwatch()..start();
    final List<Object?> r;
    try {
      r = await call(op, args) as List<Object?>;
    } on Object catch (e) {
      // The pool / library is not usable: the caller falls back to the slower route. That must not be silent: a
      // route that is quietly broken looks exactly like a route that is merely slow.
      if (_reportedBroken.add('$op: $e')) {
        stderr.writeln("[thumbnails] the engine's native thumbnailer is not working ($op: $e); using the slower route");
      }
      traceThumbnail('[dart-thumb] $op threw after ${timer.elapsedMilliseconds}ms: $e');
      return const NativeImageUnsupported();
    }
    final outcome = interpretNativeThumbnailReply(r);
    if (thumbnailTraceEnabled) {
      traceThumbnail('[dart-thumb] $op rc=${r[0]} ${outcome.runtimeType} ${timer.elapsedMilliseconds}ms');
    }
    return outcome;
  }
}

/// Turns the worker's `[resultCode, bytes?, info]` into an outcome. Public so a test can feed it replies.
NativeImageOutcome interpretNativeThumbnailReply(List<Object?> r) {
  final rc = r[0] as int;
  switch (rc) {
    case veOk:
      final bytes = r[1] as Uint8List?;
      final info = (r[2] as List<Object?>).cast<int>();
      if (bytes == null || bytes.isEmpty || info.length < 7) return const NativeImageFailed();
      return NativeImageThumb(
        bytes: bytes,
        isPng: info[0] == 1,
        sourceWidth: info[1],
        sourceHeight: info[2],
        width: info[3],
        height: info[4],
        hasAlpha: info[5] == 1,
        isBlank: info[6] == 1,
      );
    case veErrUnsupported:
      return const NativeImageUnsupported();
    case veErrTooLarge:
      return const NativeImageRefused(outOfMemory: false);
    case veErrNoMemory:
      return const NativeImageRefused(outOfMemory: true);
    default:
      return const NativeImageFailed();
  }
}
