import 'package:flutter/foundation.dart';

import 'models/edit_segment.dart';
import 'models/video_edit_math.dart';

/// Length of a segment created with "add segment"
const int kDefaultNewSegmentUs = 10 * 1000000;

/// The player reports positions in whole milliseconds, so a playhead sitting
/// "on" a keyframe can read up to this far past it. A boundary set within this
/// of a keyframe is treated as exactly that keyframe -- otherwise an end set
/// on a keyframe would snap *forward* to the next one and pull in an extra
/// group of pictures.
const int kKeyframeSlackUs = 1000;

const int _kMaxHistory = 50;

class _Snapshot {
  final List<EditSegment> segments;
  final String? selectedId;
  final bool pristine;
  const _Snapshot(this.segments, this.selectedId, this.pristine);
}

/// Editing state for the video editor: the segments on the timeline, which
/// one is selected, what the segments mean (keep vs cut out), and undo.
///
/// Segments never overlap and are kept sorted by start. Everything here is
/// plain Dart -- the player, the timeline and the export call live in the
/// screen -- so it can be unit-tested without a device.
class VideoEditorController extends ChangeNotifier {
  VideoEditorController({
    required this.durationUs,
    List<int> keyframesUs = const [],
    this.keyframesComplete = true,
  }) : keyframes = keyframesUs {
    final first = _newSegment(0, durationUs);
    _segments = [first];
    _selectedId = first.id;
  }

  final int durationUs;

  /// Ascending sync-sample times of the video track.
  final List<int> keyframes;

  /// Whether [keyframes] covers the whole file (see `VideoProbe`).
  final bool keyframesComplete;

  List<EditSegment> _segments = [];
  List<EditSegment>? _cachedSegments;
  String? _selectedId;
  VideoEditMode _mode = VideoEditMode.keep;
  int _nextId = 1;

  /// True until the first edit: the lone full-length starter segment is
  /// replaced (not added to) by the first "add segment".
  bool _pristine = true;

  final List<_Snapshot> _history = [];
  final List<_Snapshot> _redoHistory = [];

  // ── Read state ─────────────────────────────────────────────────────────

  List<EditSegment> get segments =>
      _cachedSegments ??= List.unmodifiable(_segments);
  String? get selectedId => _selectedId;
  VideoEditMode get mode => _mode;
  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;
  bool get isPristine => _pristine;
  bool get hasUnsavedChanges => !_pristine || _history.isNotEmpty;

  int get selectedIndex =>
      _selectedId == null ? -1 : _segments.indexWhere((s) => s.id == _selectedId);

  EditSegment? get selected {
    final i = selectedIndex;
    return i < 0 ? null : _segments[i];
  }

  /// The time ranges that will be exported, before keyframe snapping.
  List<TimeRange> get plannedRanges =>
      planExportRanges(_segments, _mode, durationUs);

  /// [plannedRanges] after the keyframe snapping the cutter will apply --
  /// what the exported file will really contain.
  List<TimeRange> get snappedRanges => [
        for (final r in plannedRanges) _snap(r),
      ];

  bool get canExport => _segments.isNotEmpty && plannedRanges.isNotEmpty;

  /// The ranges to hand to the native export. When merging, ranges whose
  /// snapped extents overlap (two cuts inside one group of pictures) are
  /// joined so the shared footage isn't written twice.
  List<TimeRange> exportRanges({required bool merge}) {
    if (merge && keyframesComplete && keyframes.isNotEmpty) {
      return mergeOverlapping(snappedRanges);
    }
    return plannedRanges;
  }

  /// Total length of the exported footage after snapping.
  int get totalSnappedUs => snappedRanges.fold(0, (a, r) => a + (r.endUs - r.startUs));

  /// What the cutter will export for [segment] on its own.
  TimeRange snappedFor(EditSegment segment) => _snap(segment.range);

