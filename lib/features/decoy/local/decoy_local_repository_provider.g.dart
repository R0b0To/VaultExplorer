// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decoy_local_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(decoyLocalRepository)
final decoyLocalRepositoryProvider = DecoyLocalRepositoryProvider._();

final class DecoyLocalRepositoryProvider
    extends
        $FunctionalProvider<
          DecoyLocalRepository,
          DecoyLocalRepository,
          DecoyLocalRepository
        >
    with $Provider<DecoyLocalRepository> {
  DecoyLocalRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'decoyLocalRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$decoyLocalRepositoryHash();

  @$internal
  @override
  $ProviderElement<DecoyLocalRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DecoyLocalRepository create(Ref ref) {
    return decoyLocalRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DecoyLocalRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DecoyLocalRepository>(value),
    );
  }
}

String _$decoyLocalRepositoryHash() =>
    r'4e51471a6694d2c15ec9bcd2b8729240871ac201';
