import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/panorama/device_orientation_sensor.dart';
import 'package:vaultexplorer/features/camera/panorama/panorama_channel.dart';
import 'package:vaultexplorer/features/camera/panorama/panorama_pose.dart';

enum PanoramaKind { wide, sphere }

enum PanoramaPhase {
  /// Mode is on, the user has not pressed the shutter yet.
  ready,

  /// Shooting frames as the phone is moved.
  capturing,

  /// Frames are being stitched natively.
  stitching,
}

enum PanoramaHint { none, holdStill, keepLevel, moveToDot, sweep, tooFast }

typedef PanoramaShotCaptureResult = ({
  bool ok,
  List<double>? pose,
  double? motionRad,
});

/// One frame already taken: where it looks, in the panorama frame.
class PanoramaShot {
  PanoramaShot(this.pose);
  final List<double> pose;
}

/// A spot of the sphere the user has to aim at (sphere mode).
class PanoramaTarget {
  PanoramaTarget(this.lat, this.lon);
  final double lat;

  /// Absolute longitude in the panorama frame (already offset by the start heading).
  final double lon;
  bool done = false;

  late final ({double x, double y, double z}) direction = directionOf(lat, lon);
}

/// Guided panorama / photo-sphere capture.
///
/// In *wide* mode a frame is grabbed automatically every ~0.28x FOV (~70%
/// overlap) as you sweep either horizontally or vertically, with a horizon /
/// meridian guide line and target marker. In *sphere* mode it captures when you
/// rest on a dot OR hold steady on any uncovered area, and tapping Done/Stop in
/// either mode captures the final camera view if it adds new coverage.
class PanoramaCaptureController extends ChangeNotifier {
  PanoramaCaptureController({
    required this.capture,
    required this.onFeedback,
    required this.onResult,
    this.onCapturingChanged,
  });

  final Future<PanoramaShotCaptureResult> Function(int rotationDegrees) capture;
  final VoidCallback onFeedback;
  final void Function(PanoramaResult result) onResult;
  final void Function(bool capturing)? onCapturingChanged;

  static const int maxWideShots = 60;
  static const int maxTotalShots = 72;
  static const double _alignTolerance = 6.0 * math.pi / 180;
  static const double _maxRateWideHard = 34 * math.pi / 180; // rad/s
  static const double _warnRateWide = 25 * math.pi / 180;
  static const double _maxRateSphere = 13 * math.pi / 180;
  static const double _movementBlur = 2.5 * math.pi / 180;
  static const double _levelWarnTolerance = 16 * math.pi / 180;
  static const double _levelHardTolerance = 28 * math.pi / 180;

  PanoramaKind kind = PanoramaKind.wide;
  PanoramaPhase phase = PanoramaPhase.ready;
  PanoramaHint hint = PanoramaHint.none;

  /// 0..1 progress of the hold-still timer or sweep step.
  double holdProgress = 0;

  final List<PanoramaShot> shots = <PanoramaShot>[];
  List<PanoramaTarget> targets = <PanoramaTarget>[];

  /// Reference heading & elevation of the first frame.
  double originLon = 0;
  double originLat = 0;

  /// Wide sweep axis ('h' horizontal, 'v' vertical, null before movement) and sign (+1/-1).
  String? wideAxis;
  int wideSign = 1;

  double tanX = 0.49;
  double tanY = 0.65;
  double _tanLong = 0.65;
  double _photoAspectRatio = 4 / 3;

  bool get isLandscape => _landscape;
  bool _landscape = false;
  int _rotationDegrees = 0;
  bool _tanSet = false;

  List<double> viewPose = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  List<double> _rawPose = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  bool _hasPose = false;

  StreamSubscription<List<double>>? _sub;
  bool _busy = false;
  bool _disposed = false;
  bool _capturingNotified = false;
  DateTime? _lastSample;
  double _rate = 0;
  DateTime? _stillSince;
  DateTime? _freeStillSince;

  bool get hasPose => _hasPose;
  bool get busy => _busy;
  int get shotCount => shots.length;
  bool get isSphere => kind == PanoramaKind.sphere;
  int get targetsDone => targets.where((t) => t.done).length;

