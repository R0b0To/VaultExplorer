import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

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
  const api = VaultFileIoApi(channel);
  final container = _container();

  final calls = <MethodCall>[];
  Object? nextResult;
  Object? nextError;

  setUp(() {
    calls.clear();
    nextResult = null;
    nextError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (nextError != null) throw nextError!;
      return nextResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('vaultFileIoApiProvider resolves from ProviderContainer', () {
    final containerRef = ProviderContainer();
    addTearDown(containerRef.dispose);

    final resolvedApi = containerRef.read(vaultFileIoApiProvider);
    expect(resolvedApi, isA<VaultFileIoApi>());
  });

  group('pickFilesForImport', () {
    test('sends filePath and targetPath, parses pickToken, conflicts, and items', () async {
      nextResult = <String, dynamic>{
        'pickToken': 7,
        'conflicts': [
          {'name': 'photo.jpg', 'destIsDir': false},
          {'name': 'Notes', 'destIsDir': true},
        ],
        'items': [
          {'name': 'photo.jpg', 'isDir': false, 'sizeBytes': 1024},
          {'name': 'Notes', 'isDir': true, 'sizeBytes': 0},
        ],
      };

      final result = await api.pickFilesForImport(container, 'Docs');

      expect(calls.single.method, 'pickImportFiles');
      expect(calls.single.arguments['filePath'], container.uri);
      expect(calls.single.arguments['targetPath'], 'Docs');
      expect(result, isNotNull);
      expect(result!.pickToken, 7);
      expect(result.conflicts, hasLength(2));
      expect(result.conflicts[0].name, 'photo.jpg');
      expect(result.conflicts[0].destIsDir, isFalse);
      expect(result.conflicts[1].name, 'Notes');
      expect(result.conflicts[1].destIsDir, isTrue);
      expect(result.items, hasLength(2));
      expect(result.items[0].name, 'photo.jpg');
      expect(result.items[0].isDir, isFalse);
      expect(result.items[0].sizeBytes, 1024);
      expect(result.items[1].name, 'Notes');
      expect(result.items[1].isDir, isTrue);
    });

    test('returns null when the user cancels the system picker', () async {
      nextResult = null;
      final result = await api.pickFilesForImport(container, 'Docs');
      expect(result, isNull);
    });

    test('returns null when the result has no pickToken', () async {
      nextResult = <String, dynamic>{'conflicts': <Object?>[]};
      final result = await api.pickFilesForImport(container, 'Docs');
      expect(result, isNull);
    });

    test('treats a missing conflicts key as no conflicts', () async {
      nextResult = <String, dynamic>{'pickToken': 3};
      final result = await api.pickFilesForImport(container, 'Docs');
      expect(result, isNotNull);
      expect(result!.pickToken, 3);
      expect(result.conflicts, isEmpty);
    });

    test('defaults a missing destIsDir to false', () async {
      nextResult = <String, dynamic>{
        'pickToken': 1,
        'conflicts': [
          {'name': 'a.txt'},
        ],
      };
      final result = await api.pickFilesForImport(container, 'Docs');
      expect(result!.conflicts.single.destIsDir, isFalse);
    });
  });

  group('pickFolderForImport', () {
    test('sends the pickImportFolder method with the same argument shape', () async {
      nextResult = <String, dynamic>{'pickToken': 2, 'conflicts': <Object?>[]};

      final result = await api.pickFolderForImport(container, '');

      expect(calls.single.method, 'pickImportFolder');
      expect(calls.single.arguments['filePath'], container.uri);
      expect(calls.single.arguments['targetPath'], '');
      expect(result!.pickToken, 2);
      expect(result.conflicts, isEmpty);
    });
  });

  group('cancelPickedImport', () {
    test('sends the pick token', () async {
      await api.cancelPickedImport(42);
      expect(calls.single.method, 'cancelPickedImport');
      expect(calls.single.arguments['pickToken'], 42);
    });

    test('swallows a platform error instead of throwing', () async {
      nextError = PlatformException(code: 'INVALID_ARGS');
      await expectLater(api.cancelPickedImport(42), completes);
    });
  });

  group('importFiles', () {
    test('sends opId, pickToken and conflictPlan alongside the destination', () async {
      nextResult = 3;

      final result = await api.importFiles(
        container,
        'Docs',
        99,
        7,
        conflictPlan: const {'photo.jpg': 'keepBoth', 'notes': 'skip'},
      );

      expect(calls.single.method, 'importFile');
      expect(calls.single.arguments['filePath'], container.uri);
      expect(calls.single.arguments['targetPath'], 'Docs');
      expect(calls.single.arguments['opId'], 99);
      expect(calls.single.arguments['pickToken'], 7);
      expect(calls.single.arguments['conflictPlan'], {
        'photo.jpg': 'keepBoth',
        'notes': 'skip',
      });
      expect(result, 3);
    });

    test('conflictPlan defaults to empty and result defaults to 0', () async {
      nextResult = null;
      final result = await api.importFiles(container, 'Docs', 1, 7);
      expect(calls.single.arguments['conflictPlan'], <String, String>{});
      expect(result, 0);
    });
  });

  group('importFolder', () {
    test('sends opId, pickToken and conflictPlan alongside the destination', () async {
      nextResult = 12;

      final result = await api.importFolder(
        container,
        '',
        5,
        2,
        conflictPlan: const {'notes': 'overwrite'},
      );

      expect(calls.single.method, 'importFolder');
      expect(calls.single.arguments['opId'], 5);
      expect(calls.single.arguments['pickToken'], 2);
      expect(calls.single.arguments['conflictPlan'], {'notes': 'overwrite'});
      expect(result, 12);
    });
  });

  group('onImportItemFinished callback via VaultEngineEvents', () {
    test('notifies registered listeners with parsed item finish details', () async {
      final events = VaultEngineEvents();
      events.registerHandler(channel);

      ImportItemFinished? received;
      void listener(ImportItemFinished progress) {
        received = progress;
      }

      events.addImportItemFinishedListener(listener);

      final messageCodec = const StandardMethodCodec();
      final data = messageCodec.encodeMethodCall(
        const MethodCall('onImportItemFinished', {
          'opId': 42,
          'sourceName': 'test.png',
          'resolvedName': 'test (1).png',
          'isDir': false,
          'success': true,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.aeidolon.vaultexplorer/engine', data, (b) {});

      expect(received, isNotNull);
      expect(received!.opId, 42);
      expect(received!.sourceName, 'test.png');
      expect(received!.resolvedName, 'test (1).png');
      expect(received!.isDir, isFalse);
      expect(received!.success, isTrue);

      events.removeImportItemFinishedListener(listener);
    });
  });
}