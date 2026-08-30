// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_info_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(VaultInfo)
final vaultInfoProvider = VaultInfoFamily._();

final class VaultInfoProvider
    extends $NotifierProvider<VaultInfo, VaultInfoState> {
  VaultInfoProvider._({
    required VaultInfoFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'vaultInfoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$vaultInfoHash();

  @override
  String toString() {
    return r'vaultInfoProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VaultInfo create() => VaultInfo();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultInfoState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultInfoState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VaultInfoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$vaultInfoHash() => r'40e6b9eddb64b492c45770aba392f9eeb9820f10';

final class VaultInfoFamily extends $Family
    with
        $ClassFamilyOverride<
          VaultInfo,
          VaultInfoState,
          VaultInfoState,
          VaultInfoState,
          String
        > {
  VaultInfoFamily._()
    : super(
        retry: null,
        name: r'vaultInfoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VaultInfoProvider call(String uri) =>
      VaultInfoProvider._(argument: uri, from: this);

  @override
  String toString() => r'vaultInfoProvider';
}

abstract class _$VaultInfo extends $Notifier<VaultInfoState> {
  late final _$args = ref.$arg as String;
  String get uri => _$args;

  VaultInfoState build(String uri);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VaultInfoState, VaultInfoState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VaultInfoState, VaultInfoState>,
              VaultInfoState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
