// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_browser_sheet_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(VaultBrowserController)
final vaultBrowserControllerProvider = VaultBrowserControllerFamily._();

final class VaultBrowserControllerProvider
    extends $NotifierProvider<VaultBrowserController, VaultBrowserState> {
  VaultBrowserControllerProvider._({
    required VaultBrowserControllerFamily super.from,
    required VaultBrowserParams super.argument,
  }) : super(
         retry: null,
         name: r'vaultBrowserControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$vaultBrowserControllerHash();

  @override
  String toString() {
    return r'vaultBrowserControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VaultBrowserController create() => VaultBrowserController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultBrowserState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultBrowserState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VaultBrowserControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$vaultBrowserControllerHash() =>
    r'4a8ec9eaba8a36caa6ccdb5991895b49820aed7c';

final class VaultBrowserControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          VaultBrowserController,
          VaultBrowserState,
          VaultBrowserState,
          VaultBrowserState,
          VaultBrowserParams
        > {
  VaultBrowserControllerFamily._()
    : super(
        retry: null,
        name: r'vaultBrowserControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VaultBrowserControllerProvider call(VaultBrowserParams params) =>
      VaultBrowserControllerProvider._(argument: params, from: this);

  @override
  String toString() => r'vaultBrowserControllerProvider';
}

abstract class _$VaultBrowserController extends $Notifier<VaultBrowserState> {
  late final _$args = ref.$arg as VaultBrowserParams;
  VaultBrowserParams get params => _$args;

  VaultBrowserState build(VaultBrowserParams params);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VaultBrowserState, VaultBrowserState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VaultBrowserState, VaultBrowserState>,
              VaultBrowserState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
