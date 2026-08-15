import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

/// Fakes just the pieces of [VaultExplorerApi] that
/// [DefaultContainerToolService.runBatchFileCrypto] calls when a source or
/// destination is a vault: extracting a plaintext copy to a host temp path
/// ([decryptFile]), writing generated output back in ([writeBackFile],
/// [finishWrite]), and deleting the original after a move-style encrypt
/// ([deleteFile]). Records calls so tests can assert on them without a
/// real mounted container.
class _FakeCryptoVaultApi extends VaultExplorerApi {
  bool decryptFileSucceeds = true;
  final List<String> deletedPaths = [];

  @override
  Future<bool> decryptFile(MountedContainer container, String fileName, String destPath) async {
    if (!decryptFileSucceeds) return false;
    // The real native call places plaintext bytes at destPath; the
    // orchestration code checks File(destPath).existsSync() afterward, so
    // the fake has to actually write something there to be realistic.
    await File(destPath).writeAsBytes([1, 2, 3]);
    return true;
  }

  @override
  Future<bool> writeBackFile(MountedContainer container, String fileName, String sourcePath) async => true;

  @override
  Future<bool> finishWrite(MountedContainer container, String fileName) async => true;

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    deletedPaths.add(fileName);
    return true;
  }
}

/// A [DefaultContainerToolService] whose [encryptFile]/[decryptFile] just
/// drop a small dummy output file into [destinationPath] (or throw, per
/// the flags below) instead of running a real cipher -- this suite tests
/// [runBatchFileCrypto]'s orchestration (temp files, vault I/O, per-file
/// vs. whole-batch failure handling), not the native crypto engine.
class _TestContainerToolService extends DefaultContainerToolService {
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
  }) =>
      _fakeRun(destinationPath, suffix: '.enc');

  @override
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      _fakeRun(destinationPath, suffix: '.dec');

  Future<void> _fakeRun(String? destinationPath, {required String suffix}) async {
    if (throwAuthFail) throw PlatformException(code: 'AUTH_FAIL');
    if (throwGenericError != null) throw throwGenericError!;
    if (destinationPath != null) {
      await File(p.join(destinationPath, 'output$suffix')).writeAsBytes([9, 9, 9]);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('container_tool_service_test_');
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
    test('external source to external destination succeeds without touching the vault API', () async {
      final srcFile = File(p.join(workDir.path, 'plain.txt'))..writeAsBytesSync([1]);
      final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

      final service = _TestContainerToolService();
      final result = await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.external(displayName: 'plain.txt', externalUri: Uri.file(srcFile.path).toString()),
        ],
        destination: CryptoDestination.external(displayName: 'out', externalPath: destDir.path),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'correct horse battery staple',
        keyfilePaths: const [],
        deleteOriginal: false,
      );

      expect(result.succeeded, equals(1));
      expect(result.failedNames, isEmpty);
      expect(result.aborted, isFalse);
      expect(destDir.listSync().whereType<File>(), isNotEmpty);
    });

    test('a vault source is extracted to a temp dir that is gone again afterward', () async {
      vaultExplorerApi = _FakeCryptoVaultApi();
      final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

      final tempDirsBefore = Directory.systemTemp.listSync().whereType<Directory>().map((d) => d.path).toSet();

      final service = _TestContainerToolService();
      final result = await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.vault(displayName: 'secret.txt', container: container(), relativePath: 'secret.txt'),
        ],
        destination: CryptoDestination.external(displayName: 'out', externalPath: destDir.path),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'pw',
        keyfilePaths: const [],
        deleteOriginal: false,
      );

      expect(result.succeeded, equals(1));

      // The vx_crypto_in_* temp dir created to hold the extracted
      // plaintext must not survive past the call -- this is the
      // security-relevant cleanup guarantee documented on
      // runBatchFileCrypto (Category D / SecureTempFile).
      final tempDirsAfter = Directory.systemTemp.listSync().whereType<Directory>().map((d) => d.path).toSet();
      final leftover = tempDirsAfter.difference(tempDirsBefore).where((path) => path.contains('vx_crypto_'));
      expect(leftover, isEmpty);
    });

    test('an external source to a vault destination writes back and cleans up the output temp dir', () async {
      final fakeApi = _FakeCryptoVaultApi();
      vaultExplorerApi = fakeApi;
      final srcFile = File(p.join(workDir.path, 'plain.txt'))..writeAsBytesSync([1]);

      final tempDirsBefore = Directory.systemTemp.listSync().whereType<Directory>().map((d) => d.path).toSet();

      final service = _TestContainerToolService();
      final result = await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.external(displayName: 'plain.txt', externalUri: Uri.file(srcFile.path).toString()),
        ],
        destination: CryptoDestination.vault(displayName: 'Vault', container: container(), relativePath: ''),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'pw',
        keyfilePaths: const [],
        deleteOriginal: false,
      );

      expect(result.succeeded, equals(1));

      final tempDirsAfter = Directory.systemTemp.listSync().whereType<Directory>().map((d) => d.path).toSet();
      final leftover = tempDirsAfter.difference(tempDirsBefore).where((path) => path.contains('vx_crypto_'));
      expect(leftover, isEmpty);
    });

    test('deleteOriginal removes a vault source after a successful encrypt', () async {
      final fakeApi = _FakeCryptoVaultApi();
      vaultExplorerApi = fakeApi;
      final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

      final service = _TestContainerToolService();
      await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.vault(displayName: 'secret.txt', container: container(), relativePath: 'secret.txt'),
        ],
        destination: CryptoDestination.external(displayName: 'out', externalPath: destDir.path),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'pw',
        keyfilePaths: const [],
        deleteOriginal: true,
      );

      expect(fakeApi.deletedPaths, equals(['secret.txt']));
    });

    test('an AUTH_FAIL on one file aborts the whole batch without starting the next file', () async {
      final startedIndexes = <int>[];
      final srcA = File(p.join(workDir.path, 'a.txt'))..writeAsBytesSync([1]);
      final srcB = File(p.join(workDir.path, 'b.txt'))..writeAsBytesSync([2]);
      final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

      final service = _TestContainerToolService()..throwAuthFail = true;
      final result = await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.external(displayName: 'a.txt', externalUri: Uri.file(srcA.path).toString()),
          CryptoSourceItem.external(displayName: 'b.txt', externalUri: Uri.file(srcB.path).toString()),
        ],
        destination: CryptoDestination.external(displayName: 'out', externalPath: destDir.path),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'wrong password',
        keyfilePaths: const [],
        deleteOriginal: false,
        onFileStart: (index, total) => startedIndexes.add(index),
      );

      expect(result.aborted, isTrue);
      expect(result.abortReason, equals(BatchCryptoAbortReason.authFailure));
      expect(result.succeeded, equals(0));
      expect(startedIndexes, equals([1])); // second file never started
    });

    test('a per-file error is recorded and later files still run', () async {
      final srcA = File(p.join(workDir.path, 'a.txt'))..writeAsBytesSync([1]);
      final srcB = File(p.join(workDir.path, 'b.txt'))..writeAsBytesSync([2]);
      final destDir = Directory(p.join(workDir.path, 'out'))..createSync();

      var callCount = 0;
      final service = _TestContainerToolService();
      // Fail only the first file by flipping the error flag once it's used.
      final result = await service.runBatchFileCrypto(
        direction: CryptoDirection.encrypt,
        sources: [
          CryptoSourceItem.external(displayName: 'a.txt', externalUri: Uri.file(srcA.path).toString()),
          CryptoSourceItem.external(displayName: 'b.txt', externalUri: Uri.file(srcB.path).toString()),
        ],
        destination: CryptoDestination.external(displayName: 'out', externalPath: destDir.path),
        cipher: StandaloneCipher.xChaCha20Poly1305,
        passphrase: 'pw',
        keyfilePaths: const [],
        deleteOriginal: false,
        onFileStart: (index, total) {
          callCount++;
          service.throwGenericError = callCount == 1 ? Exception('disk full') : null;
        },
      );

      expect(result.aborted, isFalse);
      expect(result.succeeded, equals(1));
      expect(result.failedNames, equals(['a.txt']));
      expect(result.totalFiles, equals(2));
    });
  });
}
