// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'authenticator_registry_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AuthenticatorRegistry)
final authenticatorRegistryProvider = AuthenticatorRegistryProvider._();

final class AuthenticatorRegistryProvider
    extends
        $NotifierProvider<AuthenticatorRegistry, AuthenticatorRegistryState> {
  AuthenticatorRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authenticatorRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authenticatorRegistryHash();

  @$internal
  @override
  AuthenticatorRegistry create() => AuthenticatorRegistry();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthenticatorRegistryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthenticatorRegistryState>(value),
    );
  }
}

String _$authenticatorRegistryHash() =>
    r'9f3d07793987510fa6abf3f4aeb59c3ed778820a';

abstract class _$AuthenticatorRegistry
    extends $Notifier<AuthenticatorRegistryState> {
  AuthenticatorRegistryState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AuthenticatorRegistryState, AuthenticatorRegistryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AuthenticatorRegistryState,
                AuthenticatorRegistryState
              >,
              AuthenticatorRegistryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
