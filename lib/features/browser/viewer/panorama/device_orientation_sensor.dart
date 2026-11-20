import 'package:flutter/services.dart';

/// Device attitude for the 360° viewer's gyro mode, from Android's fused
/// rotation-vector sensor (see ViewerOrientationPlugin.kt).
///
/// Each event is a row-major 3x3 rotation matrix (9 numbers) mapping screen
/// axes (x right, y up, z out of the screen) to world axes (East, North, Up),
/// already corrected for the display rotation.
class DeviceOrientationSensor {
  const DeviceOrientationSensor._();

  static const MethodChannel _method = MethodChannel(
    'com.aeidolon.vaultexplorer/viewer/orientation_method',
  );
  static const EventChannel _events = EventChannel(
    'com.aeidolon.vaultexplorer/viewer/orientation',
  );

  static Future<bool> isAvailable() async {
    try {
      return await _method.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The sensor is only registered natively while this stream has a listener.
  static Stream<List<double>> matrices() => _events
      .receiveBroadcastStream()
      .map((event) => (event as List).cast<num>())
      .where((m) => m.length >= 9)
      .map((m) => List<double>.generate(9, (i) => m[i].toDouble()));
}
