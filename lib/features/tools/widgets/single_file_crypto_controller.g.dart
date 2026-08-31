// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'single_file_crypto_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SingleFileCrypto)
final singleFileCryptoProvider = SingleFileCryptoFamily._();

final class SingleFileCryptoProvider
    extends $NotifierProvider<SingleFileCrypto, SingleFileCryptoState> {
  SingleFileCryptoProvider._({
    required SingleFileCryptoFamily super.from,
    required (List<CryptoSourceItem>?, CryptoDestination?, CryptoDirection?)
    super.argument,
  }) : super(
         retry: null,
         name: r'singleFileCryptoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$singleFileCryptoHash();

  @override
  String toString() {
    return r'singleFileCryptoProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SingleFileCrypto create() => SingleFileCrypto();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SingleFileCryptoState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SingleFileCryptoState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SingleFileCryptoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$singleFileCryptoHash() => r'90e72902677c98c904b92131c3e6d96be52fbb03';

final class SingleFileCryptoFamily extends $Family
    with
        $ClassFamilyOverride<
          SingleFileCrypto,
          SingleFileCryptoState,
          SingleFileCryptoState,
          SingleFileCryptoState,
          (List<CryptoSourceItem>?, CryptoDestination?, CryptoDirection?)
        > {
  SingleFileCryptoFamily._()
    : super(
        retry: null,
        name: r'singleFileCryptoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SingleFileCryptoProvider call(
    List<CryptoSourceItem>? initialSources,
    CryptoDestination? initialDestination,
    CryptoDirection? initialDirection,
  ) => SingleFileCryptoProvider._(
    argument: (initialSources, initialDestination, initialDirection),
    from: this,
  );

  @override
  String toString() => r'singleFileCryptoProvider';
}

abstract class _$SingleFileCrypto extends $Notifier<SingleFileCryptoState> {
  late final _$args =
      ref.$arg
          as (List<CryptoSourceItem>?, CryptoDestination?, CryptoDirection?);
  List<CryptoSourceItem>? get initialSources => _$args.$1;
  CryptoDestination? get initialDestination => _$args.$2;
  CryptoDirection? get initialDirection => _$args.$3;

  SingleFileCryptoState build(
    List<CryptoSourceItem>? initialSources,
    CryptoDestination? initialDestination,
    CryptoDirection? initialDirection,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SingleFileCryptoState, SingleFileCryptoState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SingleFileCryptoState, SingleFileCryptoState>,
              SingleFileCryptoState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
