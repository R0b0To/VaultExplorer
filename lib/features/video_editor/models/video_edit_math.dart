import 'edit_segment.dart';

/// Shortest segment the editor will create or keep, in microseconds.
const int kMinSegmentUs = 100000; // 0.1 s

/// An end within this of the media duration counts as "the end of the file"
/// (mirrors `END_EPSILON_US` in LosslessVideoCutter.kt).
const int kEndEpsilonUs = 1000;

// ── Keyframe lookups ─────────────────────────────────────────────────────
// [keyframes] is always ascending (the native probe walks the file forward).

/// The last keyframe at or before [t], or null if [t] precedes them all.
int? keyframeAtOrBefore(List<int> keyframes, int t) {
  var lo = 0;
  var hi = keyframes.length; // ends as the first index with keyframes[i] > t
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (keyframes[mid] <= t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo == 0 ? null : keyframes[lo - 1];
}

/// The first keyframe at or after [t], or null if [t] is past them all.
int? keyframeAtOrAfter(List<int> keyframes, int t) {
  var lo = 0;
  var hi = keyframes.length; // ends as the first index with keyframes[i] >= t
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (keyframes[mid] < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo == keyframes.length ? null : keyframes[lo];
}

/// The keyframe closest to [t] (the earlier one wins a tie), or null when
/// there are no keyframes.
int? nearestKeyframe(List<int> keyframes, int t) {
  final before = keyframeAtOrBefore(keyframes, t);
  final after = keyframeAtOrAfter(keyframes, t);
  if (before == null) return after;
  if (after == null) return before;
  return (t - before) <= (after - t) ? before : after;
}

/// What the native cutter will actually export for [range]: the start snaps
/// back to the keyframe at or before it and the end snaps forward to the
/// keyframe at or after it (or to [durationUs]). Mirrors
/// `LosslessVideoCutter.resolveRange`, so the editor can show the real
/// result before exporting.
///
/// Only trustworthy when the keyframe list covers the whole file; callers
/// pass the probe's `keyframesComplete` flag as [keyframesComplete], and an
/// end beyond the scanned part is returned unchanged.
TimeRange snapRangeOutward(
  List<int> keyframes,
  TimeRange range,
  int durationUs, {
  bool keyframesComplete = true,
}) {
  if (keyframes.isEmpty) return range;

  final start = keyframeAtOrBefore(keyframes, range.startUs) ?? 0;
  if (durationUs > 0 && range.endUs >= durationUs - kEndEpsilonUs) {
    return (startUs: start, endUs: durationUs);
  }
  if (!keyframesComplete && range.endUs > keyframes.last) {
    return (startUs: start, endUs: range.endUs);
  }
  final end = keyframeAtOrAfter(keyframes, range.endUs) ?? durationUs;
  return (startUs: start, endUs: end);
}

// ── Range planning ───────────────────────────────────────────────────────

/// Sorts [ranges] and joins any that overlap or touch.
List<TimeRange> mergeOverlapping(List<TimeRange> ranges) {
  if (ranges.isEmpty) return const [];
  final sorted = [...ranges]..sort((a, b) => a.startUs.compareTo(b.startUs));
  final out = <TimeRange>[sorted.first];
  for (final r in sorted.skip(1)) {
    final last = out.last;
    if (r.startUs <= last.endUs) {
      out[out.length - 1] = (
        startUs: last.startUs,
        endUs: r.endUs > last.endUs ? r.endUs : last.endUs,
      );
    } else {
      out.add(r);
    }
  }
  return out;
}

/// The gaps between [ranges] within `[0, durationUs]`. [ranges] must already
/// be sorted and non-overlapping (see [mergeOverlapping]).
List<TimeRange> invertRanges(List<TimeRange> ranges, int durationUs) {
  final out = <TimeRange>[];
  var cursor = 0;
  for (final r in ranges) {
    if (r.startUs > cursor) out.add((startUs: cursor, endUs: r.startUs));
    if (r.endUs > cursor) cursor = r.endUs;
  }
  if (cursor < durationUs) out.add((startUs: cursor, endUs: durationUs));
  return out;
}

/// The time ranges to export for [segments] in the given [mode], sorted and
/// with anything shorter than [kMinSegmentUs] dropped.
List<TimeRange> planExportRanges(
  List<EditSegment> segments,
  VideoEditMode mode,
  int durationUs,
) {
  final marked = mergeOverlapping([for (final s in segments) s.range]);
  final ranges =
      mode == VideoEditMode.keep ? marked : invertRanges(marked, durationUs);
  return [
    for (final r in ranges)
      if (r.endUs - r.startUs >= kMinSegmentUs) r,
  ];
}

// ── Output naming ────────────────────────────────────────────────────────

/// Names for the exported file(s), next to the source.
///
/// One output (merged, or a single segment) is `<name>_cut.<ext>`; several
/// are `<name>_cut_1.<ext>`, `<name>_cut_2.<ext>`, ... Each is passed through
/// [unique] against [existingLowercase] (lower-cased names already in the
/// folder) and added to it, so the outputs can't collide with the folder or
/// with each other.
///
/// [suffix] is the marker put after the name (`_cut` by default). Pass `''`
/// when [sourceFileName] already is the name the person chose, so it isn't
/// marked a second time (`clip_cut` would otherwise become `clip_cut_cut`):
/// one output is then `<name>.<ext>`, several are `<name>_1.<ext>`, ...
List<String> planOutputNames({
  required String sourceFileName,
  required String extension,
  required int count,
  required Set<String> existingLowercase,
  required String Function(String name, Set<String> existingLowercase) unique,
  String suffix = '_cut',
}) {
  final dot = sourceFileName.lastIndexOf('.');
  final stem = dot > 0 ? sourceFileName.substring(0, dot) : sourceFileName;
  final taken = {...existingLowercase};
  final names = <String>[];
  for (var i = 0; i < count; i++) {
    final base = count == 1 ? '$stem$suffix' : '$stem${suffix}_${i + 1}';
    final name = unique('$base.$extension', taken);
    taken.add(name.toLowerCase());
    names.add(name);
  }
  return names;
}

// ── Formatting ───────────────────────────────────────────────────────────

/// `m:ss.mmm`, or `h:mm:ss.mmm` from one hour up; [millis] false drops the
/// fraction (`m:ss`).
String formatTimecode(int us, {bool millis = true}) {
  final clamped = us < 0 ? 0 : us;
  final totalMs = clamped ~/ 1000;
  final ms = totalMs % 1000;
  final totalSec = totalMs ~/ 1000;
  final s = totalSec % 60;
  final m = (totalSec ~/ 60) % 60;
  final h = totalSec ~/ 3600;
  final ss = s.toString().padLeft(2, '0');
  final frac = millis ? '.${ms.toString().padLeft(3, '0')}' : '';
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss$frac';
  return '$m:$ss$frac';
}
