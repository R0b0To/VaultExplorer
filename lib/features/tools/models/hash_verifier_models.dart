library;

import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// Hash algorithms the File Checksum & Hash Verifier tool supports.
///
/// Deliberately just the four algorithms real-world checksum manifests
/// actually use (`.md5`/`.sha1`/`.sha256sum`/`.sha512sum`, and the BSD
/// `TAG (name) = hex` form). All four are computed the same way on both
/// sides of the platform channel with zero new native crypto surface:
/// `java.security.MessageDigest` for both vault-resident files (via the
/// incremental hash session, see
/// [VaultHashApi.beginHashSession]/[DuplicateFinderService]'s
/// full-hash pass) and external/on-device files (see
/// HashVerifierHandlers.kt) -- a standard-library implementation of
/// exactly these four digests, so there's no reason to route through the
/// custom mbedtls-backed hash layer in cipher_shim.cpp, which doesn't
/// cover MD5 at all and only exposes Whirlpool/Streebog/BLAKE2s-256 as a
/// one-shot (whole-buffer) call unsuited to multi-gigabyte ISOs/backups.
enum HashAlgorithm {
  md5,
  sha1,
  sha256,
  sha512;

  String get label => switch (this) {
        HashAlgorithm.md5 => 'MD5',
        HashAlgorithm.sha1 => 'SHA-1',
        HashAlgorithm.sha256 => 'SHA-256',
        HashAlgorithm.sha512 => 'SHA-512',
      };

  /// Name passed to Kotlin's `MessageDigest.getInstance(...)` for external
  /// files, and used as the wire key in the returned digest map -- see
  /// [VaultHashApi.computeExternalFileHash].
  String get wireName => switch (this) {
        HashAlgorithm.md5 => 'MD5',
        HashAlgorithm.sha1 => 'SHA-1',
        HashAlgorithm.sha256 => 'SHA-256',
        HashAlgorithm.sha512 => 'SHA-512',
      };

  /// Conventional file extension for a manifest of just this algorithm
  /// (GNU coreutils naming: `sha256sum`/`md5sum`/...), used to suggest an
  /// export filename.
  String get manifestExtension => switch (this) {
        HashAlgorithm.md5 => 'md5',
        HashAlgorithm.sha1 => 'sha1',
        HashAlgorithm.sha256 => 'sha256sum',
        HashAlgorithm.sha512 => 'sha512sum',
      };

  int get hexLength => switch (this) {
        HashAlgorithm.md5 => 32,
        HashAlgorithm.sha1 => 40,
        HashAlgorithm.sha256 => 64,
        HashAlgorithm.sha512 => 128,
      };

  /// Infers the algorithm from a bare hex digest's length -- the fallback
  /// used when a manifest line carries no explicit BSD-style tag. `null`
  /// on a length no supported algorithm produces (the line is skipped).
  static HashAlgorithm? fromHexLength(int len) {
    for (final algo in HashAlgorithm.values) {
      if (algo.hexLength == len) return algo;
    }
    return null;
  }

  /// Infers the algorithm from a BSD-style manifest tag
  /// (`"SHA256 (name) = hex"`). `null` for an unrecognized/unsupported tag
  /// (e.g. SHA224/SHA384, which this tool doesn't compute).
  static HashAlgorithm? fromBsdTag(String tag) => switch (tag.toUpperCase()) {
        'MD5' => HashAlgorithm.md5,
        'SHA1' => HashAlgorithm.sha1,
        'SHA256' => HashAlgorithm.sha256,
        'SHA512' => HashAlgorithm.sha512,
        _ => null,
      };
}

/// Outcome of hashing one [source] with one or more [HashAlgorithm]s in a
/// single streaming pass, for the Compute tab.
class HashComputeResult {
  final CryptoSourceItem source;

  /// Lowercase hex digest per algorithm that was requested and completed.
  final Map<HashAlgorithm, String> digests;

  /// Set when hashing this source failed; [digests] may still be partially
  /// empty in that case.
  final String? error;

  const HashComputeResult({
    required this.source,
    required this.digests,
    this.error,
  });

  bool get hasError => error != null;
}

/// One parsed line from a `.sha256sum`/`.md5`/BSD-style manifest file.
class ManifestEntry {
  /// The filename exactly as written in the manifest (may contain `/` for
  /// a subfolder-relative path). Leading `./` is stripped and backslashes
  /// are normalized to `/` by [HashVerifierService.parseManifest].
  final String fileName;

  /// Lowercase expected hex digest.
  final String expectedHex;
  final HashAlgorithm algorithm;

  const ManifestEntry({
    required this.fileName,
    required this.expectedHex,
    required this.algorithm,
  });
}

enum VerifyStatus { pending, computing, match, mismatch, missing, error }

/// One row of the Verify tab's results list: a manifest entry, the
/// candidate source file matched to it (if any), and the outcome of
/// hashing and comparing it.
class VerifyRow {
  final ManifestEntry entry;
  final CryptoSourceItem? matchedSource;
  final VerifyStatus status;
  final String? computedHex;
  final String? errorMessage;

  const VerifyRow({
    required this.entry,
    this.matchedSource,
    this.status = VerifyStatus.pending,
    this.computedHex,
    this.errorMessage,
  });

  VerifyRow copyWith({
    CryptoSourceItem? matchedSource,
    bool clearMatchedSource = false,
    VerifyStatus? status,
    String? computedHex,
    String? errorMessage,
  }) =>
      VerifyRow(
        entry: entry,
        matchedSource: clearMatchedSource ? null : (matchedSource ?? this.matchedSource),
        status: status ?? this.status,
        computedHex: computedHex ?? this.computedHex,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
