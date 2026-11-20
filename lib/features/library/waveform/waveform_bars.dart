import 'dart:math' as math;
import 'dart:typed_data';

/// Reduces a loudness envelope to the handful of bars a seek bar draws.
class WaveformBars {
  WaveformBars._();

  /// Bars the seek bar is built from.
  static const int defaultCount = 160;

  /// Never fully flat: a silent stretch still draws as a thin line, so the bar
  /// reads as a bar everywhere and can be grabbed anywhere.
  static const double floor = 0.06;

  /// Turns [peaks] (one 0..255 level per slice of time, oldest first) into
  /// [count] heights in `floor..1`.
  ///
  /// Each bar takes the loudest slice in its stretch of time, so a short sharp
  /// sound is not averaged away. Heights are scaled so the loudest bar that is
  /// not a lone spike fills the height (the 98th percentile maps to 1), then
  /// eased with [gamma] below 1 so quiet passages stay visible next to loud
  /// ones. Returns an empty list when there is nothing to draw.
  static List<double> fromPeaks(
    Uint8List peaks, {
    int count = defaultCount,
    double gamma = 0.7,
  }) {
    if (peaks.isEmpty || count <= 0) return const [];

    final raw = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final from = (i * peaks.length) ~/ count;
      var to = ((i + 1) * peaks.length) ~/ count;
      if (to <= from) to = math.min(from + 1, peaks.length);
      var max = 0;
      for (var j = from; j < to; j++) {
        if (peaks[j] > max) max = peaks[j];
      }
      raw[i] = max / 255.0;
    }

    final sorted = List<double>.of(raw)..sort();
    final ref = sorted[math.min(count - 1, (count * 0.98).floor())];
    if (ref <= 0) return List<double>.filled(count, floor);

    return [
      for (final v in raw)
        floor + (1 - floor) * math.pow(math.min(1.0, v / ref), gamma).toDouble(),
    ];
  }

  /// The bar a position falls in, for painting the played part: [fraction] is
  /// 0..1 of the track, the result 0..[count].
  static double playedBars(double fraction, int count) =>
      fraction.clamp(0.0, 1.0) * count;
}
