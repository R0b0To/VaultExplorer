import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

class _FakeVaultFileIoApi extends VaultFileIoApi {
  _FakeVaultFileIoApi() : super(const MethodChannel('test/container-tools'));

  bool decryptFileSucceeds = true;
  final List<String> deletedPaths = [];

  @override
  Future<bool> decryptFile(
    MountedContainer container,
    String fileName,
    String destPath,
  ) async {
    if (!decryptFileSucceeds) return false;
    await File(destPath).writeAsBytes([1, 2, 3]);
    return true;
  }

  @override
  Future<bool> writeBackFile(
    MountedContainer container,
    String fileName,
    String sourcePath,
  ) async => true;

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    deletedPaths.add(fileName);
    return true;
  }
}

class _FakeVaultLifecycleApi extends VaultLifecycleApi {
  _FakeVaultLifecycleApi()
    : super(const MethodChannel('test/container-tools'), VaultEngineEvents());

  @override
  Future<bool> finishWrite(MountedContainer container, String fileName) async =>
      true;
}

class _TestContainerToolService extends DefaultContainerToolService {
  _TestContainerToolService({
    super.fileIoApi,
    super.lifecycleApi,
  });

  bool throwAuthFail = false;
  Exception? throwGenericError;

  @override
  Future<void> encryptFile({
    required String sourceUri,
    required StandaloneCipher cipher,
    required String passphrase,
    List<String> keyfilePaths = const [],
    bool deleteOriginalAfter = false,
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => _fakeRun(destinationPath, suffix: '.enc');

  @override
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => _fakeRun(destinationPath, suffix: '.dec');

  Future<void> _fakeRun(
    String? destinationPath, {
    required String suffix,
  }) async {
    if (throwAuthFail) throw PlatformException(code: 'AUTH_FAIL');
    if (throwGenericError != null) throw throwGenericError!;
    if (destinationPath != null) {
      await File(
        p.join(destinationPath, 'output$suffix'),
      ).writeAsBytes([9, 9, 9]);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp(
      'container_tool_service_test_',
    );
  });

  tearDown(() async {
    if (await workDir.exists()) await workDir.delete(recursive: true);
  });

  MountedContainer container() => MountedContainer(
    uri: 'file:///test.vault',
    displayName: 'Test Vault',
    volId: 1,
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 100000000,
    freeSpace: 50000000,
  );

  group('DefaultContainerToolService.runBatchFileCrypto', () {
    test(
      'external source to external destination succeeds without touching vault API',
      () async {
        final srcFile = File(p.join(workDir.path, 'plain.txt'))
          ..writeAsBytesSync([1]);
        final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

        final service = _TestContainerToolService();
        final result = await service.runBatchFileCrypto(
          direction: CryptoDirection.encrypt,
          sources: [
            CryptoSourceItem.external(
              displayName: 'plain.txt',
              externalUri: Uri.file(srcFile.path).toString(),
            ),
          ],
          destination: CryptoDestination.external(
            displayName: 'out',
            externalPath: destDir.path,
          ),
          cipher: StandaloneCipher.xChaCha20Poly1305,
          passphrase: 'correct horse battery staple',
          keyfilePaths: const [],
          deleteOriginal: false,
        );

        expect(result.succeeded, equals(1));
        expect(result.failedNames, isEmpty);
        expect(result.aborted, isFalse);
        expect(destDir.listSync().whereType<File>(), isNotEmpty);
      },
    );

    test(
      'a vault source is extracted to a temp dir that is cleaned up afterward',
      () async {
        final fakeFileIo = _FakeVaultFileIoApi();
        final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

        final tempDirsBefore = Directory.systemTemp
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path)
            .toSet();

        final service = _TestContainerToolService(fileIoApi: fakeFileIo);
        final result = await service.runBatchFileCrypto(
          direction: CryptoDirection.encrypt,
          sources: [
            CryptoSourceItem.vault(
              displayName: 'secret.txt',
              container: container(),
              relativePath: 'secret.txt',
            ),
          ],
          destination: CryptoDestination.external(
            displayName: 'out',
            externalPath: destDir.path,
          ),
          cipher: StandaloneCipher.xChaCha20Poly1305,
          passphrase: 'pw',
          keyfilePaths: const [],
          deleteOriginal: false,
        );

        expect(result.succeeded, equals(1));

        final tempDirsAfter = Directory.systemTemp
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path)
            .toSet();
        final leftover = tempDirsAfter
            .difference(tempDirsBefore)
            .where((path) => path.contains('vx_crypto_'));
        expect(leftover, isEmpty);
      },
    );

    test(
      'an external source to a vault destination writes back and cleans up output temp dir',
      () async {
        final fakeFileIo = _FakeVaultFileIoApi();
        final srcFile = File(p.join(workDir.path, 'plain.txt'))
          ..writeAsBytesSync([1]);

        final tempDirsBefore = Directory.systemTemp
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path)
            .toSet();

        final service = _TestContainerToolService(
          fileIoApi: fakeFileIo,
          lifecycleApi: _FakeVaultLifecycleApi(),
        );
        final result = await service.runBatchFileCrypto(
          direction: CryptoDirection.encrypt,
          sources: [
            CryptoSourceItem.external(
              displayName: 'plain.txt',
              externalUri: Uri.file(srcFile.path).toString(),
            ),
          ],
          destination: CryptoDestination.vault(
            displayName: 'Vault',
            container: container(),
            relativePath: '',
          ),
          cipher: StandaloneCipher.xChaCha20Poly1305,
          passphrase: 'pw',
          keyfilePaths: const [],
          deleteOriginal: false,
        );

        expect(result.succeeded, equals(1));

        final tempDirsAfter = Directory.systemTemp
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path)
            .toSet();
        final leftover = tempDirsAfter
            .difference(tempDirsBefore)
            .where((path) => path.contains('vx_crypto_'));
        expect(leftover, isEmpty);
      },
    );

