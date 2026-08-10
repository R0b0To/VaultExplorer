import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Represents a file candidate discovered during a vault scan.
@immutable
class VaultFileItem {
  final MountedContainer container;

  /// Relative path of the file inside the container (e.g. "photos/2024/beach.jpg").
  final String relativePath;

  /// Basename of the file (e.g. "beach.jpg").
  final String name;

  /// Exact byte size.
  final int sizeBytes;

  /// Last modified timestamp in epoch seconds (0 if unknown).
  final int modifiedSecs;

  const VaultFileItem({
    required this.container,
    required this.relativePath,
    required this.name,
    required this.sizeBytes,
    required this.modifiedSecs,
  });

  /// Unique identifier for this file entry across containers.
  String get id => '${container.volId}:$relativePath';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultFileItem &&
          other.container.volId == container.volId &&
          other.relativePath == relativePath;

  @override
  int get hashCode => Object.hash(container.volId, relativePath);

  @override
  String toString() => 'VaultFileItem(${container.displayName}:$relativePath, ${sizeBytes}B)';
}

/// Represents a verified group of 2 or more byte-identical files.
@immutable
class DuplicateGroup {
  final String id;
  final int sizeBytes;
  final String fullHash;
  final List<VaultFileItem> files;

  const DuplicateGroup({
    required this.id,
    required this.sizeBytes,
    required this.fullHash,
    required this.files,
  });

  /// Wasted storage space from redundant copies (excluding 1 original).
  int get totalWasteBytes => files.length > 1 ? sizeBytes * (files.length - 1) : 0;

  DuplicateGroup copyWithFiles(List<VaultFileItem> newFiles) {
    return DuplicateGroup(
      id: id,
      sizeBytes: sizeBytes,
      fullHash: fullHash,
      files: newFiles,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicateGroup && other.id == id && listEquals(other.files, files);

  @override
  int get hashCode => Object.hash(id, fullHash, sizeBytes);
}

/// Stages of the 3-stage duplicate file scanner.
enum DuplicateScanStage {
  idle,

  /// Stage 1: Fast directory walk & size grouping
  indexing,

  /// Stage 2: 16 KB header partial hash comparison
  partialHashing,

  /// Stage 3: Full-file streaming SHA-256 hash comparison
  fullHashing,

  complete,
  cancelled,
}

/// Snapshot of live scanning progress emitted by [DuplicateFinderService].
@immutable
class DuplicateScanProgress {
  final DuplicateScanStage stage;
  final int totalFilesScanned;
  final int candidateGroupCount;
  final int totalCandidatesToHash;
  final int processedCandidates;
  final int duplicateGroupCount;
  final int duplicateFileCount;
  final int potentialSavedBytes;
  final String? currentFileName;
  final String? currentVaultName;

  const DuplicateScanProgress({
    required this.stage,
    this.totalFilesScanned = 0,
    this.candidateGroupCount = 0,
    this.totalCandidatesToHash = 0,
    this.processedCandidates = 0,
    this.duplicateGroupCount = 0,
    this.duplicateFileCount = 0,
    this.potentialSavedBytes = 0,
    this.currentFileName,
    this.currentVaultName,
  });

  double get progressFraction {
    switch (stage) {
      case DuplicateScanStage.idle:
        return 0.0;
      case DuplicateScanStage.indexing:
        return 0.15;
      case DuplicateScanStage.partialHashing:
        if (totalCandidatesToHash == 0) return 0.2;
        return 0.2 + 0.3 * (processedCandidates / totalCandidatesToHash).clamp(0.0, 1.0);
      case DuplicateScanStage.fullHashing:
        if (totalCandidatesToHash == 0) return 0.5;
        return 0.5 + 0.5 * (processedCandidates / totalCandidatesToHash).clamp(0.0, 1.0);
      case DuplicateScanStage.complete:
        return 1.0;
      case DuplicateScanStage.cancelled:
        return 0.0;
    }
  }
}
