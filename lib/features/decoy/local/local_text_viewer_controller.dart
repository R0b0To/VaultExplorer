import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_text_viewer_controller.g.dart';

class LocalTextViewerState {
  final bool loading;
  final bool tooLarge;
  final bool saving;
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
    const initial = LocalTextViewerState();
    Future.microtask(() => _load(filePath));
    return initial;
  }

  Future<void> _load(String filePath) async {
    final file = File(filePath);
    try {
      final length = await file.length();
      if (length > _maxPreviewBytes) {
        if (ref.mounted) state = const LocalTextViewerState(loading: false, tooLarge: true);
        return;
      }
      final text = await file.readAsString();
      if (!ref.mounted) return;
      state = LocalTextViewerState(loading: false, loadedText: text);
    } catch (_) {
      if (ref.mounted) state = const LocalTextViewerState(loading: false, tooLarge: true);
    }
  }

  Future<bool> save(String filePath, String content) async {
    state = LocalTextViewerState(
      loading: state.loading,
      tooLarge: state.tooLarge,
      saving: true,
      loadedText: state.loadedText,
    );
    try {
      await File(filePath).writeAsString(content);
      if (ref.mounted) {
        state = LocalTextViewerState(
          loading: state.loading,
          tooLarge: state.tooLarge,
          saving: false,
          loadedText: content,
        );
      }
      return true;
    } catch (_) {
      if (ref.mounted) {
        state = LocalTextViewerState(
          loading: state.loading,
          tooLarge: state.tooLarge,
          saving: false,
          loadedText: state.loadedText,
        );
      }
      return false;
    }
  }
}