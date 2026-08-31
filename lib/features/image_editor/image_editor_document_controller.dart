import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'image_editor_document_controller.g.dart';

/// User-visible document status for one image-editor session.
///
/// The decoded bytes and `ui.Image` are native rendering resources and stay in
/// the widget. Their loading, error, save, and dirty lifecycle is ordinary
/// asynchronous screen state and is kept here.
class ImageEditorDocumentState {
  const ImageEditorDocumentState({
    this.isLoading = true,
    this.errorMessage,
    this.isEdited = false,
    this.isSaving = false,
  });

  final bool isLoading;
  final String? errorMessage;
  final bool isEdited;
  final bool isSaving;

  ImageEditorDocumentState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? isEdited,
    bool? isSaving,
  }) => ImageEditorDocumentState(
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    isEdited: isEdited ?? this.isEdited,
    isSaving: isSaving ?? this.isSaving,
  );
}

@riverpod
class ImageEditorDocument extends _$ImageEditorDocument {
  @override
  ImageEditorDocumentState build(String sessionKey) =>
      const ImageEditorDocumentState();

  void startLoading() =>
      state = state.copyWith(isLoading: true, clearError: true);

  void loaded() => state = state.copyWith(isLoading: false, clearError: true);

  void loadFailed(String message) =>
      state = state.copyWith(isLoading: false, errorMessage: message);

  void stopLoading() => state = state.copyWith(isLoading: false);

  void markEdited() => state = state.copyWith(isEdited: true);

  void resetEdited() => state = state.copyWith(isEdited: false);

  void setSaving(bool value) => state = state.copyWith(isSaving: value);

  void saved() => state = state.copyWith(isSaving: false, isEdited: false);
}
