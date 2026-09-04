// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'password_hasher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(passwordHasher)
final passwordHasherProvider = PasswordHasherProvider._();

final class PasswordHasherProvider
    extends $FunctionalProvider<PasswordHasher, PasswordHasher, PasswordHasher>
    with $Provider<PasswordHasher> {
  PasswordHasherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'passwordHasherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$passwordHasherHash();

  @$internal
  @override
  $ProviderElement<PasswordHasher> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PasswordHasher create(Ref ref) {
    return passwordHasher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PasswordHasher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PasswordHasher>(value),
    );
  }
}

String _$passwordHasherHash() => r'f703c479d2402ae6707b670b1d950b873090a33d';
