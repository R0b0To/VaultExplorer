// Image thumbnails / previews for the desktop engine.
//
// Android decodes with BitmapFactory behind an admission guard (ImageDecodeGuard.kt). Here the
// decode uses Flutter's own codecs (dart:ui), which decode on the engine's worker threads and can
// scale while decoding, so a 40 MP photo never materialises at full size for a 180 px thumbnail.
//
// Guards, mirroring the Android contract the Dart layer already understands:
//   * a source file above [maxSourceBytes] is refused with IMAGE_TOO_LARGE,
//   * so is an image whose full decode would need more than [maxDecodeBytes] (width*height*4),
//   * at most [maxConcurrent] decodes run at once, so a screen full of thumbnails cannot spike
//     memory.
// Formats Flutter cannot decode (HEIC, AVIF, ...) give null, which callers treat as "no thumbnail".
//
// Thumbnails are returned as PNG (dart:ui cannot encode JPEG/WebP); `quality` therefore has no
// effect. `preserveAlpha` is honoured trivially, because PNG keeps the alpha channel.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

typedef ThumbnailResult = ({Uint8List bytes, int width, int height});

class DesktopImages {
  DesktopImages({required this.readWhole});

  /// Reads a whole vault file (null on failure; throws IMAGE_TOO_LARGE above [maxSourceBytes]).
  final Future<Uint8List?> Function(int vol, String path, int maxBytes) readWhole;

  static const int maxSourceBytes = 256 * 1024 * 1024;
  static const int maxDecodeBytes = 1024 * 1024 * 1024;
  static const int maxConcurrent = 3;

  int _running = 0;
  final List<Completer<void>> _waiting = [];

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future; // the releasing decode hands its slot over without decrementing
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  /// A thumbnail fitting inside [targetSize] x [targetSize]; width/height are those of the SOURCE
  /// image (callers use them for the true aspect ratio).
  Future<ThumbnailResult?> thumbnail(int vol, String path, {required int targetSize}) async {
    final data = await readWhole(vol, path, maxSourceBytes);
    if (data == null || data.isEmpty) return null;
    await _acquire();
    try {
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      try {
        buffer = await ui.ImmutableBuffer.fromUint8List(data);
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final w = descriptor.width;
        final h = descriptor.height;
        if (w <= 0 || h <= 0) return null;
        if (w * h * 4 > maxDecodeBytes) {
          throw PlatformException(
            code: 'IMAGE_TOO_LARGE',
            message: 'Image is $w x $h; decoding it would need more than ${maxDecodeBytes >> 20} MiB',
          );
        }
        final longest = math.max(w, h);
        final scale = targetSize >= longest ? 1.0 : targetSize / longest;
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (w * scale).round()),
          targetHeight: math.max(1, (h * scale).round()),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) return null;
            return (bytes: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes), width: w, height: h);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } on PlatformException {
        rethrow;
      } on Object {
        return null; // undecodable / unsupported format: "no thumbnail"
      } finally {
        descriptor?.dispose();
        buffer?.dispose();
      }
    } finally {
      _release();
    }
  }

  /// RGBA -> encoded bytes (the image editor's export). Only PNG is available here; other formats
  /// answer null, which the editor reports as a failed export.
  Future<Uint8List?> encode(Map<Object?, Object?> args) async {
    final format = '${args['format']}'.toLowerCase();
    if (format != 'png') return null;
    final rgba = args['rgba'];
    final width = (args['width'] as num?)?.toInt() ?? 0;
    final height = (args['height'] as num?)?.toInt() ?? 0;
    if (rgba is! Uint8List || width <= 0 || height <= 0 || rgba.length < width * height * 4) return null;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          return png?.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
