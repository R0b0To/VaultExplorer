// Turns a video frame (a JPEG or PNG as libmpv hands it over, at the video's own resolution) into the thumbnail
// the app asks for: scaled to fit, with the source size and a "is this a blank frame" verdict.
//
// Two decoders: [nativeFrameDecoder] (the engine; the normal route, JPEG out) and [decodeVideoFrame] (Flutter's own
// codecs, PNG out; the fallback). The fallback decodes on the Flutter engine's worker threads and scales while
// decoding, so a 4K frame never has to exist at full size just to become a 180 px thumbnail.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'desktop_native_thumbnails.dart';
import 'desktop_video_thumbnails.dart' show DecodedFrame, FrameDecoder;
import 'video_thumbnail_logic.dart';

/// JPEG quality of a video thumbnail made by the engine.
const int kNativeVideoFrameQuality = 75;

/// A [FrameDecoder] that lets the engine do the work: the frame goes to a native worker, which decodes it at reduced
/// size, scales it, takes the blank-frame verdict and encodes a small JPEG (or a PNG for a frame with transparency).
/// Compared with [decodeVideoFrame] that is no GPU read-back (two per frame there) and no PNG encode, and none of it
/// runs on the UI isolate. A frame the engine does not handle (not a JPEG / PNG / WebP, or the native pool is not
/// usable) falls back to [decodeVideoFrame].
FrameDecoder nativeFrameDecoder(DesktopNativeThumbnails native, {int quality = kNativeVideoFrameQuality}) {
  return (Uint8List encoded, int targetSize) async {
    final outcome = await native.memory(encoded, targetSize: targetSize, quality: quality);
    switch (outcome) {
      case NativeImageThumb():
        return DecodedFrame(
          png: outcome.bytes, // a JPEG, or a PNG when the frame has transparency
          sourceWidth: outcome.sourceWidth,
          sourceHeight: outcome.sourceHeight,
          isBlank: outcome.isBlank,
        );
      case NativeImageUnsupported():
        return decodeVideoFrame(encoded, targetSize);
      case NativeImageFailed():
      case NativeImageRefused():
        return null;
    }
  };
}

/// A [FrameDecoder](desktop_video_thumbnails.dart) backed by `dart:ui`. Null for anything that is not a decodable
/// image.
Future<DecodedFrame?> decodeVideoFrame(Uint8List encoded, int targetSize) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final sourceWidth = descriptor.width;
    final sourceHeight = descriptor.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) return null;

    final fit = fitWithin(sourceWidth, sourceHeight, targetSize);
    final codec = await descriptor.instantiateCodec(targetWidth: fit.width, targetHeight: fit.height);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        // The blank check looks at the SCALED pixels: an 8x8 sample of them is as good as one of the original and
        // costs a fraction of the memory.
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (png == null || rgba == null) return null;
        return DecodedFrame(
          png: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          isBlank: isLikelyBlankFrame(
            rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
            image.width,
            image.height,
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } on Object {
    return null; // not an image, or a format Flutter cannot decode: "no thumbnail"
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
