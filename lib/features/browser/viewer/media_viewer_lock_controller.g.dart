// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_viewer_lock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-viewer projection of the application-wide container-lock event.
///
/// Playback controllers, timers, and platform-view gesture state remain owned
/// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
/// is therefore kept in this family provider.

@ProviderFor(MediaViewerLock)
final mediaViewerLockProvider = MediaViewerLockFamily._();

/// Per-viewer projection of the application-wide container-lock event.
///
/// Playback controllers, timers, and platform-view gesture state remain owned
/// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
/// is therefore kept in this family provider.
final class MediaViewerLockProvider
    extends $NotifierProvider<MediaViewerLock, bool> {
  /// Per-viewer projection of the application-wide container-lock event.
  ///
  /// Playback controllers, timers, and platform-view gesture state remain owned
  /// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
  /// is therefore kept in this family provider.
  MediaViewerLockProvider._({
    required MediaViewerLockFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'mediaViewerLockProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaViewerLockHash();

  @override
  String toString() {
    return r'mediaViewerLockProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MediaViewerLock create() => MediaViewerLock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MediaViewerLockProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaViewerLockHash() => r'b357aaa200704fb4ba77148daaa4171bd0c6d751';

/// Per-viewer projection of the application-wide container-lock event.
///
/// Playback controllers, timers, and platform-view gesture state remain owned
/// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
/// is therefore kept in this family provider.

final class MediaViewerLockFamily extends $Family
    with $ClassFamilyOverride<MediaViewerLock, bool, bool, bool, int> {
  MediaViewerLockFamily._()
    : super(
        retry: null,
        name: r'mediaViewerLockProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-viewer projection of the application-wide container-lock event.
  ///
  /// Playback controllers, timers, and platform-view gesture state remain owned
  /// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
  /// is therefore kept in this family provider.

  MediaViewerLockProvider call(int volId) =>
      MediaViewerLockProvider._(argument: volId, from: this);

  @override
  String toString() => r'mediaViewerLockProvider';
}

/// Per-viewer projection of the application-wide container-lock event.
///
/// Playback controllers, timers, and platform-view gesture state remain owned
/// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
/// is therefore kept in this family provider.

abstract class _$MediaViewerLock extends $Notifier<bool> {
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
