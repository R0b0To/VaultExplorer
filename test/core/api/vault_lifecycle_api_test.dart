import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/camera/active_recording_registry.dart';

MountedContainer _container() => MountedContainer(
  uri: 'content://test-container',
  displayName: 'Test Vault',
  volId: 1,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 100000000,
  freeSpace: 50000000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  final events = VaultEngineEvents();
  final api = VaultLifecycleApi(channel, events);

  final calls = <MethodCall>[];
  Object? nextResult;
  Object? nextError;
  // Only consulted when non-empty; lets a single test stub different
  // return values per channel method (needed for methods like
  // requestAllFilesAccess that make more than one channel call).
  final resultsByMethod = <String, Object?>{};

  setUp(() {
    calls.clear();
    nextResult = null;
    nextError = null;
    resultsByMethod.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (nextError != null) throw nextError!;
          if (resultsByMethod.containsKey(call.method)) {
            return resultsByMethod[call.method];
          }
          return nextResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('vaultLifecycleApiProvider resolves from ProviderContainer', () {
    final containerRef = ProviderContainer();
    addTearDown(containerRef.dispose);

    final resolvedApi = containerRef.read(vaultLifecycleApiProvider);
    expect(resolvedApi, isA<VaultLifecycleApi>());
  });

  group('createContainer', () {
    test('sends every field and returns success', () async {
      nextResult = true;
      final result = await api.createContainer(
        displayName: 'My Vault',
        sizeBytes: 1000000,
        password: 'pw',
        pim: 0,
        fileSystem: 'fat32',
        cipherId: 1,
        hashId: 2,
        keyfilePaths: const ['content://kf1'],
      );
      expect(calls.single.method, 'createContainer');
      expect(calls.single.arguments['displayName'], 'My Vault');
      expect(calls.single.arguments['keyfilePaths'], ['content://kf1']);
      expect(calls.single.arguments['createHiddenVolume'], isFalse);
      expect(result, isTrue);
    });

    test('null result defaults to false', () async {
      nextResult = null;
      final result = await api.createContainer(
        displayName: 'V',
        sizeBytes: 1,
        password: 'pw',
        pim: 0,
        fileSystem: 'fat32',
        cipherId: 1,
        hashId: 2,
        keyfilePaths: const [],
      );
      expect(result, isFalse);
    });

    test('most PlatformExceptions are swallowed to false', () async {
      nextError = PlatformException(code: 'IO_ERROR');
      final result = await api.createContainer(
        displayName: 'V',
        sizeBytes: 1,
        password: 'pw',
        pim: 0,
        fileSystem: 'fat32',
        cipherId: 1,
        hashId: 2,
        keyfilePaths: const [],
      );
      expect(result, isFalse);
    });

    test(
      'INSUFFICIENT_SPACE is the one code that propagates instead of '
      'flattening to false, since its `details` carry the byte counts '
      'the UI needs to build a useful message',
      () async {
        nextError = PlatformException(code: 'INSUFFICIENT_SPACE', details: {
          'neededBytes': 100,
          'availableBytes': 50,
        });
        await expectLater(
          () => api.createContainer(
            displayName: 'V',
            sizeBytes: 1,
            password: 'pw',
            pim: 0,
            fileSystem: 'fat32',
            cipherId: 1,
            hashId: 2,
            keyfilePaths: const [],
          ),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INSUFFICIENT_SPACE')),
        );
      },
    );

    test('hidden-volume fields pass through when createHiddenVolume is true', () async {
      nextResult = true;
      await api.createContainer(
        displayName: 'V',
        sizeBytes: 1,
        password: 'pw',
        pim: 0,
        fileSystem: 'fat32',
        cipherId: 1,
        hashId: 2,
        keyfilePaths: const [],
        createHiddenVolume: true,
        hiddenPassword: 'hiddenpw',
        hiddenFileSystem: 'ntfs',
        hiddenSizeBytes: 500,
      );
      expect(calls.single.arguments['hiddenPassword'], 'hiddenpw');
      expect(calls.single.arguments['hiddenFileSystem'], 'ntfs');
      expect(calls.single.arguments['hiddenSizeBytes'], 500);
    });
  });

  group('getDeviceCapabilityProfile', () {
    test('parses tier/cores/memoryClassMb/isLowRamDevice', () async {
      nextResult = <String, Object?>{
        'tier': 'HIGH',
        'cores': 8,
        'memoryClassMb': 512,
        'isLowRamDevice': false,
      };
      final result = await api.getDeviceCapabilityProfile();
      expect(result.tier, 'HIGH');
      expect(result.cores, 8);
      expect(result.memoryClassMb, 512);
      expect(result.isLowRamDevice, isFalse);
    });

    test(
      'falls back to tier MEDIUM / 4 cores / 128MB on channel failure, '
      'matching resize()\'s own defaults so a caller feeding this straight '
      'into resizeForDevice() gets a consistent answer either way',
      () async {
        nextError = PlatformException(code: 'ERR');
        final result = await api.getDeviceCapabilityProfile();
        expect(result.tier, 'MEDIUM');
        expect(result.cores, 4);
        expect(result.memoryClassMb, 128);
        expect(result.isLowRamDevice, isFalse);
      },
    );
  });

  group('hasAllFilesAccess', () {
    test('returns the native result', () async {
      nextResult = false;
      expect(await api.hasAllFilesAccess(), isFalse);
    });

    test(
      'fails OPEN (true) on channel error -- the opposite of most fail-closed '
      'methods in this file, so a transient channel hiccup does not block '
      'access the user may already have granted',
      () async {
        nextError = PlatformException(code: 'ERR');
        expect(await api.hasAllFilesAccess(), isTrue);
      },
    );
  });

  group('getAndroidSdkInt', () {
    test('returns the native result', () async {
      nextResult = 33;
      expect(await api.getAndroidSdkInt(), 33);
    });

    test('falls back to 34 on channel failure, so version-gated settings default to shown', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.getAndroidSdkInt(), 34);
    });
  });

  group('requestAllFilesAccess', () {
    test('API 30+: invokes the channel and returns whether Settings was opened', () async {
      resultsByMethod['getAndroidSdkInt'] = 30;
      resultsByMethod['requestAllFilesAccess'] = true;
      final result = await api.requestAllFilesAccess();
      expect(result, isTrue);
      expect(calls.last.method, 'requestAllFilesAccess');
      expect(calls.last.arguments['openSettings'], isFalse);
    });

    test('openSettings=true forces the Settings path even below API 30', () async {
      resultsByMethod['getAndroidSdkInt'] = 25;
      resultsByMethod['requestAllFilesAccess'] = true;
      final result = await api.requestAllFilesAccess(openSettings: true);
      expect(result, isTrue);
      expect(calls.last.arguments['openSettings'], isTrue);
    });

    test('below API 26: no-op, returns true without a second channel call', () async {
      resultsByMethod['getAndroidSdkInt'] = 24;
      final result = await api.requestAllFilesAccess();
      expect(result, isTrue);
      expect(calls.where((c) => c.method == 'requestAllFilesAccess'), isEmpty);
    });
  });

  group('requestNotificationPermission', () {
    test('below API 33: no-op, returns true without calling the channel', () async {
      resultsByMethod['getAndroidSdkInt'] = 30;
      final result = await api.requestNotificationPermission();
      expect(result, isTrue);
      expect(calls.where((c) => c.method == 'requestNotificationPermission'), isEmpty);
    });
  });

  group('getUsbDeviceCapacity', () {
    test('sends deviceName, returns the native result', () async {
      nextResult = 999;
      final result = await api.getUsbDeviceCapacity('usb-1');
      expect(calls.single.arguments['deviceName'], 'usb-1');
      expect(result, 999);
    });

    test('returns null on PlatformException rather than throwing', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.getUsbDeviceCapacity('usb-1'), isNull);
    });
  });

  group('changeContainerPassword vs changeLuksContainerPassword', () {
    test('changeContainerPassword swallows failure to false', () async {
      nextError = PlatformException(code: 'AUTH_FAIL');
      final result = await api.changeContainerPassword(
        uri: 'content://c',
        oldPassword: 'old',
        newPassword: 'new',
      );
      expect(result, isFalse);
    });

    test(
      'changeLuksContainerPassword does NOT swallow -- a wrong password must '
      'surface as AUTH_FAIL so the caller can show it, matching the folder-'
      'vault change-password methods\' contract',
      () async {
        nextError = PlatformException(code: 'AUTH_FAIL', message: 'wrong password');
        await expectLater(
          () => api.changeLuksContainerPassword(
            uri: 'content://c',
            oldPassword: 'old',
            newPassword: 'new',
          ),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'AUTH_FAIL')),
        );
      },
    );

    test('changeLuksContainerPassword has no pim/cipherId/hashId args (LUKS has neither concept)', () async {
      nextResult = true;
      await api.changeLuksContainerPassword(uri: 'content://c', oldPassword: 'old', newPassword: 'new');
      expect(calls.single.arguments.containsKey('pim'), isFalse);
      expect(calls.single.arguments.containsKey('cipherId'), isFalse);
    });
  });

  group('unlockContainer', () {
    test('sends core fields and parses the unlock result', () async {
      nextResult = <Object?, Object?>{
        'volId': 3,
        'files': ['a.txt', 'b.txt'],
        'matchedCipherId': 1,
        'matchedHashId': 2,
        'containerFormat': 'veracrypt',
      };
      final result = await api.unlockContainer('content://c', 'pw', 0);
      expect(calls.single.method, 'unlockContainer');
      expect(calls.single.arguments['filePath'], 'content://c');
      expect(calls.single.arguments['password'], 'pw');
      expect(result, isNotNull);
      expect(result!.volId, 3);
      expect(result.files, ['a.txt', 'b.txt']);
    });

    test('returns null when native reports the map as null (unlock did not succeed)', () async {
      nextResult = null;
      final result = await api.unlockContainer('content://c', 'wrong', 0);
      expect(result, isNull);
    });

    test('omits hidden-volume keys entirely when protectHiddenVolume is false', () async {
      nextResult = null;
      await api.unlockContainer('content://c', 'pw', 0);
      expect(calls.single.arguments.containsKey('hiddenVolumePassword'), isFalse);
      expect(calls.single.arguments.containsKey('hiddenVolumeCipherId'), isFalse);
    });

    test('includes hidden-volume keys with defaults when protectHiddenVolume is true', () async {
      nextResult = null;
      await api.unlockContainer('content://c', 'pw', 0, protectHiddenVolume: true);
      expect(calls.single.arguments['hiddenVolumePassword'], '');
      expect(calls.single.arguments['hiddenVolumeCipherId'], 255);
      expect(calls.single.arguments['hiddenVolumeHashId'], 255);
    });

    test('omits keyfilePaths when the list is empty, includes it when non-empty', () async {
      nextResult = null;
      await api.unlockContainer('content://c', 'pw', 0, keyfilePaths: const []);
      expect(calls.single.arguments.containsKey('keyfilePaths'), isFalse);

      calls.clear();
      await api.unlockContainer('content://c', 'pw', 0, keyfilePaths: const ['content://kf']);
      expect(calls.single.arguments['keyfilePaths'], ['content://kf']);
    });

    test('base64-encodes preservedKey when supplied, omits the key otherwise', () async {
      nextResult = null;
      final key = Uint8List.fromList([1, 2, 3, 4]);
      await api.unlockContainer('content://c', 'pw', 0, preservedKey: key);
      expect(calls.single.arguments['preservedKey'], base64Encode(key));

      calls.clear();
      await api.unlockContainer('content://c', 'pw', 0);
      expect(calls.single.arguments.containsKey('preservedKey'), isFalse);
    });

    test('cipherId/hashId default to 255 (auto-detect) when not supplied', () async {
      nextResult = null;
      await api.unlockContainer('content://c', 'pw', 0);
      expect(calls.single.arguments['cipherId'], 255);
      expect(calls.single.arguments['hashId'], 255);
    });
  });

  group('unlockSplitContainer', () {
    test('uses firstPartUri instead of filePath and parses partCount', () async {
      nextResult = <Object?, Object?>{
        'volId': 1,
        'files': <Object?>[],
        'partCount': 3,
      };
      final result = await api.unlockSplitContainer('content://part1', 'pw', 0);
      expect(calls.single.method, 'unlockSplitContainer');
      expect(calls.single.arguments['firstPartUri'], 'content://part1');
      expect(calls.single.arguments.containsKey('filePath'), isFalse);
      expect(result!.partCount, 3);
    });

    test('partCount defaults to 1 when native omits it', () async {
      nextResult = <Object?, Object?>{'volId': 1, 'files': <Object?>[]};
      final result = await api.unlockSplitContainer('content://part1', 'pw', 0);
      expect(result!.partCount, 1);
    });
  });

  group('per-format folder-vault unlock (Cryptomator / gocryptfs / CryFS)', () {
    test('unlockCryptomatorVault sends filePath/password and defaults containerFormat', () async {
      nextResult = <Object?, Object?>{'volId': 1, 'files': <Object?>[]};
      final result = await api.unlockCryptomatorVault('content://v', 'pw');
      expect(calls.single.method, 'unlockCryptomatorVault');
      expect(result!.containerFormat, 'cryptomator');
    });

    test('unlockGocryptfsVault sends filePath/password and defaults containerFormat', () async {
      nextResult = <Object?, Object?>{'volId': 1, 'files': <Object?>[]};
      final result = await api.unlockGocryptfsVault('content://v', 'pw');
      expect(calls.single.method, 'unlockGocryptfsVault');
      expect(result!.containerFormat, 'gocryptfs');
    });

    test('unlockCryfsVault sends filePath/password and defaults containerFormat', () async {
      nextResult = <Object?, Object?>{'volId': 1, 'files': <Object?>[]};
      final result = await api.unlockCryfsVault('content://v', 'pw');
      expect(calls.single.method, 'unlockCryfsVault');
      expect(result!.containerFormat, 'cryfs');
    });

    test('all three return null (not throw) when native returns a null map', () async {
      nextResult = null;
      expect(await api.unlockCryptomatorVault('content://v', 'wrong'), isNull);
      expect(await api.unlockGocryptfsVault('content://v', 'wrong'), isNull);
      expect(await api.unlockCryfsVault('content://v', 'wrong'), isNull);
    });
  });

  group('unlockUsbContainer', () {
    test('sends deviceName and parses the unlock result', () async {
      nextResult = <Object?, Object?>{
        'volId': 5,
        'files': <Object?>['a'],
        'containerFormat': 'veracrypt',
      };
      final result = await api.unlockUsbContainer('usb-1', 'pw', 0);
      expect(calls.single.method, 'unlockUsbContainer');
      expect(calls.single.arguments['deviceName'], 'usb-1');
      expect(result!.volId, 5);
    });

    test('omits hidden-volume keys when protectHiddenVolume is false', () async {
      nextResult = null;
      await api.unlockUsbContainer('usb-1', 'pw', 0);
      expect(calls.single.arguments.containsKey('hiddenVolumePassword'), isFalse);
    });
  });

  group('lockContainer', () {
    test('stops an active recording for this container before locking', () async {
      final registry = ActiveRecordingRegistry();
      final localApi = VaultLifecycleApi(channel, events, registry);
      var stopped = false;
      registry.register('content://c', () async {
        stopped = true;
      });

      nextResult = true;
      final result = await localApi.lockContainer('content://c');

      expect(stopped, isTrue);
      expect(calls.single.method, 'lockContainer');
      expect(result, isTrue);
    });

    test('does nothing extra when no recording is active for this container', () async {
      final registry = ActiveRecordingRegistry();
      final localApi = VaultLifecycleApi(channel, events, registry);

      nextResult = true;
      final result = await localApi.lockContainer('content://other');

      expect(result, isTrue);
    });

    test('null result defaults to false', () async {
      final registry = ActiveRecordingRegistry();
      final localApi = VaultLifecycleApi(channel, events, registry);
      nextResult = null;
      expect(await localApi.lockContainer('content://c'), isFalse);
    });
  });

  group('fail-open helper methods (deliberately favor availability over strictness)', () {
    test('documentExists defaults to true (assume-exists) on channel failure', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.documentExists('content://c'), isTrue);
    });

    test('finishWrite defaults to true on both null result and channel failure', () async {
      final container = _container();
      nextResult = null;
      expect(await api.finishWrite(container, 'file.txt'), isTrue);

      nextError = PlatformException(code: 'ERR');
      expect(await api.finishWrite(container, 'file.txt'), isTrue);
    });

    test('detectsAsPlainDiskImage defaults to false on channel failure', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.detectsAsPlainDiskImage('content://c'), isFalse);
    });

    test('cancelUnlock never throws even when the channel call fails', () async {
      nextError = PlatformException(code: 'ERR');
      await expectLater(api.cancelUnlock(1), completes);
    });
  });

  group('listUsbDevices / requestUsbPermission', () {
    test('listUsbDevices parses deviceName/productName/hasPermission', () async {
      nextResult = <Object?>[
        {'deviceName': 'usb-1', 'productName': 'Flash Drive', 'hasPermission': true},
      ];
      final result = await api.listUsbDevices();
      expect(result.single.deviceName, 'usb-1');
      expect(result.single.hasPermission, isTrue);
    });

    test('listUsbDevices returns empty list when native returns null', () async {
      nextResult = null;
      expect(await api.listUsbDevices(), isEmpty);
    });

    test('requestUsbPermission returns false on PlatformException rather than throwing', () async {
      nextError = PlatformException(code: 'DENIED');
      expect(await api.requestUsbPermission('usb-1'), isFalse);
    });
  });

  group('SAF folder mount/unmount', () {
    test('mountContainerFolder swallows failure to false', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.mountContainerFolder('content://c', '/Docs'), isFalse);
    });

    test('unmountContainerFolder swallows failure to false', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.unmountContainerFolder('content://c', '/Docs'), isFalse);
    });

    test('getMountedContainerFolders swallows failure to an empty list', () async {
      nextError = PlatformException(code: 'ERR');
      expect(await api.getMountedContainerFolders('content://c'), isEmpty);
    });

    test('getMountedContainerFolders parses the native list on success', () async {
      nextResult = <Object?>['Docs', 'Photos'];
      expect(await api.getMountedContainerFolders('content://c'), ['Docs', 'Photos']);
    });
  });

  group('background service sync', () {
    test('syncBackgroundService sends enabled and swallows failure silently', () async {
      nextResult = null;
      await api.syncBackgroundService(enabled: true);
      expect(calls.single.arguments['enabled'], isTrue);

      nextError = PlatformException(code: 'ERR');
      await expectLater(api.syncBackgroundService(enabled: false), completes);
    });

    test('updateBackgroundServiceProgress omits null optional fields', () async {
      nextResult = null;
      await api.updateBackgroundServiceProgress(hasActive: true);
      expect(calls.single.arguments.containsKey('title'), isFalse);
      expect(calls.single.arguments.containsKey('progress'), isFalse);
      expect(calls.single.arguments['max'], 1000);
    });
  });
}
