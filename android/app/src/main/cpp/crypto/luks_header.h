#pragma once

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <functional>

// LUKS Magic Constant: {'L', 'U', 'K', 'S', 0xBA, 0xBE}
extern const uint8_t LUKS_MAGIC[6];

// LUKS1 on-disk header (592 bytes)
#pragma pack(push, 1)
struct Luks1KeySlot {
    uint32_t active;
    uint32_t iterations;
    uint8_t  salt[32];
    uint32_t keyMaterialOffset;
    uint32_t stripes;
};

struct Luks1Phdr {
    uint8_t      magic[6];
    uint16_t     version;
    char         cipherName[32];
    char         cipherMode[32];
    char         hashSpec[32];
    uint32_t     payloadOffset;
    uint32_t     keyBytes;
    uint8_t      mkDigest[20];
    uint8_t      mkDigestSalt[32];
    uint32_t     mkDigestIter;
    char         uuid[40];
    Luks1KeySlot keySlots[8];
};
#pragma pack(pop)

// Parsed structures for LUKS2 JSON metadata
struct Luks2KeyslotInfo {
    int index = -1;
    std::string kdfType;      // "pbkdf2" or "argon2id" or "argon2i"
    std::string hashName;     // hash for PBKDF2 ("sha256", "sha512", etc.)
    uint32_t iterations = 0;  // PBKDF2 iterations OR Argon2 time cost
    uint32_t memory = 0;      // Argon2 memory in KiB
    uint32_t parallelism = 0; // Argon2 parallelism
    std::vector<uint8_t> salt;
    uint64_t areaOffset = 0;  // byte offset of key material
    uint64_t areaSize = 0;    // byte size of key material
    int afStripes = 0;
    std::string afHash;       // hash for AF diffusion
    std::string areaEncryption; // e.g. "aes-xts-plain64"
    uint32_t areaKeySize = 0; // key size for area encryption in bytes
};

struct Luks2DigestInfo {
    std::string type;         // "pbkdf2"
    std::string hashName;     // hash for digest
    uint32_t iterations = 0;
    std::vector<uint8_t> salt;
    std::vector<uint8_t> digest;
    std::vector<int> keyslots;
    std::vector<int> segments;
};

struct Luks2SegmentInfo {
    std::string encryption;    // "aes-xts-plain64" etc.
    uint64_t offset = 0;       // data area byte offset
    uint64_t sectorSize = 512;
    uint32_t keySize = 0;      // key size in bytes
    // "iv_tweak": added to the sector counter used for the XTS tweak. The
    // counter itself starts at 0 at the FIRST sector of this segment (i.e.
    // it's relative to `offset`, not the start of the file) and increments
    // once per `sectorSize` bytes. Default 0 for a freshly-formatted
    // container; only nonzero after certain reencryption operations.
    uint64_t ivTweak = 0;
};

struct LuksVolumeInfo {
    int version = 0;           // 1 or 2
    std::string cipherName;    // "aes" etc.
    std::string cipherMode;    // "xts-plain64" etc.
    uint32_t keyBytes = 0;     // master key size in bytes
    uint64_t dataOffsetBytes = 0;
    uint64_t dataSectorSize = 512;
    // LUKS2 segment "iv_tweak" (always 0 for LUKS1). See Luks2SegmentInfo::ivTweak.
    uint64_t ivTweak = 0;
    std::vector<uint8_t> masterKey;
};

// Check if the header starts with LUKS magic bytes
bool isLuksContainer(const uint8_t* header, size_t len);

// Main master key recovery entry point for LUKS containers.
// Handled callbacks for cancellation and progress reporting to keep JNI logic decoupled.
bool luksRecoverMasterKey(int fd,
                          const uint8_t* password,
                          size_t passwordLen,
                          LuksVolumeInfo& outInfo,
                          int volId = -1,
                          std::function<bool(int)> cancelCheck = nullptr,
                          std::function<void(int, int, int, int)> progressCallback = nullptr);