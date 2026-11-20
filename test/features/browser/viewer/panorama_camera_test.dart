import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/panorama/panorama_camera.dart';

// Phone held upright facing north: screen x = East, screen y = Up,
// screen -z = North. Row-major screen->world (East, North, Up).
const _facingNorth = <double>[1, 0, 0, 0, 0, -1, 0, 1, 0];
// Same phone turned to face east.
const _facingEast = <double>[0, 0, -1, -1, 0, 0, 0, 1, 0];

void main() {
  PanoramaCamera camera() =>
      PanoramaCamera(yaw: 0, pitch: 0, fov: math.pi / 2);

  test('first sample anchors the view to the requested heading', () {
    final c = camera()..beginSensor(1.0);
    c.onDeviceMatrix(_facingEast);
    expect(c.forward().heading, closeTo(1.0, 1e-9));
    expect(c.forward().pitch, closeTo(0, 1e-9));
  });

  test('turning the phone turns the view by the same angle', () {
    final c = camera()..beginSensor(0);
    c.onDeviceMatrix(_facingNorth);
    expect(c.forward().heading, closeTo(0, 1e-9));
    // Feed the east sample until the smoothing has converged.
    for (var i = 0; i < 200; i++) {
      c.onDeviceMatrix(_facingEast);
    }
    expect(c.forward().heading, closeTo(math.pi / 2, 1e-3));
  });

  test('ending sensor mode keeps the look direction', () {
    final c = camera()..beginSensor(0.5);
    c.onDeviceMatrix(_facingEast);
    c.rotateBy(0.3, 0.2);
    final before = c.forward();
    c.endSensor();
    expect(c.sensorActive, isFalse);
    expect(c.yaw, closeTo(before.heading, 1e-9));
    expect(c.pitch, closeTo(before.pitch, 1e-9));
  });

  test('drag is slower when zoomed in and clamps pitch', () {
    final wide = camera()..setFov(PanoramaCamera.maxFov);
    final tight = camera()..setFov(PanoramaCamera.minFov);
    expect(tight.radiansPerPixel(800), lessThan(wide.radiansPerPixel(800)));
    final c = camera();
    c.rotateBy(0, 10);
    expect(c.pitch, closeTo(math.pi / 2, 1e-12));
  });
}
