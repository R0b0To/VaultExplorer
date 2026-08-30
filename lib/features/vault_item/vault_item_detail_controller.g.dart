// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_item_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(VaultItemDetail)
final vaultItemDetailProvider = VaultItemDetailFamily._();

final class VaultItemDetailProvider
    extends $NotifierProvider<VaultItemDetail, VaultItemDetailState> {
  VaultItemDetailProvider._({
    required VaultItemDetailFamily super.from,
    required (int, String, VaultItem) super.argument,
  }) : super(
         retry: null,
         name: r'vaultItemDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$vaultItemDetailHash();

  @override
  String toString() {
    return r'vaultItemDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  VaultItemDetail create() => VaultItemDetail();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultItemDetailState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultItemDetailState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VaultItemDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$vaultItemDetailHash() => r'cda84f29d43684ba50481b43b8f8153eb06e1fcc';

final class VaultItemDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          VaultItemDetail,
          VaultItemDetailState,
          VaultItemDetailState,
          VaultItemDetailState,
          (int, String, VaultItem)
        > {
  VaultItemDetailFamily._()
    : super(
        retry: null,
        name: r'vaultItemDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VaultItemDetailProvider call(
    int volId,
    String filePath,
    VaultItem initialItem,
  ) => VaultItemDetailProvider._(
    argument: (volId, filePath, initialItem),
    from: this,
  );

  @override
  String toString() => r'vaultItemDetailProvider';
}

abstract class _$VaultItemDetail extends $Notifier<VaultItemDetailState> {
  late final _$args = ref.$arg as (int, String, VaultItem);
  int get volId => _$args.$1;
  String get filePath => _$args.$2;
  VaultItem get initialItem => _$args.$3;

  VaultItemDetailState build(int volId, String filePath, VaultItem initialItem);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VaultItemDetailState, VaultItemDetailState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VaultItemDetailState, VaultItemDetailState>,
              VaultItemDetailState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
