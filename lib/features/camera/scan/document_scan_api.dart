// Dart side of the native document scanner (DocumentScanPlugin.kt).
//
// Everything is bytes in, bytes out: nothing is written to disk, in keeping
// with the "no plaintext on unencrypted storage" rule. The channel is private
// to the camera feature (like VaultCameraController's), so it is spelled here.

import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'scan_geometry.dart';

/// How a scanned page is post-processed. The index is the wire value and must
/// match `docscan::Filter` on the native side.
enum ScanFilter {
  /// Perspective-corrected pixels, untouched.
  original,

  /// Shadows removed and paper whitened, ink colour kept.
  color,

  /// Same as [color], but monochrome.
  gray,

  /// Near-bitonal, for text documents.
  blackWhite,
}

/// Result of looking for a document in a freshly captured photo.
class ScanDetection {
  const ScanDetection({
    required this.preview,
    required this.width,
    required this.height,
    required this.quad,
    required this.score,
  });

  /// The photo, upright (EXIF applied) and downscaled to ~1600 px as JPEG. The
  /// corners refer to exactly this image.
  final Uint8List preview;
  final int width;
  final int height;

  /// Null when no document was found.
  final ScanQuad? quad;

  /// 0..1, how convincing the detection is (0 when nothing was found).
  final double score;

  double get aspect => width / height;
}

/// A finished (cropped, flattened, filtered) page.
class ScanPage {
  const ScanPage({
    required this.bytes,
    required this.thumbnail,
    required this.width,
    required this.height,
  });

  /// JPEG of the page.
  final Uint8List bytes;
  final Uint8List thumbnail;
  final int width;
  final int height;
}

class DocumentScanApi {
  const DocumentScanApi();

  static const MethodChannel _channel = MethodChannel('com.aeidolon.vaultexplorer/docscan');

  /// Finds the document in a captured JPEG.
  Future<ScanDetection> detect(Uint8List jpeg) async {
    final res = await _channel.invokeMapMethod<String, dynamic>('detect', {'bytes': jpeg});
    if (res == null) throw PlatformException(code: 'scan_failed', message: 'No result');
    final corners = res['corners'];
    return ScanDetection(
      preview: res['preview'] as Uint8List,
      width: res['width'] as int,
      height: res['height'] as int,
      quad: corners is List && corners.length == 8
          ? ScanQuad.fromPoints([for (final v in corners) (v as num).toDouble()])
          : null,
      score: (res['score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Flattens [quad] out of [jpeg] and applies [filter].
  ///
  /// [quad] must be relative to the same upright image as [jpeg] (the
  /// [ScanDetection.preview] or the original capture, which show the same
  /// picture). [rotationDegrees] is applied to the result (multiples of 90).
  Future<ScanPage> process({
    required Uint8List jpeg,
    required ScanQuad quad,
    required ScanFilter filter,
    int rotationDegrees = 0,
    int maxLongSide = 3000,
    int quality = 88,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>('process', {
      'bytes': jpeg,
      'corners': quad.toWire(),
      'filter': filter.index,
      'rotation': rotationDegrees,
      'maxLongSide': maxLongSide,
      'quality': quality,
    });
    if (res == null) throw PlatformException(code: 'scan_failed', message: 'No result');
    return ScanPage(
      bytes: res['bytes'] as Uint8List,
      thumbnail: res['thumbnail'] as Uint8List,
      width: res['width'] as int,
      height: res['height'] as int,
    );
  }

  /// One PDF with a page per image, in order. No metadata is embedded.
  Future<Uint8List> buildPdf(List<Uint8List> pages) async {
    final res = await _channel.invokeMethod<Uint8List>('buildPdf', {'pages': pages});
    if (res == null) throw PlatformException(code: 'scan_failed', message: 'No result');
    return res;
  }
}
