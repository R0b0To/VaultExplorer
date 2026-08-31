// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf_viewer_load_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PdfViewerLoad)
final pdfViewerLoadProvider = PdfViewerLoadFamily._();

final class PdfViewerLoadProvider
    extends $NotifierProvider<PdfViewerLoad, PdfViewerLoadState> {
  PdfViewerLoadProvider._({
    required PdfViewerLoadFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pdfViewerLoadProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pdfViewerLoadHash();

  @override
  String toString() {
    return r'pdfViewerLoadProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PdfViewerLoad create() => PdfViewerLoad();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PdfViewerLoadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PdfViewerLoadState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PdfViewerLoadProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pdfViewerLoadHash() => r'255e67d45d267758ad3f8ba2c26041eb630f02ce';

final class PdfViewerLoadFamily extends $Family
    with
        $ClassFamilyOverride<
          PdfViewerLoad,
          PdfViewerLoadState,
          PdfViewerLoadState,
          PdfViewerLoadState,
          String
        > {
  PdfViewerLoadFamily._()
    : super(
        retry: null,
        name: r'pdfViewerLoadProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PdfViewerLoadProvider call(String identityKey) =>
      PdfViewerLoadProvider._(argument: identityKey, from: this);

  @override
  String toString() => r'pdfViewerLoadProvider';
}

abstract class _$PdfViewerLoad extends $Notifier<PdfViewerLoadState> {
  late final _$args = ref.$arg as String;
  String get identityKey => _$args;

  PdfViewerLoadState build(String identityKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PdfViewerLoadState, PdfViewerLoadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PdfViewerLoadState, PdfViewerLoadState>,
              PdfViewerLoadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
