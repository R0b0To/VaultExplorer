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

  Future<NativeImageOutcome> _run(String op, List<Object?> args) async {
    final List<Object?> r;
    try {
      r = await call(op, args) as List<Object?>;
    } on Object {
      return const NativeImageUnsupported(); // the pool / library is not usable: let the caller use Flutter's codecs
    }
    return interpretNativeThumbnailReply(r);
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
