import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/audio_editor/audio_editor_controller.dart';
import 'package:vaultexplorer/features/video_editor/models/edit_segment.dart' show VideoEditMode;

const _s = 1000000; // one second in microseconds

/// A 10 s track. Audio has no keyframes, so nothing snaps.
AudioEditorController _controller() => AudioEditorController(durationUs: 10 * _s);

void main() {
  group('starting state', () {
    test('one full-length segment, selected, nothing to snap to', () {
      final c = _controller();
      expect(c.segments, hasLength(1));
      expect(c.segments.first.startUs, 0);
      expect(c.segments.first.endUs, 10 * _s);
      expect(c.selectedId, c.segments.first.id);
      expect(c.keyframes, isEmpty);
      expect(c.plannedRanges, [(startUs: 0, endUs: 10 * _s)]);
      expect(c.snappedRanges, c.plannedRanges);
      expect(c.canExport, isTrue);
      expect(c.hasUnsavedChanges, isFalse);
    });
  });

  group('boundaries land exactly where they are put', () {
    test('an end set 500 us past a whole second is not pulled onto a keyframe', () {
      final c = _controller();
      expect(c.setSelectedEnd(4 * _s + 500), isTrue);
      expect(c.selected!.endUs, 4 * _s + 500);
    });

    test('trimming both ends and undoing', () {
      final c = _controller();
      expect(c.setSelectedStart(2 * _s), isTrue);
      expect(c.setSelectedEnd(7 * _s), isTrue);
      expect(c.plannedRanges, [(startUs: 2 * _s, endUs: 7 * _s)]);
      expect(c.totalSnappedUs, 5 * _s);
      expect(c.hasUnsavedChanges, isTrue);

      c.undo();
      c.undo();
      expect(c.plannedRanges, [(startUs: 0, endUs: 10 * _s)]);
    });
  });

  group('split / delete / modes', () {
    test('split then delete the second half keeps only the first', () {
      final c = _controller();
      expect(c.splitAt(5 * _s), isTrue);
      expect(c.segments, hasLength(2));
      c.select(c.segments.last.id);
      c.deleteSelected();
      expect(c.plannedRanges, [(startUs: 0, endUs: 5 * _s)]);
    });

    test('cut-out mode exports everything around the segments', () {
      final c = _controller();
      c.setSelectedStart(2 * _s);
      c.setSelectedEnd(4 * _s);
      c.setMode(VideoEditMode.cutOut);
      expect(c.plannedRanges, [
        (startUs: 0, endUs: 2 * _s),
        (startUs: 4 * _s, endUs: 10 * _s),
      ]);
      expect(c.totalSnappedUs, 8 * _s);
    });

    test('merging uses the planned ranges as they are', () {
      final c = _controller();
      c.setSelectedStart(1 * _s);
      c.setSelectedEnd(3 * _s);
      c.addSegmentAt(6 * _s);
      expect(c.exportRanges(merge: true), c.plannedRanges);
      expect(c.exportRanges(merge: false), c.plannedRanges);
    });

    test('with every segment deleted there is nothing to export', () {
      final c = _controller();
      c.deleteSelected();
      expect(c.canExport, isFalse);
    });

    test('a segment shorter than the minimum is refused', () {
      final c = _controller();
      c.setSelectedEnd(5 * _s);
      expect(c.setSelectedStart(5 * _s - 50000), isFalse);
      expect(c.selected!.startUs, 0);
    });
  });
}
