import 'dart:async';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

class NativeCameraLens {
  final String cameraId;
  final String facing;
  final bool isLogical;
  final double zoomMin;
  final double zoomMax;
  final double relativeZoom;
  final String lensType;
  final String displayName;

  const NativeCameraLens({
    required this.cameraId,
    required this.facing,
    required this.isLogical,
    required this.zoomMin,
    required this.zoomMax,
    this.relativeZoom = 1.0,
    this.lensType = 'main',
    this.displayName = '1x',
  });

  factory NativeCameraLens.fromMap(Map<dynamic, dynamic> map) {
    return NativeCameraLens(
      cameraId: map['cameraId'] as String? ?? '',
      facing: map['facing'] as String? ?? 'back',
      isLogical: map['isLogical'] as bool? ?? false,
      zoomMin: (map['zoomMin'] as num?)?.toDouble() ?? 1.0,
      zoomMax: (map['zoomMax'] as num?)?.toDouble() ?? 1.0,
      relativeZoom: (map['relativeZoom'] as num?)?.toDouble() ?? 1.0,
      lensType: map['lensType'] as String? ?? 'main',
      displayName: map['displayName'] as String? ?? '1x',
    );
  }
}

class VaultCameraSessionInfo {
  final int sessionId;
  final int textureId;
  final String cameraId;
  final double zoomMin;
  final double zoomMax;
  final double minExposureEv;
  final double maxExposureEv;
  final int previewWidth;
  final int previewHeight;
  final int sensorOrientation;
  final List<NativeCameraLens> lenses;

  const VaultCameraSessionInfo({
    required this.sessionId,
    required this.textureId,
    required this.cameraId,
    required this.zoomMin,
    required this.zoomMax,
    required this.minExposureEv,
    required this.maxExposureEv,
    required this.previewWidth,
    required this.previewHeight,
    required this.sensorOrientation,
    required this.lenses,
  });

  factory VaultCameraSessionInfo.fromMap(Map<dynamic, dynamic> map) {
    final lensesList = (map['lenses'] as List<dynamic>?)
            ?.map((e) => NativeCameraLens.fromMap(e as Map<dynamic, dynamic>))
            .toList() ??
        [];

    return VaultCameraSessionInfo(
      sessionId: (map['sessionId'] as num).toInt(),
      textureId: (map['textureId'] as num).toInt(),
      cameraId: map['cameraId'] as String? ?? '',
      zoomMin: (map['zoomMin'] as num?)?.toDouble() ?? 1.0,
      zoomMax: (map['zoomMax'] as num?)?.toDouble() ?? 1.0,
      minExposureEv: (map['minExposureEv'] as num?)?.toDouble() ?? 0.0,
      maxExposureEv: (map['maxExposureEv'] as num?)?.toDouble() ?? 0.0,
      previewWidth: (map['previewWidth'] as num?)?.toInt() ?? 1920,
      previewHeight: (map['previewHeight'] as num?)?.toInt() ?? 1080,
      sensorOrientation: (map['sensorOrientation'] as num?)?.toInt() ?? 90,
      lenses: lensesList,
    );
  }
}

class VaultCameraController {
  static const MethodChannel _channel = MethodChannel('com.aeidolon.vaultexplorer/camera');
  static const EventChannel _accelChannel = EventChannel('com.aeidolon.vaultexplorer/camera/accelerometer');

  VaultCameraController(this._engineEvents);

  final VaultEngineEvents _engineEvents;

  static Stream<({double x, double y, double z})> accelerometerEventStream() {
    return _accelChannel.receiveBroadcastStream().map((dynamic event) {
      final map = Map<String, dynamic>.from(event as Map);
      return (
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        z: (map['z'] as num).toDouble(),
      );
    });
  }

  int? _sessionId;
  int? _textureId;
  String? _cameraId;
  double _zoomMin = 1.0;
  double _zoomMax = 1.0;
  double _minExposureEv = 0.0;
  double _maxExposureEv = 0.0;
  int _previewWidth = 1920;
  int _previewHeight = 1080;
  int _sensorOrientation = 90;
  List<NativeCameraLens> _lenses = [];

