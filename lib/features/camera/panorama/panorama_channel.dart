import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Dart side of the native panorama store (PanoramaPlugin.kt).
///
/// The photos themselves never cross this channel: the camera parks each
/// panorama frame natively (see `VaultCameraController.capturePhoto(panorama:)`)
/// and Dart only commits it together with the device pose.
class PanoramaChannel {
  const PanoramaChannel._();

  static const MethodChannel _channel = MethodChannel(
    'com.aeidolon.vaultexplorer/panorama',
  );

  static Future<void> begin() => _channel.invokeMethod<void>('begin');

  static Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  static Future<void> discard() => _channel.invokeMethod<void>('discard');

  /// Adds the parked frame with its pose ([rows]: 9 numbers, see
  /// panorama_pose.dart) and the lens field of view. Returns the frame count,
  /// or null when the frame could not be added.
  static Future<int?> commit({
    required List<double> rows,
    required double tanHalfLong,
  }) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('commit', {
      'rows': rows,
      'tanHalfLong': tanHalfLong,
    });
    if (res?['success'] != true) return null;
    return (res?['count'] as num?)?.toInt();
  }

  static Future<PanoramaResult> finish({required bool sphere}) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('finish', {
      'sphere': sphere,
    });
    if (res?['success'] != true) {
      return PanoramaResult.failure(res?['error'] as String? ?? 'stitching failed');
    }
    return PanoramaResult(
      bytes: res!['bytes'] as Uint8List,
      thumbnail: res['thumbnail'] as Uint8List,
      width: (res['width'] as num).toInt(),
      height: (res['height'] as num).toInt(),
    );
  }
}

class PanoramaResult {
  PanoramaResult({
    required Uint8List this.bytes,
    required Uint8List this.thumbnail,
    required this.width,
    required this.height,
  }) : error = null;

  PanoramaResult.failure(String this.error)
    : bytes = null,
      thumbnail = null,
      width = 0,
      height = 0;

  final Uint8List? bytes;
  final Uint8List? thumbnail;
  final int width;
  final int height;
  final String? error;

  bool get success => bytes != null;
}
