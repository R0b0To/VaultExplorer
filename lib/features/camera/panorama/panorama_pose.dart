import 'dart:math' as math;

/// Orientation maths for panorama capture. A "pose" is 9 numbers, row-major:
/// the camera's rotation, mapping the upright image's axes (x right, y up, the
/// camera looks down -z) to the panorama frame (East, Up, -North). It is the
/// same convention as PanoramaCamera and the stitcher.

/// Android's screen->world matrix (East, North, Up) as a pose.
List<double> poseFromAndroid(List<double> m) => <double>[
  m[0], m[1], m[2], //
  m[6], m[7], m[8],
  -m[3], -m[4], -m[5],
];

/// Unit vector the camera looks along.
({double x, double y, double z}) lookDirection(List<double> p) =>
    (x: -p[2], y: -p[5], z: -p[8]);

/// Direction for a latitude/longitude on the panorama sphere (heading 0 = -z).
({double x, double y, double z}) directionOf(double lat, double lon) => (
  x: math.cos(lat) * math.sin(lon),
  y: math.sin(lat),
  z: -math.cos(lat) * math.cos(lon),
);

double latitudeOf(({double x, double y, double z}) d) =>
    math.asin(d.y.clamp(-1.0, 1.0).toDouble());

double longitudeOf(({double x, double y, double z}) d) => math.atan2(d.x, -d.z);

/// Angle in radians between two unit directions.
double angleBetween(
  ({double x, double y, double z}) a,
  ({double x, double y, double z}) b,
) {
  final dot = (a.x * b.x + a.y * b.y + a.z * b.z).clamp(-1.0, 1.0).toDouble();
  return math.acos(dot);
}

/// Angle in radians of the rotation taking pose [a] to pose [b] (all three
/// axes, so a roll of the phone counts too).
double poseAngle(List<double> a, List<double> b) {
  var trace = 0.0;
  for (var i = 0; i < 9; i++) {
    trace += a[i] * b[i];
  }
  return math.acos(((trace - 1) / 2).clamp(-1.0, 1.0).toDouble());
}

/// Rows of [a] blended towards [b] by [t], re-orthonormalised.
List<double> blendPoses(List<double> a, List<double> b, double t) {
  final m = List<double>.generate(9, (i) => a[i] + (b[i] - a[i]) * t);
  return orthonormalize(m);
}

List<double> orthonormalize(List<double> m) {
  List<double> norm(List<double> v) {
    final len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return len < 1e-9 ? v : <double>[v[0] / len, v[1] / len, v[2] / len];
  }

  final r0 = norm(<double>[m[0], m[1], m[2]]);
  var r1 = <double>[m[3], m[4], m[5]];
  final d = r0[0] * r1[0] + r0[1] * r1[1] + r0[2] * r1[2];
  r1 = norm(<double>[r1[0] - r0[0] * d, r1[1] - r0[1] * d, r1[2] - r0[2] * d]);
  final r2 = <double>[
    r0[1] * r1[2] - r0[2] * r1[1],
    r0[2] * r1[0] - r0[0] * r1[2],
    r0[0] * r1[1] - r0[1] * r1[0],
  ];
  return <double>[...r0, ...r1, ...r2];
}

/// Where a panorama-frame direction lands on the screen: x/y in -1..1 across
/// the image edges (so |x|,|y| <= 1 is on screen), or null behind the camera.
({double x, double y})? projectToScreen(
  List<double> p,
  ({double x, double y, double z}) d,
  double tanX,
  double tanY,
) {
  final vz = p[2] * d.x + p[5] * d.y + p[8] * d.z;
  if (vz > -1e-3) return null;
  final inv = -1 / vz;
  return (
    x: (p[0] * d.x + p[3] * d.y + p[6] * d.z) * inv / tanX,
    y: (p[1] * d.x + p[4] * d.y + p[7] * d.z) * inv / tanY,
  );
}

/// Direction of the screen point (nx, ny in -1..1) in the panorama frame.
({double x, double y, double z}) screenRay(
  List<double> p,
  double nx,
  double ny,
  double tanX,
  double tanY,
) {
  final rx = nx * tanX;
  final ry = ny * tanY;
  final x = p[0] * rx + p[1] * ry - p[2];
  final y = p[3] * rx + p[4] * ry - p[5];
  final z = p[6] * rx + p[7] * ry - p[8];
  final len = math.sqrt(x * x + y * y + z * z);
  return (x: x / len, y: y / len, z: z / len);
}

/// Wraps an angle into -pi..pi.
double wrapAngle(double a) {
  var r = (a + math.pi) % (2 * math.pi);
  if (r < 0) r += 2 * math.pi;
  return r - math.pi;
}
