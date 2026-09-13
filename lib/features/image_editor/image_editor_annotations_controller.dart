import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

part 'image_editor_annotations_controller.g.dart';

@riverpod
class ImageEditorAnnotations extends _$ImageEditorAnnotations {
  @override
  List<EditAnnotation> build(String sessionKey) => const [];

  void add(EditAnnotation annotation) =>
      state = List.unmodifiable([...state, annotation]);

  void setAll(List<EditAnnotation> annotations) =>
      state = List.unmodifiable(annotations);

  void update(int index, EditAnnotation annotation) {
    if (index < 0 || index >= state.length) return;
    final updated = List<EditAnnotation>.of(state);
    updated[index] = annotation;
    state = List.unmodifiable(updated);
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final updated = List<EditAnnotation>.of(state);
    updated.removeAt(index);
    state = List.unmodifiable(updated);
  }

  void undo() {
    if (state.isEmpty) return;
    state = List.unmodifiable(state.sublist(0, state.length - 1));
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
  }
}