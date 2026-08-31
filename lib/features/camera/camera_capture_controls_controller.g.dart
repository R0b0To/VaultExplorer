// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'camera_capture_controls_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CameraCaptureControls)
final cameraCaptureControlsProvider = CameraCaptureControlsFamily._();

final class CameraCaptureControlsProvider
    extends
        $NotifierProvider<CameraCaptureControls, CameraCaptureControlsState> {
  CameraCaptureControlsProvider._({
    required CameraCaptureControlsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'cameraCaptureControlsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cameraCaptureControlsHash();

  @override
  String toString() {
    return r'cameraCaptureControlsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CameraCaptureControls create() => CameraCaptureControls();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CameraCaptureControlsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CameraCaptureControlsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CameraCaptureControlsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cameraCaptureControlsHash() =>
    r'5dd7a12c6d5634eaabf5e4fff1179d30a5e88c90';

final class CameraCaptureControlsFamily extends $Family
    with
        $ClassFamilyOverride<
          CameraCaptureControls,
          CameraCaptureControlsState,
          CameraCaptureControlsState,
          CameraCaptureControlsState,
          String
        > {
  CameraCaptureControlsFamily._()
    : super(
        retry: null,
        name: r'cameraCaptureControlsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CameraCaptureControlsProvider call(String sessionKey) =>
      CameraCaptureControlsProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'cameraCaptureControlsProvider';
}

abstract class _$CameraCaptureControls
    extends $Notifier<CameraCaptureControlsState> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  CameraCaptureControlsState build(String sessionKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<CameraCaptureControlsState, CameraCaptureControlsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CameraCaptureControlsState,
                CameraCaptureControlsState
              >,
              CameraCaptureControlsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
