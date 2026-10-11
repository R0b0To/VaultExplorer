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
}
