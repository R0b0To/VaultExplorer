// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_editor_document_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ImageEditorDocument)
final imageEditorDocumentProvider = ImageEditorDocumentFamily._();

final class ImageEditorDocumentProvider
    extends $NotifierProvider<ImageEditorDocument, ImageEditorDocumentState> {
  ImageEditorDocumentProvider._({
    required ImageEditorDocumentFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'imageEditorDocumentProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$imageEditorDocumentHash();

  @override
  String toString() {
    return r'imageEditorDocumentProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ImageEditorDocument create() => ImageEditorDocument();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImageEditorDocumentState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImageEditorDocumentState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ImageEditorDocumentProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$imageEditorDocumentHash() =>
    r'00bba07f4163688bafeda3ec2e20db6394e9454c';

final class ImageEditorDocumentFamily extends $Family
    with
        $ClassFamilyOverride<
          ImageEditorDocument,
          ImageEditorDocumentState,
          ImageEditorDocumentState,
          ImageEditorDocumentState,
          String
        > {
  ImageEditorDocumentFamily._()
    : super(
        retry: null,
        name: r'imageEditorDocumentProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ImageEditorDocumentProvider call(String sessionKey) =>
      ImageEditorDocumentProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'imageEditorDocumentProvider';
}

abstract class _$ImageEditorDocument
    extends $Notifier<ImageEditorDocumentState> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  ImageEditorDocumentState build(String sessionKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ImageEditorDocumentState, ImageEditorDocumentState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImageEditorDocumentState, ImageEditorDocumentState>,
              ImageEditorDocumentState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
