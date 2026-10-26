import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/video_editor/models/edit_segment.dart';
import 'package:vaultexplorer/features/video_editor/models/video_edit_math.dart';

const _s = 1000000; // one second in microseconds

/// Same rule as FileOperationService.makeUniqueName, kept local so this test
/// doesn't pull in the whole file-operation service.
String _unique(String name, Set<String> existingLowercase) {
  if (!existingLowercase.contains(name.toLowerCase())) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot != -1 ? name.substring(0, dot) : name;
  final ext = dot != -1 ? name.substring(dot) : '';
  for (var i = 1; i < 9999; i++) {
    final candidate = '$stem ($i)$ext';
    if (!existingLowercase.contains(candidate.toLowerCase())) return candidate;
  }
  return name;
}

EditSegment _seg(String id, int startS, int endS) =>
    EditSegment(id: id, startUs: startS * _s, endUs: endS * _s);

void main() {
  final kf = [0, 2 * _s, 4 * _s, 6 * _s, 8 * _s];

  group('keyframe lookups', () {
    test('keyframeAtOrBefore', () {
      expect(keyframeAtOrBefore(kf, 3 * _s), 2 * _s);
      expect(keyframeAtOrBefore(kf, 4 * _s), 4 * _s); // exact hit
      expect(keyframeAtOrBefore(kf, 0), 0);
      expect(keyframeAtOrBefore(kf, -1), isNull);
      expect(keyframeAtOrBefore(kf, 9 * _s), 8 * _s);
      expect(keyframeAtOrBefore(const [], 5), isNull);
    });

    test('keyframeAtOrAfter', () {
      expect(keyframeAtOrAfter(kf, 3 * _s), 4 * _s);
      expect(keyframeAtOrAfter(kf, 4 * _s), 4 * _s); // exact hit
      expect(keyframeAtOrAfter(kf, -5), 0);
      expect(keyframeAtOrAfter(kf, 8 * _s + 1), isNull);
      expect(keyframeAtOrAfter(const [], 5), isNull);
    });

    test('nearestKeyframe prefers the earlier one on a tie', () {
      expect(nearestKeyframe(kf, 2900000), 2 * _s);
      expect(nearestKeyframe(kf, 3 * _s), 2 * _s); // tie
      expect(nearestKeyframe(kf, 3100000), 4 * _s);
      expect(nearestKeyframe(const [], 3), isNull);
    });
  });

  group('snapRangeOutward', () {
    test('start snaps back, end snaps forward', () {
      final r = snapRangeOutward(kf, (startUs: 3 * _s, endUs: 5 * _s), 9 * _s);
      expect(r, (startUs: 2 * _s, endUs: 6 * _s));
    });

    test('a range already on keyframes is unchanged', () {
      final r = snapRangeOutward(kf, (startUs: 2 * _s, endUs: 4 * _s), 9 * _s);
      expect(r, (startUs: 2 * _s, endUs: 4 * _s));
    });

    test('an end within the epsilon of the duration means "to the end"', () {
      final r = snapRangeOutward(kf, (startUs: 1 * _s, endUs: 9 * _s - 500), 9 * _s);
      expect(r, (startUs: 0, endUs: 9 * _s));
    });

    test('an end past the last keyframe runs to the duration', () {
      final r = snapRangeOutward(kf, (startUs: 7 * _s, endUs: 8500000), 9 * _s);
      expect(r, (startUs: 6 * _s, endUs: 9 * _s));
    });

    test('with an incomplete scan, an end beyond the scanned part is left alone', () {
      final r = snapRangeOutward(
        [0, 2 * _s, 4 * _s],
        (startUs: 3 * _s, endUs: 10 * _s),
        60 * _s,
        keyframesComplete: false,
      );
      expect(r, (startUs: 2 * _s, endUs: 10 * _s));
    });

    test('no keyframes: unchanged', () {
      const range = (startUs: 3, endUs: 5);
      expect(snapRangeOutward(const [], range, 10), range);
    });
  });

  group('range planning', () {
    test('mergeOverlapping sorts and joins overlapping/touching ranges', () {
      expect(
        mergeOverlapping([
          (startUs: 5, endUs: 8),
          (startUs: 1, endUs: 3),
          (startUs: 2, endUs: 4),
        ]),
        [(startUs: 1, endUs: 4), (startUs: 5, endUs: 8)],
      );
      expect(
        mergeOverlapping([(startUs: 1, endUs: 3), (startUs: 3, endUs: 5)]),
        [(startUs: 1, endUs: 5)],
      );
      expect(mergeOverlapping(const []), isEmpty);
    });

    test('invertRanges returns the gaps', () {
      expect(
        invertRanges([(startUs: 2, endUs: 4), (startUs: 6, endUs: 8)], 10),
        [(startUs: 0, endUs: 2), (startUs: 4, endUs: 6), (startUs: 8, endUs: 10)],
      );
      expect(invertRanges([(startUs: 0, endUs: 3)], 10), [(startUs: 3, endUs: 10)]);
      expect(invertRanges([(startUs: 0, endUs: 10)], 10), isEmpty);
      expect(invertRanges(const [], 10), [(startUs: 0, endUs: 10)]);
    });

    test('keep mode exports the (merged) segments', () {
      final ranges = planExportRanges(
        [_seg('a', 1, 3), _seg('b', 2, 5)],
        VideoEditMode.keep,
        10 * _s,
      );
      expect(ranges, [(startUs: 1 * _s, endUs: 5 * _s)]);
    });

    test('cut-out mode exports everything around the segments', () {
      final ranges = planExportRanges(
        [_seg('a', 2, 4)],
        VideoEditMode.cutOut,
        10 * _s,
      );
      expect(ranges, [
        (startUs: 0, endUs: 2 * _s),
        (startUs: 4 * _s, endUs: 10 * _s),
      ]);
    });

    test('ranges shorter than the minimum are dropped', () {
      final tiny = EditSegment(id: 't', startUs: 1 * _s, endUs: 1 * _s + 50000);
      expect(planExportRanges([tiny], VideoEditMode.keep, 10 * _s), isEmpty);

      final almostAll = EditSegment(id: 'x', startUs: 50000, endUs: 10 * _s);
      expect(planExportRanges([almostAll], VideoEditMode.cutOut, 10 * _s), isEmpty);
    });
  });

  group('planOutputNames', () {
    test('one output is <name>_cut', () {
      expect(
        planOutputNames(
          sourceFileName: 'clip.mp4',
          extension: 'mp4',
          count: 1,
          existingLowercase: {},
          unique: _unique,
        ),
        ['clip_cut.mp4'],
      );
    });

    test('several outputs are numbered', () {
      expect(
        planOutputNames(
          sourceFileName: 'clip.mov',
          extension: 'mp4',
          count: 2,
          existingLowercase: {},
          unique: _unique,
        ),
        ['clip_cut_1.mp4', 'clip_cut_2.mp4'],
      );
    });

    test('never collides with the folder', () {
      expect(
        planOutputNames(
          sourceFileName: 'clip.mp4',
          extension: 'mp4',
          count: 1,
          existingLowercase: {'clip_cut.mp4'},
          unique: _unique,
        ),
        ['clip_cut (1).mp4'],
      );
    });

    test('handles names without an extension or with a leading dot', () {
      expect(
        planOutputNames(
          sourceFileName: 'clip',
          extension: 'webm',
          count: 1,
          existingLowercase: {},
          unique: _unique,
        ),
        ['clip_cut.webm'],
      );
      expect(
        planOutputNames(
          sourceFileName: '.hidden',
          extension: 'mp4',
          count: 1,
          existingLowercase: {},
          unique: _unique,
        ),
        ['.hidden_cut.mp4'],
      );
    });
  });

  group('planOutputNames with an empty suffix (a name the person chose)', () {
    test('is not marked a second time', () {
      // The audio export sheet pre-fills "<name>_cut"; that must stay as typed.
      expect(
        planOutputNames(
          sourceFileName: 'clip_cut.m4a',
          extension: 'm4a',
          count: 1,
          existingLowercase: {},
          unique: _unique,
          suffix: '',
        ),
        ['clip_cut.m4a'],
      );
    });

    test('several outputs are numbered after the chosen name', () {
      expect(
        planOutputNames(
          sourceFileName: 'talk.m4a',
          extension: 'm4a',
          count: 3,
          existingLowercase: {},
          unique: _unique,
          suffix: '',
        ),
        ['talk_1.m4a', 'talk_2.m4a', 'talk_3.m4a'],
      );
    });

    test('still never collides with the folder', () {
      expect(
        planOutputNames(
          sourceFileName: 'talk.m4a',
          extension: 'm4a',
          count: 1,
          existingLowercase: {'talk.m4a'},
          unique: _unique,
          suffix: '',
        ),
        ['talk (1).m4a'],
      );
    });

    test('the default suffix is unchanged', () {
      expect(
        planOutputNames(
          sourceFileName: 'talk.m4a',
          extension: 'm4a',
          count: 2,
          existingLowercase: {},
          unique: _unique,
        ),
        ['talk_cut_1.m4a', 'talk_cut_2.m4a'],
      );
    });
  });

  group('formatTimecode', () {
    test('formats minutes, hours and the optional fraction', () {
      expect(formatTimecode(0), '0:00.000');
      expect(formatTimecode(61500000), '1:01.500');
      expect(formatTimecode(3600 * _s), '1:00:00.000');
      expect(formatTimecode(65 * _s, millis: false), '1:05');
      expect(formatTimecode(-5), '0:00.000');
    });
  });
}
