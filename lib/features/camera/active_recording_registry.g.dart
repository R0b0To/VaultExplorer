// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_recording_registry.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(activeRecordingRegistry)
final activeRecordingRegistryProvider = ActiveRecordingRegistryProvider._();

final class ActiveRecordingRegistryProvider
    extends
        $FunctionalProvider<
          ActiveRecordingRegistry,
          ActiveRecordingRegistry,
          ActiveRecordingRegistry
        >
    with $Provider<ActiveRecordingRegistry> {
  ActiveRecordingRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeRecordingRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeRecordingRegistryHash();

  @$internal
  @override
  $ProviderElement<ActiveRecordingRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ActiveRecordingRegistry create(Ref ref) {
    return activeRecordingRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActiveRecordingRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActiveRecordingRegistry>(value),
    );
  }
}

String _$activeRecordingRegistryHash() =>
    r'b215dbf7aa3449c9f8344e4b46c560c2ce1eff65';
