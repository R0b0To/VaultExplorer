// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usb_unlock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UsbUnlockController)
final usbUnlockControllerProvider = UsbUnlockControllerFamily._();

final class UsbUnlockControllerProvider
    extends $NotifierProvider<UsbUnlockController, UsbUnlockState> {
  UsbUnlockControllerProvider._({
    required UsbUnlockControllerFamily super.from,
    required UsbUnlockParams super.argument,
  }) : super(
         retry: null,
         name: r'usbUnlockControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usbUnlockControllerHash();

  @override
  String toString() {
    return r'usbUnlockControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  UsbUnlockController create() => UsbUnlockController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsbUnlockState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsbUnlockState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UsbUnlockControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usbUnlockControllerHash() =>
    r'7614dbdb943114a241d360eacdacf9dc0c5df6ee';

final class UsbUnlockControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          UsbUnlockController,
          UsbUnlockState,
          UsbUnlockState,
          UsbUnlockState,
          UsbUnlockParams
        > {
  UsbUnlockControllerFamily._()
    : super(
        retry: null,
        name: r'usbUnlockControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsbUnlockControllerProvider call(UsbUnlockParams params) =>
      UsbUnlockControllerProvider._(argument: params, from: this);

  @override
  String toString() => r'usbUnlockControllerProvider';
}

abstract class _$UsbUnlockController extends $Notifier<UsbUnlockState> {
  late final _$args = ref.$arg as UsbUnlockParams;
  UsbUnlockParams get params => _$args;

  UsbUnlockState build(UsbUnlockParams params);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UsbUnlockState, UsbUnlockState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UsbUnlockState, UsbUnlockState>,
              UsbUnlockState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