  StreamSubscription? _eventSubscription;
  final StreamController<Map<String, dynamic>> _eventsController = StreamController.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  Stream<String> get qrCodes => events
      .where((e) => e['event'] == 'qr_code' && e['data'] is String)
      .map((e) => e['data'] as String);
  int? get sessionId => _sessionId;
  int? get textureId => _textureId;
  String? get cameraId => _cameraId;
  double get zoomMin => _zoomMin;
  double get zoomMax => _zoomMax;
  double get minExposureEv => _minExposureEv;
  double get maxExposureEv => _maxExposureEv;
  int get previewWidth => _previewWidth;
  int get previewHeight => _previewHeight;
  int get sensorOrientation => _sensorOrientation;

  double get previewAspectRatio {
    final rotated = _sensorOrientation % 180 != 0;
    final w = rotated ? _previewHeight : _previewWidth;
    final h = rotated ? _previewWidth : _previewHeight;
    if (h == 0) return 1.0;
    return w / h;
  }

  List<NativeCameraLens> get lenses => _lenses;
  bool get isInitialized => _sessionId != null && _textureId != null;

  /// Quarter-turn index (0..3) of the activity's display, i.e. Android's
  /// `Surface.ROTATION_0/90/180/270`. The preview texture is always delivered
  /// upright for the device's *natural* orientation, so anything showing it
  /// has to counter-rotate it by this amount (see [CameraPreviewView]).
  static Future<int> getDisplayRotation() async {
    try {
      final res = await _channel.invokeMethod<int>('getDisplayRotation');
      return ((res ?? 0) % 4 + 4) % 4;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> hasPermissions() async {
    final res = await _channel.invokeMethod<bool>('hasPermissions');
    return res ?? false;
  }

  Future<bool> requestPermissions() async {
    final resultFuture = _engineEvents.awaitCameraPermissionResult();
    await _channel.invokeMethod('requestPermissions');
    try {
      return await resultFuture.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      return false;
    }
  }

 Future<VaultCameraSessionInfo> open({
    String? cameraId,
    String facing = 'back',
    String quality = 'fhd',
    String photoResolution = 'max',
    bool scanMode = false,
  }) async {
    await close();

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('open', {
      'cameraId': cameraId,
      'facing': facing,
      'quality': quality,
      'photoResolution': photoResolution,
      'scanMode': scanMode,
    });

    if (res == null) throw Exception('Failed to open camera');
    final info = VaultCameraSessionInfo.fromMap(res);

    _sessionId = info.sessionId;
    _textureId = info.textureId;
    _cameraId = info.cameraId;
    _zoomMin = info.zoomMin;
    _zoomMax = info.zoomMax;
    _minExposureEv = info.minExposureEv;
    _maxExposureEv = info.maxExposureEv;
    _previewWidth = info.previewWidth;
    _previewHeight = info.previewHeight;
    _sensorOrientation = info.sensorOrientation;
    _lenses = info.lenses;

    final eventChannel = EventChannel('com.aeidolon.vaultexplorer/camera/events/$_sessionId');
    _eventSubscription = eventChannel.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        _eventsController.add(Map<String, dynamic>.from(data));
      }
    });

