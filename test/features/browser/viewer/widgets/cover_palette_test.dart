import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/audio_ambient_backdrop.dart';

Uint8List _solid(int r, int g, int b, {int pixels = 400, int a = 255}) {
  final out = Uint8List(pixels * 4);
  for (var i = 0; i < pixels; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

void main() {
  test('empty or fully transparent input yields no colours', () {
    expect(CoverPalette.fromRgba(Uint8List(0)), isEmpty);
    expect(CoverPalette.fromRgba(_solid(255, 0, 0, a: 0)), isEmpty);
  });

  test('a red cover gives a reddish first colour and the full set', () {
    final colors = CoverPalette.fromRgba(_solid(220, 30, 30));
    expect(colors, hasLength(CoverPalette.count));
    final hue = HSLColor.fromColor(colors.first).hue;
    expect(hue < 15 || hue > 345, isTrue);
  });

  test('a grey cover still gives a usable set', () {
    final colors = CoverPalette.fromRgba(_solid(128, 128, 128));
    expect(colors, hasLength(CoverPalette.count));
    for (final c in colors) {
      expect(c.a, 1.0);
    }
  });

  test('two distinct hues both show up in the palette', () {
    final red = _solid(220, 30, 30, pixels: 300);
    final blue = _solid(30, 60, 220, pixels: 300);
    final both = Uint8List.fromList([...red, ...blue]);
    final colors = CoverPalette.fromRgba(both);
    final hues = colors.map((c) => HSLColor.fromColor(c).hue).toList();
    expect(
      hues.any((h) => (h - hues.first).abs() > 40 && (h - hues.first).abs() < 320),
      isTrue,
    );
  });
}
