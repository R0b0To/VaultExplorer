// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf_viewer_router_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(pdfJetpackSupported)
final pdfJetpackSupportedProvider = PdfJetpackSupportedProvider._();

final class PdfJetpackSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  PdfJetpackSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pdfJetpackSupportedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pdfJetpackSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return pdfJetpackSupported(ref);
  }
}

String _$pdfJetpackSupportedHash() =>
    r'4227f86472986e809f74ffe23d762d76aa7ef8b6';

@ProviderFor(PdfViewerRouterController)
final pdfViewerRouterControllerProvider = PdfViewerRouterControllerFamily._();

final class PdfViewerRouterControllerProvider
    extends $NotifierProvider<PdfViewerRouterController, PdfViewerRouterState> {
  PdfViewerRouterControllerProvider._({
    required PdfViewerRouterControllerFamily super.from,
    required (MountedContainer?, String?, String?) super.argument,
  }) : super(
         retry: null,
         name: r'pdfViewerRouterControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pdfViewerRouterControllerHash();

  @override
  String toString() {
    return r'pdfViewerRouterControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PdfViewerRouterController create() => PdfViewerRouterController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PdfViewerRouterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PdfViewerRouterState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PdfViewerRouterControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pdfViewerRouterControllerHash() =>
    r'637809b00f5c33a2f5d5af2144540b5ef0c950dd';

final class PdfViewerRouterControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PdfViewerRouterController,
          PdfViewerRouterState,
          PdfViewerRouterState,
          PdfViewerRouterState,
          (MountedContainer?, String?, String?)
        > {
  PdfViewerRouterControllerFamily._()
    : super(
        retry: null,
        name: r'pdfViewerRouterControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PdfViewerRouterControllerProvider call(
    MountedContainer? container,
    String? pdfPath,
    String? localUri,
  ) => PdfViewerRouterControllerProvider._(
    argument: (container, pdfPath, localUri),
    from: this,
  );

  @override
  String toString() => r'pdfViewerRouterControllerProvider';
}

abstract class _$PdfViewerRouterController
    extends $Notifier<PdfViewerRouterState> {
  late final _$args = ref.$arg as (MountedContainer?, String?, String?);
  MountedContainer? get container => _$args.$1;
  String? get pdfPath => _$args.$2;
  String? get localUri => _$args.$3;

  PdfViewerRouterState build(
    MountedContainer? container,
    String? pdfPath,
    String? localUri,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PdfViewerRouterState, PdfViewerRouterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PdfViewerRouterState, PdfViewerRouterState>,
              PdfViewerRouterState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
