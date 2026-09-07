// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composite_container_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CompositeContainer)
final compositeContainerProvider = CompositeContainerProvider._();

final class CompositeContainerProvider
    extends $NotifierProvider<CompositeContainer, CompositeContainerState> {
  CompositeContainerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'compositeContainerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$compositeContainerHash();

  @$internal
  @override
  CompositeContainer create() => CompositeContainer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CompositeContainerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CompositeContainerState>(value),
    );
  }
}

String _$compositeContainerHash() =>
    r'9fd15c60a91ca432400bc68e132ea96927239ce9';

abstract class _$CompositeContainer extends $Notifier<CompositeContainerState> {
  CompositeContainerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<CompositeContainerState, CompositeContainerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CompositeContainerState, CompositeContainerState>,
              CompositeContainerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