    test(
      'deleteOriginal removes a vault source after a successful encrypt',
      () async {
        final fakeFileIo = _FakeVaultFileIoApi();
        final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

        final service = _TestContainerToolService(fileIoApi: fakeFileIo);
        await service.runBatchFileCrypto(
          direction: CryptoDirection.encrypt,
          sources: [
            CryptoSourceItem.vault(
              displayName: 'secret.txt',
              container: container(),
              relativePath: 'secret.txt',
            ),
          ],
          destination: CryptoDestination.external(
            displayName: 'out',
            externalPath: destDir.path,
          ),
          cipher: StandaloneCipher.xChaCha20Poly1305,
          passphrase: 'pw',
          keyfilePaths: const [],
          deleteOriginal: true,
        );

        expect(fakeFileIo.deletedPaths, equals(['secret.txt']));
      },
    );

    test(
      'an AUTH_FAIL on one file aborts the whole batch without starting the next file',
      () async {
        final startedIndexes = <int>[];
        final srcA = File(p.join(workDir.path, 'a.txt'))..writeAsBytesSync([1]);
        final srcB = File(p.join(workDir.path, 'b.txt'))..writeAsBytesSync([2]);
        final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

        final service = _TestContainerToolService()..throwAuthFail = true;
        final result = await service.runBatchFileCrypto(
          direction: CryptoDirection.encrypt,
          sources: [
            CryptoSourceItem.external(
              displayName: 'a.txt',
              externalUri: Uri.file(srcA.path).toString(),
            ),
            CryptoSourceItem.external(
              displayName: 'b.txt',
              externalUri: Uri.file(srcB.path).toString(),
            ),
          ],
          destination: CryptoDestination.external(
            displayName: 'out',
            externalPath: destDir.path,
          ),
          cipher: StandaloneCipher.xChaCha20Poly1305,
          passphrase: 'wrong password',
          keyfilePaths: const [],
          deleteOriginal: false,
          onFileStart: (index, total) => startedIndexes.add(index),
        );

        expect(result.aborted, isTrue);
        expect(result.abortReason, equals(BatchCryptoAbortReason.authFailure));
        expect(result.succeeded, equals(0));
        expect(startedIndexes, equals([1]));
      },
    );

    test('a per-file error is recorded and later files still run', () async {
      final srcA = File(p.join(workDir.path, 'a.txt'))..writeAsBytesSync([1]);
      final srcB = File(p.join(workDir.path, 'b.txt'))..writeAsBytesSync([2]);
      final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

      var callCount = 0;
      final service = _TestContainerToolService();
      final result = await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.external(
            displayName: 'a.txt',
            externalUri: Uri.file(srcA.path).toString(),
          ),
          CryptoSourceItem.external(
            displayName: 'b.txt',
            externalUri: Uri.file(srcB.path).toString(),
          ),
        ],
        destination: CryptoDestination.external(
          displayName: 'out',
          externalPath: destDir.path,
        ),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'pw',
        keyfilePaths: const [],
        deleteOriginal: false,
        onFileStart: (index, total) {
          callCount++;
          service.throwGenericError = callCount == 1
              ? Exception('disk full')
              : null;
        },
      );

      expect(result.aborted, isFalse);
      expect(result.succeeded, equals(1));
      expect(result.failedNames, equals(['a.txt']));
      expect(result.totalFiles, equals(2));
    });
  });
}
