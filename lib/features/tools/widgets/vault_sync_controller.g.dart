// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_sync_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(VaultSync)
final vaultSyncProvider = VaultSyncProvider._();

final class VaultSyncProvider
    extends $NotifierProvider<VaultSync, VaultSyncState> {
  VaultSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultSyncProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultSyncHash();

  @$internal
  @override
  VaultSync create() => VaultSync();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultSyncState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultSyncState>(value),
    );
  }
}

String _$vaultSyncHash() => r'05ddf89cc8c8be02772374ecaa00333a8b313b06';

abstract class _$VaultSync extends $Notifier<VaultSyncState> {
  VaultSyncState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VaultSyncState, VaultSyncState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VaultSyncState, VaultSyncState>,
              VaultSyncState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
