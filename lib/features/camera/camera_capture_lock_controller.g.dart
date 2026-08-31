// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'camera_capture_lock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-camera-screen projection of the vault lock event.
///
/// The native camera session and recorder stay widget-owned because their
/// teardown must remain coupled to the platform texture and app lifecycle.

@ProviderFor(CameraCaptureLock)
final cameraCaptureLockProvider = CameraCaptureLockFamily._();

/// Per-camera-screen projection of the vault lock event.
///
/// The native camera session and recorder stay widget-owned because their
/// teardown must remain coupled to the platform texture and app lifecycle.
final class CameraCaptureLockProvider
    extends $NotifierProvider<CameraCaptureLock, bool> {
  /// Per-camera-screen projection of the vault lock event.
  ///
  /// The native camera session and recorder stay widget-owned because their
  /// teardown must remain coupled to the platform texture and app lifecycle.
  CameraCaptureLockProvider._({
    required CameraCaptureLockFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'cameraCaptureLockProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cameraCaptureLockHash();

  @override
  String toString() {
    return r'cameraCaptureLockProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CameraCaptureLock create() => CameraCaptureLock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CameraCaptureLockProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cameraCaptureLockHash() => r'98c156fd9492a8e0eab7222685ee707c8c4e7a06';

/// Per-camera-screen projection of the vault lock event.
///
/// The native camera session and recorder stay widget-owned because their
/// teardown must remain coupled to the platform texture and app lifecycle.

final class CameraCaptureLockFamily extends $Family
    with $ClassFamilyOverride<CameraCaptureLock, bool, bool, bool, int> {
  CameraCaptureLockFamily._()
    : super(
        retry: null,
        name: r'cameraCaptureLockProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-camera-screen projection of the vault lock event.
  ///
  /// The native camera session and recorder stay widget-owned because their
  /// teardown must remain coupled to the platform texture and app lifecycle.

  CameraCaptureLockProvider call(int volId) =>
      CameraCaptureLockProvider._(argument: volId, from: this);

  @override
  String toString() => r'cameraCaptureLockProvider';
}

/// Per-camera-screen projection of the vault lock event.
///
/// The native camera session and recorder stay widget-owned because their
/// teardown must remain coupled to the platform texture and app lifecycle.

abstract class _$CameraCaptureLock extends $Notifier<bool> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  bool build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
