// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'real_password_gate_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RealPasswordGate)
final realPasswordGateProvider = RealPasswordGateFamily._();

final class RealPasswordGateProvider
    extends $NotifierProvider<RealPasswordGate, RealPasswordGateState> {
  RealPasswordGateProvider._({
    required RealPasswordGateFamily super.from,
    required List<Map<String, String>> super.argument,
  }) : super(
         retry: null,
         name: r'realPasswordGateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$realPasswordGateHash();

  @override
  String toString() {
    return r'realPasswordGateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RealPasswordGate create() => RealPasswordGate();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RealPasswordGateState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RealPasswordGateState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RealPasswordGateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$realPasswordGateHash() => r'9d2d92806f8069d4e690c0b3a9e60d71177af8e8';

final class RealPasswordGateFamily extends $Family
    with
        $ClassFamilyOverride<
          RealPasswordGate,
          RealPasswordGateState,
          RealPasswordGateState,
          RealPasswordGateState,
          List<Map<String, String>>
        > {
  RealPasswordGateFamily._()
    : super(
        retry: null,
        name: r'realPasswordGateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RealPasswordGateProvider call(List<Map<String, String>> initialKeyfiles) =>
      RealPasswordGateProvider._(argument: initialKeyfiles, from: this);

  @override
  String toString() => r'realPasswordGateProvider';
}

abstract class _$RealPasswordGate extends $Notifier<RealPasswordGateState> {
  late final _$args = ref.$arg as List<Map<String, String>>;
  List<Map<String, String>> get initialKeyfiles => _$args;

  RealPasswordGateState build(List<Map<String, String>> initialKeyfiles);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RealPasswordGateState, RealPasswordGateState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RealPasswordGateState, RealPasswordGateState>,
              RealPasswordGateState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
