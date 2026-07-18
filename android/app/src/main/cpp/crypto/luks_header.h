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
// candidateMasterKey / candidateMasterKeyLen: optional quick-unlock fast
// path. When supplied, password/passwordLen are ignored, every keyslot's
// PBKDF2/Argon2 derivation is skipped entirely, and the candidate is
// verified directly against the header (LUKS1) or matching digest (LUKS2).
// Returns false without touching any keyslot if the candidate doesn't
// verify — callers should fall back to password/keyfile in that case.
bool luksRecoverMasterKey(int fd,
                          const uint8_t* password,
                          size_t passwordLen,
                          LuksVolumeInfo& outInfo,
                          int volId = -1,
                          std::function<bool(int)> cancelCheck = nullptr,
                          std::function<void(int, int, int, int)> progressCallback = nullptr,
                          const uint8_t* candidateMasterKey = nullptr,
                          size_t candidateMasterKeyLen = 0);

// ── Container creation ──────────────────────────────────────────────────

// Parameters describing how to format a brand-new LUKS1 or LUKS2 container.
// Kept as plain strings/ints (mirroring LuksVolumeInfo's own style) so this
// header stays independent of the app's CascadeId/HashId enums — callers
// (container_create.cpp) translate those into the fields below.
struct LuksCreateParams {
    int version = 2;                // 1 or 2

    // "aes" | "serpent" | "twofish" | "camellia" | "kuznyechik". Valid for
    // both version==1 and version==2 — see luksCreateHeader()'s doc
    // comment for why LUKS1 isn't restricted to "aes".
    std::string cipherName;

    // Keyslot PBKDF2 hash ("sha256" | "sha512"), and — for LUKS2 — also
    // the digest hash. Ignored for the keyslot KDF itself when
    // useArgon2id is true (LUKS2 only), but always used for the digest.
    std::string hashName = "sha256";

    // LUKS2 only. When true, the keyslot uses Argon2id instead of PBKDF2
    // and pbkdf2Iterations is ignored for the keyslot (the digest is
    // still always PBKDF2, per real cryptsetup behavior).
    bool useArgon2id = false;
    uint32_t argon2MemoryKiB = 0;
    uint32_t argon2TimeCost = 0;
    uint32_t argon2Parallelism = 0;

    // Keyslot PBKDF2 iteration count. Used directly for LUKS1, and for
    // LUKS2 whenever useArgon2id is false.
    uint32_t pbkdf2Iterations = 0;
};

using LuksByteWriter = std::function<bool(uint64_t offset, const void* data, size_t len)>;
// Writes a fresh LUKS1 or LUKS2 header, JSON metadata (LUKS2 only), and a
// single occupied keyslot to [fd] — encrypting a freshly-generated random
// master key with [password] (already resolved: for LUKS, a keyfile
// REPLACES the typed password rather than mixing with it, matching real
// `cryptsetup --key-file`, so callers must have already made that
// substitution before calling this). [sizeBytes] is the container's total
// size; the resulting data-area offset/length are reported back via
// [outInfo] so the caller can zero-fill the data area and format a
// filesystem exactly as it would after a real unlock — [outInfo] is filled
// with the same fields luksRecoverMasterKey() populates on a subsequent
// unlock (cipherName/cipherMode/keyBytes/dataOffsetBytes/dataSectorSize/
// ivTweak(always 0 for a fresh format)/masterKey), so no re-derivation is
// needed after this call.
//
// LUKS1 creation is NOT restricted to cipherName "aes". This app's LUKS1
// unlock path (luks1Unlock, see luks_header.cpp) decrypts the keyslot's
// AF area with whichever cipher the on-disk header declares
// (cascadeIdForCipherName(phdr.cipherName, ...) feeding keyslotAreaCrypt),
// and luks1CreateHeader() below encrypts that same AF area with the
// caller's chosen [params.cipherName] the same way — matching real
// LUKS1's convention of reusing the data cipher for the keyslot too. So a
// LUKS1 container created here with Serpent/Twofish/Camellia/Kuznyechik
// unlocks again just fine, the same as a real cryptsetup-created one
// would. (An earlier version of this function hardcoded AES-CBC for the
// keyslot regardless of cipherName, which both mismatched the spec and
// produced containers that non-AES ciphers could never be unlocked with
// again — see the inline comment further down where that was fixed.)
//
// LUKS2's keyslot area, by contrast, is governed by its own JSON
// "area.encryption" field (read dynamically by luks2Unlock, written as
// "aes-xts-plain64" by luks2CreateHeader() below) rather than following
// the segment's data cipher — matching real cryptsetup's own default of
// always keeping the LUKS2 keyslot area AES-XTS regardless of what
// cipher the volume data itself uses.
//
// Does not touch [fd] beyond writing the header/keyslot/JSON region —
// truncating/expanding the file to [sizeBytes], zero-filling the data
// area, and formatting a filesystem on top remain the caller's job (see
// createLuksContainer() in container_create.cpp).
bool luksCreateHeader(int fd, const uint8_t* password, size_t passwordLen,
                      int64_t sizeBytes, const LuksCreateParams& params,
                      LuksVolumeInfo& outInfo);

bool luksCreateHeader(const LuksByteWriter& writer, const uint8_t* password, size_t passwordLen,
                      int64_t sizeBytes, const LuksCreateParams& params,
                      LuksVolumeInfo& outInfo);               