  double get wideStepAngle {
    final t = wideAxis == 'v'
        ? tanY
        : wideAxis == 'h'
            ? tanX
            : math.min(tanX, tanY);
    return 0.28 * 2 * math.atan(t);
  }

  /// Guide dots for wide mode: two starter dots before direction is chosen, or the single ahead dot.
  List<({double x, double y, double z})> get wideGuideDirections {
    if (isSphere || phase != PanoramaPhase.capturing || shots.isEmpty) return const [];
    final step = wideStepAngle;
    final last = lookDirection(shots.last.pose);
    final lastLon = longitudeOf(last);
    final lastLat = latitudeOf(last);
    if (wideAxis == null) {
      return [
        directionOf(originLat, wrapAngle(lastLon + step)),
        directionOf(originLat, wrapAngle(lastLon - step)),
      ];
    }
    if (wideAxis == 'v') {
      final nextLat = (lastLat + wideSign * step).clamp(-math.pi / 2 + 0.04, math.pi / 2 - 0.04);
      return [directionOf(nextLat, originLon)];
    }
    return [directionOf(originLat, wrapAngle(lastLon + wideSign * step))];
  }

  PanoramaTarget? get nextTarget {
    if (!isSphere || !_hasPose) return null;
    final look = lookDirection(viewPose);
    PanoramaTarget? best;
    var bestAngle = double.infinity;
    for (final t in targets) {
      if (t.done) continue;
      final a = angleBetween(look, t.direction);
      if (a < bestAngle) {
        bestAngle = a;
        best = t;
      }
    }
    return best;
  }

  Future<void> open({
    required double? fovHalfTangentLong,
    required int rotationDegrees,
    double photoAspectRatio = 4 / 3,
  }) async {
    _tanLong = fovHalfTangentLong ?? 0.65;
    _photoAspectRatio = photoAspectRatio > 1.0 ? photoAspectRatio : 4 / 3;
    _tanSet = false;
    updateRotation(rotationDegrees);
    await PanoramaChannel.begin();
    _sub ??= DeviceOrientationSensor.matrices().listen(
      _onMatrix,
      onError: (_) {},
    );
    phase = PanoramaPhase.ready;
    shots.clear();
    targets = <PanoramaTarget>[];
    _setCapturingActive(false);
    _notify();
  }

  void updateRotation(int rotationDegrees) {
    if (rotationDegrees == _rotationDegrees && _tanSet) return;
    _tanSet = true;
    _rotationDegrees = rotationDegrees;
    _landscape = (rotationDegrees ~/ 90).isOdd;
    final short = _tanLong / _photoAspectRatio;
    tanX = _landscape ? _tanLong : short;
    tanY = _landscape ? short : _tanLong;
    _notify();
  }

  void setKind(PanoramaKind value) {
    if (phase != PanoramaPhase.ready || kind == value) return;
    kind = value;
    _notify();
  }

  void _setCapturingActive(bool active) {
    if (_capturingNotified == active) return;
    _capturingNotified = active;
    onCapturingChanged?.call(active);
  }

  void start() {
    if (phase != PanoramaPhase.ready || !_hasPose) return;
    shots.clear();
    wideAxis = null;
    wideSign = 1;
    final look = lookDirection(_rawPose);
    originLon = longitudeOf(look);
    originLat = latitudeOf(look);
    targets = isSphere ? _buildTargets(originLon) : <PanoramaTarget>[];
    phase = PanoramaPhase.capturing;
    _stillSince = null;
    _freeStillSince = null;
    _setCapturingActive(true);
    _notify();
    unawaited(_shoot(null));
  }

  List<PanoramaTarget> _buildTargets(double lon0) {
    final hFov = 2 * math.atan(tanX);
    final vFov = 2 * math.atan(tanY);
    final latStep = 0.56 * math.min(vFov, 2 * math.atan(math.max(tanX, tanY)));
    final lonStepBase = 0.56 * math.min(hFov, vFov);
    final out = <PanoramaTarget>[];
    final rings = (math.pi / 2 / latStep).floor();
    for (var k = -rings; k <= rings; k++) {
      final lat = k * latStep;
      if (lat.abs() > math.pi / 2 - 0.05) continue;
      final circumference = math.cos(lat);
      final n = math.max(1, (2 * math.pi * circumference / lonStepBase).ceil());
      for (var i = 0; i < n; i++) {
        out.add(PanoramaTarget(lat, wrapAngle(lon0 + i * 2 * math.pi / n)));
      }
    }
    out.add(PanoramaTarget(math.pi / 2 - 0.02, lon0));
    out.add(PanoramaTarget(-math.pi / 2 + 0.02, lon0));
    return out;
  }

