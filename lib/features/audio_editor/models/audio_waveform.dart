import 'dart:typed_data';

/// The loudness envelope the audio editor draws: one 0..255 level per slice of
/// time, `peaksPerSecond` slices per second, oldest first.
class AudioWaveform {
  final Uint8List peaks;
  final double peaksPerSecond;

  /// False when the native decode ran out of time before the end of the file.
  final bool complete;

  const AudioWaveform({
    required this.peaks,
    required this.peaksPerSecond,
    this.complete = true,
  });

  /// How much of the file the peaks cover, in microseconds.
  int get coveredUs => peaksPerSecond <= 0
      ? 0
      : (peaks.length / peaksPerSecond * 1000000).round();

  /// The loudest level (0..255) in `[startUs, endUs)`; 0 outside the covered
  /// part. Always looks at least one slice, so a range narrower than a slice
  /// (zoomed far in) still reads the slice it falls in.
  int peakBetween(int startUs, int endUs) {
    if (peaks.isEmpty || peaksPerSecond <= 0) return 0;
    final last = peaks.length - 1;
    var first = (startUs * peaksPerSecond / 1000000).floor();
    var end = (endUs * peaksPerSecond / 1000000).ceil();
    if (first > last || end <= 0) return 0;
    if (first < 0) first = 0;
    if (end <= first) end = first + 1;
    if (end > peaks.length) end = peaks.length;
    var max = 0;
    for (var i = first; i < end; i++) {
      final v = peaks[i];
      if (v > max) max = v;
    }
    return max;
  }
}
