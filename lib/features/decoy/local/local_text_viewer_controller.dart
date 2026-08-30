// LocalTextViewerScreen keeps its TextEditingController and `_dirty` flag
// local -- `_dirty` is just "has the user typed since the last save",
// tightly tied to the TextField's own onChanged, not real domain data. The
// actual file load/save moves here. Family-keyed by filePath: a fresh
// screen instance is pushed per file.
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_text_viewer_controller.g.dart';

class LocalTextViewerState {
  final bool loading;
  final bool tooLarge;
  final bool saving;

  /// Only meaningful once `loading` is false and `tooLarge` is false --
  /// the widget applies this to its TextEditingController exactly once,
  /// the moment it goes from null to non-null (see LocalTextViewerScreen's
  /// `ref.listen`), then never reads it again (edits live in the
  /// controller from that point on).
  final String? loadedText;

  const LocalTextViewerState({
    this.loading = true,
    this.tooLarge = false,
    this.saving = false,
    this.loadedText,
  });
}

@riverpod
class LocalTextViewer extends _$LocalTextViewer {
  static const int _maxPreviewBytes = 2 * 1024 * 1024; // 2 MB

  @override
  LocalTextViewerState build(String filePath) {
    _load(filePath);
    return const LocalTextViewerState();
  }

  LocalTextViewerState _copy({bool? loading, bool? tooLarge, bool? saving, String? loadedText}) =>
      LocalTextViewerState(
        loading: loading ?? state.loading,
        tooLarge: tooLarge ?? state.tooLarge,
        saving: saving ?? state.saving,
        loadedText: loadedText ?? state.loadedText,
      );

  Future<void> _load(String filePath) async {
    final file = File(filePath);
    try {
      final length = await file.length();
      if (length > _maxPreviewBytes) {
        if (ref.mounted) state = _copy(loading: false, tooLarge: true);
        return;
      }
      final text = await file.readAsString();
      if (!ref.mounted) return;
      state = _copy(loading: false, loadedText: text);
    } catch (_) {
      if (ref.mounted) state = _copy(loading: false, tooLarge: true);
    }
  }

  /// Returns true on success -- the widget clears its dirty flag and
  /// shows the corresponding snackbar either way.
  Future<bool> save(String filePath, String content) async {
    state = _copy(saving: true);
    try {
      await File(filePath).writeAsString(content);
      if (ref.mounted) state = _copy(saving: false);
      return true;
    } catch (_) {
      if (ref.mounted) state = _copy(saving: false);
      return false;
    }
  }
}
