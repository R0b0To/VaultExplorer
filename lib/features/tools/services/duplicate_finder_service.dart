import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/duplicate_finder_models.dart';

/// Cancellation flag for [DuplicateFinderService]'s scan pipeline. Kept as
/// its own type (see [CancellationToken]'s doc comment) so a token from
/// this tool can't accidentally be handed to a different one.
class DuplicateFinderCancellationToken extends CancellationToken {}

/// Core service implementing the 3-stage vault duplicate file finder pipeline.
class DuplicateFinderService {
  static const int _partialHeaderSize = 16 * 1024; // 16 KB
  static const int _fullHashChunkSize = 256 * 1024; // 256 KB
  static const int _maxDepth = 24;

  int _hashOpIdCounter = 0;
  int _nextHashOpId() => ++_hashOpIdCounter;

  /// Scans [containers] using a 3-stage filtering pipeline:
  /// Stage 1: Fast directory walk & size grouping
  /// Stage 2: Partial 16 KB header SHA-256 hash check
  /// Stage 3: Full-file streaming SHA-256 hash comparison
  ///
  /// Emits updates via the returned Stream.
  Stream<DuplicateScanResult> scanVaults({
    required List<MountedContainer> containers,
    DuplicateFinderCancellationToken? cancelToken,
  }) async* {
    if (containers.isEmpty) {
      yield const DuplicateScanResult(
        progress: DuplicateScanProgress(stage: DuplicateScanStage.complete),
        groups: [],
      );
      return;
    }

    final allFiles = <VaultFileItem>[];
    int totalFilesScanned = 0;

    // ── STAGE 1: Size Grouping (Instant metadata walk) ───────────────────────
    yield DuplicateScanProgress(
      stage: DuplicateScanStage.indexing,
      totalFilesScanned: 0,
      currentVaultName: containers.length == 1 ? containers.first.displayName : 'All Vaults',
    ).toResult([]);

    for (final container in containers) {
      if (cancelToken?.isCancelled ?? false) {
        yield const DuplicateScanProgress(stage: DuplicateScanStage.cancelled).toResult([]);
        return;
      }

      Future<void> walkDir(String dirPath, int depth) async {
        if (depth > _maxDepth || (cancelToken?.isCancelled ?? false)) return;

        List<String>? raw;
        try {
          raw = await vaultExplorerApi.listDirectory(container, dirPath);
        } catch (_) {
          return;
        }
        if (raw == null) return;

        for (final entry in RawEntry.parseAll(raw)) {
          if (cancelToken?.isCancelled ?? false) return;
          final fullPath = dirPath.isEmpty ? entry.name : '$dirPath/${entry.name}';
          if (entry.isDir) {
            await walkDir(fullPath, depth + 1);
          } else {
            totalFilesScanned++;
            allFiles.add(VaultFileItem(
              container: container,
              relativePath: fullPath,
              name: entry.name,
              sizeBytes: entry.sizeBytes,
              modifiedSecs: entry.modifiedSecs,
            ));
          }
        }
      }

      await walkDir('', 0);
    }

    if (cancelToken?.isCancelled ?? false) {
      yield const DuplicateScanProgress(stage: DuplicateScanStage.cancelled).toResult([]);
      return;
    }

    // Group files by size (ignore files <= 0 bytes or unique sizes)
    final sizeGroups = <int, List<VaultFileItem>>{};
    for (final item in allFiles) {
      if (item.sizeBytes <= 0) continue;
      sizeGroups.putIfAbsent(item.sizeBytes, () => []).add(item);
    }
    sizeGroups.removeWhere((_, list) => list.length < 2);

    final stage1Candidates = sizeGroups.values.expand((list) => list).toList();
    if (stage1Candidates.isEmpty) {
      yield DuplicateScanProgress(
        stage: DuplicateScanStage.complete,
        totalFilesScanned: totalFilesScanned,
      ).toResult([]);
      return;
    }

    // ── STAGE 2: Partial Header Hash Check (16 KB Header) ─────────────────────
    final partialCandidateGroups = <String, List<VaultFileItem>>{};
    int stage2Processed = 0;
    final totalStage2Candidates = stage1Candidates.length;

    yield DuplicateScanProgress(
      stage: DuplicateScanStage.partialHashing,
      totalFilesScanned: totalFilesScanned,
      candidateGroupCount: sizeGroups.length,
      totalCandidatesToHash: totalStage2Candidates,
      processedCandidates: 0,
    ).toResult([]);

    for (final item in stage1Candidates) {
      if (cancelToken?.isCancelled ?? false) {
        yield const DuplicateScanProgress(stage: DuplicateScanStage.cancelled).toResult([]);
        return;
      }

      stage2Processed++;
      if (stage2Processed % 5 == 0 || stage2Processed == totalStage2Candidates) {
        yield DuplicateScanProgress(
          stage: DuplicateScanStage.partialHashing,
          totalFilesScanned: totalFilesScanned,
          candidateGroupCount: sizeGroups.length,
          totalCandidatesToHash: totalStage2Candidates,
          processedCandidates: stage2Processed,
          currentFileName: item.name,
          currentVaultName: item.container.displayName,
        ).toResult([]);
      }

      final readLen = item.sizeBytes < _partialHeaderSize ? item.sizeBytes : _partialHeaderSize;
      Uint8List? headerBytes;
      try {
        headerBytes = await vaultExplorerApi.readFileChunk(
          item.container,
          item.relativePath,
          0,
          readLen,
        );
      } catch (_) {
        // headerBytes stays null; the check right below skips this
        // candidate for this scan. Conservative failure direction for a
        // duplicate-finder: missing a real duplicate is fine, falsely
        // flagging one as a duplicate to delete would not be.
      }

      if (headerBytes == null) continue;

      final headerHash = await vaultExplorerApi.hashBytesSha256(headerBytes);
      final groupKey = '${item.sizeBytes}:$headerHash';
      partialCandidateGroups.putIfAbsent(groupKey, () => []).add(item);
    }

    partialCandidateGroups.removeWhere((_, list) => list.length < 2);

    final stage2Candidates = partialCandidateGroups.values.expand((list) => list).toList();
    if (stage2Candidates.isEmpty) {
      yield DuplicateScanProgress(
        stage: DuplicateScanStage.complete,
        totalFilesScanned: totalFilesScanned,
      ).toResult([]);
      return;
    }

    // ── STAGE 3: Full Hash Comparison (Exact Match) ───────────────────────────
    final fullHashGroups = <String, List<VaultFileItem>>{};
    int stage3Processed = 0;
    final totalStage3Candidates = stage2Candidates.length;

    yield DuplicateScanProgress(
      stage: DuplicateScanStage.fullHashing,
      totalFilesScanned: totalFilesScanned,
      candidateGroupCount: partialCandidateGroups.length,
      totalCandidatesToHash: totalStage3Candidates,
      processedCandidates: 0,
    ).toResult([]);

    for (final item in stage2Candidates) {
      if (cancelToken?.isCancelled ?? false) {
        yield const DuplicateScanProgress(stage: DuplicateScanStage.cancelled).toResult([]);
        return;
      }

      stage3Processed++;
      final fullHash = await _computeFullHash(item, cancelToken);

      if (cancelToken?.isCancelled ?? false) {
        yield const DuplicateScanProgress(stage: DuplicateScanStage.cancelled).toResult([]);
        return;
      }

      if (fullHash != null) {
        final groupKey = '${item.sizeBytes}:$fullHash';
        fullHashGroups.putIfAbsent(groupKey, () => []).add(item);
      }

      // Rebuilding + re-sorting the full duplicate-group list is O(n) per
      // call, so doing it on every single hashed candidate makes this loop
      // O(n^2) for large duplicate sets. Throttle it the same way Stage 2
      // throttles its progress emission — the UI still updates smoothly,
      // just not on every single file.
      if (stage3Processed % 5 == 0 || stage3Processed == totalStage3Candidates) {
        final currentVerified = _buildDuplicateGroups(fullHashGroups);
        final totalWaste = currentVerified.fold<int>(0, (sum, g) => sum + g.totalWasteBytes);
        final dupFileCount = currentVerified.fold<int>(0, (sum, g) => sum + g.files.length);

        yield DuplicateScanProgress(
          stage: DuplicateScanStage.fullHashing,
          totalFilesScanned: totalFilesScanned,
          candidateGroupCount: partialCandidateGroups.length,
          totalCandidatesToHash: totalStage3Candidates,
          processedCandidates: stage3Processed,
          duplicateGroupCount: currentVerified.length,
          duplicateFileCount: dupFileCount,
          potentialSavedBytes: totalWaste,
          currentFileName: item.name,
          currentVaultName: item.container.displayName,
        ).toResult(currentVerified);
      }
    }

    final finalVerified = _buildDuplicateGroups(fullHashGroups);
    final totalWaste = finalVerified.fold<int>(0, (sum, g) => sum + g.totalWasteBytes);
    final dupFileCount = finalVerified.fold<int>(0, (sum, g) => sum + g.files.length);

    yield DuplicateScanProgress(
      stage: DuplicateScanStage.complete,
      totalFilesScanned: totalFilesScanned,
      duplicateGroupCount: finalVerified.length,
      duplicateFileCount: dupFileCount,
      potentialSavedBytes: totalWaste,
    ).toResult(finalVerified);
  }

