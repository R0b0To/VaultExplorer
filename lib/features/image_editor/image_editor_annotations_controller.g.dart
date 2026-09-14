// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_editor_annotations_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ImageEditorAnnotations)
final imageEditorAnnotationsProvider = ImageEditorAnnotationsFamily._();

final class ImageEditorAnnotationsProvider
    extends $NotifierProvider<ImageEditorAnnotations, List<EditAnnotation>> {
  ImageEditorAnnotationsProvider._({
    required ImageEditorAnnotationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'imageEditorAnnotationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$imageEditorAnnotationsHash();

  @override
  String toString() {
    return r'imageEditorAnnotationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ImageEditorAnnotations create() => ImageEditorAnnotations();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<EditAnnotation> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<EditAnnotation>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ImageEditorAnnotationsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$imageEditorAnnotationsHash() =>
    r'72e6fba2e205d2d5b877b7da1b39e74c5da01f3e';

final class ImageEditorAnnotationsFamily extends $Family
    with
        $ClassFamilyOverride<
          ImageEditorAnnotations,
          List<EditAnnotation>,
          List<EditAnnotation>,
          List<EditAnnotation>,
          String
        > {
  ImageEditorAnnotationsFamily._()
    : super(
        retry: null,
        name: r'imageEditorAnnotationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ImageEditorAnnotationsProvider call(String sessionKey) =>
      ImageEditorAnnotationsProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'imageEditorAnnotationsProvider';
}

abstract class _$ImageEditorAnnotations
    extends $Notifier<List<EditAnnotation>> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  List<EditAnnotation> build(String sessionKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<EditAnnotation>, List<EditAnnotation>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<EditAnnotation>, List<EditAnnotation>>,
              List<EditAnnotation>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
