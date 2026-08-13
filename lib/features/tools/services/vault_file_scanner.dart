library;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// One file discovered by [VaultFileScanner.scan]. Carries a
/// vault-relative, forward-slash-separated path (never an absolute one),
/// same as the manual vault file picker produces.
@immutable
class VaultFile {
  final MountedContainer container;

  /// Path relative to the vault root (e.g. "Photos/2026/trip.jpg"). Never
  /// starts with a leading slash.
  final String relativePath;

  /// Basename (e.g. "trip.jpg").
  final String name;

  final int sizeBytes;

  /// Last-modified time in Unix seconds (UTC). 0 = unknown.
  final int modifiedSecs;

  const VaultFile({
    required this.container,
    required this.relativePath,
    required this.name,
    required this.sizeBytes,
    required this.modifiedSecs,
  });

  /// This file as a [CryptoSourceItem], the shape every other checksum
  /// code path (manual selection, hashing, results) already works in --
  /// see [CryptoSourceItem.vault].
  CryptoSourceItem toSourceItem() => CryptoSourceItem.vault(
        displayName: name,
        container: container,
        relativePath: relativePath,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultFile &&
          other.container.volId == container.volId &&
          other.relativePath == relativePath;

  @override
  int get hashCode => Object.hash(container.volId, relativePath);

  @override
  String toString() => 'VaultFile(${container.displayName}:$relativePath, ${sizeBytes}B)';
}

/// Default recursion limit, matching [DuplicateFinderService]'s
/// `_maxDepth` -- deep enough for any real vault layout while still
/// bounding a pathological/cyclical listing.
const int kVaultScanDefaultMaxDepth = 24;

/// Reusable recursive vault traversal, owned once here instead of
/// duplicated per-feature. Answers only "what files exist in this vault?"
/// -- hashing them is a separate concern handled elsewhere (plan §3-4).
///
/// Backs the "Check entire vault" checksum workflow
/// ([HashOperationController.scanVault]) and
/// [HashVerifierService.collectVaultManifestSiblings]; also reusable for
/// future vault-wide features (verify-against-manifest, manifest
/// generation, duplicate detection, vault statistics, integrity audits).
class VaultFileScanner {
  /// Recursively walks [vault] starting at [rootPath] (vault-relative;
  /// empty string = vault root), yielding each file as it's discovered.
  /// Directories are recursed into but never yielded themselves.
  ///
  /// This is deliberately stream-oriented rather than
  /// `Future<List<VaultFile>>` so a caller can render live discovery
  /// progress and so a huge vault never forces holding every entry in
  /// memory at once inside the scanner itself (plan §5) -- callers that
  /// need the full list for a confirmation step accumulate it themselves,
  /// e.g. [HashOperationController]'s `VaultScanSession`.
  ///
  /// [isCancelled] is polled between directory listings and between
  /// yielded entries; once it returns true the stream ends (without
  /// throwing) as soon as that's noticed. Passing the same predicate used
  /// elsewhere in an operation (e.g. backed by a shared
  /// `HashCancellationToken`) lets scanning and a later hashing phase
  /// share one cancellation signal (plan §12).
  ///
  /// [onDirectoryError] is called (and that subtree skipped) whenever
  /// listing one directory fails -- a vault becoming unavailable mid-walk
  /// shouldn't abort discovery of everything already reachable. When
  /// omitted, directory errors are silently skipped, matching every
  /// existing recursive-walk call site in this codebase.
  Stream<VaultFile> scan(
    MountedContainer vault, {
    String rootPath = '',
    int maxDepth = kVaultScanDefaultMaxDepth,
    bool Function()? isCancelled,
    void Function(String dirPath, Object error)? onDirectoryError,
  }) =>
      _walk(vault, rootPath, 0, maxDepth, isCancelled, onDirectoryError);

  Stream<VaultFile> _walk(
    MountedContainer vault,
    String dirPath,
    int depth,
    int maxDepth,
    bool Function()? isCancelled,
    void Function(String dirPath, Object error)? onDirectoryError,
  ) async* {
    if (depth > maxDepth) return;
    if (isCancelled?.call() ?? false) return;

    List<String>? raw;
    try {
      raw = await vaultExplorerApi.listDirectory(vault, dirPath);
    } catch (e) {
      onDirectoryError?.call(dirPath, e);
      return;
    }
    if (raw == null) return;

    List<RawEntry> entries;
    try {
      entries = RawEntry.parseAll(raw);
    } catch (e) {
      onDirectoryError?.call(dirPath, e);
      return;
    }

    for (final entry in entries) {
      if (isCancelled?.call() ?? false) return;
      final fullPath = dirPath.isEmpty ? entry.name : '$dirPath/${entry.name}';
      if (entry.isDir) {
        yield* _walk(vault, fullPath, depth + 1, maxDepth, isCancelled, onDirectoryError);
      } else {
        yield VaultFile(
          container: vault,
          relativePath: fullPath,
          name: entry.name,
          sizeBytes: entry.sizeBytes,
          modifiedSecs: entry.modifiedSecs,
        );
      }
    }
  }
}