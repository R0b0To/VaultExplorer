library;

import 'dart:async';

import 'package:vaultexplorer/features/tools/models/hash_operation.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/services/hash_verifier_service.dart';
import 'package:vaultexplorer/features/tools/services/vault_file_scanner.dart';

/// Every file [VaultFileScanner] finds during one "Check entire vault"
/// scan, accumulated as [HashOperationController.scanVault]'s stream
/// progresses. The scanner itself stays list-free (plan §3's "avoid
/// building a giant UI selection model") -- this accumulator lives one
/// layer up, purely because the post-scan confirmation step and the
/// hashing phase that follows it both need the full discovered list.
class VaultScanSession {
  final List<VaultFile> files = [];
  int totalBytes = 0;
}

/// Orchestrates the "Check entire vault" workflow -- scan, then (once the
/// caller's confirmation step accepts) hash -- on top of
/// [VaultFileScanner] and [HashVerifierService]. A [FileHashOperation]
/// doesn't need this: [HashVerifierSheet]'s existing Compute tab already
/// goes straight from manual selection to
/// [HashVerifierService.computeHashes], skipping the scanning/confirming
/// phases entirely (plan §6, §15).
class HashOperationController {
  final HashVerifierService _hashService;
  final VaultFileScanner _scanner;

  HashOperationController({
    required this._hashService,
    required this._scanner,
  });

  /// Recursively scans [operation]'s vault, emitting a
  /// [HashOperationProgress] snapshot as each file is discovered and
  /// accumulating every discovered file into [session] for the caller's
  /// confirmation step (plan §7). The final emitted progress carries
  /// [HashOperationPhase.confirming] (normal completion) or
  /// [HashOperationPhase.cancelled] (if [cancelToken] fired mid-walk).
  Stream<HashOperationProgress> scanVault(
    VaultHashOperation operation, {
    required HashCancellationToken cancelToken,
    required VaultScanSession session,
  }) async* {
    yield const HashOperationProgress(phase: HashOperationPhase.scanning);

    try {
      await for (final file in _scanner.scan(
        operation.vault,
        isCancelled: () => cancelToken.isCancelled,
      )) {
        if (cancelToken.isCancelled) break;
        session.files.add(file);
        session.totalBytes += file.sizeBytes;
        yield HashOperationProgress(
          phase: HashOperationPhase.scanning,
          discoveredFiles: session.files.length,
          discoveredBytes: session.totalBytes,
          currentPath: file.relativePath,
        );
      }
    } catch (e) {
      yield HashOperationProgress(
        phase: HashOperationPhase.failed,
        discoveredFiles: session.files.length,
        discoveredBytes: session.totalBytes,
        failureMessage: e.toString(),
      );
      return;
    }

    yield HashOperationProgress(
      phase: cancelToken.isCancelled ? HashOperationPhase.cancelled : HashOperationPhase.confirming,
      discoveredFiles: session.files.length,
      discoveredBytes: session.totalBytes,
    );
  }

  /// Hashes every file in [session] (as accumulated by [scanVault]),
  /// emitting structured progress -- including live per-file byte progress
  /// -- as the returned stream. One file's hashing failure is recorded in
  /// that file's [HashComputeResult.error] and does not abort the run;
  /// only cancellation, or an operation-level problem, stops it early
  /// (plan §11). The final emitted [HashOperationProgress] carries
  /// [HashOperationPhase.completed] or [HashOperationPhase.cancelled] and
  /// a populated [HashOperationProgress.aggregate] (plan §10).
  Stream<HashOperationProgress> hashVaultFiles(
    VaultScanSession session, {
    required Set<HashAlgorithm> algorithms,
    required HashCancellationToken cancelToken,
  }) {
    final controller = StreamController<HashOperationProgress>();

    Future<void> run() async {
      final results = <HashComputeResult>[];
      final stopwatch = Stopwatch()..start();
      final totalFiles = session.files.length;
      final totalBytes = session.totalBytes;
      var bytesBeforeCurrentFile = 0;
      var failedFiles = 0;

      try {
        controller.add(HashOperationProgress(
          phase: HashOperationPhase.hashing,
          discoveredFiles: totalFiles,
          discoveredBytes: totalBytes,
        ));

        for (final file in session.files) {
          if (cancelToken.isCancelled) break;
          final source = file.toSourceItem();
          final baseProcessed = bytesBeforeCurrentFile;

          try {
            final digests = await _hashService.computeHashes(
              source: source,
              algorithms: algorithms,
              cancelToken: cancelToken,
              onProgress: (done, total) {
                if (controller.isClosed) return;
                controller.add(HashOperationProgress(
                  phase: HashOperationPhase.hashing,
                  discoveredFiles: totalFiles,
                  completedFiles: results.length,
                  failedFiles: failedFiles,
                  discoveredBytes: totalBytes,
                  processedBytes: baseProcessed + done,
                  currentPath: file.relativePath,
                  currentFileBytes: total,
                  currentFileProcessedBytes: done,
                ));
              },
            );
            results.add(HashComputeResult(source: source, digests: digests));
          } on HashOperationCancelledException {
            break;
          } catch (e) {
            failedFiles++;
            results.add(HashComputeResult(source: source, digests: const {}, error: e.toString()));
          }

          bytesBeforeCurrentFile = baseProcessed + file.sizeBytes;
          if (!controller.isClosed) {
            controller.add(HashOperationProgress(
              phase: HashOperationPhase.hashing,
              discoveredFiles: totalFiles,
              completedFiles: results.length,
              failedFiles: failedFiles,
              discoveredBytes: totalBytes,
              processedBytes: bytesBeforeCurrentFile,
              currentPath: file.relativePath,
            ));
          }
        }

        stopwatch.stop();
        final aggregate = HashOperationAggregateResult(
          fileResults: results,
          filesChecked: results.length,
          filesSucceeded: results.length - failedFiles,
          filesFailed: failedFiles,
          bytesProcessed: bytesBeforeCurrentFile,
          elapsed: stopwatch.elapsed,
        );

        if (!controller.isClosed) {
          controller.add(HashOperationProgress(
            phase:
                cancelToken.isCancelled ? HashOperationPhase.cancelled : HashOperationPhase.completed,
            discoveredFiles: totalFiles,
            completedFiles: results.length,
            failedFiles: failedFiles,
            discoveredBytes: totalBytes,
            processedBytes: bytesBeforeCurrentFile,
            aggregate: aggregate,
          ));
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(HashOperationProgress(
            phase: HashOperationPhase.failed,
            discoveredFiles: totalFiles,
            completedFiles: results.length,
            failedFiles: failedFiles,
            failureMessage: e.toString(),
          ));
        }
      } finally {
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }
}
