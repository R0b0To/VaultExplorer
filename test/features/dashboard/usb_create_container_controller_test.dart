import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('UsbCreateContainerController remember', () {
    // build() kicks off a fire-and-forget loadDevices() microtask that hits
    // the (unmocked, in this lightweight test) platform channel; that call
    // fails and is swallowed into state.error internally, but has no
    // bearing on the synchronous initial state asserted here.
    test('initializes with remember defaulting to true', () {
      final state = container.read(usbCreateContainerProvider);
      // Unlike UnlockState.remember (defaults false for an arbitrary picked
      // file), a freshly created container defaults to being remembered.
      expect(state.remember, isTrue);
    });

    test('setRemember toggles whether the new container is pinned on the dashboard', () {
      final controller = container.read(usbCreateContainerProvider.notifier);

      controller.setRemember(false);
      expect(container.read(usbCreateContainerProvider).remember, isFalse);

      controller.setRemember(true);
      expect(container.read(usbCreateContainerProvider).remember, isTrue);
    });
  });
}
