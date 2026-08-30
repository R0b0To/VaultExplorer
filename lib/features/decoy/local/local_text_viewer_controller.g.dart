// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_text_viewer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LocalTextViewer)
final localTextViewerProvider = LocalTextViewerFamily._();

final class LocalTextViewerProvider
    extends $NotifierProvider<LocalTextViewer, LocalTextViewerState> {
  LocalTextViewerProvider._({
    required LocalTextViewerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'localTextViewerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$localTextViewerHash();

  @override
  String toString() {
    return r'localTextViewerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LocalTextViewer create() => LocalTextViewer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalTextViewerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalTextViewerState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocalTextViewerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$localTextViewerHash() => r'ad7467ce59d8413ba2115a187e6829d8639f736f';

final class LocalTextViewerFamily extends $Family
    with
        $ClassFamilyOverride<
          LocalTextViewer,
          LocalTextViewerState,
          LocalTextViewerState,
          LocalTextViewerState,
          String
        > {
  LocalTextViewerFamily._()
    : super(
        retry: null,
        name: r'localTextViewerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LocalTextViewerProvider call(String filePath) =>
      LocalTextViewerProvider._(argument: filePath, from: this);

  @override
  String toString() => r'localTextViewerProvider';
}

abstract class _$LocalTextViewer extends $Notifier<LocalTextViewerState> {
  late final _$args = ref.$arg as String;
  String get filePath => _$args;

  LocalTextViewerState build(String filePath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LocalTextViewerState, LocalTextViewerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LocalTextViewerState, LocalTextViewerState>,
              LocalTextViewerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