    return info;
  }

  Future<void> setZoom(double zoom) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setZoom', {
      'sessionId': sId,
      'zoom': zoom,
    });
  }

  Future<void> setFlash(String mode) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setFlash', {
      'sessionId': sId,
      'mode': mode,
    });
  }

  Future<void> setExposureOffset(double ev) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setExposureOffset', {
      'sessionId': sId,
      'ev': ev,
    });
  }

  Future<void> setFocusAndExposurePoint(double x, double y) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setFocusAndExposurePoint', {
      'sessionId': sId,
      'x': x,
      'y': y,
    });
  }

  Future<void> setOrientationDegrees(int degrees) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setOrientationDegrees', {
      'sessionId': sId,
      'degrees': degrees,
    });
  }

   Future<({bool success, Uint8List? bytes, Uint8List? thumbnail, String? error})> capturePhoto() async {
    final sId = _sessionId;
    if (sId == null) return (success: false, bytes: null, thumbnail: null, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('capturePhoto', {
      'sessionId': sId,
    });

    final ok = res?['success'] as bool? ?? false;
    final bytes = res?['bytes'] as Uint8List?;
    final thumbnail = res?['thumbnail'] as Uint8List?;
    final error = res?['error'] as String?;
    return (success: ok, bytes: bytes, thumbnail: thumbnail, error: error);
  }

  Future<bool> savePhotoToVault({
    required Uint8List bytes,
    required int volId,
    required String virtualPath,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('savePhotoToVault', {
        'bytes': bytes,
        'volId': volId,
        'virtualPath': virtualPath,
      });
      return res?['success'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<({bool success, String? error})> takePhoto({
    required int volId,
    required String virtualPath,
  }) async {
    final sId = _sessionId;
    if (sId == null) return (success: false, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('takePhoto', {
      'sessionId': sId,
      'volId': volId,
      'virtualPath': virtualPath,
    });

    final ok = res?['success'] as bool? ?? false;
    final error = res?['error'] as String?;
    return (success: ok, error: error);
  }

  Future<({bool success, String? error})> takePhotoToScratchpad({
    required String sessionToken,
    required String scratchpadPath,
  }) async {
    final sId = _sessionId;
    if (sId == null) return (success: false, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('takePhotoToScratchpad', {
      'sessionId': sId,
      'sessionToken': sessionToken,
      'scratchpadPath': scratchpadPath,
    });

    final ok = res?['success'] as bool? ?? false;
    final error = res?['error'] as String?;
    return (success: ok, error: error);
  }

  Future<({bool success, String? error})> startVideoRecording({
    required int volId,
    required String virtualPath,
  }) async {
    final sId = _sessionId;
    if (sId == null) return (success: false, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('startVideoRecording', {
      'sessionId': sId,
      'volId': volId,
      'virtualPath': virtualPath,
    });

    final ok = res?['success'] as bool? ?? false;
    final error = res?['error'] as String?;
    return (success: ok, error: error);
  }

  Future<({bool success, String? error})> startVideoRecordingToScratchpad({
    required String sessionToken,
    required String scratchpadPath,
  }) async {
    final sId = _sessionId;
    if (sId == null) return (success: false, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'startVideoRecordingToScratchpad',
      {
        'sessionId': sId,
        'sessionToken': sessionToken,
        'scratchpadPath': scratchpadPath,
      },
    );

    final ok = res?['success'] as bool? ?? false;
    final error = res?['error'] as String?;
    return (success: ok, error: error);
  }

   Future<({bool success, String? videoPath, int durationMs, Uint8List? thumbnail, String? error})> stopVideoRecordingForReview() async {
    final sId = _sessionId;
    if (sId == null) return (success: false, videoPath: null, durationMs: 0, thumbnail: null, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('stopVideoRecordingForReview', {
      'sessionId': sId,
    });

    final ok = res?['success'] as bool? ?? false;
    final videoPath = res?['videoPath'] as String?;
    final durationMs = (res?['durationMs'] as num?)?.toInt() ?? 0;
    final thumbnail = res?['thumbnail'] as Uint8List?;
    final error = res?['error'] as String?;
    return (success: ok, videoPath: videoPath, durationMs: durationMs, thumbnail: thumbnail, error: error);
  }

  Future<String?> trimVideo({
    required String videoPath,
    required int startMs,
    required int endMs,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('trimVideo', {
        'videoPath': videoPath,
        'startMs': startMs,
        'endMs': endMs,
      });
      return res?['videoPath'] as String?;
    } catch (_) {
      return videoPath;
    }
  }

  Future<bool> saveVideoToVault({
    required String videoPath,
    required int volId,
    required String virtualPath,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('saveVideoToVault', {
        'videoPath': videoPath,
        'volId': volId,
        'virtualPath': virtualPath,
      });
      return res?['success'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveVideoToScratchpad({
    required String videoPath,
    required String sessionToken,
    required String scratchpadPath,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('saveVideoToScratchpad', {
        'videoPath': videoPath,
        'sessionToken': sessionToken,
        'scratchpadPath': scratchpadPath,
      });
      return res?['success'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> discardVideo(String videoPath) async {
    try {
      await _channel.invokeMethod('discardVideo', {'videoPath': videoPath});
    } catch (_) {}
  }

  Future<({bool success, int durationMs, String? error})> stopVideoRecording() async {
    final sId = _sessionId;
    if (sId == null) return (success: false, durationMs: 0, error: 'Camera not open');

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('stopVideoRecording', {
      'sessionId': sId,
    });

    final ok = res?['success'] as bool? ?? false;
    final durationMs = (res?['durationMs'] as num?)?.toInt() ?? 0;
    final error = res?['error'] as String?;
    return (success: ok, durationMs: durationMs, error: error);
  }
  Future<void> setWhiteBalance(String mode) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setWhiteBalance', {
      'sessionId': sId,
      'mode': mode,
    });
  }

  Future<void> resetFocusAndExposure() async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('resetFocusAndExposure', {
      'sessionId': sId,
    });
  }

  Future<void> setScanMode(bool enable) async {
    final sId = _sessionId;
    if (sId == null) return;
    await _channel.invokeMethod('setScanMode', {
      'sessionId': sId,
      'enable': enable,
    });
  }

  Future<void> close() async {
    final sId = _sessionId;
    _sessionId = null;
    _textureId = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (sId != null) {
      try {
        await _channel.invokeMethod('close', {'sessionId': sId});
      } catch (e) {
        VeLog.e('VaultCameraController', 'Native session close failed (sessionId=$sId)', e);
      }
    }
  }

  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Gesture-handler helpers shared by camera_capture_screen.dart and
// quick_capture_screen.dart. Both screens wire up an identical set of
// focus/zoom/exposure/flash gestures against a [VaultCameraController];
// these wrap that boilerplate (the native call is advisory — local session
// state, not the hardware round trip, is the source of truth for what the
// UI shows, so a failure here is swallowed rather than surfaced) so it
// exists in one place instead of two.

/// Tap-to-focus. Not high-frequency (one call per tap), so failures are
/// logged.
Future<void> applyFocusAndExposurePoint(
  VaultCameraController controller,
  double x,
  double y, {
  required String logTag,
}) async {
  try {
    await controller.setFocusAndExposurePoint(x, y);
  } catch (e) {
    VeLog.w(logTag, 'setFocusAndExposurePoint failed', e);
  }
}

/// Re-applies flash mode after a photo/video mode switch. One call per
/// switch, so failures are logged.
Future<void> applyFlash(
  VaultCameraController controller,
  String mode, {
  required String logTag,
}) async {
  try {
    await controller.setFlash(mode);
  } catch (e) {
    VeLog.w(logTag, 'setFlash failed after mode switch', e);
  }
}

/// Discrete zoom-level chip tap. One call per tap, so failures are logged.
Future<void> applyZoomLogged(
  VaultCameraController controller,
  double zoom, {
  required String logTag,
}) async {
  try {
    await controller.setZoom(zoom);
  } catch (e) {
    VeLog.w(logTag, 'setZoom failed', e);
  }
}

/// Pinch-to-zoom. Fires on every pointer-move of the gesture, so this is
/// deliberately unlogged to avoid spamming the log stream during a drag.
Future<void> applyZoomSilent(
  VaultCameraController controller,
  double zoom,
) async {
  try {
    await controller.setZoom(zoom);
  } catch (_) {}
}

/// Exposure slider drag. Fires on every pointer-move, same reasoning as
/// [applyZoomSilent].
Future<void> applyExposureOffsetSilent(
  VaultCameraController controller,
  double ev,
) async {
  try {
    await controller.setExposureOffset(ev);
  } catch (_) {}
}

/// Device-rotation counter-rotation, called from the accelerometer stream
/// listener on every snapped-angle change — high-frequency and, unlike the
/// other setters here, wasn't even wrapped in a try/catch before, so a
/// failure became an unhandled Future error. Deliberately unlogged for the
/// same reason as [applyZoomSilent]; the try/catch itself is the fix.
Future<void> applyOrientationSilent(
  VaultCameraController controller,
  int degrees,
) async {
  try {
    await controller.setOrientationDegrees(degrees);
  } catch (_) {}
}