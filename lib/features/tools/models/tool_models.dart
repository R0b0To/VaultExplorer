library;

import 'package:vaultexplorer/data/models/mounted_container.dart';

enum ChunkSizePreset {
  fourMb(4),
  cloud8mb(8),
  cloud32mb(32),
  cloud100mb(100),
  fat32_2gb(2000),
  fourGb(4000),
  custom(null);

  final int? megabytes;
  const ChunkSizePreset(this.megabytes);
}

enum CryptoDirection { encrypt, decrypt }

enum StandaloneCipher {
  xChaCha20Poly1305,
  aes256Gcm,
  aesCrypt,
  aes256Xts,
  serpent,
  twofish,
  camellia,
  kuznyechik,
  aesTwofish,
  serpentAes,
  twofishSerpent,
  aesTwofishSerpent,
  serpentTwofishAes,
  camelliaKuznyechik,
  camelliaSerpent,
  kuznyechikAes,
  kuznyechikSerpentCamellia,
  kuznyechikTwofish;

  String get label => switch (this) {
        StandaloneCipher.xChaCha20Poly1305 => 'XChaCha20-Poly1305 (AEAD)',
        StandaloneCipher.aes256Gcm => 'AES-256-GCM (AEAD)',
        StandaloneCipher.aesCrypt => 'AES Crypt (.aes)',
        StandaloneCipher.aes256Xts => 'AES-256',
        StandaloneCipher.serpent => 'Serpent',
        StandaloneCipher.twofish => 'Twofish',
        StandaloneCipher.camellia => 'Camellia',
        StandaloneCipher.kuznyechik => 'Kuznyechik',
        StandaloneCipher.aesTwofish => 'AES-Twofish (Cascade)',
        StandaloneCipher.serpentAes => 'Serpent-AES (Cascade)',
        StandaloneCipher.twofishSerpent => 'Twofish-Serpent (Cascade)',
        StandaloneCipher.aesTwofishSerpent => 'AES-Twofish-Serpent (Cascade)',
        StandaloneCipher.serpentTwofishAes => 'Serpent-Twofish-AES (Cascade)',
        StandaloneCipher.camelliaKuznyechik => 'Camellia-Kuznyechik (Cascade)',
        StandaloneCipher.camelliaSerpent => 'Camellia-Serpent (Cascade)',
        StandaloneCipher.kuznyechikAes => 'Kuznyechik-AES (Cascade)',
        StandaloneCipher.kuznyechikSerpentCamellia => 'Kuznyechik-Serpent-Camellia (Cascade)',
        StandaloneCipher.kuznyechikTwofish => 'Kuznyechik-Twofish (Cascade)',
      };
}

sealed class RepairTarget {
  const RepairTarget();
}

class UnmountedFileTarget extends RepairTarget {
  final String uri;
  final String displayName;
  const UnmountedFileTarget({required this.uri, required this.displayName});
}

class MountedVolumeTarget extends RepairTarget {
  final int volId;
  final String displayName;
  const MountedVolumeTarget({required this.volId, required this.displayName});
}

/// A gocryptfs/CryFS/Cryptomator vault, picked as a SAF folder rather than
/// a single container file -- see [ContainerToolService.checkFolderVault].
/// [format] is the wire name ("gocryptfs" | "cryfs" | "cryptomator") the
/// folder picker's own format auto-detection already resolved it to.
class FolderVaultTarget extends RepairTarget {
  final String treeUri;
  final String displayName;
  final String format;
  const FolderVaultTarget({
    required this.treeUri,
    required this.displayName,
    required this.format,
  });
}

enum RepairDiagnosis {
  healthy,
  headerCorrupted,
  filesystemDirty,
}

/// One problem found by [ContainerToolService.checkFolderVault]. [path] is
/// the cleartext path when it could be decrypted, otherwise the closest
/// on-disk location -- see FolderVaultChecker.kt for exactly what each
/// severity means per format.
enum FolderVaultIssueSeverity { info, warning, critical }

class FolderVaultIssue {
  final FolderVaultIssueSeverity severity;
  final String path;
  final String message;
  const FolderVaultIssue({
    required this.severity,
    required this.path,
    required this.message,
  });

  factory FolderVaultIssue.fromWire(Map<Object?, Object?> wire) {
    const severities = FolderVaultIssueSeverity.values;
    final wireIndex = (wire['severity'] as num?)?.toInt() ?? 0;
    return FolderVaultIssue(
      severity: wireIndex >= 0 && wireIndex < severities.length ? severities[wireIndex] : FolderVaultIssueSeverity.info,
      path: wire['path'] as String? ?? '',
      message: wire['message'] as String? ?? '',
    );
  }
}

