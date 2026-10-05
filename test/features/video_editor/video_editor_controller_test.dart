import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/video_editor/models/edit_segment.dart';
import 'package:vaultexplorer/features/video_editor/video_editor_controller.dart';

const _s = 1000000; // one second in microseconds

/// A 10 s video with a keyframe every 2 s.
VideoEditorController _controller({bool withKeyframes = true}) =>
    VideoEditorController(
      durationUs: 10 * _s,
      keyframesUs: withKeyframes
          ? [0, 2 * _s, 4 * _s, 6 * _s, 8 * _s]
          : const [],
    );

void main() {
  group('starting state', () {
    test('one full-length segment, selected', () {
      final c = _controller();
      expect(c.segments, hasLength(1));
      expect(c.segments.first.startUs, 0);
      expect(c.segments.first.endUs, 10 * _s);
      expect(c.selectedId, c.segments.first.id);
      expect(c.plannedRanges, [(startUs: 0, endUs: 10 * _s)]);
      expect(c.canUndo, isFalse);
      expect(c.canExport, isTrue);
    });
  });

  group('set start / end', () {
    test('moves the selected segment and can be undone', () {
      final c = _controller(withKeyframes: false);
      expect(c.setSelectedStart(3 * _s), isTrue);
      expect(c.setSelectedEnd(7 * _s), isTrue);
      expect(c.selected!.startUs, 3 * _s);
      expect(c.selected!.endUs, 7 * _s);

      c.undo();
      expect(c.selected!.endUs, 10 * _s);
      c.undo();
      expect(c.selected!.startUs, 0);
      expect(c.canUndo, isFalse);
    });

    test('refuses to leave the segment too short and changes nothing', () {
      final c = _controller(withKeyframes: false);
      c.setSelectedEnd(5 * _s);
      expect(c.setSelectedStart(5 * _s), isFalse);
      expect(c.setSelectedStart(5 * _s - 50000), isFalse);
      expect(c.selected!.startUs, 0);

      expect(c.setSelectedEnd(50000), isFalse);
      expect(c.selected!.endUs, 5 * _s);
    });

    test('a boundary within a millisecond of a keyframe snaps onto it', () {
      // The player reports whole milliseconds, so "on the keyframe" can read
      // a few hundred microseconds late. It must not push the end forward.
      final c = _controller();
      expect(c.setSelectedEnd(4 * _s + 500), isTrue);
      expect(c.selected!.endUs, 4 * _s);
      expect(c.snappedFor(c.selected!), (startUs: 0, endUs: 4 * _s));
    });

    test('a boundary between keyframes is snapped outward only in the preview', () {
      final c = _controller();
      c.setSelectedStart(3 * _s);
      expect(c.selected!.startUs, 3 * _s); // the segment keeps the exact point
      expect(c.snappedFor(c.selected!), (startUs: 2 * _s, endUs: 10 * _s));
    });
  });

  group('add / split / delete', () {
    test('the first add replaces the untouched starter segment', () {
      final c = _controller(withKeyframes: false);
      expect(c.addSegmentAt(2 * _s), isTrue);
      expect(c.segments, hasLength(1));
      expect(c.segments.first.startUs, 2 * _s);
      expect(c.segments.first.endUs, 10 * _s); // 2 s + 10 s clamps to the end
    });

    test('later adds create new segments, but never inside an existing one', () {
      final c = _controller(withKeyframes: false);
      c.setSelectedEnd(4 * _s);
      expect(c.addSegmentAt(6 * _s), isTrue);
      expect(c.segments, hasLength(2));
      expect(c.selected!.startUs, 6 * _s);

      expect(c.addSegmentAt(1 * _s), isFalse); // inside the first segment
      expect(c.segments, hasLength(2));
    });

    test('a new segment stops at the next segment', () {
      final c = _controller(withKeyframes: false);
      c.setSelectedEnd(2 * _s);
      c.addSegmentAt(5 * _s);
      expect(c.addSegmentAt(3 * _s), isTrue);
      final added = c.selected!;
      expect(added.startUs, 3 * _s);
      expect(added.endUs, 5 * _s);
      expect(c.segments.map((s) => s.startUs), [0, 3 * _s, 5 * _s]); // sorted
    });

    test('split divides the segment under the playhead', () {
      final c = _controller(withKeyframes: false);
      expect(c.splitAt(5 * _s), isTrue);
      expect(c.segments, hasLength(2));
      expect(c.segments[0].endUs, 5 * _s);
      expect(c.segments[1].startUs, 5 * _s);
      expect(c.segments[1].endUs, 10 * _s);
    });

    test('split refuses to make a sliver', () {
      final c = _controller(withKeyframes: false);
      expect(c.splitAt(50000), isFalse);
      expect(c.splitAt(10 * _s - 50000), isFalse);
      expect(c.segments, hasLength(1));
    });

    test('delete selects a neighbour, and an empty list cannot export', () {
      final c = _controller(withKeyframes: false);
      c.splitAt(5 * _s);
      final first = c.segments[0];
      c.select(first.id);
      c.deleteSelected();
      expect(c.segments, hasLength(1));
      expect(c.selected, isNotNull);

      c.deleteSelected();
      expect(c.segments, isEmpty);
      expect(c.selectedId, isNull);
      expect(c.canExport, isFalse);
    });
  });

  group('modes and export planning', () {
    test('cut-out exports the parts around the marked segment', () {
      final c = _controller(withKeyframes: false);
      c.setSelectedStart(2 * _s);
      c.setSelectedEnd(4 * _s);
      c.setMode(VideoEditMode.cutOut);
      expect(c.plannedRanges, [
        (startUs: 0, endUs: 2 * _s),
        (startUs: 4 * _s, endUs: 10 * _s),
      ]);
    });

    test('merging joins clips whose snapped extents overlap', () {
      // 1-2.5 s snaps to 0-4 s and 3-5 s snaps to 2-6 s: they share footage.
      final c = _controller();
      c.setSelectedStart(1 * _s);
      c.setSelectedEnd(2 * _s + 500000);
      c.addSegmentAt(3 * _s);
      c.setSelectedEnd(5 * _s);

      expect(c.exportRanges(merge: false), [
        (startUs: 1 * _s, endUs: 2 * _s + 500000),
        (startUs: 3 * _s, endUs: 5 * _s),
      ]);
      expect(c.exportRanges(merge: true), [(startUs: 0, endUs: 6 * _s)]);
    });

    test('total length reflects keyframe snapping', () {
      final c = _controller();
      c.setSelectedStart(3 * _s); // snaps back to 2 s
      expect(c.totalSnappedUs, 8 * _s);
    });
  });

  group('keyframe navigation', () {
    test('previous/next skip the keyframe the playhead is on', () {
      final c = _controller();
      expect(c.previousKeyframe(4 * _s), 2 * _s);
      expect(c.nextKeyframe(4 * _s), 6 * _s);
      expect(c.previousKeyframe(4500000), 4 * _s);
      expect(c.nextKeyframe(4500000), 6 * _s);
    });

    test('there is nothing before the first or after the last', () {
      final c = _controller();
      expect(c.previousKeyframe(0), isNull);
      expect(c.nextKeyframe(8 * _s), isNull);
    });
  });

  group('selection and notifications', () {
    test('selectAt picks the segment under a time', () {
      final c = _controller(withKeyframes: false);
      c.splitAt(5 * _s);
      expect(c.selectAt(7 * _s), isTrue);
      expect(c.selected!.startUs, 5 * _s);
      expect(c.selectAt(10 * _s), isFalse); // the end is exclusive
    });

    test('edits notify listeners; no-ops do not', () {
      final c = _controller(withKeyframes: false);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.setSelectedStart(2 * _s);
      expect(notifications, 1);
      c.setSelectedStart(2 * _s); // already there
      expect(notifications, 1);
      c.setMode(VideoEditMode.keep); // already keep
      expect(notifications, 1);
    });
  });

  group('redo and dirty state', () {
    test('redo restores undone state and clears on new edit', () {
      final c = _controller(withKeyframes: false);
      expect(c.isPristine, isTrue);
      expect(c.hasUnsavedChanges, isFalse);
      expect(c.canRedo, isFalse);

      c.setSelectedStart(2 * _s);
      expect(c.isPristine, isFalse);
      expect(c.hasUnsavedChanges, isTrue);
      expect(c.canUndo, isTrue);
      expect(c.canRedo, isFalse);

      c.undo();
      expect(c.selected!.startUs, 0);
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.selected!.startUs, 2 * _s);
      expect(c.canRedo, isFalse);

      // Undoing then making a new edit wipes redo history
      c.undo();
      expect(c.canRedo, isTrue);
      c.setSelectedEnd(8 * _s);
      expect(c.canRedo, isFalse);
    });

    test('handle dragging updates boundaries without spamming history', () {
      final c = _controller(withKeyframes: false);
      c.beginHandleDrag();
      c.updateSelectedStart(1 * _s);
      c.updateSelectedStart(2 * _s);
      c.updateSelectedStart(3 * _s);
      c.endHandleDrag();

      expect(c.selected!.startUs, 3 * _s);
      // Only 1 undo step was created by beginHandleDrag
      c.undo();
      expect(c.selected!.startUs, 0);
      expect(c.canUndo, isFalse);
    });
  });
}
