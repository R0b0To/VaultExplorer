import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_document_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  final provider = imageEditorDocumentProvider('image-a');

  test('starts loading with a clean document state', () {
    final state = container.read(provider);

    expect(state.isLoading, isTrue);
    expect(state.errorMessage, isNull);
    expect(state.isEdited, isFalse);
    expect(state.isSaving, isFalse);
  });

  test('tracks load success and failure independently from edit state', () {
    final controller = container.read(provider.notifier);

    controller.loaded();
    expect(container.read(provider).isLoading, isFalse);

    controller.markEdited();
    controller.startLoading();
    controller.loadFailed('Unsupported image');
    final state = container.read(provider);
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, 'Unsupported image');
    expect(state.isEdited, isTrue);
  });

  test('save completion clears saving and edited state', () {
    final controller = container.read(provider.notifier);

    controller.loaded();
    controller.markEdited();
    controller.setSaving(true);
    controller.saved();

    final state = container.read(provider);
    expect(state.isLoading, isFalse);
    expect(state.isSaving, isFalse);
    expect(state.isEdited, isFalse);
  });

  test('keeps document status isolated per editor session', () {
    container.read(provider.notifier).loadFailed('bad image');
    container
        .read(imageEditorDocumentProvider('image-b').notifier)
        .setSaving(true);

    expect(container.read(provider).errorMessage, 'bad image');
    expect(container.read(provider).isSaving, isFalse);
    expect(
      container.read(imageEditorDocumentProvider('image-b')).errorMessage,
      isNull,
    );
    expect(
      container.read(imageEditorDocumentProvider('image-b')).isSaving,
      isTrue,
    );
  });
}
