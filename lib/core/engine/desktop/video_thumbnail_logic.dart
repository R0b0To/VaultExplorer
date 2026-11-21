// Pure helpers behind desktop video thumbnails (see desktop_video_thumbnails.dart). Nothing here touches Flutter,
// the engine or a player, so it can be tested on its own.
//
// The frame-selection rules mirror Android's (`VideoThumbnailCoordinator` / `ThumbnailHandlers` in Kotlin) so a
// video gets the same kind of thumbnail on every platform:
//   * `firstFrame`         the frame at time 0;
//   * `frameAtPercentage`  the frame at `framePosition` of the duration (clamped to 5%..90%);
//   * `hybrid` (default)   the frame at time 0 and, when that looks blank (black leader, fade-in, slate), the first
//                          not-blank frame at `framePosition`, 25% or 45% of the duration.
import 'dart:math' as math;
import 'dart:typed_data';

/// Smallest and largest fraction of a video's duration a thumbnail may be taken at.
const double kMinThumbnailFraction = 0.05;
const double kMaxThumbnailFraction = 0.90;

/// Where a blank first frame is retried, after the configured position (same list as Android).
const List<double> kBlankFrameRetryFractions = [0.25, 0.45];

/// The largest size with the aspect ratio of [width] x [height] that fits in [target] x [target]. Never scales
/// up: a source already inside the box keeps its size.
({int width, int height}) fitWithin(int width, int height, int target) {
  if (width <= 0 || height <= 0 || target <= 0) return (width: math.max(width, 1), height: math.max(height, 1));
  final longest = math.max(width, height);
  if (longest <= target) return (width: width, height: height);
  final scale = target / longest;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// [fraction] clamped to the range thumbnails are taken from.
double clampThumbnailFraction(double fraction) =>
    fraction.isNaN ? 0.12 : fraction.clamp(kMinThumbnailFraction, kMaxThumbnailFraction).toDouble();

/// The positions (as fractions of the duration) to try, in order, after the frame at time 0 turned out blank.
List<double> blankFrameRetryFractions(double preferred) {
  final out = <double>[];
  for (final f in [clampThumbnailFraction(preferred), ...kBlankFrameRetryFractions]) {
    if (!out.contains(f)) out.add(f);
  }
  return out;
}

/// The point at [fraction] of [duration].
Duration timeAtFraction(Duration duration, double fraction) =>
    Duration(microseconds: (duration.inMicroseconds * clampThumbnailFraction(fraction)).round());

/// Whether a frame is uninformative as a thumbnail: flat colour, near-black or blown-out, a slate that is mostly
/// background, or very low contrast. Port of `VideoThumbnailCoordinator.isLikelyBlankFrame`: an 8x8 grid of
/// samples out of [rgba] (tightly packed R, G, B, A bytes, [width] x [height]).
///
/// Unreadable input (wrong size) is "not blank": a thumbnail that might be fine is better than none.
bool isLikelyBlankFrame(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) return false;

  const grid = 8;
  const total = grid * grid;
  var minLuma = 255, maxLuma = 0;
  var minR = 255, maxR = 0;
  var minG = 255, maxG = 0;
  var minB = 255, maxB = 0;
  var sumLuma = 0;
  var dark = 0, bright = 0;
  final lumas = List<int>.filled(total, 0);
  var n = 0;

  for (var row = 0; row < grid; row++) {
    for (var col = 0; col < grid; col++) {
      final x = math.min(math.max((((col + 0.5) / grid) * width).toInt(), 0), width - 1);
      final y = math.min(math.max((((row + 0.5) / grid) * height).toInt(), 0), height - 1);
      final i = (y * width + x) * 4;
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final luma = (r * 299 + g * 587 + b * 114) ~/ 1000;

      lumas[n++] = luma;
      sumLuma += luma;
      if (luma < 25) dark++;
      if (luma > 230) bright++;

      minLuma = math.min(minLuma, luma);
      maxLuma = math.max(maxLuma, luma);
      minR = math.min(minR, r);
      maxR = math.max(maxR, r);
      minG = math.min(minG, g);
      maxG = math.max(maxG, g);
      minB = math.min(minB, b);
      maxB = math.max(maxB, b);
    }
  }

  final lumaRange = maxLuma - minLuma;
  final channelRange = math.max(maxR - minR, math.max(maxG - minG, maxB - minB));

  // 1. Solid / flat colour.
  if (lumaRange <= 14 && channelRange <= 18) return true;

  final avg = sumLuma / total;

  // 2. Near pitch-black or blown-out white.
  if (avg < 18.0 || avg > 240.0) return true;

  // 3. Slates and title cards: most of the frame is background.
  if (dark >= total * 0.80 && avg < 35.0) return true;
  if (bright >= total * 0.85 && avg > 215.0) return true;

  // 4. Low contrast / low detail.
  var variance = 0.0;
  for (final l in lumas) {
    final d = l - avg;
    variance += d * d;
  }
  return math.sqrt(variance / total) < 8.0;
}
