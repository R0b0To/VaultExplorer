// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'container_repair_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ContainerRepair)
final containerRepairProvider = ContainerRepairProvider._();

final class ContainerRepairProvider
    extends $NotifierProvider<ContainerRepair, ContainerRepairState> {
  ContainerRepairProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'containerRepairProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$containerRepairHash();

  @$internal
  @override
  ContainerRepair create() => ContainerRepair();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContainerRepairState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContainerRepairState>(value),
    );
  }
}

String _$containerRepairHash() => r'0b3ac7b7bb3a45ccee997776045284d4c34aa98a';

abstract class _$ContainerRepair extends $Notifier<ContainerRepairState> {
  ContainerRepairState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ContainerRepairState, ContainerRepairState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ContainerRepairState, ContainerRepairState>,
              ContainerRepairState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
