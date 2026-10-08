import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';

/// Applies a 4x5 color matrix (offsets in 0..255) to an RGB triple in 0..1.
List<double> _apply(List<double> m, double r, double g, double b) {
  double row(int i) =>
      (m[i * 5] * r + m[i * 5 + 1] * g + m[i * 5 + 2] * b + m[i * 5 + 4] / 255.0);
  return [row(0), row(1), row(2)];
}

void main() {
  group('ViewerAdjustments', () {
    test('default is identity with neutral values', () {
      const a = ViewerAdjustments();
      expect(a.isIdentity, isTrue);
      expect(a.isNotIdentity, isFalse);
      expect(a.brightness, 0.0);
      expect(a.contrast, 1.0);
      expect(a.saturation, 1.0);
      expect(a.hue, 0.0);
      expect(a.gamma, 1.0);
      expect(a, ViewerAdjustments.identity);
    });

    test('any single non-neutral value breaks identity', () {
      expect(const ViewerAdjustments(brightness: 0.1).isIdentity, isFalse);
      expect(const ViewerAdjustments(contrast: 1.1).isIdentity, isFalse);
      expect(const ViewerAdjustments(saturation: 0.9).isIdentity, isFalse);
      expect(const ViewerAdjustments(hue: 5).isIdentity, isFalse);
      expect(const ViewerAdjustments(gamma: 1.2).isIdentity, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      const a = ViewerAdjustments(brightness: 0.2, gamma: 1.5);
      final b = a.copyWith(contrast: 1.3);
      expect(b.brightness, 0.2);
      expect(b.gamma, 1.5);
      expect(b.contrast, 1.3);
      expect(b.saturation, 1.0);
      expect(a.copyWith(), a);
    });

    test('equality and hashCode follow the values', () {
      const a = ViewerAdjustments(brightness: 0.2, hue: 30);
      const b = ViewerAdjustments(brightness: 0.2, hue: 30);
      const c = ViewerAdjustments(brightness: 0.2, hue: 31);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('hueRadians converts degrees', () {
      expect(const ViewerAdjustments(hue: 180).hueRadians, closeTo(math.pi, 1e-9));
      expect(const ViewerAdjustments(hue: -90).hueRadians, closeTo(-math.pi / 2, 1e-9));
    });

    test('presets are not identity and stay inside the slider ranges', () {
      for (final p in [ViewerAdjustments.vivid, ViewerAdjustments.blackAndWhite]) {
        expect(p.isIdentity, isFalse);
        expect(p.contrast, inInclusiveRange(ViewerAdjustments.minContrast, ViewerAdjustments.maxContrast));
        expect(p.saturation, inInclusiveRange(ViewerAdjustments.minSaturation, ViewerAdjustments.maxSaturation));
      }
      expect(ViewerAdjustments.blackAndWhite.saturation, 0.0);
    });
  });

  group('ViewerAdjustments.toColorMatrix (fallback path)', () {
    test('identity adjustments give the identity matrix', () {
      final m = const ViewerAdjustments().toColorMatrix();
      const expected = [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];
      for (var i = 0; i < 20; i++) {
        expect(m[i], closeTo(expected[i].toDouble(), 1e-9), reason: 'index $i');
      }
    });

    test('brightness adds an offset to RGB only', () {
      final m = const ViewerAdjustments(brightness: 0.2).toColorMatrix();
      final out = _apply(m, 0.1, 0.5, 0.9);
      expect(out[0], closeTo(0.3, 1e-9));
      expect(out[1], closeTo(0.7, 1e-9));
      expect(out[2], closeTo(1.1, 1e-9)); // clamping is the renderer's job
      expect(m[15 + 3], 1.0); // alpha row untouched
      expect(m[19], 0.0);
    });

    test('contrast pivots around mid gray', () {
      final m = const ViewerAdjustments(contrast: 2.0).toColorMatrix();
      final mid = _apply(m, 0.5, 0.5, 0.5);
      expect(mid, everyElement(closeTo(0.5, 1e-9)));
      final out = _apply(m, 0.25, 0.5, 0.75);
      expect(out[0], closeTo(0.0, 1e-9));
      expect(out[2], closeTo(1.0, 1e-9));
    });

    test('zero saturation makes every channel equal to luma', () {
      final m = const ViewerAdjustments(saturation: 0).toColorMatrix();
      final out = _apply(m, 0.8, 0.2, 0.4);
      final luma = 0.2126 * 0.8 + 0.7152 * 0.2 + 0.0722 * 0.4;
      for (final c in out) {
        expect(c, closeTo(luma, 1e-9));
      }
    });

    test('hue rotation leaves grays alone and a full turn is a no-op', () {
      final m = const ViewerAdjustments(hue: 73).toColorMatrix();
      final gray = _apply(m, 0.4, 0.4, 0.4);
      expect(gray, everyElement(closeTo(0.4, 1e-9)));

      final full = const ViewerAdjustments(hue: 360).toColorMatrix();
      final out = _apply(full, 0.9, 0.3, 0.1);
      expect(out[0], closeTo(0.9, 1e-9));
      expect(out[1], closeTo(0.3, 1e-9));
      expect(out[2], closeTo(0.1, 1e-9));
    });

    test('120 degree hue rotation cycles the channels', () {
      final m = const ViewerAdjustments(hue: 120).toColorMatrix();
      final out = _apply(m, 1.0, 0.0, 0.0);
      expect(out[0], closeTo(0.0, 1e-9));
      expect(out[1], closeTo(1.0, 1e-9));
      expect(out[2], closeTo(0.0, 1e-9));
    });

    test('gamma is intentionally ignored by the matrix', () {
      final a = const ViewerAdjustments(gamma: 2.0).toColorMatrix();
      final b = const ViewerAdjustments().toColorMatrix();
      for (var i = 0; i < 20; i++) {
        expect(a[i], closeTo(b[i], 1e-9));
      }
    });
  });
}
