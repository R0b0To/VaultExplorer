// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'container_config_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ContainerConfigController)
final containerConfigControllerProvider = ContainerConfigControllerFamily._();

final class ContainerConfigControllerProvider
    extends $NotifierProvider<ContainerConfigController, ContainerConfigState> {
  ContainerConfigControllerProvider._({
    required ContainerConfigControllerFamily super.from,
    required ContainerConfigParams super.argument,
  }) : super(
         retry: null,
         name: r'containerConfigControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$containerConfigControllerHash();

  @override
  String toString() {
    return r'containerConfigControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ContainerConfigController create() => ContainerConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContainerConfigState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContainerConfigState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ContainerConfigControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$containerConfigControllerHash() =>
    r'fed09e1812459fcba9ac9fef86fd491381565585';

final class ContainerConfigControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ContainerConfigController,
          ContainerConfigState,
          ContainerConfigState,
          ContainerConfigState,
          ContainerConfigParams
        > {
  ContainerConfigControllerFamily._()
    : super(
        retry: null,
        name: r'containerConfigControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ContainerConfigControllerProvider call(ContainerConfigParams params) =>
      ContainerConfigControllerProvider._(argument: params, from: this);

  @override
  String toString() => r'containerConfigControllerProvider';
}

abstract class _$ContainerConfigController
    extends $Notifier<ContainerConfigState> {
  late final _$args = ref.$arg as ContainerConfigParams;
  ContainerConfigParams get params => _$args;

  ContainerConfigState build(ContainerConfigParams params);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ContainerConfigState, ContainerConfigState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ContainerConfigState, ContainerConfigState>,
              ContainerConfigState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
