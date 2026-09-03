// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_engine_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single platform channel every VaultXxxApi class talks over --
/// matches the `const _channel = MethodChannel(...)` top-level constant the
/// pre-migration VaultExplorerApi used, but resolvable/overridable through
/// Riverpod instead of being a bare global.

@ProviderFor(vaultEngineChannel)
final vaultEngineChannelProvider = VaultEngineChannelProvider._();

/// The single platform channel every VaultXxxApi class talks over --
/// matches the `const _channel = MethodChannel(...)` top-level constant the
/// pre-migration VaultExplorerApi used, but resolvable/overridable through
/// Riverpod instead of being a bare global.

final class VaultEngineChannelProvider
    extends $FunctionalProvider<MethodChannel, MethodChannel, MethodChannel>
    with $Provider<MethodChannel> {
  /// The single platform channel every VaultXxxApi class talks over --
  /// matches the `const _channel = MethodChannel(...)` top-level constant the
  /// pre-migration VaultExplorerApi used, but resolvable/overridable through
  /// Riverpod instead of being a bare global.
  VaultEngineChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultEngineChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultEngineChannelHash();

  @$internal
  @override
  $ProviderElement<MethodChannel> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MethodChannel create(Ref ref) {
    return vaultEngineChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MethodChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MethodChannel>(value),
    );
  }
}

String _$vaultEngineChannelHash() =>
    r'5239103770ea2a3d4314ad6514b69365042ab20f';

/// Cross-cutting native-event listener registries + the method-call
/// dispatch that used to live as static state directly on VaultExplorerApi.
/// `keepAlive: true` + registering the handler exactly once here reproduces
/// the old "single static handler for the process lifetime" behaviour
/// (previously wired up by `VaultExplorerApi.initMethodCallHandler()` in
/// `main()` -- see lib/main.dart, which should call
/// `ref.read(vaultEngineEventsProvider)` once at startup instead once all
/// consumers have migrated off the old static listener methods).

@ProviderFor(vaultEngineEvents)
final vaultEngineEventsProvider = VaultEngineEventsProvider._();

/// Cross-cutting native-event listener registries + the method-call
/// dispatch that used to live as static state directly on VaultExplorerApi.
/// `keepAlive: true` + registering the handler exactly once here reproduces
/// the old "single static handler for the process lifetime" behaviour
/// (previously wired up by `VaultExplorerApi.initMethodCallHandler()` in
/// `main()` -- see lib/main.dart, which should call
/// `ref.read(vaultEngineEventsProvider)` once at startup instead once all
/// consumers have migrated off the old static listener methods).

final class VaultEngineEventsProvider
    extends
        $FunctionalProvider<
          VaultEngineEvents,
          VaultEngineEvents,
          VaultEngineEvents
        >
    with $Provider<VaultEngineEvents> {
  /// Cross-cutting native-event listener registries + the method-call
  /// dispatch that used to live as static state directly on VaultExplorerApi.
  /// `keepAlive: true` + registering the handler exactly once here reproduces
  /// the old "single static handler for the process lifetime" behaviour
  /// (previously wired up by `VaultExplorerApi.initMethodCallHandler()` in
  /// `main()` -- see lib/main.dart, which should call
  /// `ref.read(vaultEngineEventsProvider)` once at startup instead once all
  /// consumers have migrated off the old static listener methods).
  VaultEngineEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultEngineEventsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultEngineEventsHash();

  @$internal
  @override
  $ProviderElement<VaultEngineEvents> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultEngineEvents create(Ref ref) {
    return vaultEngineEvents(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultEngineEvents value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultEngineEvents>(value),
    );
  }
}

String _$vaultEngineEventsHash() => r'2fb9055779fd8f94c1b53f7869b40bdb03cfc554';

@ProviderFor(vaultCryptoApi)
final vaultCryptoApiProvider = VaultCryptoApiProvider._();

final class VaultCryptoApiProvider
    extends $FunctionalProvider<VaultCryptoApi, VaultCryptoApi, VaultCryptoApi>
    with $Provider<VaultCryptoApi> {
  VaultCryptoApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultCryptoApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultCryptoApiHash();

  @$internal
  @override
  $ProviderElement<VaultCryptoApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultCryptoApi create(Ref ref) {
    return vaultCryptoApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultCryptoApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultCryptoApi>(value),
    );
  }
}

String _$vaultCryptoApiHash() => r'bcac6c31a1408f36b8c683cec9237d44411f79b1';

@ProviderFor(vaultFileIoApi)
final vaultFileIoApiProvider = VaultFileIoApiProvider._();

final class VaultFileIoApiProvider
    extends $FunctionalProvider<VaultFileIoApi, VaultFileIoApi, VaultFileIoApi>
    with $Provider<VaultFileIoApi> {
  VaultFileIoApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultFileIoApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultFileIoApiHash();

  @$internal
  @override
  $ProviderElement<VaultFileIoApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultFileIoApi create(Ref ref) {
    return vaultFileIoApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultFileIoApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultFileIoApi>(value),
    );
  }
}

String _$vaultFileIoApiHash() => r'27320c2e879924ce79b6cf345760222001eef127';

@ProviderFor(vaultHashApi)
final vaultHashApiProvider = VaultHashApiProvider._();

final class VaultHashApiProvider
    extends $FunctionalProvider<VaultHashApi, VaultHashApi, VaultHashApi>
    with $Provider<VaultHashApi> {
  VaultHashApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultHashApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultHashApiHash();

  @$internal
  @override
  $ProviderElement<VaultHashApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultHashApi create(Ref ref) {
    return vaultHashApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultHashApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultHashApi>(value),
    );
  }
}

