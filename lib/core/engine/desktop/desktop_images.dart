// Image thumbnails / previews for the desktop engine.
//
// The normal route is the engine's own (desktop_native_thumbnails.dart, imaging/thumb.cpp): one blocking native call
// on a worker isolate reads the file through a read-ahead buffer, decodes a JPEG / PNG / WebP at reduced size and
// answers a small JPEG (a PNG when the picture really has transparency). Android makes thumbnails the same way.
//
// What the engine does not handle (a GIF, BMP, ICO, an animated WebP, a CMYK JPEG, ...) -- or an engine whose native
// pool cannot run -- falls back to Flutter's own codecs (dart:ui), which decode on the Flutter engine's worker
// threads and can scale while decoding, so a 40 MP photo never materialises at full size for a 180 px thumbnail.
// That route reads the whole file into Dart first and answers PNG (dart:ui cannot encode JPEG / WebP), so `quality`
// has no effect there.
//
// Guards, mirroring the Android contract the Dart layer already understands (both routes):
//   * a source file above [maxSourceBytes] is refused with IMAGE_TOO_LARGE,
//   * so is an image the native decoder judges too large to decode (a progressive JPEG or interlaced PNG whose
//     decode would need more than 1 GiB), and on the Flutter route one whose full decode would need more than
//     [maxDecodeBytes] (width*height*4); a machine that runs out of memory answers OUT_OF_MEMORY,
//   * the Flutter route runs at most [maxConcurrent] decodes at once, so a screen full of thumbnails cannot spike
//     memory (the native pool has its own, per-core limit).
// Formats neither route can decode (HEIC, AVIF, ...) give null, which callers treat as "no thumbnail".
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'desktop_native_thumbnails.dart';

typedef ThumbnailResult = ({Uint8List bytes, int width, int height});

class DesktopImages {
  DesktopImages({required this.readWhole, this.native});

  /// Reads a whole vault file (null on failure; throws IMAGE_TOO_LARGE above [maxSourceBytes]).
  final Future<Uint8List?> Function(int vol, String path, int maxBytes) readWhole;

  /// Optional native thumbnailer; when null (or when it answers [NativeImageUnsupported]), falls back to Flutter codecs.
  final DesktopNativeThumbnails? native;

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

  /// A thumbnail of the picture at [path] in unlocked slot [vol] (or, with [hostFile], the file at that path on
  /// this machine) fitting inside [targetSize] x [targetSize]; width/height are those of the SOURCE image (callers
  /// use them for the true aspect ratio).
  Future<ThumbnailResult?> thumbnail(
    int? vol,
    String path, {
    required int targetSize,
    int quality = 70,
    bool preserveAlpha = false,
    bool hostFile = false,
  }) async {
    final engine = native;
    if (engine != null) {
      final outcome = hostFile
          ? await engine.hostFile(path,
              targetSize: targetSize, quality: quality, preserveAlpha: preserveAlpha, maxSourceBytes: maxSourceBytes)
          : await engine.vaultFile(vol!, path,
              targetSize: targetSize, quality: quality, preserveAlpha: preserveAlpha, maxSourceBytes: maxSourceBytes);
      switch (outcome) {
        case NativeImageThumb():
          return (bytes: outcome.bytes, width: outcome.sourceWidth, height: outcome.sourceHeight);
        case NativeImageFailed():
          return null;
        case NativeImageRefused():
          throw PlatformException(
            code: outcome.outOfMemory ? 'OUT_OF_MEMORY' : 'IMAGE_TOO_LARGE',
            message: outcome.outOfMemory
                ? 'Not enough memory to decode this image'
                : 'Decoding this image would need more memory than the limit allows',
          );
        case NativeImageUnsupported():
          break; // not one of the formats the engine handles: Flutter's codecs below
      }
    }
    return _flutterThumbnail(vol, path, targetSize: targetSize, hostFile: hostFile);
  }

  /// Flutter's codecs: the whole file is read into Dart, decoded by dart:ui with scaling, answered as PNG.
  Future<ThumbnailResult?> _flutterThumbnail(
    int? vol,
    String path, {
    required int targetSize,
    required bool hostFile,
  }) async {
    final Uint8List? data;
    if (hostFile) {
      data = await _readHostFile(path);
    } else {
      data = await readWhole(vol!, path, maxSourceBytes);
    }
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

  /// A file on this machine, whole; IMAGE_TOO_LARGE above [maxSourceBytes]; null when it cannot be read.
  Future<Uint8List?> _readHostFile(String path) async {
    try {
      final file = File(path);
      final size = await file.length();
      if (size > maxSourceBytes) {
        throw PlatformException(
          code: 'IMAGE_TOO_LARGE',
          message: 'File is $size bytes; the limit for in-memory decoding is $maxSourceBytes',
        );
      }
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
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
