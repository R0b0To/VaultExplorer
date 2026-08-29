// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_items_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// No internal mutable state -> exposed as a pure keep-alive provider per
/// the migration plan's Phase 3 rule, not a Notifier.

@ProviderFor(vaultItemsService)
final vaultItemsServiceProvider = VaultItemsServiceProvider._();

/// No internal mutable state -> exposed as a pure keep-alive provider per
/// the migration plan's Phase 3 rule, not a Notifier.

final class VaultItemsServiceProvider
    extends
        $FunctionalProvider<
          VaultItemsService,
          VaultItemsService,
          VaultItemsService
        >
    with $Provider<VaultItemsService> {
  /// No internal mutable state -> exposed as a pure keep-alive provider per
  /// the migration plan's Phase 3 rule, not a Notifier.
  VaultItemsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultItemsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultItemsServiceHash();

  @$internal
  @override
  $ProviderElement<VaultItemsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultItemsService create(Ref ref) {
    return vaultItemsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultItemsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultItemsService>(value),
    );
  }
}

String _$vaultItemsServiceHash() => r'fab770d630488c1a885c3c644e8d2bd74975b3af';
