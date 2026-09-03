// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_dashboard_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(VaultDashboardController)
final vaultDashboardControllerProvider = VaultDashboardControllerProvider._();

final class VaultDashboardControllerProvider
    extends
        $NotifierProvider<VaultDashboardController, VaultDashboardViewState> {
  VaultDashboardControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultDashboardControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultDashboardControllerHash();

  @$internal
  @override
  VaultDashboardController create() => VaultDashboardController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultDashboardViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultDashboardViewState>(value),
    );
  }
}

String _$vaultDashboardControllerHash() =>
    r'0a25de4d0236d17b7a499dabad7cf048727a00f4';

abstract class _$VaultDashboardController
    extends $Notifier<VaultDashboardViewState> {
  VaultDashboardViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<VaultDashboardViewState, VaultDashboardViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VaultDashboardViewState, VaultDashboardViewState>,
              VaultDashboardViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
