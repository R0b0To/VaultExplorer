import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

part 'image_editor_annotations_controller.g.dart';

/// Committed, normalized annotations for one image-editor session.
///
/// Live pen/redaction gesture points and the rendered `ui.Image` stay in the
/// widget because they are frame-bound resources. Once a gesture is committed,
/// its immutable annotation is editor-session state and belongs here.
@riverpod
class ImageEditorAnnotations extends _$ImageEditorAnnotations {
  @override
  List<EditAnnotation> build(String sessionKey) => const [];

  void add(EditAnnotation annotation) =>
      state = List.unmodifiable([...state, annotation]);

  void undo() {
    if (state.isEmpty) return;
    state = List.unmodifiable(state.sublist(0, state.length - 1));
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
  }
}
