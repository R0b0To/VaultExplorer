import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where the 360° viewer is looking, for both touch and gyro modes.
///
/// Conventions match shaders/panorama_viewer.frag: +Y is up, heading 0 looks
/// down -Z, and heading grows towards +X. In gyro mode the world frame is
/// (East, Up, -North), so heading 0 is north.
///
/// * Touch mode: [yaw] and [pitch] are the absolute look direction.
/// * Gyro mode: the look direction is the device attitude ([rows]) with
///   [pitch] as a local tilt offset and [yaw] as a heading offset, so a drag
///   lets the user re-centre without fighting the sensor.
class PanoramaCamera extends ChangeNotifier {
  PanoramaCamera({
    required this.yaw,
    required this.pitch,
    required double fov,
  }) : fov = fov.clamp(minFov, maxFov).toDouble();

  static const double minFov = 35 * math.pi / 180;
  static const double maxFov = 110 * math.pi / 180;

  /// Drag sensitivity: 1.0 would make the image follow the finger exactly at
  /// the centre of the screen. Lower is calmer. Scaling by the field of view
  /// means a zoomed-in view pans proportionally slower, instead of a swipe
  /// always being a fixed fraction of a full turn.
  static const double panSensitivity = 0.65;

  /// Per-sample blend towards the newest sensor reading (0..1). Removes
  /// micro-jitter without noticeable lag at the ~50 Hz sensor rate.
  static const double sensorSmoothing = 0.25;

  double yaw;
  double pitch;
  double fov;

  bool _sensorActive = false;
  bool _hasSample = false;
  double _anchorHeading = 0;

  /// Rotation rows (panorama frame) as 9 numbers, row-major.
  final List<double> rows = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];

  bool get sensorActive => _sensorActive;
  bool get hasSensorSample => _hasSample;

  /// Radians per screen pixel at the current zoom.
  double radiansPerPixel(double viewportHeight) =>
      viewportHeight <= 0 ? 0 : fov / viewportHeight * panSensitivity;

  void panBy(Offset delta, double viewportHeight) {
    final rpp = radiansPerPixel(viewportHeight);
    rotateBy(-delta.dx * rpp, delta.dy * rpp);
  }

  void rotateBy(double dYaw, double dPitch) {
    yaw += dYaw;
    pitch = (pitch + dPitch).clamp(-math.pi / 2, math.pi / 2).toDouble();
    notifyListeners();
  }

  void setFov(double value) {
    fov = value.clamp(minFov, maxFov).toDouble();
    notifyListeners();
  }

  /// Starts following the device. The first sample is anchored so that it
  /// looks towards [anchorHeading] (radians), e.g. the image's initial view,
  /// instead of towards real north.
  void beginSensor(double anchorHeading) {
    _sensorActive = true;
    _hasSample = false;
    _anchorHeading = anchorHeading;
    pitch = 0;
    notifyListeners();
  }

  /// Stops following the device and converts the current look direction back
  /// into [yaw]/[pitch] so switching to touch mode does not jump.
  void endSensor() {
    if (_sensorActive && _hasSample) {
      final f = forward();
      yaw = f.heading;
      pitch = f.pitch;
    }
    _sensorActive = false;
    _hasSample = false;
    notifyListeners();
  }

  /// Keeps the current view across a pause (app in background): the next
  /// sample re-anchors to where the user was looking.
  void suspendSensor() {
    if (!_sensorActive) return;
    if (_hasSample) _anchorHeading = forward().heading;
    _hasSample = false;
  }

  void onDeviceMatrix(List<double> m) {
    if (!_sensorActive || m.length < 9) return;
    // World (East, North, Up) -> panorama frame (East, Up, -North).
    final target = <double>[
      m[0], m[1], m[2], //
      m[6], m[7], m[8],
      -m[3], -m[4], -m[5],
    ];
    if (!_hasSample) {
      for (var i = 0; i < 9; i++) {
        rows[i] = target[i];
      }
      _hasSample = true;
      yaw = _anchorHeading - _headingOfRows();
      notifyListeners();
      return;
    }
    for (var i = 0; i < 9; i++) {
      rows[i] += (target[i] - rows[i]) * sensorSmoothing;
    }
    _orthonormalize();
    notifyListeners();
  }

  /// Heading (clockwise from the panorama's centre, radians) and pitch of the
  /// direction currently shown in the middle of the screen.
  ({double heading, double pitch}) forward() {
    if (!_sensorActive || !_hasSample) {
      return (heading: yaw, pitch: pitch);
    }
    final dir = _applyYaw(_deviceRotate(0, math.sin(pitch), -math.cos(pitch)));
    return (
      heading: math.atan2(dir[0], -dir[2]),
      pitch: math.asin(dir[1].clamp(-1.0, 1.0).toDouble()),
    );
  }

  // Heading of the raw device direction (screen -Z axis), ignoring offsets.
  double _headingOfRows() => math.atan2(-rows[2], rows[8]);

  List<double> _deviceRotate(double x, double y, double z) => <double>[
    rows[0] * x + rows[1] * y + rows[2] * z,
    rows[3] * x + rows[4] * y + rows[5] * z,
    rows[6] * x + rows[7] * y + rows[8] * z,
  ];

  List<double> _applyYaw(List<double> w) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return <double>[c * w[0] - s * w[2], w[1], s * w[0] + c * w[2]];
  }

  void _orthonormalize() {
    var r0 = _row(0);
    var r1 = _row(1);
    r0 = _normalize(r0);
    final d = _dot(r0, r1);
    r1 = _normalize(<double>[
      r1[0] - r0[0] * d,
      r1[1] - r0[1] * d,
      r1[2] - r0[2] * d,
    ]);
    final r2 = <double>[
      r0[1] * r1[2] - r0[2] * r1[1],
      r0[2] * r1[0] - r0[0] * r1[2],
      r0[0] * r1[1] - r0[1] * r1[0],
    ];
    for (var i = 0; i < 3; i++) {
      rows[i] = r0[i];
      rows[3 + i] = r1[i];
      rows[6 + i] = r2[i];
    }
  }

  List<double> _row(int i) => <double>[rows[i * 3], rows[i * 3 + 1], rows[i * 3 + 2]];

  static double _dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  static List<double> _normalize(List<double> v) {
    final len = math.sqrt(_dot(v, v));
    if (len < 1e-9) return v;
    return <double>[v[0] / len, v[1] / len, v[2] / len];
  }
}
