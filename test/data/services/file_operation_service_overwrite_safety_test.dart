import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/paste_conflict_detection.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  final l10n = AppLocalizationsEn();

  late Directory tempDir;
  late Directory srcDir;
  late Directory destDir;
  late ProviderContainer providerContainer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ve_overwrite_safety_');
    srcDir = Directory(p.join(tempDir.path, 'source'))..createSync();
    destDir = Directory(p.join(tempDir.path, 'dest'))..createSync();

    providerContainer = ProviderContainer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() async {
    providerContainer.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('FileOperationService overwrite safety on missing source', () {
    test('local transfer does not delete dest file when source file is missing and overwrite is chosen', () async {
      // Setup: dest file exists
      final destFile = File(p.join(destDir.path, 'doc.txt'));
      await destFile.writeAsString('precious destination content');

      // Source file doc.txt does NOT exist in srcDir
      final srcFile = File(p.join(srcDir.path, 'doc.txt'));
      expect(srcFile.existsSync(), isFalse);

      final opSvc = providerContainer.read(fileOperationServiceProvider);

      final srcContainer = buildLocalStorageContainer(
        rootPath: srcDir.path,
        displayName: 'Local Source',
      );
      final destContainer = buildLocalStorageContainer(
        rootPath: destDir.path,
        displayName: 'Local Dest',
      );

      final op = opSvc.enqueueLocalTransfer(
        isCut: true,
        source: srcContainer,
        dest: destContainer,
        destDirPath: '',
        items: const [
          ClipboardItem(path: 'doc.txt', isDir: false),
        ],
        conflictPlan: const {
          'doc.txt': ConflictResolution.overwrite,
        },
        l10n: l10n,
      );

      // Wait for operation to complete
      while (op.status == FileOperationStatus.running ||
          op.status == FileOperationStatus.pending) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // DESTINATION FILE MUST STILL EXIST AND CONTAIN ITS ORIGINAL CONTENT!
      expect(destFile.existsSync(), isTrue,
          reason: 'Destination file must not be prematurely deleted when source does not exist');
      expect(await destFile.readAsString(), 'precious destination content');
      expect(op.itemStatuses.single.result, FileItemResult.failed);
    });

    test('vault transfer does not delete dest file when source is missing and overwrite is chosen', () async {
      final deletedPaths = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getFileSize') {
              // Source file is missing
              return -1;
            }
            if (call.method == 'listDirectory') {
              return ['F|100|0|doc.txt'];
            }
            if (call.method == 'deleteFile') {
              deletedPaths.add((call.arguments as Map)['fileName'] as String);
              return true;
            }
            return null;
          });

      final opSvc = providerContainer.read(fileOperationServiceProvider);

      final srcContainer = MountedContainer(
        volId: 1,
        displayName: 'Vault A',
        uri: 'content://vaultA',
        readOnly: false,
        rootFiles: const [],
        mountedAt: DateTime(2026, 1, 1),
        totalSpace: 100000000,
        freeSpace: 50000000,
      );
      final destContainer = MountedContainer(
        volId: 2,
        displayName: 'Vault B',
        uri: 'content://vaultB',
        readOnly: false,
        rootFiles: const [],
        mountedAt: DateTime(2026, 1, 1),
        totalSpace: 100000000,
        freeSpace: 50000000,
      );

      final op = opSvc.enqueue(
        isCut: true,
        source: srcContainer,
        dest: destContainer,
        destDirPath: '',
        items: const [
          ClipboardItem(path: 'doc.txt', isDir: false),
        ],
        conflictPlan: const {
          'doc.txt': ConflictResolution.overwrite,
        },
        l10n: l10n,
      );

      while (op.status == FileOperationStatus.running ||
          op.status == FileOperationStatus.pending) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // deleteFile must NEVER have been called on destination!
      expect(deletedPaths, isEmpty,
          reason: 'deleteFile must not be called when source does not exist');
      expect(op.itemStatuses.single.result, FileItemResult.failed);
    });
  });
}
