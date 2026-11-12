import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/waveform/waveform_bars.dart';

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  test('nothing to draw gives no bars', () {
    expect(WaveformBars.fromPeaks(Uint8List(0)), isEmpty);
    expect(WaveformBars.fromPeaks(_bytes([1, 2, 3]), count: 0), isEmpty);
  });

  test('always the requested number of bars, in the floor..1 range', () {
    final peaks = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));
    final bars = WaveformBars.fromPeaks(peaks, count: 160);
    expect(bars.length, 160);
    for (final b in bars) {
      expect(b >= WaveformBars.floor - 1e-9, isTrue);
      expect(b <= 1.0 + 1e-9, isTrue);
    }
  });

  test('silence is a flat line at the floor, not a gap or a division by zero', () {
    final bars = WaveformBars.fromPeaks(Uint8List(1000), count: 40);
    expect(bars.length, 40);
    expect(bars.every((b) => b == WaveformBars.floor), isTrue);
  });

  test('each bar takes the loudest slice of its stretch, so short sounds survive', () {
    final peaks = Uint8List(1000);
    peaks[500] = 255; // a single click in the middle
    final bars = WaveformBars.fromPeaks(peaks, count: 10, gamma: 1);
    // Bar 5 covers slices 500..599 and must stand out from its neighbours.
    expect(bars[5] > bars[4], isTrue);
    expect(bars[5] > bars[6], isTrue);
  });

  test('a lone loud spike does not flatten the rest of the track', () {
    final peaks = Uint8List.fromList(List.filled(10000, 60));
    peaks[0] = 255; // would dominate a max-normalised scale
    final bars = WaveformBars.fromPeaks(peaks, count: 100, gamma: 1);
    // The ordinary passages still reach the top of the scale.
    expect(bars.skip(1).every((b) => b > 0.99), isTrue);
  });

  test('quiet passages stay visible next to loud ones', () {
    final peaks = Uint8List.fromList([
      ...List.filled(500, 250),
      ...List.filled(500, 40),
    ]);
    final bars = WaveformBars.fromPeaks(peaks, count: 2);
    expect(bars[0] > bars[1], isTrue);
    expect(bars[1] > 0.3, isTrue); // eased, not crushed to near zero
  });

  test('fewer slices than bars still gives every bar a height', () {
    final bars = WaveformBars.fromPeaks(_bytes([10, 200, 10]), count: 9);
    expect(bars.length, 9);
    expect(bars.any((b) => b > 0.9), isTrue);
  });

  test('playedBars maps a track fraction to a bar position and clamps', () {
    expect(WaveformBars.playedBars(0.5, 100), 50);
    expect(WaveformBars.playedBars(-1, 100), 0);
    expect(WaveformBars.playedBars(3, 100), 100);
  });
}
