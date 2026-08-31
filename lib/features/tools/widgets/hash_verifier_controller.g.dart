// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hash_verifier_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(hashVerifierService)
final hashVerifierServiceProvider = HashVerifierServiceProvider._();

final class HashVerifierServiceProvider
    extends
        $FunctionalProvider<
          HashVerifierService,
          HashVerifierService,
          HashVerifierService
        >
    with $Provider<HashVerifierService> {
  HashVerifierServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hashVerifierServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hashVerifierServiceHash();

  @$internal
  @override
  $ProviderElement<HashVerifierService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  HashVerifierService create(Ref ref) {
    return hashVerifierService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HashVerifierService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HashVerifierService>(value),
    );
  }
}

String _$hashVerifierServiceHash() =>
    r'02cf420544fc3c087718a02ddc2b89c7e9458d6e';

@ProviderFor(HashVerifier)
final hashVerifierProvider = HashVerifierProvider._();

final class HashVerifierProvider
    extends $NotifierProvider<HashVerifier, HashVerifierState> {
  HashVerifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hashVerifierProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hashVerifierHash();

  @$internal
  @override
  HashVerifier create() => HashVerifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HashVerifierState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HashVerifierState>(value),
    );
  }
}

String _$hashVerifierHash() => r'eeb5b8b17cc0f5aaf0ec44a3626291371453b81f';

abstract class _$HashVerifier extends $Notifier<HashVerifierState> {
  HashVerifierState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HashVerifierState, HashVerifierState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HashVerifierState, HashVerifierState>,
              HashVerifierState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
