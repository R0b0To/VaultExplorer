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