  /// Calculates streaming SHA-256 over entire file in chunks, via the
  /// native hash session (see [VaultExplorerApi.beginHashSession]) rather
  /// than a Dart hashing package.
  Future<String?> _computeFullHash(VaultFileItem item, DuplicateFinderCancellationToken? cancelToken) async {
    final opId = _nextHashOpId();
    try {
      await vaultExplorerApi.beginHashSession(opId, const ['SHA-256']);

      int offset = 0;
      final size = item.sizeBytes;

      while (offset < size) {
        if (cancelToken?.isCancelled ?? false) {
          await vaultExplorerApi.discardHashSession(opId);
          return null;
        }
        final length = (size - offset) < _fullHashChunkSize ? (size - offset) : _fullHashChunkSize;
        final chunk = await vaultExplorerApi.readFileChunk(
          item.container,
          item.relativePath,
          offset,
          length,
        );
        if (chunk == null) {
          await vaultExplorerApi.discardHashSession(opId);
          return null;
        }
        await vaultExplorerApi.updateHashSession(opId, chunk);
        offset += length;
      }

      final result = await vaultExplorerApi.finishHashSession(opId);
      return result['SHA-256'];
    } catch (_) {
      await vaultExplorerApi.discardHashSession(opId);
      return null;
    }
  }