String _$vaultHashApiHash() => r'4b7d4eb1e20db958e16551acbb9254b5a0df562a';

@ProviderFor(vaultLifecycleApi)
final vaultLifecycleApiProvider = VaultLifecycleApiProvider._();

final class VaultLifecycleApiProvider
    extends
        $FunctionalProvider<
          VaultLifecycleApi,
          VaultLifecycleApi,
          VaultLifecycleApi
        >
    with $Provider<VaultLifecycleApi> {
  VaultLifecycleApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultLifecycleApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultLifecycleApiHash();

  @$internal
  @override
  $ProviderElement<VaultLifecycleApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultLifecycleApi create(Ref ref) {
    return vaultLifecycleApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultLifecycleApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultLifecycleApi>(value),
    );
  }
}

String _$vaultLifecycleApiHash() => r'a3e9982df794c9cb0081a87d11655ae5c66efcdc';

@ProviderFor(vaultPdfApi)
final vaultPdfApiProvider = VaultPdfApiProvider._();

final class VaultPdfApiProvider
    extends $FunctionalProvider<VaultPdfApi, VaultPdfApi, VaultPdfApi>
    with $Provider<VaultPdfApi> {
  VaultPdfApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultPdfApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultPdfApiHash();

  @$internal
  @override
  $ProviderElement<VaultPdfApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultPdfApi create(Ref ref) {
    return vaultPdfApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultPdfApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultPdfApi>(value),
    );
  }
}

String _$vaultPdfApiHash() => r'e39ed6656d23d5614f9e6783b43b1ade087c0d56';

@ProviderFor(vaultRepairApi)
final vaultRepairApiProvider = VaultRepairApiProvider._();

final class VaultRepairApiProvider
    extends $FunctionalProvider<VaultRepairApi, VaultRepairApi, VaultRepairApi>
    with $Provider<VaultRepairApi> {
  VaultRepairApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultRepairApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultRepairApiHash();

  @$internal
  @override
  $ProviderElement<VaultRepairApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultRepairApi create(Ref ref) {
    return vaultRepairApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultRepairApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultRepairApi>(value),
    );
  }
}

String _$vaultRepairApiHash() => r'c61a93bbbba302bad3647fde7435c0aef971db19';

@ProviderFor(vaultSplitJoinApi)
final vaultSplitJoinApiProvider = VaultSplitJoinApiProvider._();

final class VaultSplitJoinApiProvider
    extends
        $FunctionalProvider<
          VaultSplitJoinApi,
          VaultSplitJoinApi,
          VaultSplitJoinApi
        >
    with $Provider<VaultSplitJoinApi> {
  VaultSplitJoinApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultSplitJoinApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultSplitJoinApiHash();

  @$internal
  @override
  $ProviderElement<VaultSplitJoinApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultSplitJoinApi create(Ref ref) {
    return vaultSplitJoinApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultSplitJoinApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultSplitJoinApi>(value),
    );
  }
}

String _$vaultSplitJoinApiHash() => r'f1a960aa71053aba255b8bf3375ef3fe9265b9b1';

@ProviderFor(vaultAutomationApi)
final vaultAutomationApiProvider = VaultAutomationApiProvider._();

final class VaultAutomationApiProvider
    extends
        $FunctionalProvider<
          VaultAutomationApi,
          VaultAutomationApi,
          VaultAutomationApi
        >
    with $Provider<VaultAutomationApi> {
  VaultAutomationApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultAutomationApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultAutomationApiHash();

  @$internal
  @override
  $ProviderElement<VaultAutomationApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultAutomationApi create(Ref ref) {
    return vaultAutomationApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultAutomationApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultAutomationApi>(value),
    );
  }
}

String _$vaultAutomationApiHash() =>
    r'6c1269bda89292bf927cb81b55a2558d3203c1e6';

@ProviderFor(vaultLocalShareApi)
final vaultLocalShareApiProvider = VaultLocalShareApiProvider._();

final class VaultLocalShareApiProvider
    extends
        $FunctionalProvider<
          VaultLocalShareApi,
          VaultLocalShareApi,
          VaultLocalShareApi
        >
    with $Provider<VaultLocalShareApi> {
  VaultLocalShareApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultLocalShareApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultLocalShareApiHash();

  @$internal
  @override
  $ProviderElement<VaultLocalShareApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultLocalShareApi create(Ref ref) {
    return vaultLocalShareApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultLocalShareApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultLocalShareApi>(value),
    );
  }
}

String _$vaultLocalShareApiHash() =>
    r'174a25a8be5dcbd75b771876e7ba8dc4029b4a26';

@ProviderFor(vaultArchiveApi)
final vaultArchiveApiProvider = VaultArchiveApiProvider._();

final class VaultArchiveApiProvider
    extends
        $FunctionalProvider<VaultArchiveApi, VaultArchiveApi, VaultArchiveApi>
    with $Provider<VaultArchiveApi> {
  VaultArchiveApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultArchiveApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultArchiveApiHash();

  @$internal
  @override
  $ProviderElement<VaultArchiveApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultArchiveApi create(Ref ref) {
    return vaultArchiveApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultArchiveApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultArchiveApi>(value),
    );
  }
}

String _$vaultArchiveApiHash() => r'025e1ccc4940bd28fac907c636ce780a3a1e4e5b';
