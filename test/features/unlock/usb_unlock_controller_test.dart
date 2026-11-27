import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'listUsbDevices':
          return [
            {
              'deviceName': 'sdb1',
              'productName': 'SanDisk Ultra',
              'hasPermission': true,
            }
          ];
        case 'getUsbDeviceCapacity':
          return 16 * 1024 * 1024 * 1024; // 16 GB
        default:
          return null;
      }
    });

    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('UsbUnlockController Tests', () {
    const params = UsbUnlockParams(
      prefillPassword: 'saved-password',
      documentProvider: false,
    );

    test('initializes and selects single connected device automatically', () async {
      final controller = container.read(usbUnlockControllerProvider(params).notifier);
      await controller.loadDevices();

      final state = container.read(usbUnlockControllerProvider(params));
      expect(state.devices, hasLength(1));
      expect(state.selected?.deviceName, 'sdb1');
      expect(state.selected?.productName, 'SanDisk Ultra');
      expect(state.loadingDevices, isFalse);
      // Android's host sends only the three basic keys: the desktop extras take their defaults.
      expect(state.selected?.detail, isNull);
      expect(state.selected?.bus, isEmpty);
      expect(state.selected?.inUse, isFalse);
      expect(state.selected?.isSystem, isFalse);
      expect(state.selected?.formats, isEmpty);
    });

    test('reads the extra fields a desktop drive list carries', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'listUsbDevices') return null;
        return [
          {
            'deviceName': '/dev/disk/by-id/usb-Samsung_T7_0123',
            'productName': 'Samsung PSSD T7',
            'hasPermission': false,
            'detail': '1.0 TB · USB · /dev/disk/by-id/usb-Samsung_T7_0123',
            'bus': 'usb',
            'inUse': true,
            'system': false,
            'formats': ['bitlocker', 'luks'],
          },
          {
            'deviceName': '/dev/nvme0n1',
            'productName': 'WD Black SN850X',
            'hasPermission': true,
            'bus': 'nvme',
            'system': true,
          },
        ];
      });
      final controller = container.read(usbUnlockControllerProvider(params).notifier);
      await controller.loadDevices();

      final devices = container.read(usbUnlockControllerProvider(params)).devices;
      expect(devices, hasLength(2));
      final usb = devices.first;
      expect(usb.deviceName, '/dev/disk/by-id/usb-Samsung_T7_0123');
      expect(usb.hasPermission, isFalse);
      expect(usb.detail, startsWith('1.0 TB'));
      expect(usb.bus, 'usb');
      expect(usb.inUse, isTrue);
      expect(usb.isSystem, isFalse);
      expect(usb.formats, ['bitlocker', 'luks']);
      final nvme = devices.last;
      expect(nvme.isSystem, isTrue);
      expect(nvme.inUse, isFalse); // keys the host leaves out default
      expect(nvme.formats, isEmpty);
      expect(nvme.detail, isNull);
    });

    test('selectDevice updates selection state', () {
      final controller = container.read(usbUnlockControllerProvider(params).notifier);
      final device = const UsbDeviceInfo(
        deviceName: 'sdc1',
        productName: 'Kingston DataTraveler',
        hasPermission: true,
      );

      controller.selectDevice(device);
      expect(container.read(usbUnlockControllerProvider(params)).selected?.deviceName, 'sdc1');
    });

    test('toggles readOnly and remember settings', () {
      final controller = container.read(usbUnlockControllerProvider(params).notifier);

      controller.setReadOnly(true);
      expect(container.read(usbUnlockControllerProvider(params)).readOnly, isTrue);

      controller.setRemember(true);
      expect(container.read(usbUnlockControllerProvider(params)).remember, isTrue);
    });

    test('initializes the session toggle from the persistent vault default', () async {
      const record = ContainerRecord(
        uri: 'usb:sdb1',
        label: 'USB Vault',
        alwaysOpenReadOnly: true,
      );
      final existingParams = UsbUnlockParams(existingRecord: record);
      container.listen(usbUnlockControllerProvider(existingParams), (_, _) {});
      for (var i = 0; i < 100; i++) {
        final state = container.read(usbUnlockControllerProvider(existingParams));
        if (!state.loadingAuth && !state.loadingDevices) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final controller = container.read(usbUnlockControllerProvider(existingParams).notifier);
      expect(container.read(usbUnlockControllerProvider(existingParams)).readOnly, isTrue);

      controller.setReadOnly(false);
      expect(container.read(usbUnlockControllerProvider(existingParams)).readOnly, isFalse);
      expect(record.alwaysOpenReadOnly, isTrue);
    });
  });
}
