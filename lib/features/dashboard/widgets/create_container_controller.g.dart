// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_container_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CreateContainer)
final createContainerProvider = CreateContainerProvider._();

final class CreateContainerProvider
    extends $NotifierProvider<CreateContainer, CreateContainerState> {
  CreateContainerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'createContainerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$createContainerHash();

  @$internal
  @override
  CreateContainer create() => CreateContainer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CreateContainerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CreateContainerState>(value),
    );
  }
}

String _$createContainerHash() => r'651306561e47b60e9d832f256dcea7062ce4fbd2';

abstract class _$CreateContainer extends $Notifier<CreateContainerState> {
  CreateContainerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CreateContainerState, CreateContainerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CreateContainerState, CreateContainerState>,
              CreateContainerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
