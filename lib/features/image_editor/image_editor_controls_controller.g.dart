// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_editor_controls_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ImageEditorControls)
final imageEditorControlsProvider = ImageEditorControlsFamily._();

final class ImageEditorControlsProvider
    extends $NotifierProvider<ImageEditorControls, ImageEditorControlsState> {
  ImageEditorControlsProvider._({
    required ImageEditorControlsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'imageEditorControlsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$imageEditorControlsHash();

  @override
  String toString() {
    return r'imageEditorControlsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ImageEditorControls create() => ImageEditorControls();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImageEditorControlsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImageEditorControlsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ImageEditorControlsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$imageEditorControlsHash() =>
    r'8d89d9ea53fe2675191424a4efa7c98ef66c5893';

final class ImageEditorControlsFamily extends $Family
    with
        $ClassFamilyOverride<
          ImageEditorControls,
          ImageEditorControlsState,
          ImageEditorControlsState,
          ImageEditorControlsState,
          String
        > {
  ImageEditorControlsFamily._()
    : super(
        retry: null,
        name: r'imageEditorControlsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ImageEditorControlsProvider call(String sessionKey) =>
      ImageEditorControlsProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'imageEditorControlsProvider';
}

abstract class _$ImageEditorControls
    extends $Notifier<ImageEditorControlsState> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  ImageEditorControlsState build(String sessionKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ImageEditorControlsState, ImageEditorControlsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImageEditorControlsState, ImageEditorControlsState>,
              ImageEditorControlsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
