import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/hash_operation.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/hash_operation_controller.dart';
import 'package:vaultexplorer/features/tools/services/hash_verifier_service.dart';
import 'package:vaultexplorer/features/tools/services/vault_file_scanner.dart';

MountedContainer _testContainer() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

class FakeVaultFileScanner extends VaultFileScanner {
  final List<VaultFile> filesToReturn;
  final bool shouldThrow;

  FakeVaultFileScanner({this.filesToReturn = const [], this.shouldThrow = false})
      : super(VaultFileIoApi(const MethodChannel('test/file-io')));

  @override
  Stream<VaultFile> scan(
    MountedContainer vault, {
    String rootPath = '',
    int maxDepth = 10,
    bool Function()? isCancelled,
    void Function(String dirPath, Object error)? onDirectoryError,
  }) async* {
    if (shouldThrow) {
      throw Exception('Disk read error during scan');
    }
    for (final file in filesToReturn) {
      if (isCancelled?.call() == true) break;
      yield file;
    }
  }
}

class FakeHashVerifierService extends HashVerifierService {
  final Map<String, Map<HashAlgorithm, String>> fileDigests;
  final Set<String> filesThatThrow;

  FakeHashVerifierService({
    this.fileDigests = const {},
    this.filesThatThrow = const {},
  }) : super(
         hashApi: VaultHashApi(const MethodChannel('test/hash')),
         fileIoApi: VaultFileIoApi(const MethodChannel('test/file-io')),
         engineEvents: VaultEngineEvents(),
         scanner: VaultFileScanner(
           VaultFileIoApi(const MethodChannel('test/scanner')),
         ),
       );

  @override
  Future<Map<HashAlgorithm, String>> computeHashes({
    required CryptoSourceItem source,
    required Set<HashAlgorithm> algorithms,
    HashCancellationToken? cancelToken,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw const HashOperationCancelledException();
    }
    final path = source.relativePath ?? source.displayName;
    if (filesThatThrow.contains(path)) {
      throw Exception('Corrupted chunk in $path');
    }

    onProgress?.call(100, 100);

    return fileDigests[path] ??
        {
          HashAlgorithm.sha256: 'fake_sha256_$path',
        };
  }
}

void main() {
  group('HashOperationController Tests', () {
    final vault = _testContainer();
    final file1 = VaultFile(
      container: vault,
      relativePath: 'doc.txt',
      name: 'doc.txt',
      sizeBytes: 100,
      modifiedSecs: 1000,
    );
    final file2 = VaultFile(
      container: vault,
      relativePath: 'image.png',
      name: 'image.png',
      sizeBytes: 200,
      modifiedSecs: 1000,
    );

    test('scanVault completes and moves to confirming phase', () async {
      final scanner = FakeVaultFileScanner(filesToReturn: [file1, file2]);
      final controller = HashOperationController(
        hashService: FakeHashVerifierService(),
        scanner: scanner,
      );
      final session = VaultScanSession();
      final cancelToken = HashCancellationToken();

      final events = await controller
          .scanVault(
            VaultHashOperation(vault),
            cancelToken: cancelToken,
            session: session,
          )
          .toList();

      expect(events.first.phase, HashOperationPhase.scanning);
      expect(events.last.phase, HashOperationPhase.confirming);
      expect(session.files.length, 2);
      expect(session.totalBytes, 300);
      expect(events.last.discoveredFiles, 2);
      expect(events.last.discoveredBytes, 300);
    });

    test('scanVault handles cancellation mid-walk', () async {
      final cancelToken = HashCancellationToken();
      final scanner = FakeVaultFileScanner(filesToReturn: [file1, file2]);
      final controller = HashOperationController(
        hashService: FakeHashVerifierService(),
        scanner: scanner,
      );
      final session = VaultScanSession();

      cancelToken.cancel();
      final events = await controller
          .scanVault(
            VaultHashOperation(vault),
            cancelToken: cancelToken,
            session: session,
          )
          .toList();

      expect(events.last.phase, HashOperationPhase.cancelled);
    });

    test('scanVault handles scan exception with failed phase', () async {
      final scanner = FakeVaultFileScanner(shouldThrow: true);
      final controller = HashOperationController(
        hashService: FakeHashVerifierService(),
        scanner: scanner,
      );
      final session = VaultScanSession();
      final cancelToken = HashCancellationToken();

      final events = await controller
          .scanVault(
            VaultHashOperation(vault),
            cancelToken: cancelToken,
            session: session,
          )
          .toList();

      expect(events.last.phase, HashOperationPhase.failed);
      expect(events.last.failureMessage, contains('Disk read error'));
    });

    test('hashVaultFiles computes digests and returns aggregate result', () async {
      final hashService = FakeHashVerifierService();
      final controller = HashOperationController(
        hashService: hashService,
        scanner: FakeVaultFileScanner(),
      );
      final session = VaultScanSession()
        ..files.addAll([file1, file2])
        ..totalBytes = 300;
      final cancelToken = HashCancellationToken();

      final events = await controller
          .hashVaultFiles(
            session,
            algorithms: {HashAlgorithm.sha256},
            cancelToken: cancelToken,
          )
          .toList();

      expect(events.first.phase, HashOperationPhase.hashing);
      expect(events.last.phase, HashOperationPhase.completed);
      expect(events.last.aggregate, isNotNull);

      final aggregate = events.last.aggregate!;
      expect(aggregate.filesChecked, 2);
      expect(aggregate.filesSucceeded, 2);
      expect(aggregate.filesFailed, 0);
      expect(aggregate.bytesProcessed, 300);
      expect(aggregate.fileResults.length, 2);
    });

    test('hashVaultFiles handles per-file failures without failing overall run', () async {
      final hashService = FakeHashVerifierService(filesThatThrow: {'doc.txt'});
      final controller = HashOperationController(
        hashService: hashService,
        scanner: FakeVaultFileScanner(),
      );
      final session = VaultScanSession()
        ..files.addAll([file1, file2])
        ..totalBytes = 300;
      final cancelToken = HashCancellationToken();

      final events = await controller
          .hashVaultFiles(
            session,
            algorithms: {HashAlgorithm.sha256},
            cancelToken: cancelToken,
          )
          .toList();

      expect(events.last.phase, HashOperationPhase.completed);
      final aggregate = events.last.aggregate!;
      expect(aggregate.filesChecked, 2);
      expect(aggregate.filesSucceeded, 1);
      expect(aggregate.filesFailed, 1);

      final failedResult = aggregate.fileResults.firstWhere((r) => r.source.displayName == 'doc.txt');
      expect(failedResult.hasError, isTrue);
      expect(failedResult.error, contains('Corrupted chunk'));
    });
  });
}
