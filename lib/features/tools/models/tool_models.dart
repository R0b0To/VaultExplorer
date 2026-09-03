library;

import 'dart:convert';
import 'dart:typed_data';

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
///
/// [mountedVolId] is set when this target was picked from the "already
/// mounted" list instead of the SAF folder picker (see
/// [ContainerRepairSheet]'s mounted-containers section) -- i.e. the vault
/// is currently unlocked elsewhere in the app. When non-null,
/// [ContainerToolService.checkFolderVault] can run a full deep scan right
/// away, reusing that session's already-derived key, without ever prompting
/// for a password.
class FolderVaultTarget extends RepairTarget {
  final String treeUri;
  final String displayName;
  final String format;
  final int? mountedVolId;
  const FolderVaultTarget({
    required this.treeUri,
    required this.displayName,
    required this.format,
    this.mountedVolId,
  });

  bool get isAlreadyMounted => mountedVolId != null;
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

// ── Header Backup tool (Container Header Exporter / Backup Vault) ────────
//
// Two very different "headers" can be backed up here: a single-file
// container's (VeraCrypt/LUKS1/LUKS2) header+keyslot region -- see
// container_repair.cpp's "Header Backup / Restore" section for exactly
// what that region is -- and a folder vault's (gocryptfs/CryFS/
// Cryptomator) config/masterkey file, its ENTIRE key material despite
// being a few KB. Both end up wrapped in the same [HeaderBackupFile]
// envelope so one restore flow (and one on-disk file format) covers both.

/// Which of the two things above a [HeaderBackupFile] holds.
enum HeaderBackupKind {
  containerHeader,
  folderVaultConfig;

  String get wireName => switch (this) {
    HeaderBackupKind.containerHeader => 'containerHeader',
    HeaderBackupKind.folderVaultConfig => 'folderVaultConfig',
  };

  static HeaderBackupKind? fromWire(String wire) => switch (wire) {
    'containerHeader' => HeaderBackupKind.containerHeader,
    'folderVaultConfig' => HeaderBackupKind.folderVaultConfig,
    _ => null,
  };
}

/// A Header Backup file, decoded or about to be [encode]d. Not a standard
/// format -- a small envelope purpose-built for this tool, so a picked
/// file can be validated as genuinely one of these (not some unrelated
/// file selected by mistake) before any restore logic touches a real
/// container or vault.
///
/// On-disk layout: an ASCII magic+version line, then a single-line JSON
/// metadata object, then the raw payload bytes immediately after that
/// line's newline -- e.g. opening an exported file in a text editor
/// immediately shows what it is and when it was made, which a fully-binary
/// format wouldn't.
class HeaderBackupFile {
  static const _magic = 'VXHDRBKP1';

  final HeaderBackupKind kind;
  /// Wire-name format: veracrypt/luks1/luks2 for [HeaderBackupKind.containerHeader],
  /// gocryptfs/cryfs/cryptomator for [HeaderBackupKind.folderVaultConfig].
  final String format;
  final Uint8List payload;
  final String sha256Hex;
  /// The source file/vault's total size at export time, purely
  /// informational (shown so the person can recognize "yes, that's my
  /// vault"). Null for [HeaderBackupKind.folderVaultConfig], where it
  /// wouldn't mean much (the config file itself is tiny regardless of how
  /// much data the vault holds).
  final int? containerSizeBytes;
  final int exportedAtMs;
  /// Display name of the original container file or vault folder, purely
  /// informational.
  final String sourceName;

  const HeaderBackupFile({
    required this.kind,
    required this.format,
    required this.payload,
    required this.sha256Hex,
    required this.containerSizeBytes,
    required this.exportedAtMs,
    required this.sourceName,
  });

  Uint8List encode() {
    final metaLine = jsonEncode({
      'kind': kind.wireName,
      'format': format,
      'length': payload.length,
      'sha256': sha256Hex,
      if (containerSizeBytes != null) 'containerSizeBytes': containerSizeBytes,
      'exportedAtMs': exportedAtMs,
      'sourceName': sourceName,
    });
    final builder = BytesBuilder(copy: false);
    builder.add(utf8.encode('$_magic\n'));
    builder.add(utf8.encode('$metaLine\n'));
    builder.add(payload);
    return builder.toBytes();
  }

