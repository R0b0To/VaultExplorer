import 'dart:async';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';

class NativeCameraLens {
  final String cameraId;
  final String facing; // 'back', 'front', 'external'
  final bool isLogical;
  final double zoomMin;
  final double zoomMax;
  // Approximate optical zoom factor vs. this facing's primary/wide lens
  // (e.g. ~0.5 for ultrawide, 1.0 for the main lens, ~2-5 for telephoto).
  // Derived natively from focal length + sensor size, since each physical
  // lens's own zoomMin/zoomMax is relative to itself (nearly always 1.0)
  // and isn't meaningful for comparing lenses against each other.
  final double relativeZoom;

  const NativeCameraLens({
    required this.cameraId,
    required this.facing,
    required this.isLogical,
    required this.zoomMin,
    required this.zoomMax,
    this.relativeZoom = 1.0,
  });

  factory NativeCameraLens.fromMap(Map<dynamic, dynamic> map) {
    return NativeCameraLens(
      cameraId: map['cameraId'] as String? ?? '',
      facing: map['facing'] as String? ?? 'back',
      isLogical: map['isLogical'] as bool? ?? false,
      zoomMin: (map['zoomMin'] as num?)?.toDouble() ?? 1.0,
      zoomMax: (map['zoomMax'] as num?)?.toDouble() ?? 1.0,
      relativeZoom: (map['relativeZoom'] as num?)?.toDouble() ?? 1.0,
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
  /// The preview's on-screen aspect ratio (width / height) once the sensor's
  /// mounting rotation is accounted for. Camera2 always reports preview
  /// sizes in the sensor's own landscape coordinate space, so a 90/270
  /// mounting (true on virtually every phone) means the on-screen aspect
  /// ratio is actually the *inverse* of previewWidth/previewHeight.
  double get previewAspectRatio {
    final rotated = _sensorOrientation % 180 != 0;
    final w = rotated ? _previewHeight : _previewWidth;
    final h = rotated ? _previewWidth : _previewHeight;
    if (h == 0) return 1.0;
    return w / h;
  }

  List<NativeCameraLens> get lenses => _lenses;
  bool get isInitialized => _sessionId != null && _textureId != null;

  static Future<bool> hasPermissions() async {
    final res = await _channel.invokeMethod<bool>('hasPermissions');
    return res ?? false;
  }

  /// Requests camera + microphone permission and waits for the user to
  /// actually answer the system dialog, returning whether it was granted.
  /// Previously this only fired the request and returned immediately, so
  /// callers proceeded to open the camera before the dialog was answered.
  Future<bool> requestPermissions() async {
    final resultFuture = _engineEvents.awaitCameraPermissionResult();
    await _channel.invokeMethod('requestPermissions');
    try {
      return await resultFuture.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      // The user backgrounded the app / dismissed the dialog without it
      // resolving (shouldn't normally happen, but don't hang forever).
      return false;
    }
  }

  Future<VaultCameraSessionInfo> open({
    String? cameraId,
    String facing = 'back',
    String quality = 'fhd',
  }) async {
    await close();

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('open', {
      if (cameraId != null) 'cameraId': cameraId,
      'facing': facing,
      'quality': quality,
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

  Future<void> switchLens(String cameraId) async {
    final sId = _sessionId;
    if (sId == null) return;

    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('switchLens', {
      'sessionId': sId,
      'cameraId': cameraId,
    });

    if (res != null) {
      _textureId = (res['textureId'] as num?)?.toInt() ?? _textureId;
      _cameraId = res['cameraId'] as String? ?? _cameraId;
      _zoomMin = (res['zoomMin'] as num?)?.toDouble() ?? _zoomMin;
      _zoomMax = (res['zoomMax'] as num?)?.toDouble() ?? _zoomMax;
      _minExposureEv = (res['minExposureEv'] as num?)?.toDouble() ?? _minExposureEv;
      _maxExposureEv = (res['maxExposureEv'] as num?)?.toDouble() ?? _maxExposureEv;
      _previewWidth = (res['previewWidth'] as num?)?.toInt() ?? _previewWidth;
      _previewHeight = (res['previewHeight'] as num?)?.toInt() ?? _previewHeight;
      _sensorOrientation = (res['sensorOrientation'] as num?)?.toInt() ?? _sensorOrientation;
    }
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

  Future<void> close() async {
    final sId = _sessionId;
    _sessionId = null;
    _textureId = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (sId != null) {
      try {
        await _channel.invokeMethod('close', {'sessionId': sId});
      } catch (_) {
        // Best-effort teardown: _sessionId is already cleared above, so
        // this controller is done with the native session regardless of
        // whether the close call itself succeeds.
      }
    }
  }

  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}
