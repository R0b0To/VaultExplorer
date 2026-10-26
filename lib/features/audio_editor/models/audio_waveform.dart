import 'dart:math' as math;
import 'dart:typed_data';

/// The loudness envelope the audio editor draws: one 0..255 level per slice of
/// time, `peaksPerSecond` slices per second, oldest first.
///
/// While a long file is still being decoded the envelope is only known up to
/// [filledPeaks]; [peaks] is already its final length (the rest is zeros), so
/// the timeline keeps its scale and the waveform simply grows from the left.
class AudioWaveform {
  /// Peaks per [_coarse] entry. Zoomed out on a long file one pixel covers
  /// thousands of peaks; the coarse level answers those ranges 64x faster.
  static const int _coarseFactor = 64;

  /// A range spanning at least this many peaks is answered through [_coarse].
  static const int _coarseThreshold = _coarseFactor * 3;

  final Uint8List peaks;
  final double peaksPerSecond;

  /// False when the native decode stopped before the end of the file; the part
  /// it never reached is then drawn flat. Also false for a waveform that is
  /// still being decoded (see [filledPeaks]).
  final bool complete;

  /// How many peaks from the start are real measurements. Defaults to all of
  /// them; smaller only for a waveform that is still growing.
  final int filledPeaks;

  AudioWaveform({
    required this.peaks,
    required this.peaksPerSecond,
    this.complete = true,
    int? filledPeaks,
  }) : filledPeaks = math.min(peaks.length, math.max(0, filledPeaks ?? peaks.length));

  /// How much of the file the measured peaks cover, in microseconds.
  int get coveredUs => peaksPerSecond <= 0
      ? 0
      : (filledPeaks / peaksPerSecond * 1000000).round();

  /// Max of every [_coarseFactor] peaks, built on first use. A new
  /// [AudioWaveform] is made for every update of a growing waveform, so this
  /// never goes stale.
  late final Uint8List _coarse = _buildCoarse();

  Uint8List _buildCoarse() {
    final out = Uint8List((filledPeaks + _coarseFactor - 1) ~/ _coarseFactor);
    for (var i = 0; i < out.length; i++) {
      final from = i * _coarseFactor;
      final to = math.min(from + _coarseFactor, filledPeaks);
      var max = 0;
      for (var j = from; j < to; j++) {
        final v = peaks[j];
        if (v > max) max = v;
      }
      out[i] = max;
    }
    return out;
  }

  /// The loudest level (0..255) in `[startUs, endUs)`; 0 outside the measured
  /// part. Always looks at least one slice, so a range narrower than a slice
  /// (zoomed far in) still reads the slice it falls in.
  int peakBetween(int startUs, int endUs) {
    if (filledPeaks == 0 || peaksPerSecond <= 0) return 0;
    final last = filledPeaks - 1;
    var first = (startUs * peaksPerSecond / 1000000).floor();
    var end = (endUs * peaksPerSecond / 1000000).ceil();
    if (first > last || end <= 0) return 0;
    if (first < 0) first = 0;
    if (end <= first) end = first + 1;
    if (end > filledPeaks) end = filledPeaks;

    if (end - first < _coarseThreshold) return _maxOf(first, end);

    // Long range: ragged ends one by one, the whole blocks in between through
    // the coarse level.
    final firstBlock = (first + _coarseFactor - 1) ~/ _coarseFactor;
    final endBlock = end ~/ _coarseFactor;
    var max = math.max(
      _maxOf(first, firstBlock * _coarseFactor),
      _maxOf(endBlock * _coarseFactor, end),
    );
    for (var b = firstBlock; b < endBlock; b++) {
      final v = _coarse[b];
      if (v > max) max = v;
    }
    return max;
  }

  int _maxOf(int from, int to) {
    var max = 0;
    for (var i = from; i < to; i++) {
      final v = peaks[i];
      if (v > max) max = v;
    }
    return max;
  }
}
