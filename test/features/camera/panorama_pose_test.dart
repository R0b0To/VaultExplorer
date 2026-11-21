import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/camera/panorama/panorama_pose.dart';

// Phone upright facing north / east (Android screen->world, row-major).
const _north = <double>[1, 0, 0, 0, 0, -1, 0, 1, 0];
const _east = <double>[0, 0, -1, -1, 0, 0, 0, 1, 0];

void main() {
  test('facing north looks at heading 0, facing east at +90 degrees', () {
    final n = lookDirection(poseFromAndroid(_north));
    expect(longitudeOf(n), closeTo(0, 1e-9));
    expect(latitudeOf(n), closeTo(0, 1e-9));
    final e = lookDirection(poseFromAndroid(_east));
    expect(longitudeOf(e), closeTo(math.pi / 2, 1e-9));
  });

  test('a direction at the view centre projects to the screen centre', () {
    final pose = poseFromAndroid(_east);
    final p = projectToScreen(pose, lookDirection(pose), 0.5, 0.65)!;
    expect(p.x, closeTo(0, 1e-9));
    expect(p.y, closeTo(0, 1e-9));
    // Directly behind the camera is not visible.
    final d = lookDirection(pose);
    expect(
      projectToScreen(pose, (x: -d.x, y: -d.y, z: -d.z), 0.5, 0.65),
      isNull,
    );
  });

  test('screenRay is the inverse of projectToScreen', () {
    final pose = poseFromAndroid(_east);
    final ray = screenRay(pose, 0.4, -0.3, 0.5, 0.65);
    final back = projectToScreen(pose, ray, 0.5, 0.65)!;
    expect(back.x, closeTo(0.4, 1e-9));
    expect(back.y, closeTo(-0.3, 1e-9));
  });

  test('poseAngle measures the turn between two poses', () {
    final a = poseFromAndroid(_north);
    final b = poseFromAndroid(_east);
    expect(poseAngle(a, a), closeTo(0, 1e-6));
    expect(poseAngle(a, b), closeTo(math.pi / 2, 1e-9));
  });

  test('blendPoses stays a rotation', () {
    final m = blendPoses(poseFromAndroid(_north), poseFromAndroid(_east), 0.5);
    // Rows are orthonormal.
    double dot(int i, int j) =>
        m[i * 3] * m[j * 3] + m[i * 3 + 1] * m[j * 3 + 1] + m[i * 3 + 2] * m[j * 3 + 2];
    expect(dot(0, 0), closeTo(1, 1e-9));
    expect(dot(1, 1), closeTo(1, 1e-9));
    expect(dot(2, 2), closeTo(1, 1e-9));
    expect(dot(0, 1), closeTo(0, 1e-9));
    expect(poseAngle(poseFromAndroid(_north), m), closeTo(math.pi / 4, 1e-6));
  });
}
