library;

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

enum RepairDiagnosis {
  healthy,
  headerCorrupted,
  filesystemDirty,
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