  void _onMatrix(List<double> m) {
    if (_disposed) return;
    final pose = poseFromAndroid(m);
    final now = DateTime.now();
    if (_hasPose) {
      final dt = _lastSample == null
          ? 0.02
          : (now.difference(_lastSample!).inMicroseconds / 1e6).clamp(0.005, 0.2);
      final instant = poseAngle(_rawPose, pose) / dt;
      _rate += (instant - _rate) * 0.4;
      viewPose = blendPoses(viewPose, pose, 0.45);
    } else {
      viewPose = pose;
      _hasPose = true;
    }
    _rawPose = pose;
    _lastSample = now;
    if (phase == PanoramaPhase.capturing && !_busy) _drive(now);
    _notify();
  }

  double _minAngleToShots(({double x, double y, double z}) dir) {
    var best = double.infinity;
    for (final s in shots) {
      final a = angleBetween(dir, lookDirection(s.pose));
      if (a < best) best = a;
    }
    return best;
  }

  void _markTargetsCoveredBy(List<double> pose) {
    if (!isSphere) return;
    final shotDir = lookDirection(pose);
    final coverAngle = 0.42 * 2 * math.atan(math.min(tanX, tanY));
    for (final t in targets) {
      if (!t.done && angleBetween(shotDir, t.direction) <= coverAngle) {
        t.done = true;
      }
    }
  }

  void _drive(DateTime now) {
    final look = lookDirection(viewPose);

    if (isSphere) {
      if (shots.length >= maxTotalShots) {
        unawaited(finish());
        return;
      }
      final target = nextTarget;
      if (target == null) {
        unawaited(finish());
        return;
      }
      final off = angleBetween(look, target.direction);
      if (off <= _alignTolerance) {
        _freeStillSince = null;
        if (_rate > _maxRateSphere) {
          hint = PanoramaHint.holdStill;
          _stillSince = null;
          holdProgress = 0;
          return;
        }
        _stillSince ??= now;
        final held = now.difference(_stillSince!).inMilliseconds;
        holdProgress = (held / 140).clamp(0.0, 1.0);
        hint = PanoramaHint.holdStill;
        if (held >= 140) unawaited(_shoot(target));
        return;
      }

      // Free-point auto-capture: if user holds steady at an uncovered position
      // between circle dots, capture it anyway so they aren't stuck on dots.
      _stillSince = null;
      final minFov = 2 * math.atan(math.min(tanX, tanY));
      final nearestShot = _minAngleToShots(look);
      if (nearestShot >= 0.48 * minFov && _rate <= _maxRateSphere) {
        _freeStillSince ??= now;
        final held = now.difference(_freeStillSince!).inMilliseconds;
        holdProgress = (held / 240).clamp(0.0, 1.0);
        hint = PanoramaHint.holdStill;
        if (held >= 240) unawaited(_shoot(null));
      } else {
        _freeStillSince = null;
        holdProgress = 0;
        hint = PanoramaHint.moveToDot;
      }
      return;
    }

    // Wide mode
    if (shots.isEmpty) return;
    if (shots.length >= maxWideShots || shots.length >= maxTotalShots) {
      unawaited(finish());
      return;
    }

    if (wideAxis == null) {
      final firstLook = lookDirection(shots.first.pose);
      final movedFirst = angleBetween(look, firstLook);
      if (movedFirst > 4.0 * math.pi / 180) {
        final dLon = wrapAngle(longitudeOf(look) - originLon);
        final dLat = latitudeOf(look) - originLat;
        if (dLon.abs() >= dLat.abs()) {
          wideAxis = 'h';
          wideSign = dLon >= 0 ? 1 : -1;
        } else {
          wideAxis = 'v';
          wideSign = dLat >= 0 ? 1 : -1;
        }
      }
    }

    final drift = wideAxis == 'v'
        ? wrapAngle(longitudeOf(look) - originLon).abs()
        : (latitudeOf(look) - originLat).abs();
    if (drift > _levelHardTolerance) {
      hint = PanoramaHint.keepLevel;
      holdProgress = 0;
      return;
    }

    final last = lookDirection(shots.last.pose);
    final moved = angleBetween(look, last);
    final step = wideStepAngle;
    if (moved < step) {
      hint = drift > _levelWarnTolerance
          ? PanoramaHint.keepLevel
          : (_rate > _warnRateWide ? PanoramaHint.tooFast : PanoramaHint.sweep);
      holdProgress = (moved / step).clamp(0.0, 1.0);
      return;
    }
    if (_minAngleToShots(look) < step * 0.60) {
      hint = PanoramaHint.sweep;
      holdProgress = 0;
      return;
    }
    if (_rate > _maxRateWideHard) {
      hint = PanoramaHint.tooFast;
      return;
    }
    holdProgress = 1;
    hint = _rate > _warnRateWide ? PanoramaHint.tooFast : PanoramaHint.sweep;
    unawaited(_shoot(null));
  }