  List<DuplicateGroup> _buildDuplicateGroups(Map<String, List<VaultFileItem>> map) {
    final result = <DuplicateGroup>[];
    int groupIdCounter = 1;

    for (final entry in map.entries) {
      if (entry.value.length < 2) continue;
      final parts = entry.key.split(':');
      final sizeBytes = int.tryParse(parts[0]) ?? 0;
      final fullHash = parts.length > 1 ? parts[1] : '';

      result.add(DuplicateGroup(
        id: 'group_$groupIdCounter',
        sizeBytes: sizeBytes,
        fullHash: fullHash,
        files: List.unmodifiable(entry.value),
      ));
      groupIdCounter++;
    }

    // Sort groups descending by space savings (size * (length - 1))
    result.sort((a, b) => b.totalWasteBytes.compareTo(a.totalWasteBytes));
    return result;
  }

  /// Deletes selected files from their respective containers.
  Future<int> deleteFiles(List<VaultFileItem> itemsToDelete) async {
    int deletedCount = 0;
    for (final item in itemsToDelete) {
      try {
        final success = await vaultExplorerApi.deleteFile(item.container, item.relativePath);
        if (success) {
          deletedCount++;
        }
      } catch (_) {
        // Continue the batch rather than aborting on one failure;
        // deletedCount only counts confirmed successes, so the count
        // returned to the caller never overstates what was actually
        // deleted.
      }
    }
    return deletedCount;
  }
}

@immutable
class DuplicateScanResult {
  final DuplicateScanProgress progress;
  final List<DuplicateGroup> groups;

  const DuplicateScanResult({
    required this.progress,
    required this.groups,
  });
}

extension _ProgressToResult on DuplicateScanProgress {
  DuplicateScanResult toResult(List<DuplicateGroup> groups) =>
      DuplicateScanResult(progress: this, groups: groups);
}