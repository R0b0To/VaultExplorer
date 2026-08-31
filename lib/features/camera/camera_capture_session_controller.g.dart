// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'camera_capture_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CameraCaptureSession)
final cameraCaptureSessionProvider = CameraCaptureSessionFamily._();

final class CameraCaptureSessionProvider
    extends $NotifierProvider<CameraCaptureSession, CameraCaptureSessionState> {
  CameraCaptureSessionProvider._({
    required CameraCaptureSessionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'cameraCaptureSessionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cameraCaptureSessionHash();

  @override
  String toString() {
    return r'cameraCaptureSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CameraCaptureSession create() => CameraCaptureSession();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CameraCaptureSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CameraCaptureSessionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CameraCaptureSessionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cameraCaptureSessionHash() =>
    r'465de7c6058d9aa3d38e8163ecb8dac804302013';

final class CameraCaptureSessionFamily extends $Family
    with
        $ClassFamilyOverride<
          CameraCaptureSession,
          CameraCaptureSessionState,
          CameraCaptureSessionState,
          CameraCaptureSessionState,
          String
        > {
  CameraCaptureSessionFamily._()
    : super(
        retry: null,
        name: r'cameraCaptureSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CameraCaptureSessionProvider call(String sessionKey) =>
      CameraCaptureSessionProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'cameraCaptureSessionProvider';
}

abstract class _$CameraCaptureSession
    extends $Notifier<CameraCaptureSessionState> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  CameraCaptureSessionState build(String sessionKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<CameraCaptureSessionState, CameraCaptureSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CameraCaptureSessionState, CameraCaptureSessionState>,
              CameraCaptureSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