  TimeRange _snap(TimeRange r) => snapRangeOutward(
        keyframes,
        r,
        durationUs,
        keyframesComplete: keyframesComplete,
      );

  // ── Keyframe navigation ────────────────────────────────────────────────

  int? previousKeyframe(int fromUs) =>
      keyframeAtOrBefore(keyframes, fromUs - kKeyframeSlackUs);

  int? nextKeyframe(int fromUs) =>
      keyframeAtOrAfter(keyframes, fromUs + kKeyframeSlackUs);

  // ── Editing ────────────────────────────────────────────────────────────

  void select(String id) {
    if (_selectedId == id || !_segments.any((s) => s.id == id)) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Selects the segment under [us]; returns false when there is none.
  bool selectAt(int us) {
    final i = _segments.indexWhere((s) => s.containsUs(us));
    if (i < 0) return false;
    select(_segments[i].id);
    return true;
  }

  /// Moves the selected segment's start to [us]. Returns false when that would leave the segment too short.
  bool setSelectedStart(int us) {
    final i = selectedIndex;
    if (i < 0) return false;
    final s = _segments[i];
    var t = _normalize(us);
    final floor = i == 0 ? 0 : _segments[i - 1].endUs;
    if (t < floor) t = floor;
    if (t > s.endUs - kMinSegmentUs) return false;
    if (t != s.startUs) {
      _pushHistory();
      _cachedSegments = null;
      _segments[i] = s.copyWith(startUs: t);
      _pristine = false;
      notifyListeners();
    }
    return true;
  }

  /// Moves the selected segment's end to [us]. Returns false when that would
  /// leave the segment too short.
  bool setSelectedEnd(int us) {
    final i = selectedIndex;
    if (i < 0) return false;
    final s = _segments[i];
    var t = _normalize(us);
    final ceiling = i == _segments.length - 1 ? durationUs : _segments[i + 1].startUs;
    if (t > ceiling) t = ceiling;
    if (t < s.startUs + kMinSegmentUs) return false;
    if (t != s.endUs) {
      _pushHistory();
      _cachedSegments = null;
      _segments[i] = s.copyWith(endUs: t);
      _pristine = false;
      notifyListeners();
    }
    return true;
  }

  // ── Handle dragging (continuous updates during gesture) ────────────────

  /// Called once when user begins dragging an edge handle. Saves undo history.
  void beginHandleDrag() {
    final i = selectedIndex;
    if (i < 0) return;
    _pushHistory();
    _pristine = false;
  }

  /// Updates start during continuous handle drag without adding multiple history entries.
  bool updateSelectedStart(int us) {
    final i = selectedIndex;
    if (i < 0) return false;
    final s = _segments[i];
    final floor = i == 0 ? 0 : _segments[i - 1].endUs;
    var t = us.clamp(0, durationUs).toInt();
    if (t < floor) t = floor;
    if (t > s.endUs - kMinSegmentUs) t = s.endUs - kMinSegmentUs;
    if (t != s.startUs) {
      _cachedSegments = null;
      _segments[i] = s.copyWith(startUs: t);
      _pristine = false;
      notifyListeners();
    }
    return true;
  }

  /// Updates end during continuous handle drag without adding multiple history entries.
  bool updateSelectedEnd(int us) {
    final i = selectedIndex;
    if (i < 0) return false;
    final s = _segments[i];
    final ceiling = i == _segments.length - 1 ? durationUs : _segments[i + 1].startUs;
    var t = us.clamp(0, durationUs).toInt();
    if (t > ceiling) t = ceiling;
    if (t < s.startUs + kMinSegmentUs) t = s.startUs + kMinSegmentUs;
    if (t != s.endUs) {
      _cachedSegments = null;
      _segments[i] = s.copyWith(endUs: t);
      _pristine = false;
      notifyListeners();
    }
    return true;
  }

  /// Called when user finishes dragging a handle to normalize slack onto keyframe.
  void endHandleDrag() {
    final i = selectedIndex;
    if (i < 0) return;
    final s = _segments[i];
    final normStart = _normalize(s.startUs);
    final normEnd = _normalize(s.endUs);
    if (normStart != s.startUs || normEnd != s.endUs) {
      _cachedSegments = null;
      _segments[i] = s.copyWith(startUs: normStart, endUs: normEnd);
      notifyListeners();
    }
  }

  /// Adds a segment starting at [us], up to [kDefaultNewSegmentUs] long but
  /// never running into the next segment. Returns false when [us] is inside
  /// an existing segment or there's no room. The untouched starter segment is
  /// replaced rather than added to.
  bool addSegmentAt(int us) {
    final t = _normalize(us);
    if (!_pristine && _segments.any((s) => s.containsUs(t))) return false;

    final others = _pristine ? const <EditSegment>[] : _segments;
    var end = t + kDefaultNewSegmentUs;
    if (end > durationUs) end = durationUs;
    for (final s in others) {
      if (s.startUs > t && s.startUs < end) end = s.startUs;
    }
    if (end - t < kMinSegmentUs) return false;

    _pushHistory();
    final added = _newSegment(t, end);
    _segments = [...others, added]..sort((a, b) => a.startUs.compareTo(b.startUs));
    _cachedSegments = null;
    _selectedId = added.id;
    _pristine = false;
    notifyListeners();
    return true;
  }

  /// Splits the segment under [us] in two. Returns false when [us] is outside
  /// every segment or either half would be too short.
  bool splitAt(int us) {
    final t = _normalize(us);
    final i = _segments.indexWhere((s) => s.containsUs(t));
    if (i < 0) return false;
    final s = _segments[i];
    if (t - s.startUs < kMinSegmentUs || s.endUs - t < kMinSegmentUs) return false;

    _pushHistory();
    final right = _newSegment(t, s.endUs);
    _segments[i] = s.copyWith(endUs: t);
    _segments.insert(i + 1, right);
    _cachedSegments = null;
    _pristine = false;
    notifyListeners();
    return true;
  }

  void deleteSelected() {
    final i = selectedIndex;
    if (i < 0) return;
    _pushHistory();
    _segments.removeAt(i);
    _cachedSegments = null;
    _selectedId = _segments.isEmpty
        ? null
        : _segments[i.clamp(0, _segments.length - 1).toInt()].id;
    _pristine = false;
    notifyListeners();
  }

  void setMode(VideoEditMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void undo() {
    if (_history.isEmpty) return;
    _redoHistory.add(_Snapshot([..._segments], _selectedId, _pristine));
    final snap = _history.removeLast();
    _segments = [...snap.segments];
    _cachedSegments = null;
    _selectedId = snap.selectedId;
    _pristine = snap.pristine;
    notifyListeners();
  }

  void redo() {
    if (_redoHistory.isEmpty) return;
    _history.add(_Snapshot([..._segments], _selectedId, _pristine));
    final snap = _redoHistory.removeLast();
    _segments = [...snap.segments];
    _cachedSegments = null;
    _selectedId = snap.selectedId;
    _pristine = snap.pristine;
    notifyListeners();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  EditSegment _newSegment(int startUs, int endUs) =>
      EditSegment(id: '${_nextId++}', startUs: startUs, endUs: endUs);

  void _pushHistory() {
    _history.add(_Snapshot([..._segments], _selectedId, _pristine));
    _redoHistory.clear();
    if (_history.length > _kMaxHistory) _history.removeAt(0);
  }

  /// Clamps [us] into the file and pulls it onto a keyframe it's within
  /// [kKeyframeSlackUs] past.
  int _normalize(int us) {
    final t = us.clamp(0, durationUs).toInt();
    final k = keyframeAtOrBefore(keyframes, t);
    if (k != null && t - k < kKeyframeSlackUs) return k;
    return t;
  }
}
