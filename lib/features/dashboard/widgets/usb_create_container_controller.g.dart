// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usb_create_container_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UsbCreateContainer)
final usbCreateContainerProvider = UsbCreateContainerProvider._();

final class UsbCreateContainerProvider
    extends $NotifierProvider<UsbCreateContainer, UsbCreateContainerState> {
  UsbCreateContainerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'usbCreateContainerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$usbCreateContainerHash();

  @$internal
  @override
  UsbCreateContainer create() => UsbCreateContainer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsbCreateContainerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsbCreateContainerState>(value),
    );
  }
}

String _$usbCreateContainerHash() =>
    r'3347b620154fc97dce564976344b4ce8cdf9fdd5';

abstract class _$UsbCreateContainer extends $Notifier<UsbCreateContainerState> {
  UsbCreateContainerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<UsbCreateContainerState, UsbCreateContainerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UsbCreateContainerState, UsbCreateContainerState>,
              UsbCreateContainerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
