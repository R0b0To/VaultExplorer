// TextEditorScreen was a StatefulWidget owning load/save/autosave/error
// state directly as State fields, alongside a TextEditingController and
// UndoHistoryController. Family-keyed by (volId, filePath), the same shape
// as VaultItemDetail: a fresh screen instance is pushed per file. Mirrors
// LocalTextViewerController's split -- TextEditingController, its own
// dirty/line/char tracking (all tightly tied to the TextField's own
// listener, not real domain data), and the debounced-autosave Timer stay
// widget-owned; load/save move here. Unlike the local sibling, `save()`
// takes the MountedContainer at call time rather than baking it into the
// family key -- readWholeFile/writeWholeFile need the whole object, but
// only volId (not the full container) is meaningful as part of "which
// screen session is this".
import 'dart:convert';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

part 'text_editor_controller.g.dart';

class TextEditorLoadState {
  final bool isLoading;
  final bool hasError;
  final String errorMessage;

  /// Only meaningful the moment loading finishes successfully -- the
  /// widget applies this to its TextEditingController exactly once (see
  /// TextEditorScreen's `ref.listen`), then edits live in the controller
  /// from that point on. Null both before load finishes and after the
  /// widget has consumed it.
  final String? loadedText;

  const TextEditorLoadState({
    this.isLoading = true,
    this.hasError = false,
    this.errorMessage = '',
    this.loadedText,
  });
}

@riverpod
class TextEditorLoad extends _$TextEditorLoad {
  @override
  TextEditorLoadState build(int volId, String filePath) {
    return const TextEditorLoadState();
  }

  Future<void> load(MountedContainer container, String errorFallback, String invalidTextMessage) async {
    state = const TextEditorLoadState(isLoading: true);
    try {
      final bytes = await ref.read(vaultFileIoApiProvider).readWholeFile(container, filePath);
      if (bytes == null) {
        throw Exception(errorFallback);
      }
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw FormatException(invalidTextMessage);
      }
      if (!ref.mounted) return;
      state = TextEditorLoadState(isLoading: false, loadedText: text);
    } catch (e) {
      if (!ref.mounted) return;
      state = TextEditorLoadState(isLoading: false, hasError: true, errorMessage: e.toString());
    }
  }

  /// Returns null on success, or the error text to show on failure --
  /// matching the original's `'$e'` snackbar, including the underlying
  /// exception's own message, not just a generic write-back-failed string.
  /// Encodes straight to bytes in memory and hands them to writeWholeFile,
  /// which stages the write as ciphertext inside the vault itself (atomic
  /// temp-path-then-rename, all server-side) -- no plaintext copy of the
  /// edited text ever touches host disk.
  Future<String?> save(MountedContainer container, String content, String writeBackFailedMessage) async {
    try {
      final ok = await ref
          .read(vaultFileIoApiProvider)
          .writeWholeFile(container, filePath, Uint8List.fromList(utf8.encode(content)));
      if (!ok) throw Exception(writeBackFailedMessage);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
