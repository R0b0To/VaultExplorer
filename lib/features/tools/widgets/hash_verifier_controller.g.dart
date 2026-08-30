// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hash_verifier_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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

String _$hashVerifierHash() => r'fea9f3751e11f9fc2c86a84944d4dda66e93b236';

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
