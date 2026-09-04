// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'secure_screen_policy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(secureScreenPolicy)
final secureScreenPolicyProvider = SecureScreenPolicyProvider._();

final class SecureScreenPolicyProvider
    extends
        $FunctionalProvider<
          SecureScreenPolicy,
          SecureScreenPolicy,
          SecureScreenPolicy
        >
    with $Provider<SecureScreenPolicy> {
  SecureScreenPolicyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secureScreenPolicyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secureScreenPolicyHash();

  @$internal
  @override
  $ProviderElement<SecureScreenPolicy> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SecureScreenPolicy create(Ref ref) {
    return secureScreenPolicy(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SecureScreenPolicy value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SecureScreenPolicy>(value),
    );
  }
}

String _$secureScreenPolicyHash() =>
    r'a17d5affc879ae40a7fdf73cb8e2a8b5948a740e';
