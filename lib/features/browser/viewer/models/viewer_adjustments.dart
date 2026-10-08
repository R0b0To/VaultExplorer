import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Non-destructive picture adjustments applied while viewing an image or
/// video. Nothing here is written into the file.
///
/// Neutral values leave the picture untouched; see [isIdentity].
@immutable
class ViewerAdjustments {
  const ViewerAdjustments({
    this.brightness = neutralBrightness,
    this.contrast = neutralContrast,
    this.saturation = neutralSaturation,
    this.hue = neutralHue,
    this.gamma = neutralGamma,
  });

  /// Additive offset, -1.0 to 1.0 (shown to the user as -100..100).
  final double brightness;

  /// Multiplier around mid-gray, 0.0 to 2.0.
  final double contrast;

  /// 0.0 (grayscale) to 2.0.
  final double saturation;

  /// Rotation around the gray axis in degrees, -180 to 180.
  final double hue;

  /// Midtone curve, 0.3 to 3.0. Greater than 1 brightens midtones.
  final double gamma;

  static const double neutralBrightness = 0.0;
  static const double neutralContrast = 1.0;
  static const double neutralSaturation = 1.0;
  static const double neutralHue = 0.0;
  static const double neutralGamma = 1.0;

  static const double minBrightness = -1.0;
  static const double maxBrightness = 1.0;
  static const double minContrast = 0.0;
  static const double maxContrast = 2.0;
  static const double minSaturation = 0.0;
  static const double maxSaturation = 2.0;
  static const double minHue = -180.0;
  static const double maxHue = 180.0;
  static const double minGamma = 0.3;
  static const double maxGamma = 3.0;

  static const ViewerAdjustments identity = ViewerAdjustments();

  // ---- presets -------------------------------------------------------------
  // Built only from the five controls, so a preset is just a starting point
  // the sliders can refine.

  /// Punchier contrast and color.
  static const ViewerAdjustments vivid = ViewerAdjustments(
    contrast: 1.15,
    saturation: 1.35,
  );

  /// Grayscale with a touch of extra contrast.
  static const ViewerAdjustments blackAndWhite = ViewerAdjustments(
    contrast: 1.1,
    saturation: 0.0,
  );

  /// A gentle warm color shift with slightly richer contrast.
  static const ViewerAdjustments warm = ViewerAdjustments(
    contrast: 1.05,
    saturation: 1.08,
    hue: 9.0,
    gamma: 1.02,
  );

  /// A subtle cool color shift with slightly richer contrast.
  static const ViewerAdjustments cool = ViewerAdjustments(
    contrast: 1.08,
    saturation: 1.08,
    hue: -9.0,
  );

  /// True when every value is neutral, so no filter layer is needed.
  bool get isIdentity =>
      brightness == neutralBrightness &&
      contrast == neutralContrast &&
      saturation == neutralSaturation &&
      hue == neutralHue &&
      gamma == neutralGamma;

  bool get isNotIdentity => !isIdentity;

  /// Hue in radians, as the shader expects it.
  double get hueRadians => hue * math.pi / 180.0;

  ViewerAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hue,
    double? gamma,
  }) => ViewerAdjustments(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    hue: hue ?? this.hue,
    gamma: gamma ?? this.gamma,
  );

  /// A 5x4 [ColorFilter.matrix] approximating everything except [gamma]
  /// (a power curve cannot be written as a matrix). Used only as a fallback
  /// when the fragment shader is unavailable.
  ///
  /// Order matches the shader: brightness, contrast, saturation, hue.
  List<double> toColorMatrix() {
    var m = _identityMatrix();
    m = _multiply(_brightnessMatrix(brightness), m);
    m = _multiply(_contrastMatrix(contrast), m);
    m = _multiply(_saturationMatrix(saturation), m);
    m = _multiply(_hueMatrix(hueRadians), m);
    return m;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewerAdjustments &&
          other.brightness == brightness &&
          other.contrast == contrast &&
          other.saturation == saturation &&
          other.hue == hue &&
          other.gamma == gamma;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, hue, gamma);

  @override
  String toString() =>
      'ViewerAdjustments(brightness: $brightness, '
      'contrast: $contrast, saturation: $saturation, hue: $hue, '
      'gamma: $gamma)';

  // ---- matrix helpers -----------------------------------------------------
  // Row-major 4x5 as Flutter's ColorFilter.matrix expects: each row is
  // [R, G, B, A, offset] with the offset in 0..255 units.

  static List<double> _identityMatrix() => <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> _brightnessMatrix(double b) {
    final o = b * 255.0;
    return <double>[
      1, 0, 0, 0, o, //
      0, 1, 0, 0, o, //
      0, 0, 1, 0, o, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _contrastMatrix(double c) {
    final o = (0.5 - 0.5 * c) * 255.0;
    return <double>[
      c, 0, 0, 0, o, //
      0, c, 0, 0, o, //
      0, 0, c, 0, o, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _saturationMatrix(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final inv = 1.0 - s;
    return <double>[
      lr * inv + s, lg * inv, lb * inv, 0, 0, //
      lr * inv, lg * inv + s, lb * inv, 0, 0, //
      lr * inv, lg * inv, lb * inv + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Rotation around the (1,1,1)/sqrt(3) axis, same maths as the shader.
  static List<double> _hueMatrix(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    const k = 1.0 / 3.0;
    final q = math.sqrt(1.0 / 3.0);
    final d = k * (1 - c);
    return <double>[
      c + d, d - q * s, d + q * s, 0, 0, //
      d + q * s, c + d, d - q * s, 0, 0, //
      d - q * s, d + q * s, c + d, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Returns `a ∘ b` (apply [b] first, then [a]) for 4x5 color matrices.
  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var v = 0.0;
        for (var i = 0; i < 4; i++) {
          v += a[row * 5 + i] * b[i * 5 + col];
        }
        if (col == 4) v += a[row * 5 + 4];
        out[row * 5 + col] = v;
      }
    }
    return out;
  }
}
