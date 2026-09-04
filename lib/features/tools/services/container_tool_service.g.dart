// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'container_tool_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(containerToolService)
final containerToolServiceProvider = ContainerToolServiceProvider._();

final class ContainerToolServiceProvider
    extends
        $FunctionalProvider<
          ContainerToolService,
          ContainerToolService,
          ContainerToolService
        >
    with $Provider<ContainerToolService> {
  ContainerToolServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'containerToolServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$containerToolServiceHash();

  @$internal
  @override
  $ProviderElement<ContainerToolService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ContainerToolService create(Ref ref) {
    return containerToolService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContainerToolService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContainerToolService>(value),
    );
  }
}

String _$containerToolServiceHash() =>
    r'4bb4f9f464d59b7cac0835ca3979ad8adb59d425';