  Future<void> _shoot(
    PanoramaTarget? target, {
    bool ignoreMotionLimit = false,
  }) async {
    if (_busy || _disposed || shots.length >= maxTotalShots) return;
    _busy = true;
    _stillSince = null;
    _freeStillSince = null;
    _notify();
    try {
      final before = List<double>.of(_rawPose);
      final shot = await capture(_rotationDegrees);
      final after = List<double>.of(_rawPose);
      if (!shot.ok) {
        await PanoramaChannel.discard();
        return;
      }
      final motion = shot.motionRad ?? poseAngle(before, after);
      final maxAllowed = ignoreMotionLimit ? 6.0 * math.pi / 180 : _movementBlur;
      if (motion > maxAllowed) {
        await PanoramaChannel.discard();
        return;
      }
      final pose = (shot.pose != null && shot.pose!.length >= 9)
          ? shot.pose!
          : blendPoses(before, after, 0.5);
      final count = await PanoramaChannel.commit(rows: pose, tanHalfLong: _tanLong);
      if (count == null) return;
      shots.add(PanoramaShot(pose));
      target?.done = true;
      _markTargetsCoveredBy(pose);
      holdProgress = 0;
      onFeedback();
    } catch (_) {
      await PanoramaChannel.discard();
    } finally {
      _busy = false;
      _notify();
    }
  }

  bool _finishing = false;

  /// Captures the final stopping view if it adds coverage, then stitches.
  Future<void> finish() async {
    if (phase != PanoramaPhase.capturing || _finishing) return;
    _finishing = true;
    try {
      var guard = 0;
      while (_busy && guard++ < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_disposed) return;

      // Always grab the user's stopping view if they moved away from earlier shots
      // (fixes cutting off the end of a wide sweep or stopping between sphere dots).
      if (shots.isNotEmpty && shots.length < maxTotalShots && _hasPose) {
        final minGap = isSphere
            ? 8.0 * math.pi / 180.0
            : 5.0 * math.pi / 180.0;
        final nearest = _minAngleToShots(lookDirection(_rawPose));
        if (nearest >= minGap) {
          await _shoot(null, ignoreMotionLimit: true);
        }
      }

      if (_disposed) return;
      _setCapturingActive(false);
      if (shots.length < 2) {
        await cancel();
        onResult(PanoramaResult.failure('too few frames'));
        return;
      }
      phase = PanoramaPhase.stitching;
      _notify();
      final result = await PanoramaChannel.finish(sphere: isSphere);
      if (_disposed) return;
      reset();
      onResult(result);
    } finally {
      _finishing = false;
    }
  }

  Future<void> cancel() async {
    await PanoramaChannel.cancel();
    reset();
  }

  void reset() {
    _setCapturingActive(false);
    phase = PanoramaPhase.ready;
    shots.clear();
    targets = <PanoramaTarget>[];
    wideAxis = null;
    holdProgress = 0;
    hint = PanoramaHint.none;
    _stillSince = null;
    _freeStillSince = null;
    _notify();
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _hasPose = false;
    _lastSample = null;
    _rate = 0;
    try {
      await PanoramaChannel.cancel();
    } catch (_) {}
    reset();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _setCapturingActive(false);
    unawaited(_sub?.cancel());
    super.dispose();
  }
}