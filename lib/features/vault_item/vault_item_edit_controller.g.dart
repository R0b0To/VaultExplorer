// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_item_edit_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(VaultItemEdit)
final vaultItemEditProvider = VaultItemEditFamily._();

final class VaultItemEditProvider
    extends $NotifierProvider<VaultItemEdit, VaultItemEditState> {
  VaultItemEditProvider._({
    required VaultItemEditFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'vaultItemEditProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$vaultItemEditHash();

  @override
  String toString() {
    return r'vaultItemEditProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VaultItemEdit create() => VaultItemEdit();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultItemEditState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultItemEditState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VaultItemEditProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$vaultItemEditHash() => r'e2ab6f3b0219310ad7de3f5a5bd0d987c4014bb6';

final class VaultItemEditFamily extends $Family
    with
        $ClassFamilyOverride<
          VaultItemEdit,
          VaultItemEditState,
          VaultItemEditState,
          VaultItemEditState,
          int
        > {
  VaultItemEditFamily._()
    : super(
        retry: null,
        name: r'vaultItemEditProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VaultItemEditProvider call(int volId) =>
      VaultItemEditProvider._(argument: volId, from: this);

  @override
  String toString() => r'vaultItemEditProvider';
}

abstract class _$VaultItemEdit extends $Notifier<VaultItemEditState> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  VaultItemEditState build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VaultItemEditState, VaultItemEditState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VaultItemEditState, VaultItemEditState>,
              VaultItemEditState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