/// Result of [ContainerToolService.checkFolderVault]. [deepScanPerformed]
/// is true once a password was supplied and every file's content was
/// AEAD-verified, not just the vault's on-disk structure -- see
/// FolderVaultChecker.kt's doc comment for what each depth covers.
class FolderVaultCheckReport {
  final String format;
  final int filesScanned;
  final List<FolderVaultIssue> issues;
  final bool deepScanPerformed;
  const FolderVaultCheckReport({
    required this.format,
    required this.filesScanned,
    required this.issues,
    required this.deepScanPerformed,
  });

  bool get healthy => issues.every((i) => i.severity == FolderVaultIssueSeverity.info);

  factory FolderVaultCheckReport.fromWire(Map<Object?, Object?> wire) {
    final rawIssues = (wire['issues'] as List?) ?? const [];
    return FolderVaultCheckReport(
      format: wire['format'] as String? ?? '',
      filesScanned: (wire['filesScanned'] as num?)?.toInt() ?? 0,
      deepScanPerformed: wire['deepScanPerformed'] as bool? ?? false,
      issues: rawIssues.map((e) => FolderVaultIssue.fromWire(e as Map<Object?, Object?>)).toList(),
    );
  }
}

/// Thrown by [ContainerToolService.checkFolderVault] when the picked
/// folder isn't recognizable at all as the requested format (no
/// gocryptfs.conf/cryfs.config/masterkey.cryptomator, or it doesn't parse).
class FolderVaultInvalidException implements Exception {
  final String message;
  const FolderVaultInvalidException(this.message);
  @override
  String toString() => message;
}

/// Thrown by [ContainerToolService.restoreBackupHeader] when the target's
/// backup-header copy can only be trusted once its password has decrypted
/// and verified it (VeraCrypt/TrueCrypt) -- unlike LUKS2, whose header
/// checksum is unencrypted and needs no password at all. Callers should
/// prompt for a password and retry with it.
class RepairPasswordRequiredException implements Exception {
  const RepairPasswordRequiredException();
}

/// Thrown when a password was supplied but didn't decrypt any backup
/// header slot.
class RepairIncorrectPasswordException implements Exception {
  const RepairIncorrectPasswordException();
  @override
  String toString() => 'Incorrect password.';
}

/// Thrown when the target's format has no backup-header restore path
/// implemented at all (e.g. LUKS1, which has no on-disk backup copy to
/// restore from -- see luks_header.h's header-integrity doc comment).
class RepairUnsupportedFormatException implements Exception {
  const RepairUnsupportedFormatException();
  @override
  String toString() => 'This container format doesn\'t support backup-header restore yet.';
}

class StorageEntry {
  final String path;
  final String name;
  final int sizeBytes;
  const StorageEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });
}

class StorageCategoryBreakdown {
  final String category;
  final int sizeBytes;
  final int fileCount;
  const StorageCategoryBreakdown({
    required this.category,
    required this.sizeBytes,
    required this.fileCount,
  });
}

/// Why a [runBatchFileCrypto] run stopped before processing every source
/// file. `null` on [BatchCryptoBatchResult.abortReason] means the batch
/// ran to completion (individual per-file failures still land in
/// [BatchCryptoBatchResult.failedNames] rather than aborting the batch).
enum BatchCryptoAbortReason { notImplemented, authFailure }

/// Outcome of a [ContainerToolService.runBatchFileCrypto] run.
class BatchCryptoBatchResult {
  final BatchCryptoAbortReason? abortReason;
  final int succeeded;
  final int totalFiles;
  final List<String> failedNames;

  const BatchCryptoBatchResult({
    this.abortReason,
    required this.succeeded,
    required this.totalFiles,
    required this.failedNames,
  });

  bool get aborted => abortReason != null;
}
/// external device storage or from a currently-mounted vault.
class CryptoSourceItem {
  final String displayName;
  final String? externalUri;
  final MountedContainer? container;
  final String? relativePath;
  final bool isFromVault;

  const CryptoSourceItem.external({
    required this.displayName,
    required this.externalUri,
  })  : container = null,
        relativePath = null,
        isFromVault = false;

  const CryptoSourceItem.vault({
    required this.displayName,
    required this.container,
    required this.relativePath,
  })  : externalUri = null,
        isFromVault = true;

  String get id => isFromVault
      ? 'vault:${container!.volId}:$relativePath'
      : 'ext:$externalUri';
}

/// Where the Single File Crypto tool should write its output: either
/// external device storage or a folder inside a currently-mounted vault.
class CryptoDestination {
  final String displayName;
  final String? externalPath;
  final String? externalTreeUri;
  final MountedContainer? container;
  final String? relativePath;
  final bool isVault;

  const CryptoDestination.external({
    required this.displayName,
    required this.externalPath,
    this.externalTreeUri,
  })  : container = null,
        relativePath = null,
        isVault = false;

  const CryptoDestination.vault({
    required this.displayName,
    required this.container,
    required this.relativePath,
  })  : externalPath = null,
        externalTreeUri = null,
        isVault = true;
}