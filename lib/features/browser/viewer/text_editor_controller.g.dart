// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'text_editor_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TextEditorLoad)
final textEditorLoadProvider = TextEditorLoadFamily._();

final class TextEditorLoadProvider
    extends $NotifierProvider<TextEditorLoad, TextEditorLoadState> {
  TextEditorLoadProvider._({
    required TextEditorLoadFamily super.from,
    required (int, String) super.argument,
  }) : super(
         retry: null,
         name: r'textEditorLoadProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$textEditorLoadHash();

  @override
  String toString() {
    return r'textEditorLoadProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  TextEditorLoad create() => TextEditorLoad();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TextEditorLoadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TextEditorLoadState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TextEditorLoadProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$textEditorLoadHash() => r'f1df1c2592ea9be3747f59daf35f38f9924effde';

final class TextEditorLoadFamily extends $Family
    with
        $ClassFamilyOverride<
          TextEditorLoad,
          TextEditorLoadState,
          TextEditorLoadState,
          TextEditorLoadState,
          (int, String)
        > {
  TextEditorLoadFamily._()
    : super(
        retry: null,
        name: r'textEditorLoadProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TextEditorLoadProvider call(int volId, String filePath) =>
      TextEditorLoadProvider._(argument: (volId, filePath), from: this);

  @override
  String toString() => r'textEditorLoadProvider';
}

abstract class _$TextEditorLoad extends $Notifier<TextEditorLoadState> {
  late final _$args = ref.$arg as (int, String);
  int get volId => _$args.$1;
  String get filePath => _$args.$2;

  TextEditorLoadState build(int volId, String filePath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TextEditorLoadState, TextEditorLoadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TextEditorLoadState, TextEditorLoadState>,
              TextEditorLoadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