  /// Parses the envelope structure only -- the magic line, the JSON
  /// metadata line, and that the payload length matches what's declared.
  /// Does NOT verify [sha256Hex] against [payload] (that needs an async
  /// native hash call) -- see [ContainerToolService.loadHeaderBackupFile],
  /// which checks both. Throws [HeaderBackupInvalidException] if the
  /// envelope itself doesn't parse.
  static HeaderBackupFile decode(Uint8List raw) {
    final firstNewline = raw.indexOf(0x0A);
    if (firstNewline < 0) {
      throw const HeaderBackupInvalidException('Not a Header Backup file.');
    }
    final magicLine = utf8.decode(raw.sublist(0, firstNewline));
    if (magicLine != _magic) {
      throw const HeaderBackupInvalidException('Not a Header Backup file.');
    }
    final secondNewline = raw.indexOf(0x0A, firstNewline + 1);
    if (secondNewline < 0) {
      throw const HeaderBackupInvalidException('This backup file is truncated.');
    }

    final Map<String, Object?> meta;
    try {
      final decoded = jsonDecode(utf8.decode(raw.sublist(firstNewline + 1, secondNewline)));
      meta = decoded as Map<String, Object?>;
    } catch (_) {
      throw const HeaderBackupInvalidException('This backup file is corrupted.');
    }

    final kind = HeaderBackupKind.fromWire(meta['kind'] as String? ?? '');
    final format = meta['format'] as String?;
    final sha256Hex = meta['sha256'] as String?;
    final declaredLength = (meta['length'] as num?)?.toInt();
    if (kind == null || format == null || sha256Hex == null || declaredLength == null) {
      throw const HeaderBackupInvalidException('This backup file is corrupted.');
    }

    final payload = raw.sublist(secondNewline + 1);
    if (payload.length != declaredLength) {
      throw const HeaderBackupInvalidException('This backup file is truncated.');
    }

    return HeaderBackupFile(
      kind: kind,
      format: format,
      payload: payload,
      sha256Hex: sha256Hex,
      containerSizeBytes: (meta['containerSizeBytes'] as num?)?.toInt(),
      exportedAtMs: (meta['exportedAtMs'] as num?)?.toInt() ?? 0,
      sourceName: meta['sourceName'] as String? ?? 'backup',
    );
  }
}

/// Thrown by [ContainerToolService.exportContainerHeader] when the picked
/// file isn't a container format this app recognizes at all.
class HeaderBackupUnrecognizedFileException implements Exception {
  const HeaderBackupUnrecognizedFileException();
  @override
  String toString() => 'This doesn\'t look like a container this app recognizes.';
}

/// Thrown when a container's header/keyslot region can't be sized because
/// its own cleartext fields don't parse -- try Check & Repair first.
class HeaderBackupUnreadableException implements Exception {
  const HeaderBackupUnreadableException();
  @override
  String toString() => 'Could not read this container\'s header fields. Try Check & Repair first.';
}

/// Thrown by [ContainerToolService.restoreContainerHeader]/
/// [ContainerToolService.restoreFolderVaultConfig], or by
/// [HeaderBackupFile.decode]/[ContainerToolService.loadHeaderBackupFile],
/// whenever a backup file doesn't verify as genuine -- a corrupted/
/// truncated backup file, the wrong backup for this container, or
/// (VeraCrypt) one that doesn't decrypt under the given password.
class HeaderBackupInvalidException implements Exception {
  final String message;
  const HeaderBackupInvalidException([
    this.message = 'This backup doesn\'t look genuine for this container.',
  ]);
  @override
  String toString() => message;
}

/// Thrown when the restore target is smaller than the backup's header
/// region -- almost certainly the wrong file was selected.
class HeaderBackupSizeMismatchException implements Exception {
  const HeaderBackupSizeMismatchException();
  @override
  String toString() => 'The selected container is smaller than the backup header. Wrong file?';
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

class FolderVaultRepairReport {
  final String format;
  final int fixedCount;
  final int recoveredCount;
  final int removedCount;
  final List<FolderVaultIssue> remainingIssues;

  const FolderVaultRepairReport({
    required this.format,
    required this.fixedCount,
    required this.recoveredCount,
    required this.removedCount,
    required this.remainingIssues,
  });

  bool get healthy => remainingIssues.every((i) => i.severity == FolderVaultIssueSeverity.info);

  factory FolderVaultRepairReport.fromWire(Map<Object?, Object?> wire) {
    final rawIssues = (wire['remainingIssues'] as List?) ?? const [];
    return FolderVaultRepairReport(
      format: wire['format'] as String? ?? '',
      fixedCount: (wire['fixedCount'] as num?)?.toInt() ?? 0,
      recoveredCount: (wire['recoveredCount'] as num?)?.toInt() ?? 0,
      removedCount: (wire['removedCount'] as num?)?.toInt() ?? 0,
      remainingIssues: rawIssues.map((e) => FolderVaultIssue.fromWire(e as Map<Object?, Object?>)).toList(),
    );
  }
}