// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pattern_pin_verify_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PatternVerify)
final patternVerifyProvider = PatternVerifyFamily._();

final class PatternVerifyProvider
    extends $NotifierProvider<PatternVerify, VerifyState> {
  PatternVerifyProvider._({
    required PatternVerifyFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'patternVerifyProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$patternVerifyHash();

  @override
  String toString() {
    return r'patternVerifyProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PatternVerify create() => PatternVerify();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VerifyState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VerifyState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PatternVerifyProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$patternVerifyHash() => r'd62f0c49235ae3793016d7388d8bbf21abb3c303';

final class PatternVerifyFamily extends $Family
    with
        $ClassFamilyOverride<
          PatternVerify,
          VerifyState,
          VerifyState,
          VerifyState,
          String
        > {
  PatternVerifyFamily._()
    : super(
        retry: null,
        name: r'patternVerifyProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PatternVerifyProvider call(String storedHash) =>
      PatternVerifyProvider._(argument: storedHash, from: this);

  @override
  String toString() => r'patternVerifyProvider';
}

abstract class _$PatternVerify extends $Notifier<VerifyState> {
  late final _$args = ref.$arg as String;
  String get storedHash => _$args;

  VerifyState build(String storedHash);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VerifyState, VerifyState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VerifyState, VerifyState>,
              VerifyState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(PinVerify)
final pinVerifyProvider = PinVerifyFamily._();

final class PinVerifyProvider
    extends $NotifierProvider<PinVerify, VerifyState> {
  PinVerifyProvider._({
    required PinVerifyFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pinVerifyProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pinVerifyHash();

  @override
  String toString() {
    return r'pinVerifyProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PinVerify create() => PinVerify();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VerifyState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VerifyState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PinVerifyProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pinVerifyHash() => r'bc4813862d16ff6599113fcb887346b8de569c17';

final class PinVerifyFamily extends $Family
    with
        $ClassFamilyOverride<
          PinVerify,
          VerifyState,
          VerifyState,
          VerifyState,
          String
        > {
  PinVerifyFamily._()
    : super(
        retry: null,
        name: r'pinVerifyProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PinVerifyProvider call(String storedHash) =>
      PinVerifyProvider._(argument: storedHash, from: this);

  @override
  String toString() => r'pinVerifyProvider';
}

abstract class _$PinVerify extends $Notifier<VerifyState> {
  late final _$args = ref.$arg as String;
  String get storedHash => _$args;

  VerifyState build(String storedHash);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VerifyState, VerifyState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VerifyState, VerifyState>,
              VerifyState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
