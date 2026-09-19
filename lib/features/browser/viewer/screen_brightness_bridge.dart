import 'package:flutter/services.dart';

/// Thin static bridge over the native player channel's screen-brightness
/// commands.
///
/// Brightness is a per-window (Activity) property, not tied to any single
/// video or audio file, so this intentionally sits outside
/// [NativeMedia3Controller] -- playlist items' controllers come and go as
/// the person swipes through media, while the screen itself (and its
/// brightness override) persists for the life of the whole media viewer.
/// It reuses the same `"com.aeidolon.vaultexplorer/player"` channel that
/// controller already talks to rather than standing up a second channel,
/// since MainActivity only needs the Activity's own `window` to service it.
/// Thin static bridge over the native player channel's device volume commands.
class DeviceVolumeBridge {
  DeviceVolumeBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.aeidolon.vaultexplorer/player');

  static Future<double> getVolume() async {
    try {
      final res = await _channel.invokeMethod<double>('getDeviceVolume');
      return res ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  static Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod('setDeviceVolume', {
        'volume': clamped,
      });
    } catch (_) {
      // Best-effort
    }
  }
}

class ScreenBrightnessBridge {
  ScreenBrightnessBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.aeidolon.vaultexplorer/player');

  /// Best-effort in-memory record of the last level this bridge set.
  /// Android doesn't hand back a per-app brightness override to read, so
  /// each new [MediaPlayerWidget] instance seeds its edge-swipe gesture
  /// from here rather than always restarting from a fixed default.
  static double lastKnownLevel = 0.5;

  /// Sets the Activity window's brightness override. [value] is clamped to
  /// 0.0-1.0. Best-effort: a failed call shouldn't disrupt playback.
  static Future<void> setBrightness(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    lastKnownLevel = clamped;
    try {
      await _channel.invokeMethod('setScreenBrightness', {
        'brightness': clamped,
      });
    } catch (_) {
      // Best-effort -- see class doc.
    }
  }

  /// Clears the Activity window's brightness override, returning to
  /// whatever the system brightness is. Call this when the media viewer
  /// screen itself is torn down (not on every playlist item change) so the
  /// override doesn't leak into the rest of the app.
  static Future<void> clearOverride() async {
    try {
      await _channel.invokeMethod('setScreenBrightness', {
        'brightness': -1.0,
      });
    } catch (_) {
      // Best-effort teardown, matching NativeMedia3Controller.dispose()'s
      // release() call.
    }
  }
}