import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/audio_editor/models/audio_waveform.dart';

/// Four slices of 100 ms each (10 per second): levels 10, 200, 30, 40.
AudioWaveform _wave({bool complete = true}) => AudioWaveform(
      peaks: Uint8List.fromList([10, 200, 30, 40]),
      peaksPerSecond: 10,
      complete: complete,
    );

void main() {
  group('peakBetween', () {
    test('reads exactly one slice for a range that spans it', () {
      expect(_wave().peakBetween(0, 100000), 10);
      expect(_wave().peakBetween(300000, 400000), 40);
    });

    test('takes the loudest slice a range touches', () {
      expect(_wave().peakBetween(0, 400000), 200);
      expect(_wave().peakBetween(150000, 250000), 200);
      expect(_wave().peakBetween(200000, 400000), 40);
    });

    test('a range narrower than a slice still reads the slice it falls in', () {
      // Zoomed far in, one pixel is a few ms: far less than a 100 ms slice.
      expect(_wave().peakBetween(310000, 320000), 40);
      expect(_wave().peakBetween(150000, 150000), 200);
    });

    test('is zero outside the covered part', () {
      expect(_wave().peakBetween(500000, 600000), 0);
      expect(_wave().peakBetween(-200000, -100000), 0);
    });

    test('clips a range that runs past the end', () {
      expect(_wave().peakBetween(300000, 9000000), 40);
      expect(_wave().peakBetween(-100000, 100000), 10);
    });

    test('an empty waveform reads as silence', () {
      final empty = AudioWaveform(peaks: Uint8List(0), peaksPerSecond: 100);
      expect(empty.peakBetween(0, 1000000), 0);
    });
  });

  group('coveredUs', () {
    test('is the length of time the peaks cover', () {
      expect(_wave().coveredUs, 400000);
    });

    test('is zero when there are no peaks per second', () {
      final broken = AudioWaveform(peaks: Uint8List(4), peaksPerSecond: 0);
      expect(broken.coveredUs, 0);
      expect(broken.peakBetween(0, 100), 0);
    });
  });

  test('complete defaults to true and can be turned off', () {
    expect(AudioWaveform(peaks: Uint8List(1), peaksPerSecond: 1).complete, isTrue);
    expect(_wave(complete: false).complete, isFalse);
  });

  group('a waveform that is still being decoded', () {
    // Ten slices of 100 ms, but only the first four are measured.
    AudioWaveform growing() => AudioWaveform(
      peaks: Uint8List.fromList([10, 200, 30, 40, 250, 250, 250, 250, 250, 250]),
      peaksPerSecond: 10,
      complete: false,
      filledPeaks: 4,
    );

    test('covers only the measured part', () {
      expect(growing().coveredUs, 400000);
    });

    test('reads silence past the frontier, whatever the buffer holds', () {
      expect(growing().peakBetween(0, 400000), 200);
      expect(growing().peakBetween(400000, 900000), 0);
      expect(growing().peakBetween(300000, 900000), 40);
    });

    test('filledPeaks is clamped to the buffer', () {
      final w = AudioWaveform(
        peaks: Uint8List(3),
        peaksPerSecond: 10,
        filledPeaks: 99,
      );
      expect(w.filledPeaks, 3);
      expect(
        AudioWaveform(peaks: Uint8List(3), peaksPerSecond: 10, filledPeaks: -5)
            .filledPeaks,
        0,
      );
    });
  });

  group('long ranges (answered through the coarse level)', () {
    // 3 hours at 46 peaks per second is ~500k peaks.
    final rng = math.Random(7);
    final peaks = Uint8List.fromList([
      for (var i = 0; i < 20000; i++) rng.nextInt(256),
    ]);
    final wave = AudioWaveform(peaks: peaks, peaksPerSecond: 50);

    int brute(int startUs, int endUs, int filled) {
      var first = (startUs * 50 / 1000000).floor();
      var end = (endUs * 50 / 1000000).ceil();
      if (first < 0) first = 0;
      if (end <= first) end = first + 1;
      if (end > filled) end = filled;
      var max = 0;
      for (var i = first; i < end; i++) {
        if (peaks[i] > max) max = peaks[i];
      }
      return max;
    }

    test('agree with a plain scan for many random ranges', () {
      for (var n = 0; n < 2000; n++) {
        final a = (rng.nextInt(399000) + 1) * 1000;
        final b = a + rng.nextInt(120000) * 1000;
        expect(wave.peakBetween(a, b), brute(a, b, peaks.length), reason: '$a..$b');
      }
    });

    test('agree at block boundaries and at the very end', () {
      // 64 peaks = 1.28 s here.
      for (final a in [0, 1280000, 1279999, 1280001, 2560000]) {
        for (final len in [3800000, 3840000, 3900000, 9000000]) {
          expect(
            wave.peakBetween(a, a + len),
            brute(a, a + len, peaks.length),
            reason: '$a +$len',
          );
        }
      }
      expect(wave.peakBetween(0, 1 << 40), brute(0, 1 << 40, peaks.length));
    });

    test('stop at the frontier of a growing waveform', () {
      final partial = AudioWaveform(
        peaks: peaks,
        peaksPerSecond: 50,
        complete: false,
        filledPeaks: 5000,
      );
      for (var n = 0; n < 500; n++) {
        final a = (rng.nextInt(399000) + 1) * 1000;
        final b = a + rng.nextInt(120000) * 1000;
        expect(partial.peakBetween(a, b), brute(a, b, 5000), reason: '$a..$b');
      }
    });
  });
}
