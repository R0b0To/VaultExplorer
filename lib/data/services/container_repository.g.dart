// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'container_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(containerRepository)
final containerRepositoryProvider = ContainerRepositoryProvider._();

final class ContainerRepositoryProvider
    extends
        $FunctionalProvider<
          ContainerRepository,
          ContainerRepository,
          ContainerRepository
        >
    with $Provider<ContainerRepository> {
  ContainerRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'containerRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$containerRepositoryHash();

  @$internal
  @override
  $ProviderElement<ContainerRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ContainerRepository create(Ref ref) {
    return containerRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContainerRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContainerRepository>(value),
    );
  }
}

String _$containerRepositoryHash() =>
    r'138e59bf38c27d5e88cba816a82ef6d13f8c0781';
