// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migrate_cryptomator_vault_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MigrateCryptomatorVault)
final migrateCryptomatorVaultProvider = MigrateCryptomatorVaultFamily._();

final class MigrateCryptomatorVaultProvider
    extends
        $NotifierProvider<
          MigrateCryptomatorVault,
          MigrateCryptomatorVaultState
        > {
  MigrateCryptomatorVaultProvider._({
    required MigrateCryptomatorVaultFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'migrateCryptomatorVaultProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$migrateCryptomatorVaultHash();

  @override
  String toString() {
    return r'migrateCryptomatorVaultProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MigrateCryptomatorVault create() => MigrateCryptomatorVault();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MigrateCryptomatorVaultState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MigrateCryptomatorVaultState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MigrateCryptomatorVaultProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$migrateCryptomatorVaultHash() =>
    r'a140300f96654009a00415fcd7e035799a372cb1';

final class MigrateCryptomatorVaultFamily extends $Family
    with
        $ClassFamilyOverride<
          MigrateCryptomatorVault,
          MigrateCryptomatorVaultState,
          MigrateCryptomatorVaultState,
          MigrateCryptomatorVaultState,
          String
        > {
  MigrateCryptomatorVaultFamily._()
    : super(
        retry: null,
        name: r'migrateCryptomatorVaultProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MigrateCryptomatorVaultProvider call(String uri) =>
      MigrateCryptomatorVaultProvider._(argument: uri, from: this);

  @override
  String toString() => r'migrateCryptomatorVaultProvider';
}

abstract class _$MigrateCryptomatorVault
    extends $Notifier<MigrateCryptomatorVaultState> {
  late final _$args = ref.$arg as String;
  String get uri => _$args;

  MigrateCryptomatorVaultState build(String uri);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<MigrateCryptomatorVaultState, MigrateCryptomatorVaultState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                MigrateCryptomatorVaultState,
                MigrateCryptomatorVaultState
              >,
              MigrateCryptomatorVaultState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
