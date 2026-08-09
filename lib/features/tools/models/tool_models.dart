/// Shared value types for the Tools tab's workflows (Container
/// Splitter/Joiner, Single-File Encrypt/Decrypt, Storage Analyzer,
/// Container Check & Repair).
///
/// These are UI-facing choices only. Container Splitter/Joiner's engine
/// exists now (`SplitJoinHandlers` on the native side, via
/// [ContainerToolService]'s [NativeContainerToolService]) — the
/// AEAD-container and repair engines described elsewhere in this file
/// still don't. Kept in their own file so the sheets/screens and the
/// service implementation agree on the same vocabulary from day one.
library;

/// Preset chunk sizes offered by the Container Splitter, plus a custom
/// option. Values are informational (MB) for the concrete presets;
/// [custom] defers to whatever the user types into the size field.
///
/// [cloud8mb] is the default: splitting for cloud sync (rather than for a
/// legacy filesystem's single-file size cap) means a change deep inside a
/// large container should only have to re-upload the handful of chunks it
/// actually touched, so small chunks matter more here than they do for
/// the two legacy size-cap presets below, which exist for FAT32/generic
/// "my provider rejects big files" cases and stay large on purpose.
enum ChunkSizePreset {
  cloud8mb(8),
  cloud32mb(32),
  cloud100mb(100),
  fat32_2gb(2000),
  fourGb(4000),
  custom(null);

  final int? megabytes;
  const ChunkSizePreset(this.megabytes);
}

/// Which direction a Single-File Encrypt/Decrypt run performs.
enum CryptoDirection { encrypt, decrypt }

/// Standalone AEAD ciphers offered for single-file encryption. Distinct
/// from [CipherAlgo] (crypto_algorithms.dart), which enumerates VeraCrypt
/// block-container cascades — this is a single, non-cascaded cipher for a
/// lightweight standalone encrypted file, not a full volume.
enum StandaloneCipher {
  aes256Gcm,
  xChaCha20Poly1305;

  String get label => switch (this) {
        StandaloneCipher.aes256Gcm => 'AES-256-GCM',
        StandaloneCipher.xChaCha20Poly1305 => 'XChaCha20-Poly1305',
      };
}

/// What the Repair wizard is pointed at: a file that isn't currently
/// mounted, or an already-mounted volume (by `volId`).
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

/// Outcome of the Repair wizard's diagnostic scan step.
enum RepairDiagnosis {
  healthy,
  headerCorrupted,
  filesystemDirty,
}

/// One heaviest-file entry in the Storage Analyzer's breakdown, resolved
/// from a real directory walk ([StorageAnalyzerScreen]'s
/// `_walkMountedVolume`) via `listDirectory`/`RawEntry`.
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

/// A single slice of the Storage Analyzer's file-type breakdown bar.
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