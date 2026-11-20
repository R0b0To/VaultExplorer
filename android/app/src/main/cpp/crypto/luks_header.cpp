#include "luks_header.h"
#include "cipher_shim.h"
#include "cascade.h"
#include "luks_cipher.h"
#include "user_entropy.h"
#include <cstring>
#include <cmath>
#include <cstdint>
#include <functional>
#include <future>
#include <string>
#include <vector>
#include <algorithm>
#include <cerrno>
#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include "thread_pool.h"
#include <unistd.h>
#include <android/log.h>
#include <cJSON.h>

#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/base64.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"

#include <cstdio>
#include <cstdlib>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

const uint8_t LUKS_MAGIC[6] = {'L', 'U', 'K', 'S', 0xBA, 0xBE};
static constexpr uint8_t LUKS2_SECONDARY_MAGIC[6] = {'S', 'K', 'U', 'L', 0xBA, 0xBE};

// ── Endian Helpers ────────────────────────────────────────────────────────

static uint16_t readBE16(const uint8_t* p) {
    return (uint16_t(p[0]) << 8) | p[1];
}

static uint32_t readBE32(const uint8_t* p) {
    return (uint32_t(p[0]) << 24) |
           (uint32_t(p[1]) << 16) |
           (uint32_t(p[2]) << 8)  |
           p[3];
}

static uint64_t readBE64(const uint8_t* p) {
    return (uint64_t(readBE32(p)) << 32) | readBE32(p + 4);
}

// Check magic
bool isLuksContainer(const uint8_t* header, size_t len) {
    if (len < 6) return false;
    return std::memcmp(header, LUKS_MAGIC, 6) == 0;
}

// Base64 decoding helper using mbedtls
static std::vector<uint8_t> base64Decode(const std::string& b64) {
    std::vector<uint8_t> out;
    if (b64.empty()) return out;
    size_t olen = 0;
    mbedtls_base64_decode(nullptr, 0, &olen, (const unsigned char*)b64.data(), b64.size());
    if (olen == 0) {
        olen = b64.size() * 3 / 4 + 2;
    }
    out.resize(olen);
    int ret = mbedtls_base64_decode(out.data(), out.size(), &olen, (const unsigned char*)b64.data(), b64.size());
    if (ret != 0) {
        out.clear();
    } else {
        out.resize(olen);
    }
    return out;
}

// Map hash spec string to mbedtls digest type
static mbedtls_md_type_t mapHashSpec(const std::string& hash) {
    std::string h = hash;
    std::transform(h.begin(), h.end(), h.begin(), ::tolower);
    if (h == "sha256" || h == "sha-256") return MBEDTLS_MD_SHA256;
    if (h == "sha512" || h == "sha-512") return MBEDTLS_MD_SHA512;
    if (h == "sha1" || h == "sha-1") return MBEDTLS_MD_SHA1;
    if (h == "ripemd160" || h == "ripemd-160") return MBEDTLS_MD_RIPEMD160;
    // cryptsetup/libgcrypt accept these for LUKS2 kdf/af/digest/checksum hashes
    if (h == "sha224" || h == "sha-224") return MBEDTLS_MD_SHA224;
    if (h == "sha384" || h == "sha-384") return MBEDTLS_MD_SHA384;
    if (h == "sha3-224") return MBEDTLS_MD_SHA3_224;
    if (h == "sha3-256") return MBEDTLS_MD_SHA3_256;
    if (h == "sha3-384") return MBEDTLS_MD_SHA3_384;
    if (h == "sha3-512") return MBEDTLS_MD_SHA3_512;
    return MBEDTLS_MD_NONE;
}

static size_t getDigestSize(mbedtls_md_type_t mdType) {
    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(mdType);
    return mdInfo ? mbedtls_md_get_size(mdInfo) : 0;
}

// ── Hash spec resolution ─────────────────────────────────────────────────
//
// LUKS hash names ("sha256", "whirlpool", ...) resolve to one of two
// disjoint backends: the four hashes mbedTLS provides natively
// (sha1/sha256/sha512/ripemd160, via mapHashSpec() above), or the three
// hashes this app implements itself in cipher_shim.cpp for VeraCrypt
// (whirlpool/streebog/blake2s-256). Real cryptsetup/libgcrypt LUKS1
// volumes commonly use "whirlpool" in particular — previously only the
// mbedTLS four were recognized here, so any volume hashed with anything
// else (most notably whirlpool) failed to unlock outright, on both LUKS1
// and LUKS2. Every PBKDF2/digest/AF-diffusion call site below should go
// through this instead of calling mapHashSpec() directly.
enum class HashBackend { kNone, kMbedtls, kCustom };
struct DigestSpec {
    HashBackend backend = HashBackend::kNone;
    mbedtls_md_type_t mbedtlsType = MBEDTLS_MD_NONE;
    HashId customId = HashId::kSha512; // meaningful only when backend == kCustom
    size_t digestLen = 0;
};

static DigestSpec resolveHashSpec(const std::string& hashSpecIn) {
    std::string h = hashSpecIn;
    std::transform(h.begin(), h.end(), h.begin(), ::tolower);

    DigestSpec spec;
    mbedtls_md_type_t mdType = mapHashSpec(h);
    if (mdType != MBEDTLS_MD_NONE) {
        spec.backend = HashBackend::kMbedtls;
        spec.mbedtlsType = mdType;
        spec.digestLen = getDigestSize(mdType);
        return spec;
    }
    if (h == "whirlpool") {
        spec.backend = HashBackend::kCustom;
        spec.customId = HashId::kWhirlpool;
        spec.digestLen = 64;
    } else if (h == "streebog512" || h == "streebog-512" || h == "streebog") {
        // This app's Streebog implementation is the 512-bit variant only
        // (see hashDigestSize() in cipher_shim.cpp) — "streebog256" isn't
        // recognized here since we can't correctly produce it.
        spec.backend = HashBackend::kCustom;
        spec.customId = HashId::kStreebog;
        spec.digestLen = 64;
    } else if (h == "blake2s-256" || h == "blake2s256") {
        spec.backend = HashBackend::kCustom;
        spec.customId = HashId::kBlake2s256;
        spec.digestLen = 32;
    }
    return spec;
}

// Wraps an already-resolved mbedTLS type as a DigestSpec, for the
// container-creation paths below — those only ever pass sha256/sha512
// (LuksCreateParams::hashName is documented as accepting only those two),
// so they have no need for resolveHashSpec()'s custom-hash branch.
static DigestSpec digestSpecForMbedtls(mbedtls_md_type_t mdType) {
    DigestSpec spec;
    if (mdType == MBEDTLS_MD_NONE) return spec;
    spec.backend = HashBackend::kMbedtls;
    spec.mbedtlsType = mdType;
    spec.digestLen = getDigestSize(mdType);
    return spec;
}

// ── Keyslot-area cipher ──────────────────────────────────────────────────
//
// A keyslot's AF-split key material is encrypted with a cipher that is
// *declared by the header*: LUKS1 uses the header's cipherName/cipherMode
// (the same as the data area), LUKS2 uses the keyslot's own
// "area.encryption" + "area.key_size" (which cryptsetup defaults to
// aes-xts-plain64/512 but which --keyslot-cipher / --keyslot-key-size and
// older LUKS1-style volumes change). Both are handled by the shared
// luks_cipher module (XTS-128/256, CBC with plain/plain64/essiv:sha256),
// with sector numbers counted from 0 at the start of the keyslot area.
//
// Maps a LUKS cipher-name string ("aes", "serpent", ...) to this app's
// CascadeId. Returns false for anything not supported.
static bool cascadeIdForCipherName(const std::string& name, CascadeId& out) {
    if (name == "aes") { out = CascadeId::kAes; return true; }
    if (name == "serpent") { out = CascadeId::kSerpent; return true; }
    if (name == "twofish") { out = CascadeId::kTwofish; return true; }
    if (name == "camellia") { out = CascadeId::kCamellia; return true; }
    if (name == "kuznyechik") { out = CascadeId::kKuznyechik; return true; }
    return false;
}

// Encrypts/decrypts a keyslot area for an already-parsed cipher spec.
// [dataLen] must be a whole multiple of 512. Sector tweaks/IVs count from 0.
static bool areaCrypt(const LuksCipherSpec& spec, bool encrypt,
                      const uint8_t* key, size_t keyLen,
                      const uint8_t* in, uint8_t* out, size_t dataLen) {
    if (dataLen == 0 || dataLen % 512 != 0) return false;
    std::unique_ptr<LuksCipherContext> ctx(new LuksCipherContext());
    bool ok = luksCipherInit(*ctx, spec, key, keyLen) &&
              luksCipherCrypt(*ctx, encrypt, 0, 512, in, out, dataLen);
    luksCipherWipe(*ctx);
    return ok;
}

// Creation-time convenience: single-layer XTS-plain64 keyslot area keyed with
// a 64-byte (256-bit data + 256-bit tweak) key, as the LUKS1 creator uses.
static bool keyslotAreaCrypt(CascadeId cipherId, bool encrypt,
                              const unsigned char* keyMaterial, size_t keyMaterialLen,
                              const unsigned char* in, unsigned char* out, size_t dataLen) {
    LuksCipherSpec spec;
    spec.chain = LuksChain::kXts;
    spec.iv = LuksIvMode::kPlain64;
    spec.keyBytes = static_cast<uint32_t>(keyMaterialLen);
    switch (cipherId) {
        case CascadeId::kAes: spec.cipher = CipherId::kAes; break;
        case CascadeId::kSerpent: spec.cipher = CipherId::kSerpent; break;
        case CascadeId::kTwofish: spec.cipher = CipherId::kTwofish; break;
        case CascadeId::kCamellia: spec.cipher = CipherId::kCamellia; break;
        case CascadeId::kKuznyechik: spec.cipher = CipherId::kKuznyechik; break;
        default: return false;
    }
    return areaCrypt(spec, encrypt, keyMaterial, keyMaterialLen, in, out, dataLen);
}

// ── Shared on-disk constants & the LUKS2 binary header ───────────────────
//
// Real cryptsetup's LUKS1 default: 4000 AF stripes, keyslots 4096-byte
// aligned, integrity-check-only master-key-digest iteration count.
static constexpr uint32_t kLuks1Stripes = 4000;
static constexpr uint64_t kLuks1AlignBytes = 4096;
static constexpr uint64_t kLuks1PayloadAlign = 1024 * 1024;
static constexpr uint32_t kLuks1MkDigestIter = 100000;
static constexpr uint64_t kLuksMinExtraSpace = 300 * 1024; // headroom for a usable ext2/3/4 fs
static constexpr uint32_t kLuks1KeyEnabled = 0x00AC71F3;
static constexpr uint32_t kLuks1KeyDisabled = 0x0000DEAD;
static constexpr uint32_t kLuksMaxKeyBytes = 1024;          // sanity cap (real keys are 16..64 bytes)

// LUKS2 binary header (4096 bytes) — see the real cryptsetup on-disk
// format spec. Multi-byte integer fields are big-endian.
#pragma pack(push, 1)
struct Luks2HdrDisk {
    char     magic[6];
    uint16_t version;
    uint64_t hdrSize;
    uint64_t seqid;
    char     label[48];
    char     checksumAlg[32];
    uint8_t  salt[64];
    char     uuid[40];
    char     subsystem[48];
    uint64_t hdrOffset;
    uint8_t  padding[184];
    uint8_t  csum[64];
    uint8_t  padding4096[7 * 512];
};
#pragma pack(pop)
static_assert(sizeof(Luks2HdrDisk) == 4096, "Luks2HdrDisk must match the real 4096-byte LUKS2 binary header layout");

static constexpr uint64_t kLuks2BinHdrSize = 4096;
static constexpr uint64_t kLuks2HdrCopySize = 16384;                             // default: one header copy (bin + JSON)
static constexpr uint64_t kLuks2JsonAreaSize = kLuks2HdrCopySize - kLuks2BinHdrSize; // 12288
static constexpr uint64_t kLuks2HeadersTotal = 2 * kLuks2HdrCopySize;            // primary + secondary copy
static constexpr uint32_t kLuks2AfStripes = 4000;
static constexpr uint64_t kLuks2KeyslotAlign = 4096;
static constexpr uint64_t kLuks2DataAlign = 1024 * 1024;
static constexpr uint32_t kLuks2DigestIter = 100000; // integrity check only, not security critical
static constexpr uint64_t kLuks2HdrSizeMin = 16384;                              // cryptsetup: LUKS2_HDR_16K_LEN
static constexpr uint64_t kLuks2HdrSizeMax = 4 * 1024 * 1024;                    // cryptsetup: LUKS2_HDR_OFFSET_MAX
static constexpr uint64_t kLuks2MaxKeyslotsSize = 128ull * 1024 * 1024;
static constexpr uint32_t kMaxArgon2MemoryKiB = 1048576;                         // 1 GiB; larger => slot is skipped, never silently clamped
// Every secondary-header location cryptsetup knows (LUKS2_HDR2_OFFSETS).
static constexpr uint64_t kLuks2SecondaryOffsets[] = {
    0x4000, 0x8000, 0x10000, 0x20000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000};

// ── AF Diffusion & Merge ───────────────────────────────────────────────────

static int afDiffuse(const DigestSpec& spec, size_t blocklen, uint8_t* block) {
    size_t digestlen = spec.digestLen;
    if (digestlen == 0) return -1;

    size_t hashcount = blocklen / digestlen;
    size_t finallen = blocklen % digestlen;
    if (finallen) {
        hashcount++;
    } else {
        finallen = digestlen;
    }

    const mbedtls_md_info_t* mdInfo = nullptr;
    mbedtls_md_context_t ctx;
    bool mbedtlsInitialized = false;

    if (spec.backend == HashBackend::kMbedtls) {
        mdInfo = mbedtls_md_info_from_type(spec.mbedtlsType);
        if (!mdInfo) return -1;
        
        mbedtls_md_init(&ctx);
        if (mbedtls_md_setup(&ctx, mdInfo, 0) != 0) {
            mbedtls_md_free(&ctx);
            return -1;
        }
        mbedtlsInitialized = true;
    } else if (spec.backend != HashBackend::kCustom) {
        return -1;
    }

    for (uint32_t i = 0; i < hashcount; i++) {
        uint32_t iv = i;
        // Big endian conversion for the IV
        uint8_t ivBuf[4];
        ivBuf[0] = (iv >> 24) & 0xFF;
        ivBuf[1] = (iv >> 16) & 0xFF;
        ivBuf[2] = (iv >> 8)  & 0xFF;
        ivBuf[3] = iv         & 0xFF;

        size_t chunkLen = (i == (hashcount - 1)) ? finallen : digestlen;
        uint8_t digest[64];

        if (spec.backend == HashBackend::kMbedtls) {
            mbedtls_md_starts(&ctx);
            mbedtls_md_update(&ctx, ivBuf, 4);
            mbedtls_md_update(&ctx, block + (i * digestlen), chunkLen);
            mbedtls_md_finish(&ctx, digest);
        } else {
            if (genericHashOneShot(spec.customId, ivBuf, 4,
                                    block + (i * digestlen), chunkLen, digest) == 0) {
                return -1;
            }
        }

        std::memcpy(block + (i * digestlen), digest, chunkLen);
    }
    
    if (mbedtlsInitialized) {
        mbedtls_md_free(&ctx);
    }
    
    return 0;
}

static void afXor(size_t blocklen, const uint8_t* in1, const uint8_t* in2, uint8_t* out) {
    for (size_t i = 0; i < blocklen; i++) {
        out[i] = in1[i] ^ in2[i];
    }
}

static int afMerge(const DigestSpec& spec, size_t keySize, uint32_t stripes,
                   const uint8_t* src, uint8_t* dst) {
    // stripes == 0 would make (stripes - 1) wrap to 4294967295 and read far past [src].
    if (stripes == 0 || keySize == 0) return -1;
    std::unique_ptr<uint8_t[]> block(new uint8_t[keySize]());
    size_t i;
    for (i = 0; i < (stripes - 1); i++) {
        afXor(keySize, src + (i * keySize), block.get(), block.get());
        if (afDiffuse(spec, keySize, block.get()) < 0) {
            return -1;
        }
    }
    afXor(keySize, src + (i * keySize), block.get(), dst);
    mbedtls_platform_zeroize(block.get(), keySize);
    return 0;
}

// ── Keyslot PBKDF2 Helper ──────────────────────────────────────────────────

static bool luksDeriveKdfKey(const DigestSpec& spec,
                             const uint8_t* password, size_t passwordLen,
                             const uint8_t* salt, size_t saltLen,
                             uint32_t iterations,
                             uint8_t* outKey, size_t outKeyLen,
                             std::function<bool()> cancelCheck = nullptr) {
    if (outKeyLen == 0 || outKeyLen > 1024 || iterations == 0) return false;
    if (spec.backend == HashBackend::kMbedtls) {
        const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(spec.mbedtlsType);
        if (!mdInfo) return false;

        mbedtls_md_context_t ctx;
        mbedtls_md_init(&ctx);
        if (mbedtls_md_setup(&ctx, mdInfo, 1) != 0) {
            mbedtls_md_free(&ctx);
            return false;
        }

        int ret = mbedtls_pkcs5_pbkdf2_hmac(&ctx, password, passwordLen, salt, saltLen, iterations, outKeyLen, outKey);
        mbedtls_md_free(&ctx);
        return ret == 0;
    }
    if (spec.backend == HashBackend::kCustom) {
        return pbkdf2Hmac(spec.customId, password, passwordLen, salt, saltLen, iterations, outKey, outKeyLen, cancelCheck);
    }
    return false;
}

static bool luksVerifyMasterKey(const DigestSpec& spec,
                                const uint8_t* candidateKey, size_t keyLen,
                                const uint8_t* salt, size_t saltLen,
                                uint32_t iterations,
                                const uint8_t* expectedDigest, size_t expectedDigestLen,
                                std::function<bool()> cancelCheck = nullptr) {
    if (expectedDigestLen == 0 || expectedDigestLen > 1024) return false;
    std::vector<uint8_t> derived(expectedDigestLen);
    if (!luksDeriveKdfKey(spec, candidateKey, keyLen, salt, saltLen, iterations, derived.data(), derived.size(), cancelCheck)) {
        return false;
    }
    // Constant-time comparison: the digest check gates master-key acceptance.
    uint8_t diff = 0;
    for (size_t i = 0; i < expectedDigestLen; i++) diff |= static_cast<uint8_t>(derived[i] ^ expectedDigest[i]);
    bool match = (diff == 0);
    mbedtls_platform_zeroize(derived.data(), derived.size());
    return match;
}

// ── LUKS1 header parsing & validation ────────────────────────────────────
//
// Mirrors cryptsetup's _check_and_convert_hdr() + LUKS_check_keyslots()
// (lib/luks1/keymanage.c): a LUKS1 header is rejected unless EVERY one of
// the eight keyslots (active or not) has stripes == 4000 and a key-material
// area that starts after the binary header, lies before the payload and
// does not overlap another slot. Beyond matching upstream, this makes
// every size derived below (keyBytes * 4000) provably overflow-free.

static std::string fixedCString(const char* p, size_t cap) {
    size_t n = 0;
    while (n < cap && p[n] != '\0') n++;
    return std::string(p, n);
}

// AF_split_sectors(keyBytes, 4000): sectors occupied by one AF-split key.
static uint64_t luks1SecsPerStripes(uint32_t keyBytes) {
    const uint64_t af = static_cast<uint64_t>(keyBytes) * kLuks1Stripes;
    return (af + 511) / 512;
}

struct Luks1Parsed {
    Luks1Phdr phdr;
    std::string cipherName, cipherMode, hashSpec;
    uint32_t keyBytes = 0;
    uint32_t payloadOffset = 0;
    uint32_t mkDigestIter = 0;
    uint32_t slotActive[8] = {};
    uint32_t slotIterations[8] = {};
    uint32_t slotStripes[8] = {};
    uint32_t slotOffset[8] = {};
    DigestSpec hash;
    LuksCipherSpec cipherSpec;
    bool cipherSpecOk = false;   // false => keyslots cannot be decrypted by this implementation
};

static bool luks1ParseHeader(const LuksByteReader& reader, Luks1Parsed& P) {
    if (!reader(0, &P.phdr, sizeof(Luks1Phdr))) {
        LOGI("LUKS1: Failed to read phdr");
        return false;
    }
    const Luks1Phdr& h = P.phdr;
    if (std::memcmp(h.magic, LUKS_MAGIC, 6) != 0) return false;
    if (readBE16(reinterpret_cast<const uint8_t*>(&h.version)) != 1) return false;

    // The three name fields are fixed-size and NOT guaranteed NUL-terminated
    // on disk; never treat them as C strings.
    P.cipherName = fixedCString(h.cipherName, sizeof(h.cipherName));
    P.cipherMode = fixedCString(h.cipherMode, sizeof(h.cipherMode));
    P.hashSpec = fixedCString(h.hashSpec, sizeof(h.hashSpec));

    P.keyBytes = readBE32(reinterpret_cast<const uint8_t*>(&h.keyBytes));
    P.payloadOffset = readBE32(reinterpret_cast<const uint8_t*>(&h.payloadOffset));
    P.mkDigestIter = readBE32(reinterpret_cast<const uint8_t*>(&h.mkDigestIter));

    P.hash = resolveHashSpec(P.hashSpec);
    if (P.hash.backend == HashBackend::kNone || P.hash.digestLen < 20) {
        LOGI("LUKS1: Unsupported hashSpec: %s", P.hashSpec.c_str());
        return false;
    }
    if (P.keyBytes == 0 || P.keyBytes > kLuksMaxKeyBytes) {
        LOGI("LUKS1: implausible keyBytes %u", P.keyBytes);
        return false;
    }
    if (P.mkDigestIter == 0) return false;

    const uint64_t secs = luks1SecsPerStripes(P.keyBytes);
    std::vector<uint64_t> starts;
    for (int i = 0; i < 8; i++) {
        const Luks1KeySlot& s = h.keySlots[i];
        P.slotActive[i] = readBE32(reinterpret_cast<const uint8_t*>(&s.active));
        P.slotIterations[i] = readBE32(reinterpret_cast<const uint8_t*>(&s.iterations));
        P.slotStripes[i] = readBE32(reinterpret_cast<const uint8_t*>(&s.stripes));
        P.slotOffset[i] = readBE32(reinterpret_cast<const uint8_t*>(&s.keyMaterialOffset));

        if (P.slotStripes[i] != kLuks1Stripes) {
            LOGI("LUKS1: keyslot %d has invalid stripes %u", i, P.slotStripes[i]);
            return false;
        }
        const uint64_t start = P.slotOffset[i];
        if (start * 512 < sizeof(Luks1Phdr)) return false;                   // overlaps the binary header
        if (P.payloadOffset != 0) {                                          // 0 = detached header
            if (P.payloadOffset <= start || P.payloadOffset < start + secs) return false;
        }
        starts.push_back(start);
    }
    std::sort(starts.begin(), starts.end());
    for (size_t k = 1; k < starts.size(); k++) {
        if (starts[k] < starts[k - 1] + secs) {
            LOGI("LUKS1: overlapping keyslot areas");
            return false;
        }
    }

    P.cipherSpecOk = luksParseCipherSpec(P.cipherName, P.cipherMode, P.keyBytes, P.cipherSpec);
    return true;
}

static void fillLuks1Info(const Luks1Parsed& P, const std::vector<uint8_t>& masterKey, LuksVolumeInfo& outInfo) {
    outInfo.version = 1;
    outInfo.cipherName = P.cipherName;
    outInfo.cipherMode = P.cipherMode;
    outInfo.keyBytes = P.keyBytes;
    outInfo.dataOffsetBytes = static_cast<uint64_t>(P.payloadOffset) * 512;
    outInfo.dataSectorSize = 512;
    outInfo.masterKey = masterKey;
}

// ── LUKS1 Unlocking ─────────────────────────────────────────────────────────

static bool luks1Unlock(const LuksByteReader& reader,
                        const uint8_t* password, size_t passwordLen,
                        LuksVolumeInfo& outInfo,
                        int volId,
                        std::function<bool(int)> cancelCheck,
                        std::function<void(int, int, int, int)> progressCallback,
                        const uint8_t* candidateMasterKey = nullptr,
                        size_t candidateMasterKeyLen = 0) {
    Luks1Parsed P;
    if (!luks1ParseHeader(reader, P)) return false;
    const Luks1Phdr& phdr = P.phdr;
    const uint32_t keyBytes = P.keyBytes;
    const DigestSpec& hashDigest = P.hash;

    // ── Fast path: verify a cached master key directly against the header
    // digest. Skips every keyslot's PBKDF2-AF derivation entirely — this is
    // the whole point of quick-unlock. ──
    if (candidateMasterKey != nullptr) {
        if (candidateMasterKeyLen == keyBytes &&
            luksVerifyMasterKey(hashDigest, candidateMasterKey, keyBytes,
                                 phdr.mkDigestSalt, 32, P.mkDigestIter,
                                 phdr.mkDigest, 20)) {
            fillLuks1Info(P, std::vector<uint8_t>(candidateMasterKey, candidateMasterKey + candidateMasterKeyLen), outInfo);
            LOGI("LUKS1: quick-unlock candidate key verified");
            return true;
        }
        LOGI("LUKS1: quick-unlock candidate key stale/invalid");
        return false; // stale cached key — caller falls back to password/keyfile
    }

    if (!P.cipherSpecOk) {
        LOGI("LUKS1: keyslot cipher %s-%s/%u is not supported", P.cipherName.c_str(), P.cipherMode.c_str(), keyBytes);
        return false;
    }

    // Collect active keyslot indices, then try them concurrently — one
    // thread per active slot, first one to verify against mkDigest wins.
    std::vector<int> activeSlotIndices;
    for (int i = 0; i < 8; i++) {
        if (P.slotActive[i] == kLuks1KeyEnabled && P.slotIterations[i] != 0) activeSlotIndices.push_back(i);
    }
    const int activeSlotsCount = static_cast<int>(activeSlotIndices.size());

    std::atomic<bool> found{false};
    std::atomic<int> attemptedCount{0};
    std::mutex resultMutex;
    std::vector<uint8_t> resultMasterKey;

    auto tryOneSlot = [&](int i) {
        if (found.load(std::memory_order_acquire) || (cancelCheck && cancelCheck(volId))) return;

        if (progressCallback) {
            // Display-only ID: mbedTLS's own type enum for mbedTLS-backed
            // hashes, or 1000+HashId for the custom ones (never collide).
            int displayHashId = (hashDigest.backend == HashBackend::kMbedtls)
                                     ? static_cast<int>(hashDigest.mbedtlsType)
                                     : (1000 + static_cast<int>(hashDigest.customId));
            progressCallback(attemptedCount.fetch_add(1) + 1, activeSlotsCount, displayHashId, 0);
        }

        // 1. Derive keyslot key
        std::vector<uint8_t> slotKey(keyBytes);
        if (!luksDeriveKdfKey(hashDigest, password, passwordLen, phdr.keySlots[i].salt, 32,
                              P.slotIterations[i], slotKey.data(), slotKey.size())) {
            return;
        }
        if (found.load(std::memory_order_acquire)) {
            mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
            return;
        }

        // 2. Read the AF key material (whole sectors, like cryptsetup).
        const size_t afLen = static_cast<size_t>(keyBytes) * kLuks1Stripes;
        const size_t afPadded = static_cast<size_t>(luks1SecsPerStripes(keyBytes)) * 512;
        std::vector<uint8_t> afMaterial(afPadded), afDecrypted(afPadded);
        bool ok = reader(static_cast<uint64_t>(P.slotOffset[i]) * 512, afMaterial.data(), afPadded);

        // 3. Decrypt it with the header's cipher (sector IVs count from 0 at
        // the start of this keyslot's material), 4. merge the stripes.
        std::vector<uint8_t> candidateKey(keyBytes);
        ok = ok && areaCrypt(P.cipherSpec, false, slotKey.data(), slotKey.size(),
                             afMaterial.data(), afDecrypted.data(), afPadded) &&
                   afMerge(hashDigest, keyBytes, kLuks1Stripes, afDecrypted.data(), candidateKey.data()) == 0;
        (void)afLen;

        // 5. Verify master key candidate
        bool verified = ok && luksVerifyMasterKey(hashDigest, candidateKey.data(), keyBytes,
                                                  phdr.mkDigestSalt, 32, P.mkDigestIter, phdr.mkDigest, 20);
        if (verified) {
            bool expected = false;
            if (found.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
                std::lock_guard<std::mutex> lock(resultMutex);
                resultMasterKey = candidateKey;
            }
        }

        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
        mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
        mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
    };

    if (activeSlotIndices.size() <= 1) {
        if (!activeSlotIndices.empty()) tryOneSlot(activeSlotIndices[0]);
    } else {
        std::vector<std::future<void>> futures;
        futures.reserve(activeSlotIndices.size());
        for (int i : activeSlotIndices) futures.push_back(ThreadPool::getInstance().enqueue(tryOneSlot, i));
        for (auto& f : futures) f.get();
    }

    if (!found.load(std::memory_order_acquire)) {
        if (cancelCheck && cancelCheck(volId)) {
            LOGI("LUKS1: Unlock cancelled");
        }
        return false;
    }

    fillLuks1Info(P, resultMasterKey, outInfo);
    mbedtls_platform_zeroize(resultMasterKey.data(), resultMasterKey.size());
    return true;
}

// ── LUKS2 metadata layer ─────────────────────────────────────────────────
//
// One implementation of "find and validate the LUKS2 metadata", shared by
// unlock, password change, integrity check/repair, probing and resize, so
// every code path agrees with cryptsetup (lib/luks2/luks2_disk_metadata.c):
//
//  * header size is whatever the primary header says (16 KiB .. 4 MiB, i.e.
//    --luks2-metadata-size), NOT a hard-coded 16 KiB;
//  * the checksum covers the 4096-byte binary header (csum zeroed) plus the
//    WHOLE JSON area (hdr_size - 4096 bytes);
//  * the secondary copy lives at offset == hdr_size; when the primary is
//    damaged, all nine legal secondary offsets are scanned;
//  * the valid copy with the greatest seqid wins (primary on a tie).

struct JsonDeleter { void operator()(cJSON* j) const { if (j) cJSON_Delete(j); } };
using JsonPtr = std::unique_ptr<cJSON, JsonDeleter>;

// ── JSON field helpers (strict: no clamping, no silent truncation) ──
static const cJSON* jget(const cJSON* o, const char* k) {
    return (o && cJSON_IsObject(o)) ? cJSON_GetObjectItemCaseSensitive(const_cast<cJSON*>(o), k) : nullptr;
}
static bool jsonStr(const cJSON* f, std::string& out) {
    if (!f || !cJSON_IsString(f) || !f->valuestring) return false;
    out = f->valuestring;
    return true;
}
static bool jsonU32(const cJSON* f, uint32_t& out) {
    if (!f || !cJSON_IsNumber(f)) return false;
    const double d = f->valuedouble;
    if (!(d >= 0.0 && d <= 4294967295.0) || d != std::floor(d)) return false;
    out = static_cast<uint32_t>(d);
    return true;
}
// LUKS2 stores sizes/offsets as decimal STRINGS (they exceed 2^53); numbers are
// accepted too when exactly representable.
static bool jsonU64(const cJSON* f, uint64_t& out) {
    if (!f) return false;
    if (cJSON_IsString(f) && f->valuestring) {
        const char* s = f->valuestring;
        if (!*s) return false;
        uint64_t v = 0;
        for (; *s; s++) {
            if (*s < '0' || *s > '9') return false;
            const uint64_t digit = static_cast<uint64_t>(*s - '0');
            if (v > (UINT64_MAX - digit) / 10) return false;
            v = v * 10 + digit;
        }
        out = v;
        return true;
    }
    if (cJSON_IsNumber(f)) {
        const double d = f->valuedouble;
        if (!(d >= 0.0 && d < 9007199254740992.0) || d != std::floor(d)) return false;
        out = static_cast<uint64_t>(d);
        return true;
    }
    return false;
}
static bool parseIndexKey(const char* key, int& out) {
    if (!key || !*key) return false;
    long v = 0;
    for (const char* p = key; *p; p++) {
        if (*p < '0' || *p > '9') return false;
        v = v * 10 + (*p - '0');
        if (v > 1000000) return false;
    }
    out = static_cast<int>(v);
    return true;
}

// ── Checksum ──
static bool luks2ComputeChecksum(const std::string& alg, const uint8_t* bin4096,
                                 const uint8_t* json, size_t jsonLen,
                                 uint8_t out[64], size_t& outLen) {
    const DigestSpec spec = resolveHashSpec(alg);
    if (spec.backend == HashBackend::kNone || spec.digestLen == 0 || spec.digestLen > 64) return false;
    uint8_t bin[kLuks2BinHdrSize];
    std::memcpy(bin, bin4096, sizeof(bin));
    std::memset(bin + 448, 0, 64);                       // csum field
    if (spec.backend == HashBackend::kMbedtls) {
        const mbedtls_md_info_t* info = mbedtls_md_info_from_type(spec.mbedtlsType);
        if (!info) return false;
        mbedtls_md_context_t ctx;
        mbedtls_md_init(&ctx);
        bool ok = mbedtls_md_setup(&ctx, info, 0) == 0 && mbedtls_md_starts(&ctx) == 0 &&
                  mbedtls_md_update(&ctx, bin, sizeof(bin)) == 0 &&
                  mbedtls_md_update(&ctx, json, jsonLen) == 0 && mbedtls_md_finish(&ctx, out) == 0;
        mbedtls_md_free(&ctx);
        if (!ok) return false;
    } else {
        // Custom hashes only offer a two-chunk one-shot; hash header||json in one buffer.
        std::vector<uint8_t> all(sizeof(bin) + jsonLen);
        std::memcpy(all.data(), bin, sizeof(bin));
        std::memcpy(all.data() + sizeof(bin), json, jsonLen);
        if (genericHashOneShot(spec.customId, all.data(), all.size(), nullptr, 0, out) == 0) return false;
    }
    outLen = spec.digestLen;
    return true;
}

struct Luks2Copy {
    bool magicOk = false;     // magic/version/hdr_offset/hdr_size are sane (location recognised)
    bool checksumOk = false;  // checksum over header + JSON area verifies
    bool ok = false;          // checksumOk && JSON parsed and structurally valid
    uint64_t offset = 0;
    uint64_t hdrSize = 0;
    uint64_t seqid = 0;
    std::vector<uint8_t> bin;   // 4096 bytes
    std::vector<uint8_t> json;  // hdrSize - 4096 bytes (raw, NUL padded)
    JsonPtr root;
};

struct Luks2Meta {
    Luks2Copy primary, secondary;
    const Luks2Copy* selected = nullptr;
};

// Structural checks every LUKS2 JSON area must pass (cryptsetup requires all
// five sections and a json_size matching the header).
static bool luks2ValidateTopLevel(const cJSON* root, uint64_t hdrSize) {
    for (const char* name : {"keyslots", "tokens", "segments", "digests", "config"}) {
        if (!cJSON_IsObject(jget(root, name))) return false;
    }
    const cJSON* config = jget(root, "config");
    uint64_t jsonSize = 0, keyslotsSize = 0;
    if (!jsonU64(jget(config, "json_size"), jsonSize) || jsonSize != hdrSize - kLuks2BinHdrSize) return false;
    if (!jsonU64(jget(config, "keyslots_size"), keyslotsSize) || keyslotsSize > kLuks2MaxKeyslotsSize) return false;
    return true;
}

static void luks2ReadCopy(const LuksByteReader& reader, uint64_t offset, bool secondary,
                          bool validateJson, Luks2Copy& c) {
    c = Luks2Copy();
    c.offset = offset;
    c.bin.assign(kLuks2BinHdrSize, 0);
    if (!reader(offset, c.bin.data(), kLuks2BinHdrSize)) return;
    const uint8_t* b = c.bin.data();

    const bool magicPrimary = std::memcmp(b, LUKS_MAGIC, 6) == 0;
    const bool magicSecondary = std::memcmp(b, LUKS2_SECONDARY_MAGIC, 6) == 0;
    // Earlier builds of this app wrote the primary magic into the secondary
    // copy; cryptsetup rejects that, but it still carries valid metadata.
    if (secondary ? !(magicSecondary || magicPrimary) : !magicPrimary) return;
    if (readBE16(b + 6) != 2) return;
    c.hdrSize = readBE64(b + 8);
    c.seqid = readBE64(b + 16);
    if (c.hdrSize < kLuks2HdrSizeMin || c.hdrSize > kLuks2HdrSizeMax) return;
    if (readBE64(b + 256) != offset) return;              // hdr_offset must equal where it lives
    if (secondary ? offset != c.hdrSize : offset != 0) return;
    c.magicOk = true;

    const size_t jsonLen = static_cast<size_t>(c.hdrSize - kLuks2BinHdrSize);
    c.json.assign(jsonLen, 0);
    if (!reader(offset + kLuks2BinHdrSize, c.json.data(), jsonLen)) return;

    const std::string alg = fixedCString(reinterpret_cast<const char*>(b + 72), 32);
    uint8_t calc[64];
    size_t calcLen = 0;
    if (!luks2ComputeChecksum(alg, b, c.json.data(), jsonLen, calc, calcLen)) return;
    if (std::memcmp(calc, b + 448, calcLen) != 0) return;
    c.checksumOk = true;

    if (!validateJson) { c.ok = true; return; }

    const void* nul = std::memchr(c.json.data(), 0, jsonLen);
    if (!nul) return;                                     // JSON must be NUL terminated inside its area
    c.root.reset(cJSON_ParseWithOpts(reinterpret_cast<const char*>(c.json.data()), nullptr, 0));
    if (!c.root || !luks2ValidateTopLevel(c.root.get(), c.hdrSize)) { c.root.reset(); return; }
    c.ok = true;
}

static bool luks2LoadMeta(const LuksByteReader& reader, Luks2Meta& m, bool validateJson = true) {
    m = Luks2Meta();
    luks2ReadCopy(reader, 0, false, validateJson, m.primary);

    std::vector<uint64_t> candidates;
    if (m.primary.magicOk) candidates.push_back(m.primary.hdrSize);   // authoritative when readable
    for (uint64_t off : kLuks2SecondaryOffsets) {
        if (std::find(candidates.begin(), candidates.end(), off) == candidates.end()) candidates.push_back(off);
    }
    // A healthy primary tells us exactly where the secondary is; only scan the
    // whole list when the primary is unusable (same as cryptsetup).
    const size_t limit = m.primary.ok ? 1 : candidates.size();
    for (size_t i = 0; i < limit; i++) {
        Luks2Copy c;
        luks2ReadCopy(reader, candidates[i], true, validateJson, c);
        const bool better = c.ok || (c.checksumOk && !m.secondary.ok) || (c.magicOk && !m.secondary.magicOk);
        if (better) m.secondary = std::move(c);
        if (m.secondary.ok) break;
    }

    const Luks2Copy& p = m.primary;
    const Luks2Copy& s = m.secondary;
    if (p.ok && s.ok) m.selected = (s.seqid > p.seqid) ? &s : &p;
    else if (p.ok) m.selected = &p;
    else if (s.ok) m.selected = &s;
    return m.selected != nullptr;
}

// ── Parsed LUKS2 objects ─────────────────────────────────────────────────

struct Luks2Keyslot {
    Luks2KeyslotInfo info;      // info.areaKeySize = AREA key size; info.afStripes is the effective 4000
    uint32_t volumeKeySize = 0; // size of the key stored in the keyslot ("key_size" of the keyslot itself)
    int priority = 1;           // 0 ignore, 1 normal, 2 prefer
    DigestSpec kdfHash;
    DigestSpec afHash;
    LuksCipherSpec areaSpec;
    size_t afPadded = 0;        // AF bytes rounded up to whole sectors (what cryptsetup reads/writes)
};

struct Luks2Digest {
    Luks2DigestInfo info;
    DigestSpec hash;
};

static bool luks2ParseKeyslot(const cJSON* item, uint64_t hdrSize, uint64_t keyslotsEnd, Luks2Keyslot& ks) {
    if (!item || !item->string || !parseIndexKey(item->string, ks.info.index)) return false;
    std::string type;
    if (!jsonStr(jget(item, "type"), type) || type != "luks2") return false;

    // The volume key stored in the slot and the key that encrypts the slot's
    // area are two different things (they differ for e.g. aes-cbc-essiv:sha256
    // with a 256-bit volume key and the default 512-bit aes-xts-plain64 area).
    uint32_t keySize = 0;
    if (!jsonU32(jget(item, "key_size"), keySize) || keySize == 0 || keySize > kLuksMaxKeyBytes) return false;
    ks.volumeKeySize = keySize;

    uint32_t prio = 1;
    if (jget(item, "priority") && (!jsonU32(jget(item, "priority"), prio) || prio > 2)) return false;
    ks.priority = static_cast<int>(prio);

    const cJSON* kdf = jget(item, "kdf");
    const cJSON* af = jget(item, "af");
    const cJSON* area = jget(item, "area");
    if (!kdf || !af || !area) return false;

    std::string saltB64;
    if (!jsonStr(jget(kdf, "type"), ks.info.kdfType) || !jsonStr(jget(kdf, "salt"), saltB64)) return false;
    ks.info.salt = base64Decode(saltB64);
    if (ks.info.salt.size() != 32) return false;          // LUKS_SALTSIZE: cryptsetup requires exactly 32
    if (ks.info.kdfType == "pbkdf2") {
        if (!jsonStr(jget(kdf, "hash"), ks.info.hashName) || !jsonU32(jget(kdf, "iterations"), ks.info.iterations) ||
            ks.info.iterations == 0)
            return false;
        ks.kdfHash = resolveHashSpec(ks.info.hashName);
        if (ks.kdfHash.backend == HashBackend::kNone) return false;
    } else if (ks.info.kdfType == "argon2i" || ks.info.kdfType == "argon2id") {
        if (!jsonU32(jget(kdf, "time"), ks.info.iterations) || ks.info.iterations == 0 ||
            !jsonU32(jget(kdf, "memory"), ks.info.memory) ||
            !jsonU32(jget(kdf, "cpus"), ks.info.parallelism) || ks.info.parallelism == 0)
            return false;
        if (ks.info.memory < 8ull * ks.info.parallelism) return false;
    } else {
        return false;
    }

    // cryptsetup ignores "af.stripes" when opening and always uses 4000.
    std::string afType;
    if (!jsonStr(jget(af, "type"), afType) || afType != "luks1" || !jsonStr(jget(af, "hash"), ks.info.afHash)) return false;
    ks.afHash = resolveHashSpec(ks.info.afHash);
    if (ks.afHash.backend == HashBackend::kNone) return false;
    ks.info.afStripes = static_cast<int>(kLuks2AfStripes);
    ks.afPadded = static_cast<size_t>(luks1SecsPerStripes(keySize)) * 512;

    std::string areaType;
    if (!jsonStr(jget(area, "type"), areaType) || areaType != "raw") return false;
    if (!jsonU64(jget(area, "offset"), ks.info.areaOffset) || !jsonU64(jget(area, "size"), ks.info.areaSize)) return false;
    if (!jsonStr(jget(area, "encryption"), ks.info.areaEncryption) || !jsonU32(jget(area, "key_size"), ks.info.areaKeySize)) return false;
    if (ks.info.areaKeySize == 0 || ks.info.areaKeySize > kLuksMaxKeyBytes) return false;
    if (!luksParseCipherString(ks.info.areaEncryption, ks.info.areaKeySize, ks.areaSpec)) return false;

    // Area must hold the AF material and lie inside the keyslots region.
    const uint64_t off = ks.info.areaOffset, size = ks.info.areaSize;
    if (size < ks.afPadded || size > kLuks2MaxKeyslotsSize) return false;
    if (off < 2 * hdrSize || off > UINT64_MAX - size) return false;
    if (keyslotsEnd != 0 && off + size > keyslotsEnd) return false;
    return true;
}

static bool luks2ParseDigest(const cJSON* item, Luks2Digest& d) {
    if (!item || !item->string) return false;
    std::string type, saltB64, digB64;
    if (!jsonStr(jget(item, "type"), type) || type != "pbkdf2") return false;
    d.info.type = type;
    if (!jsonStr(jget(item, "hash"), d.info.hashName) || !jsonU32(jget(item, "iterations"), d.info.iterations) ||
        d.info.iterations == 0 || !jsonStr(jget(item, "salt"), saltB64) || !jsonStr(jget(item, "digest"), digB64))
        return false;
    d.hash = resolveHashSpec(d.info.hashName);
    if (d.hash.backend == HashBackend::kNone) return false;
    d.info.salt = base64Decode(saltB64);
    d.info.digest = base64Decode(digB64);
    if (d.info.salt.size() != 32 || d.info.digest.empty() || d.info.digest.size() > 128) return false;
    for (const char* listName : {"keyslots", "segments"}) {
        const cJSON* arr = jget(item, listName);
        if (!arr || !cJSON_IsArray(arr)) continue;
        for (const cJSON* e = arr->child; e; e = e->next) {
            int v;
            if (cJSON_IsString(e) && parseIndexKey(e->valuestring, v))
                (listName[0] == 'k' ? d.info.keyslots : d.info.segments).push_back(v);
        }
    }
    return true;
}

// The data segment cryptsetup mounts: segment "0" (CRYPT_DEFAULT_SEGMENT), or
// the lowest-numbered one when "0" is absent. (JSON object order is NOT
// numeric order, so never just take the first child.)
static const cJSON* luks2PickDataSegment(const cJSON* root, int& indexOut, uint32_t& countOut) {
    const cJSON* segs = jget(root, "segments");
    const cJSON* best = nullptr;
    int bestIdx = INT32_MAX;
    countOut = 0;
    for (const cJSON* s = segs ? segs->child : nullptr; s; s = s->next) {
        countOut++;
        int idx;
        if (!parseIndexKey(s->string, idx)) continue;
        if (idx < bestIdx) { bestIdx = idx; best = s; }
    }
    indexOut = best ? bestIdx : -1;
    return best;
}

static bool luks2ParseSegment(const cJSON* root, Luks2SegmentInfo& seg, uint32_t& count, int& segIndex) {
    const cJSON* s = luks2PickDataSegment(root, segIndex, count);
    if (!s) return false;
    std::string type;
    seg.isCryptSegment = jsonStr(jget(s, "type"), type) && type == "crypt";
    // These change how the data area is interpreted or mark an operation/layout
    // this app does not implement; preserve them so callers can refuse safely.
    seg.hasIntegrity = jget(s, "integrity") != nullptr;
    seg.hasFlags = jget(s, "flags") != nullptr;
    const cJSON* req = jget(jget(root, "config"), "requirements");
    const cJSON* mandatory = jget(req, "mandatory");
    seg.hasMandatoryRequirements = mandatory && (!cJSON_IsArray(mandatory) || mandatory->child != nullptr);

    jsonStr(jget(s, "encryption"), seg.encryption);
    uint64_t v = 0;
    if (!jsonU64(jget(s, "offset"), seg.offset)) return false;
    uint32_t ss = 0;
    if (!jsonU32(jget(s, "sector_size"), ss) || ss < 512 || ss > 4096 || (ss & (ss - 1)) != 0) return false;
    seg.sectorSize = ss;
    if (!jsonU64(jget(s, "iv_tweak"), seg.ivTweak)) return false;
    std::string size;
    if (!jsonStr(jget(s, "size"), size)) return false;
    if (size == "dynamic") {
        seg.dynamicSize = true;
    } else if (jsonU64(jget(s, "size"), v) && v > 0) {
        seg.sizeBytes = v;
        seg.dynamicSize = false;
    } else {
        return false;
    }
    return true;
}

struct Luks2Parsed {
    const Luks2Copy* copy = nullptr;
    Luks2SegmentInfo seg;
    uint32_t segCount = 0;
    int segIndex = 0;
    std::vector<Luks2Digest> digests;
    std::vector<Luks2Keyslot> keyslots;  // usable keyslots, "prefer" first; "ignore" slots excluded
};

static bool luks2ParseAll(const Luks2Copy& copy, Luks2Parsed& L) {
    L = Luks2Parsed();
    L.copy = &copy;
    const cJSON* root = copy.root.get();
    if (!luks2ParseSegment(root, L.seg, L.segCount, L.segIndex)) {
        LOGI("LUKS2: missing or invalid segment size/offset/sector_size/iv_tweak metadata");
        return false;
    }
    for (const cJSON* d = jget(root, "digests")->child; d; d = d->next) {
        Luks2Digest dg;
        if (luks2ParseDigest(d, dg)) L.digests.push_back(std::move(dg));
    }
    uint64_t keyslotsSize = 0;
    jsonU64(jget(jget(root, "config"), "keyslots_size"), keyslotsSize);
    const uint64_t keyslotsEnd = 2 * copy.hdrSize + keyslotsSize;
    for (const cJSON* k = jget(root, "keyslots")->child; k; k = k->next) {
        Luks2Keyslot ks;
        if (luks2ParseKeyslot(k, copy.hdrSize, keyslotsEnd, ks)) L.keyslots.push_back(std::move(ks));
        else LOGI("LUKS2: ignoring keyslot %s (unsupported or invalid)", k->string ? k->string : "?");
    }
    // cryptsetup tries "prefer" slots first and never tries "ignore" slots
    // unless one is named explicitly (--key-slot), which this API cannot do.
    L.keyslots.erase(std::remove_if(L.keyslots.begin(), L.keyslots.end(),
                                    [](const Luks2Keyslot& k) { return k.priority == 0; }),
                     L.keyslots.end());
    std::stable_sort(L.keyslots.begin(), L.keyslots.end(),
                     [](const Luks2Keyslot& a, const Luks2Keyslot& b) { return a.priority > b.priority; });
    return true;
}

// The digest that authenticates keyslot [slotIndex] for the data segment:
// must list the keyslot; prefer one that also lists the segment.
static const Luks2Digest* luks2DigestForKeyslot(const Luks2Parsed& L, int slotIndex) {
    const Luks2Digest* fallback = nullptr;
    for (const auto& d : L.digests) {
        if (std::find(d.info.keyslots.begin(), d.info.keyslots.end(), slotIndex) == d.info.keyslots.end()) continue;
        if (d.info.segments.empty() ||
            std::find(d.info.segments.begin(), d.info.segments.end(), L.segIndex) != d.info.segments.end())
            return &d;
        if (!fallback) fallback = &d;
    }
    return fallback;
}

static void luks2FillInfo(const Luks2Parsed& L, uint32_t keyBytes, const uint8_t* masterKey, size_t masterKeyLen,
                          LuksVolumeInfo& out) {
    out.version = 2;
    const size_t dash = L.seg.encryption.find('-');
    if (dash != std::string::npos) {
        out.cipherName = L.seg.encryption.substr(0, dash);
        out.cipherMode = L.seg.encryption.substr(dash + 1);
    } else {
        out.cipherName = "aes";
        out.cipherMode = "xts-plain64";
    }
    out.keyBytes = keyBytes;
    out.dataOffsetBytes = L.seg.offset;
    out.dataSectorSize = L.seg.sectorSize;
    out.dataSizeBytes = L.seg.sizeBytes;
    out.dynamicSize = L.seg.dynamicSize;
    out.dataSegmentCount = L.segCount;
    out.dataIsCryptSegment = L.seg.isCryptSegment;
    out.ivTweak = L.seg.ivTweak;
    out.dataHasIntegrity = L.seg.hasIntegrity;
    out.dataSegmentHasFlags = L.seg.hasFlags;
    out.hasMandatoryRequirements = L.seg.hasMandatoryRequirements;
    out.masterKey.assign(masterKey, masterKey + masterKeyLen);
}

// Derives the area key for [ks] from [password]; false on failure/cancel/unsupported cost.
static bool luks2DeriveAreaKey(const Luks2Keyslot& ks, const uint8_t* password, size_t passwordLen,
                               std::vector<uint8_t>& out, const std::function<bool()>& cancel) {
    const Luks2KeyslotInfo& i = ks.info;
    out.assign(i.areaKeySize, 0);
    if (i.kdfType == "pbkdf2")
        return luksDeriveKdfKey(ks.kdfHash, password, passwordLen, i.salt.data(), i.salt.size(), i.iterations,
                                out.data(), out.size());
    if (i.memory > kMaxArgon2MemoryKiB) {
        // Previously clamped, which silently derived the WRONG key (the slot then
        // looked like a wrong password). Skip it instead.
        LOGI("LUKS2: keyslot %d needs %u KiB of Argon2 memory (> %u KiB supported); skipped",
             i.index, i.memory, kMaxArgon2MemoryKiB);
        return false;
    }
    return i.kdfType == "argon2id"
        ? argon2idDeriveKey(password, passwordLen, i.salt.data(), i.salt.size(), i.memory, i.iterations,
                            i.parallelism, out.data(), out.size(), cancel)
        : argon2iDeriveKey(password, passwordLen, i.salt.data(), i.salt.size(), i.memory, i.iterations,
                           i.parallelism, out.data(), out.size(), cancel);
}

// Runs one keyslot: KDF -> read area -> decrypt -> AF merge -> digest check.
static bool luks2OpenKeyslot(const LuksByteReader& reader, const Luks2Parsed& L, const Luks2Keyslot& ks,
                             const Luks2Digest& digest, const uint8_t* password, size_t passwordLen,
                             const std::function<bool()>& cancel, std::vector<uint8_t>& masterKeyOut) {
    std::vector<uint8_t> areaKey;
    if (!luks2DeriveAreaKey(ks, password, passwordLen, areaKey, cancel)) return false;
    if (cancel && cancel()) { mbedtls_platform_zeroize(areaKey.data(), areaKey.size()); return false; }

    std::vector<uint8_t> afMaterial(ks.afPadded), afDecrypted(ks.afPadded);
    std::vector<uint8_t> candidate(ks.volumeKeySize);
    bool ok = reader(ks.info.areaOffset, afMaterial.data(), ks.afPadded) &&
              areaCrypt(ks.areaSpec, false, areaKey.data(), areaKey.size(),
                        afMaterial.data(), afDecrypted.data(), ks.afPadded) &&
              afMerge(ks.afHash, ks.volumeKeySize, kLuks2AfStripes, afDecrypted.data(), candidate.data()) == 0 &&
              luksVerifyMasterKey(digest.hash, candidate.data(), candidate.size(), digest.info.salt.data(),
                                  digest.info.salt.size(), digest.info.iterations, digest.info.digest.data(),
                                  digest.info.digest.size());
    if (ok) masterKeyOut = candidate;
    mbedtls_platform_zeroize(areaKey.data(), areaKey.size());
    mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
    mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
    mbedtls_platform_zeroize(candidate.data(), candidate.size());
    (void)L;
    return ok;
}

// ── LUKS2 Unlocking ─────────────────────────────────────────────────────────

static bool luks2Unlock(const LuksByteReader& reader,
                        const uint8_t* password, size_t passwordLen,
                        LuksVolumeInfo& outInfo,
                        int volId,
                        std::function<bool(int)> cancelCheck,
                        std::function<void(int, int, int, int)> progressCallback,
                        const uint8_t* candidateMasterKey = nullptr,
                        size_t candidateMasterKeyLen = 0) {
    LOGI("LUKS2: Starting unlock...");
    Luks2Meta meta;
    if (!luks2LoadMeta(reader, meta)) {
        LOGI("LUKS2: no valid metadata copy");
        return false;
    }
    Luks2Parsed L;
    if (!luks2ParseAll(*meta.selected, L)) return false;

    // ── Fast path: verify a cached master key against whichever digest
    // covers the data segment (LUKS2 keys the master key to a digest). ──
    if (candidateMasterKey != nullptr) {
        for (const auto& d : L.digests) {
            if (!d.info.segments.empty() &&
                std::find(d.info.segments.begin(), d.info.segments.end(), L.segIndex) == d.info.segments.end())
                continue;
            if (luksVerifyMasterKey(d.hash, candidateMasterKey, candidateMasterKeyLen, d.info.salt.data(),
                                    d.info.salt.size(), d.info.iterations, d.info.digest.data(),
                                    d.info.digest.size())) {
                luks2FillInfo(L, static_cast<uint32_t>(candidateMasterKeyLen), candidateMasterKey,
                              candidateMasterKeyLen, outInfo);
                LOGI("LUKS2: quick-unlock candidate key verified");
                return true;
            }
        }
        LOGI("LUKS2: quick-unlock candidate key stale/invalid");
        return false; // caller falls back to password/keyfile
    }

    const int activeSlotsCount = static_cast<int>(L.keyslots.size());
    std::atomic<bool> found{false};
    std::atomic<int> attemptedCount{0};
    std::mutex resultMutex;
    std::vector<uint8_t> resultKey;

    auto tryOneKeyslot = [&](size_t idx) {
        const Luks2Keyslot& ks = L.keyslots[idx];
        if (found.load(std::memory_order_acquire) || (cancelCheck && cancelCheck(volId))) return;
        const Luks2Digest* digest = luks2DigestForKeyslot(L, ks.info.index);
        if (!digest) return;

        if (progressCallback) {
            const DigestSpec& hs = (ks.info.kdfType == "pbkdf2") ? ks.kdfHash : ks.afHash;
            int displayHashId = (hs.backend == HashBackend::kMbedtls)
                                     ? static_cast<int>(hs.mbedtlsType)
                                     : (1000 + static_cast<int>(hs.customId));
            progressCallback(attemptedCount.fetch_add(1) + 1, activeSlotsCount, displayHashId, 1);
        }
        // Argon2 can run for a long time: stop it on user cancel and when a
        // sibling keyslot has already verified.
        auto cancel = [&found, &cancelCheck, volId]() -> bool {
            return found.load(std::memory_order_acquire) || (cancelCheck && cancelCheck(volId));
        };
        std::vector<uint8_t> key;
        if (luks2OpenKeyslot(reader, L, ks, *digest, password, passwordLen, cancel, key)) {
            bool expected = false;
            if (found.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
                std::lock_guard<std::mutex> lock(resultMutex);
                resultKey = key;
            }
        }
        mbedtls_platform_zeroize(key.data(), key.size());
    };

    if (L.keyslots.size() <= 1) {
        if (!L.keyslots.empty()) tryOneKeyslot(0);
    } else {
        std::vector<std::future<void>> futures;
        futures.reserve(L.keyslots.size());
        for (size_t idx = 0; idx < L.keyslots.size(); idx++)
            futures.push_back(ThreadPool::getInstance().enqueue(tryOneKeyslot, idx));
        for (auto& f : futures) f.get();
    }

    const bool unlocked = found.load(std::memory_order_acquire);
    if (unlocked) {
        luks2FillInfo(L, static_cast<uint32_t>(resultKey.size()), resultKey.data(), resultKey.size(), outInfo);
        mbedtls_platform_zeroize(resultKey.data(), resultKey.size());
    } else if (cancelCheck && cancelCheck(volId)) {
        LOGI("LUKS2: Unlock cancelled");
    }
    LOGI("LUKS2: Unlock finished. Success=%d", unlocked);
    return unlocked;
}

// ── Main Entry Point ────────────────────────────────────────────────────────

bool luksRecoverMasterKey(const LuksByteReader& reader,
                          const uint8_t* password,
                          size_t passwordLen,
                          LuksVolumeInfo& outInfo,
                          int volId,
                          std::function<bool(int)> cancelCheck,
                          std::function<void(int, int, int, int)> progressCallback,
                          const uint8_t* candidateMasterKey,
                          size_t candidateMasterKeyLen) {
    if (!reader) return false;
    if (!password && !candidateMasterKey) return false;

    // The primary header's magic + version pick the path. If the primary is
    // damaged (no magic / unreadable version) LUKS2 can still be recovered
    // from its secondary copy, so fall through to the LUKS2 path, which
    // validates every candidate copy itself and fails cleanly on non-LUKS data.
    uint8_t head[8];
    if (reader(0, head, sizeof(head)) && std::memcmp(head, LUKS_MAGIC, 6) == 0 &&
        ((uint16_t(head[6]) << 8) | head[7]) == 1) {
        LOGI("luksRecoverMasterKey: detected LUKS1 container");
        return luks1Unlock(reader, password, passwordLen, outInfo, volId, cancelCheck, progressCallback,
                            candidateMasterKey, candidateMasterKeyLen);
    }
    LOGI("luksRecoverMasterKey: trying LUKS2 metadata");
    return luks2Unlock(reader, password, passwordLen, outInfo, volId, cancelCheck, progressCallback,
                        candidateMasterKey, candidateMasterKeyLen);
}

bool luksRecoverMasterKey(int fd,
                          const uint8_t* password,
                          size_t passwordLen,
                          LuksVolumeInfo& outInfo,
                          int volId,
                          std::function<bool(int)> cancelCheck,
                          std::function<void(int, int, int, int)> progressCallback,
                          const uint8_t* candidateMasterKey,
                          size_t candidateMasterKeyLen) {
    if (fd < 0) return false;
    LuksByteReader reader = [fd](uint64_t offset, void* outData, size_t len) -> bool {
        return pread(fd, outData, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
    };
    return luksRecoverMasterKey(reader, password, passwordLen, outInfo, volId,
                                std::move(cancelCheck), std::move(progressCallback),
                                candidateMasterKey, candidateMasterKeyLen);
}


// ── Container creation ──────────────────────────────────────────────────

// ── Small helpers shared by both LUKS1 and LUKS2 creation ──────────────

// /dev/urandom, enriched with user-collected entropy when the JNI entry point
// installed some for this thread (crypto/user_entropy.h). Covers the master
// key, the digest/keyslot salts, the anti-forensic split material and the
// UUID of a new LUKS container.
static bool randomBytes(uint8_t* buf, size_t len) {
    return userentropy::fillRandom(buf, len);
}

static std::string generateUuidV4() {
    uint8_t raw[16] = {0};
    randomBytes(raw, sizeof(raw));
    raw[6] = (raw[6] & 0x0F) | 0x40; // version 4
    raw[8] = (raw[8] & 0x3F) | 0x80; // variant 10xx
    char buf[37];
    std::snprintf(buf, sizeof(buf),
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
        raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]);
    return std::string(buf);
}

static std::string base64Encode(const uint8_t* data, size_t len) {
    size_t olen = 0;
    mbedtls_base64_encode(nullptr, 0, &olen, data, len);
    std::string out(olen, '\0');
    size_t actual = 0;
    if (mbedtls_base64_encode(reinterpret_cast<unsigned char*>(&out[0]), out.size(), &actual, data, len) != 0) {
        return std::string();
    }
    out.resize(actual);
    return out;
}

static void writeBE16(uint8_t* p, uint16_t v) {
    p[0] = (v >> 8) & 0xFF; p[1] = v & 0xFF;
}
static void writeBE32(uint8_t* p, uint32_t v) {
    p[0] = (v >> 24) & 0xFF; p[1] = (v >> 16) & 0xFF; p[2] = (v >> 8) & 0xFF; p[3] = v & 0xFF;
}
static void writeBE64(uint8_t* p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (v >> (56 - i * 8)) & 0xFF;
}

// Anti-forensic split — the inverse of afMerge() above. Fills the
// stripes*keySize-byte output with stripes-1 random blocks followed by a
// final block chosen so that afMerge(afSplit(masterKey)) == masterKey:
// afMerge folds src[0..stripes-2] through the same running
// XOR-then-diffuse "block" accumulator computed here, so setting
// dst[stripes-1] = masterKey XOR block reproduces masterKey exactly once
// merged back.
static int afSplit(const DigestSpec& spec, size_t keySize, uint32_t stripes,
                   const uint8_t* masterKey, uint8_t* dst) {
    if (stripes == 0) return -1;
    std::unique_ptr<uint8_t[]> block(new uint8_t[keySize]());

    if (stripes > 1) {
        const size_t randLen = (size_t)(stripes - 1) * keySize;
        if (!randomBytes(dst, randLen)) return -1;
        for (uint32_t i = 0; i < stripes - 1; i++) {
            afXor(keySize, dst + (size_t)i * keySize, block.get(), block.get());
            if (afDiffuse(spec, keySize, block.get()) < 0) return -1;
        }
    }
    afXor(keySize, masterKey, block.get(), dst + (size_t)(stripes - 1) * keySize);
    mbedtls_platform_zeroize(block.get(), keySize);
    return 0;
}


static bool luks1CreateHeader(const LuksByteWriter& writer, const uint8_t* password, size_t passwordLen,
                              int64_t sizeBytes, const LuksCreateParams& params,
                              LuksVolumeInfo& outInfo) {
    CascadeId dataCipherId;
    if (!cascadeIdForCipherName(params.cipherName, dataCipherId)) {
        LOGI("luks1CreateHeader: unsupported cipher %s", params.cipherName.c_str());
        return false;
    }
    mbedtls_md_type_t mdType = mapHashSpec(params.hashName);
    if (mdType == MBEDTLS_MD_NONE) {
        LOGI("luks1CreateHeader: unsupported hash %s", params.hashName.c_str());
        return false;
    }
    DigestSpec hashDigest = digestSpecForMbedtls(mdType);

    constexpr uint32_t keyBytes = 64; // *-xts-plain64, 512-bit key (32B data + 32B tweak) — all 5 supported ciphers
    const uint64_t slot0Offset = kLuks1AlignBytes; // 8 sectors in
    const uint64_t afMaterialLen = (uint64_t)keyBytes * kLuks1Stripes; // 256000 bytes, 500 sectors
    // cryptsetup 4096-aligns every keyslot area (504 sectors for a 512-bit key); keep the
    // same layout so slots 1..7 sit where cryptsetup expects them.
    const uint64_t afReservedLen = ((afMaterialLen + kLuks1AlignBytes - 1) / kLuks1AlignBytes) * kLuks1AlignBytes;
    
    // We must reserve space for all 8 contiguous keyslots (even if disabled)
    // so that payloadOffsetBytes starts safely after keyslot 7's ending sector.
    uint64_t payloadOffsetBytes = slot0Offset + 8 * afReservedLen;
    payloadOffsetBytes = ((payloadOffsetBytes + kLuks1PayloadAlign - 1) / kLuks1PayloadAlign) * kLuks1PayloadAlign;

    if (sizeBytes <= 0 || (uint64_t)sizeBytes <= payloadOffsetBytes + kLuksMinExtraSpace) {
        LOGI("luks1CreateHeader: sizeBytes too small for header+keyslot+filesystem");
        return false;
    }

    uint8_t masterKey[keyBytes];
    uint8_t mkDigestSalt[32];
    uint8_t keyslotSalt[32];
    if (!randomBytes(masterKey, sizeof(masterKey)) ||
        !randomBytes(mkDigestSalt, sizeof(mkDigestSalt)) ||
        !randomBytes(keyslotSalt, sizeof(keyslotSalt))) {
        LOGI("luks1CreateHeader: urandom read failed");
        return false;
    }

    uint8_t mkDigest[20];
    if (!luksDeriveKdfKey(hashDigest, masterKey, keyBytes, mkDigestSalt, sizeof(mkDigestSalt),
                              kLuks1MkDigestIter, mkDigest, sizeof(mkDigest))) {
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    // Keyslot PBKDF2 iteration count is the security-critical one (what an
    // attacker has to redo per password guess) — always caller-supplied,
    // see the argon2ParamsForPim()/iterationsForHash() callers in
    // container_create.cpp's createLuksContainer().
    std::vector<uint8_t> slotKey(keyBytes);
    if (!luksDeriveKdfKey(hashDigest, password, passwordLen, keyslotSalt, sizeof(keyslotSalt),
                              params.pbkdf2Iterations, slotKey.data(), slotKey.size())) {
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    std::vector<uint8_t> afMaterial(afMaterialLen);
    if (afSplit(hashDigest, keyBytes, kLuks1Stripes, masterKey, afMaterial.data()) != 0) {
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        return false;
    }

    // Keyslot AF material uses the SAME cipher as the data area, in
    // single-layer XTS with sector tweaks counted from 0 at the start of
    // the AF area — matching real LUKS1's keyslot encryption convention.
    // (Previously hardcoded to AES-CBC-plain(IV=0) regardless of
    // cipherName, which both mismatched the spec and produced containers
    // that non-AES ciphers could never actually be unlocked again with.)
    std::vector<uint8_t> afEncrypted(afMaterialLen);
    {
        const bool cryptOk = keyslotAreaCrypt(dataCipherId, true, slotKey.data(), slotKey.size(),
                                              afMaterial.data(), afEncrypted.data(), afMaterialLen);
        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
        if (!cryptOk) {
            LOGI("luks1CreateHeader: keyslot AF encryption failed");
            mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
            return false;
        }
    }

    if (!writer(slot0Offset, afEncrypted.data(), afEncrypted.size())) {
        LOGI("luks1CreateHeader: keyslot write failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    Luks1Phdr phdr;
    std::memset(&phdr, 0, sizeof(phdr));
    std::memcpy(phdr.magic, LUKS_MAGIC, 6);
    writeBE16((uint8_t*)&phdr.version, 1);
    std::strncpy(phdr.cipherName, params.cipherName.c_str(), sizeof(phdr.cipherName) - 1);
    std::strncpy(phdr.cipherMode, "xts-plain64", sizeof(phdr.cipherMode) - 1);
    std::strncpy(phdr.hashSpec, params.hashName.c_str(), sizeof(phdr.hashSpec) - 1);
    writeBE32((uint8_t*)&phdr.payloadOffset, (uint32_t)(payloadOffsetBytes / 512));
    writeBE32((uint8_t*)&phdr.keyBytes, keyBytes);
    std::memcpy(phdr.mkDigest, mkDigest, sizeof(mkDigest));
    std::memcpy(phdr.mkDigestSalt, mkDigestSalt, sizeof(mkDigestSalt));
    writeBE32((uint8_t*)&phdr.mkDigestIter, kLuks1MkDigestIter);
    std::string uuid = generateUuidV4();
    std::strncpy(phdr.uuid, uuid.c_str(), sizeof(phdr.uuid) - 1);

    // Initialize all 8 keyslots. Linux cryptsetup checks stripes and keyMaterialOffset 
    // unconditionally for ALL slots, even inactive ones. If we leave them zeroed, 
    // it triggers invalid stripes or invalid offset errors and rejects the entire header.
    for (int i = 0; i < 8; i++) {
        uint64_t slotOffset = slot0Offset + i * afReservedLen;
        writeBE32((uint8_t*)&phdr.keySlots[i].active, i == 0 ? 0x00AC71F3 : 0x0000DEAD);
        writeBE32((uint8_t*)&phdr.keySlots[i].iterations, i == 0 ? params.pbkdf2Iterations : 0);
        writeBE32((uint8_t*)&phdr.keySlots[i].keyMaterialOffset, (uint32_t)(slotOffset / 512));
        writeBE32((uint8_t*)&phdr.keySlots[i].stripes, kLuks1Stripes);
        
        if (i == 0) {
            std::memcpy(phdr.keySlots[0].salt, keyslotSalt, sizeof(keyslotSalt));
        } else {
            std::memset(phdr.keySlots[i].salt, 0, 32);
        }
    }

    if (!writer(0, &phdr, sizeof(phdr))) {
        LOGI("luks1CreateHeader: phdr write failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    outInfo.version = 1;
    outInfo.cipherName = params.cipherName;
    outInfo.cipherMode = "xts-plain64";
    outInfo.keyBytes = keyBytes;
    outInfo.dataOffsetBytes = payloadOffsetBytes;
    outInfo.dataSectorSize = 512;
    outInfo.ivTweak = 0;
    outInfo.masterKey.assign(masterKey, masterKey + keyBytes);
    mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
    LOGI("luks1CreateHeader: created, dataOffset=%llu", (unsigned long long)payloadOffsetBytes);
    return true;
}


static bool luks2CreateHeader(const LuksByteWriter& writer, const uint8_t* password, size_t passwordLen,
                              int64_t sizeBytes, const LuksCreateParams& params,
                              LuksVolumeInfo& outInfo) {

    CascadeId unusedDataCipherId;
    if (!cascadeIdForCipherName(params.cipherName, unusedDataCipherId)) {
        LOGI("luks2CreateHeader: unsupported cipher %s", params.cipherName.c_str());
        return false;
    }
    mbedtls_md_type_t digestMd = mapHashSpec(params.hashName);
    if (digestMd == MBEDTLS_MD_NONE) {
        LOGI("luks2CreateHeader: unsupported hash %s", params.hashName.c_str());
        return false;
    }
    DigestSpec digestSpec = digestSpecForMbedtls(digestMd);

    constexpr uint32_t keyBytes = 64;           // *-xts-plain64, 512-bit key — all 5 supported ciphers
    constexpr uint32_t keyslotAreaKeyBytes = 64; // keyslot area is always AES-XTS — see doc comment

    const uint64_t keyslotAreaOffset = kLuks2HeadersTotal; // single keyslot, right after both header copies
    const uint64_t afMaterialLen = (uint64_t)keyBytes * kLuks2AfStripes; // 256000 bytes, 500 sectors
    const uint64_t afReservedLen = ((afMaterialLen + kLuks2KeyslotAlign - 1) / kLuks2KeyslotAlign) * kLuks2KeyslotAlign;
    uint64_t dataOffsetBytes = keyslotAreaOffset + afReservedLen;
    dataOffsetBytes = ((dataOffsetBytes + kLuks2DataAlign - 1) / kLuks2DataAlign) * kLuks2DataAlign;

    if (sizeBytes <= 0 || (uint64_t)sizeBytes <= dataOffsetBytes + kLuksMinExtraSpace) {
        LOGI("luks2CreateHeader: sizeBytes too small for header+keyslot+filesystem");
        return false;
    }

    uint8_t masterKey[keyBytes];
    uint8_t digestSalt[32];
    uint8_t keyslotSalt[32];
    if (!randomBytes(masterKey, sizeof(masterKey)) ||
        !randomBytes(digestSalt, sizeof(digestSalt)) ||
        !randomBytes(keyslotSalt, sizeof(keyslotSalt))) {
        LOGI("luks2CreateHeader: urandom read failed");
        return false;
    }

    // Digest: always PBKDF2 regardless of the keyslot's own KDF, matching
    // real cryptsetup — it's a cheap integrity check of the master key
    // (which is only ever reached AFTER the expensive keyslot KDF/AF
    // recovery succeeds), not something worth memory-hardening itself.
    size_t digestLen = getDigestSize(digestMd);
    std::vector<uint8_t> digestBuf(digestLen);
    if (!luksDeriveKdfKey(digestSpec, masterKey, keyBytes, digestSalt, sizeof(digestSalt),
                              kLuks2DigestIter, digestBuf.data(), digestBuf.size())) {
        LOGI("luks2CreateHeader: digest derivation failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    // Keyslot KDF → derive the key that encrypts the AF-split master key.
    std::vector<uint8_t> slotKey(keyslotAreaKeyBytes);
    bool kdfOk;
    if (params.useArgon2id) {
        kdfOk = argon2idDeriveKey(password, passwordLen, keyslotSalt, sizeof(keyslotSalt),
                                  params.argon2MemoryKiB, params.argon2TimeCost, params.argon2Parallelism,
                                  slotKey.data(), slotKey.size());
    } else {
        mbedtls_md_type_t keyslotMd = mapHashSpec(params.hashName);
        DigestSpec keyslotSpec = digestSpecForMbedtls(keyslotMd);
        kdfOk = luksDeriveKdfKey(keyslotSpec, password, passwordLen, keyslotSalt, sizeof(keyslotSalt),
                                     params.pbkdf2Iterations, slotKey.data(), slotKey.size());
    }
    if (!kdfOk) {
        LOGI("luks2CreateHeader: keyslot KDF failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    // AF stripe hash: reuse the digest's hash family — real cryptsetup
    // ties these together too ("af": {"hash": <same as digest/kdf hash>}).
    std::vector<uint8_t> afMaterial(afMaterialLen);
    if (afSplit(digestSpec, keyBytes, kLuks2AfStripes, masterKey, afMaterial.data()) != 0) {
        LOGI("luks2CreateHeader: afSplit failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        return false;
    }

    std::vector<uint8_t> afEncrypted(afMaterial.size());
    {
        mbedtls_aes_xts_context xtsCtx;
        mbedtls_aes_xts_init(&xtsCtx);
        bool ok = (mbedtls_aes_xts_setkey_enc(&xtsCtx, slotKey.data(), keyslotAreaKeyBytes * 8) == 0);
        for (size_t sec = 0; ok && sec < afMaterial.size() / 512; sec++) {
            uint8_t tweakBuf[16] = {0};
            for (int b = 0; b < 8; b++) tweakBuf[b] = (sec >> (b * 8)) & 0xFF;
            if (mbedtls_aes_crypt_xts(&xtsCtx, MBEDTLS_AES_ENCRYPT, 512, tweakBuf,
                                      afMaterial.data() + sec * 512,
                                      afEncrypted.data() + sec * 512) != 0) {
                ok = false;
            }
        }
        mbedtls_aes_xts_free(&xtsCtx);
        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
        if (!ok) {
            LOGI("luks2CreateHeader: keyslot area encryption failed");
            mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
            return false;
        }
    }

    // cryptsetup sizes every keyslot area to a 4096-byte multiple (258048 for a 512-bit key)
    // and records that size in area.size; the tail past the AF material is random padding,
    // like its format-time wipe leaves. (An unaligned area.size also misaligns every keyslot
    // cryptsetup later adds after this one.)
    {
        const size_t afBytes = afEncrypted.size();
        afEncrypted.resize(static_cast<size_t>(afReservedLen));
        if (afReservedLen > afBytes && !randomBytes(afEncrypted.data() + afBytes, afReservedLen - afBytes)) {
            LOGI("luks2CreateHeader: padding generation failed");
            mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
            return false;
        }
    }

    if (!writer(keyslotAreaOffset, afEncrypted.data(), afEncrypted.size())) {
        LOGI("luks2CreateHeader: keyslot area write failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    // ── Build JSON metadata ──────────────────────────────────────────
    cJSON* root = cJSON_CreateObject();
    cJSON* keyslots = cJSON_CreateObject();
    cJSON* tokens = cJSON_CreateObject();
    cJSON* segments = cJSON_CreateObject();
    cJSON* digests = cJSON_CreateObject();
    cJSON* config = cJSON_CreateObject();

    {
        cJSON* ks = cJSON_CreateObject();
        cJSON_AddStringToObject(ks, "type", "luks2");
        cJSON_AddNumberToObject(ks, "key_size", keyslotAreaKeyBytes);

        cJSON* kdf = cJSON_CreateObject();
        std::string keyslotSaltB64 = base64Encode(keyslotSalt, sizeof(keyslotSalt));
        if (params.useArgon2id) {
            cJSON_AddStringToObject(kdf, "type", "argon2id");
            cJSON_AddNumberToObject(kdf, "time", params.argon2TimeCost);
            cJSON_AddNumberToObject(kdf, "memory", params.argon2MemoryKiB);
            cJSON_AddNumberToObject(kdf, "cpus", params.argon2Parallelism);
        } else {
            cJSON_AddStringToObject(kdf, "type", "pbkdf2");
            cJSON_AddStringToObject(kdf, "hash", params.hashName.c_str());
            cJSON_AddNumberToObject(kdf, "iterations", params.pbkdf2Iterations);
        }
        cJSON_AddStringToObject(kdf, "salt", keyslotSaltB64.c_str());
        cJSON_AddItemToObject(ks, "kdf", kdf);

        cJSON* af = cJSON_CreateObject();
        cJSON_AddStringToObject(af, "type", "luks1"); // real cryptsetup's name for this AF-splitter scheme
        cJSON_AddNumberToObject(af, "stripes", kLuks2AfStripes);
        cJSON_AddStringToObject(af, "hash", params.hashName.c_str());
        cJSON_AddItemToObject(ks, "af", af);

        cJSON* area = cJSON_CreateObject();
        cJSON_AddStringToObject(area, "type", "raw");
        cJSON_AddStringToObject(area, "offset", std::to_string(keyslotAreaOffset).c_str());
        cJSON_AddStringToObject(area, "size", std::to_string(afEncrypted.size()).c_str());
        cJSON_AddStringToObject(area, "encryption", "aes-xts-plain64");
        cJSON_AddNumberToObject(area, "key_size", keyslotAreaKeyBytes);
        cJSON_AddItemToObject(ks, "area", area);

        cJSON_AddItemToObject(keyslots, "0", ks);
    }

    {
        cJSON* seg = cJSON_CreateObject();
        cJSON_AddStringToObject(seg, "type", "crypt");
        cJSON_AddStringToObject(seg, "offset", std::to_string(dataOffsetBytes).c_str());
        cJSON_AddStringToObject(seg, "size", "dynamic");
        cJSON_AddStringToObject(seg, "iv_tweak", "0");
        std::string encName = params.cipherName + "-xts-plain64";
        cJSON_AddStringToObject(seg, "encryption", encName.c_str());
        cJSON_AddNumberToObject(seg, "sector_size", 512);
        cJSON_AddItemToObject(segments, "0", seg);
    }

    {
        cJSON* dg = cJSON_CreateObject();
        cJSON_AddStringToObject(dg, "type", "pbkdf2");
        cJSON* ksArr = cJSON_CreateArray();
        cJSON_AddItemToArray(ksArr, cJSON_CreateString("0"));
        cJSON_AddItemToObject(dg, "keyslots", ksArr);
        cJSON* segArr = cJSON_CreateArray();
        cJSON_AddItemToArray(segArr, cJSON_CreateString("0"));
        cJSON_AddItemToObject(dg, "segments", segArr);
        cJSON_AddStringToObject(dg, "hash", params.hashName.c_str());
        cJSON_AddNumberToObject(dg, "iterations", kLuks2DigestIter);
        cJSON_AddStringToObject(dg, "salt", base64Encode(digestSalt, sizeof(digestSalt)).c_str());
        cJSON_AddStringToObject(dg, "digest", base64Encode(digestBuf.data(), digestBuf.size()).c_str());
        cJSON_AddItemToObject(digests, "0", dg);
    }

    cJSON_AddStringToObject(config, "json_size", std::to_string(kLuks2JsonAreaSize).c_str());
    cJSON_AddStringToObject(config, "keyslots_size",
                            std::to_string(dataOffsetBytes - keyslotAreaOffset).c_str());

    cJSON_AddItemToObject(root, "keyslots", keyslots);
    cJSON_AddItemToObject(root, "tokens", tokens);
    cJSON_AddItemToObject(root, "segments", segments);
    cJSON_AddItemToObject(root, "digests", digests);
    cJSON_AddItemToObject(root, "config", config);

    char* jsonText = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (!jsonText) {
        LOGI("luks2CreateHeader: JSON serialization failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }
    size_t jsonTextLen = std::strlen(jsonText);
    if (jsonTextLen + 1 > kLuks2JsonAreaSize) {
        LOGI("luks2CreateHeader: JSON too large for reserved area (%zu > %llu)",
             jsonTextLen, (unsigned long long)kLuks2JsonAreaSize);
        free(jsonText);
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }
    std::vector<uint8_t> jsonArea(kLuks2JsonAreaSize, 0);
    std::memcpy(jsonArea.data(), jsonText, jsonTextLen);
    free(jsonText);

    std::string uuid = generateUuidV4();
    auto buildBinHdr = [&](uint64_t hdrOffsetField) {
        Luks2HdrDisk hdr;
        std::memset(&hdr, 0, sizeof(hdr));
        std::memcpy(hdr.magic, hdrOffsetField == 0 ? LUKS_MAGIC : LUKS2_SECONDARY_MAGIC, 6);
        writeBE16((uint8_t*)&hdr.version, 2);
        writeBE64((uint8_t*)&hdr.hdrSize, kLuks2HdrCopySize);
        writeBE64((uint8_t*)&hdr.seqid, 1);
        std::strncpy(hdr.checksumAlg, "sha256", sizeof(hdr.checksumAlg) - 1);
        randomBytes(hdr.salt, sizeof(hdr.salt));
        std::strncpy(hdr.uuid, uuid.c_str(), sizeof(hdr.uuid) - 1);
        writeBE64((uint8_t*)&hdr.hdrOffset, hdrOffsetField);
        return hdr;
    };

    Luks2HdrDisk primaryHdr = buildBinHdr(0);
    Luks2HdrDisk secondaryHdr = buildBinHdr(kLuks2HdrCopySize);

    // Checksum covers the full header copy (binary header with csum
    // zeroed, followed by the JSON area) — matches real cryptsetup so a
    // Linux `cryptsetup luksDump`/mount will accept these headers.
    auto computeChecksum = [&](Luks2HdrDisk& hdr, const std::vector<uint8_t>& json, uint8_t out[32]) {
        std::memset(hdr.csum, 0, sizeof(hdr.csum));
        mbedtls_md_context_t ctx;
        mbedtls_md_init(&ctx);
        const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
        mbedtls_md_setup(&ctx, info, 0);
        mbedtls_md_starts(&ctx);
        mbedtls_md_update(&ctx, reinterpret_cast<const uint8_t*>(&hdr), sizeof(hdr));
        mbedtls_md_update(&ctx, json.data(), json.size());
        mbedtls_md_finish(&ctx, out);
        mbedtls_md_free(&ctx);
    };

    uint8_t csum1[32], csum2[32];
    computeChecksum(primaryHdr, jsonArea, csum1);
    computeChecksum(secondaryHdr, jsonArea, csum2);
    std::memcpy(primaryHdr.csum, csum1, sizeof(csum1));
    std::memcpy(secondaryHdr.csum, csum2, sizeof(csum2));

    if (!writer(0, &primaryHdr, sizeof(primaryHdr)) ||
        !writer(kLuks2BinHdrSize, jsonArea.data(), jsonArea.size()) ||
        !writer(kLuks2HdrCopySize, &secondaryHdr, sizeof(secondaryHdr)) ||
        !writer(kLuks2HdrCopySize + kLuks2BinHdrSize, jsonArea.data(), jsonArea.size())) {
        LOGI("luks2CreateHeader: header/JSON write failed");
        mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
        return false;
    }

    outInfo.version = 2;
    outInfo.cipherName = params.cipherName;
    outInfo.cipherMode = "xts-plain64";
    outInfo.keyBytes = keyBytes;
    outInfo.dataOffsetBytes = dataOffsetBytes;
    outInfo.dataSectorSize = 512;
    outInfo.ivTweak = 0;
    outInfo.masterKey.assign(masterKey, masterKey + keyBytes);
    mbedtls_platform_zeroize(masterKey, sizeof(masterKey));
    LOGI("luks2CreateHeader: created, cipher=%s, dataOffset=%llu",
         params.cipherName.c_str(), (unsigned long long)dataOffsetBytes);
    return true;
}

bool luksCreateHeader(const LuksByteWriter& writer, const uint8_t* password, size_t passwordLen,
                      int64_t sizeBytes, const LuksCreateParams& params,
                      LuksVolumeInfo& outInfo) {
    if (!writer || passwordLen == 0) return false;
    if (params.version == 1) {
        return luks1CreateHeader(writer, password, passwordLen, sizeBytes, params, outInfo);
    } else if (params.version == 2) {
        return luks2CreateHeader(writer, password, passwordLen, sizeBytes, params, outInfo);
    }
    LOGI("luksCreateHeader: unsupported version %d", params.version);
    return false;
}

bool luksCreateHeader(int fd, const uint8_t* password, size_t passwordLen,
                      int64_t sizeBytes, const LuksCreateParams& params,
                      LuksVolumeInfo& outInfo) {
    if (fd < 0 || passwordLen == 0) return false;
    LuksByteWriter writer = [fd](uint64_t offset, const void* data, size_t len) -> bool {
        return pwrite(fd, data, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
    };
    return luksCreateHeader(writer, password, passwordLen, sizeBytes, params, outInfo);
}

// ── LUKS2 metadata commit ────────────────────────────────────────────────
//
// Writes [jsonText] as the new metadata state to BOTH header copies using the
// selected copy's real hdr_size, with seqid = selected + 1 and a fresh
// per-copy salt (like cryptsetup). The copy that is NOT the selected one is
// written first, so a power loss at any instant leaves at least one complete,
// checksum-valid copy whose seqid is consistent with the data it describes.

static bool luks2MakeHeaderBytes(const std::vector<uint8_t>& baseBin, uint64_t offset, uint64_t seqid,
                                 const uint8_t* json, size_t jsonLen, std::vector<uint8_t>& out) {
    out = baseBin;
    out.resize(kLuks2BinHdrSize, 0);
    std::memcpy(out.data(), offset == 0 ? LUKS_MAGIC : LUKS2_SECONDARY_MAGIC, 6);
    writeBE64(out.data() + 16, seqid);
    writeBE64(out.data() + 256, offset);
    if (!randomBytes(out.data() + 104, 64)) return false;     // salt is unique per header copy
    const std::string alg = fixedCString(reinterpret_cast<const char*>(out.data() + 72), 32);
    uint8_t csum[64];
    size_t csumLen = 0;
    if (!luks2ComputeChecksum(alg, out.data(), json, jsonLen, csum, csumLen)) return false;
    std::memset(out.data() + 448, 0, 64);
    std::memcpy(out.data() + 448, csum, csumLen);
    return true;
}

static bool luks2CommitMeta(const LuksByteWriter& writer, const LuksByteSync& sync,
                            const Luks2Meta& meta, const std::string& jsonText) {
    const Luks2Copy* sel = meta.selected;
    if (!sel || !writer) return false;
    const uint64_t jsonAreaLen = sel->hdrSize - kLuks2BinHdrSize;
    if (jsonText.size() + 1 > jsonAreaLen) {
        LOGI("LUKS2: new metadata does not fit its JSON area (%zu > %llu)", jsonText.size() + 1,
             (unsigned long long)jsonAreaLen);
        return false;
    }
    if (sel->seqid == UINT64_MAX) return false;
    const uint64_t newSeq = sel->seqid + 1;
    std::vector<uint8_t> json(jsonAreaLen, 0);
    std::memcpy(json.data(), jsonText.data(), jsonText.size());

    const bool selectedIsPrimary = sel->offset == 0;
    const uint64_t order[2] = {selectedIsPrimary ? sel->hdrSize : 0, selectedIsPrimary ? 0 : sel->hdrSize};
    for (int i = 0; i < 2; i++) {
        std::vector<uint8_t> hdr;
        if (!luks2MakeHeaderBytes(sel->bin, order[i], newSeq, json.data(), json.size(), hdr)) return false;
        if (!writer(order[i] + kLuks2BinHdrSize, json.data(), json.size()) ||
            !writer(order[i], hdr.data(), hdr.size()))
            return false;
        if (i == 0 && sync && !sync()) return false;
    }
    return !sync || sync();
}

static bool wipeRandom(const LuksByteWriter& writer, uint64_t offset, uint64_t len) {
    std::vector<uint8_t> buf(static_cast<size_t>(std::min<uint64_t>(len, 1024 * 1024)));
    for (uint64_t done = 0; done < len;) {
        const size_t n = static_cast<size_t>(std::min<uint64_t>(buf.size(), len - done));
        if (!randomBytes(buf.data(), n) || !writer(offset + done, buf.data(), n)) return false;
        done += n;
    }
    return true;
}

static uint64_t alignUp(uint64_t v, uint64_t a) { return (v + a - 1) / a * a; }

// ── Password change ─────────────────────────────────────────────────────
//
// Find the keyslot the OLD password opens, then re-wrap the (unchanged) master
// key under the NEW password with a fresh salt, reusing the slot's KDF cost
// parameters. Like cryptsetup's luksChangeKey the new key material is written
// to a FREE area/slot first and the old one is retired only after the new
// metadata is committed, so an interrupted change can never leave the volume
// without a working keyslot. Only when no free area/slot exists is the
// material overwritten in place (same fallback as upstream).

static LuksChangePasswordResult luks1ChangeKeyslotPassword(
    const LuksByteReader& reader, const LuksByteWriter& writer,
    const uint8_t* oldPassword, size_t oldPasswordLen,
    const uint8_t* newPassword, size_t newPasswordLen) {
    Luks1Parsed P;
    if (!luks1ParseHeader(reader, P) || !P.cipherSpecOk) return LuksChangePasswordResult::kError;
    const uint32_t keyBytes = P.keyBytes;
    const size_t afLen = static_cast<size_t>(keyBytes) * kLuks1Stripes;
    const size_t afPadded = static_cast<size_t>(luks1SecsPerStripes(keyBytes)) * 512;

    int foundSlot = -1;
    std::vector<uint8_t> masterKey;
    bool anyActive = false;
    for (int i = 0; i < 8 && foundSlot < 0; i++) {
        if (P.slotActive[i] != kLuks1KeyEnabled || P.slotIterations[i] == 0) continue;
        anyActive = true;
        std::vector<uint8_t> slotKey(keyBytes), af(afPadded), afDec(afPadded), cand(keyBytes);
        bool ok = luksDeriveKdfKey(P.hash, oldPassword, oldPasswordLen, P.phdr.keySlots[i].salt, 32,
                                   P.slotIterations[i], slotKey.data(), slotKey.size()) &&
                  reader(static_cast<uint64_t>(P.slotOffset[i]) * 512, af.data(), afPadded) &&
                  areaCrypt(P.cipherSpec, false, slotKey.data(), slotKey.size(), af.data(), afDec.data(), afPadded) &&
                  afMerge(P.hash, keyBytes, kLuks1Stripes, afDec.data(), cand.data()) == 0 &&
                  luksVerifyMasterKey(P.hash, cand.data(), keyBytes, P.phdr.mkDigestSalt, 32, P.mkDigestIter,
                                      P.phdr.mkDigest, 20);
        if (ok) { foundSlot = i; masterKey = cand; }
        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        mbedtls_platform_zeroize(af.data(), af.size());
        mbedtls_platform_zeroize(afDec.data(), afDec.size());
        mbedtls_platform_zeroize(cand.data(), cand.size());
    }
    if (foundSlot < 0) return anyActive ? LuksChangePasswordResult::kWrongOldPassword : LuksChangePasswordResult::kError;

    // Target: a free (disabled) slot if there is one, else the same slot.
    int target = foundSlot;
    for (int j = 0; j < 8; j++) {
        if (P.slotActive[j] == kLuks1KeyDisabled) { target = j; break; }
    }
    const bool relocate = target != foundSlot;
    const uint32_t iterations = P.slotIterations[foundSlot];

    uint8_t newSalt[32];
    std::vector<uint8_t> newKey(keyBytes), split(afPadded, 0), enc(afPadded);
    LuksChangePasswordResult result = LuksChangePasswordResult::kError;
    if (randomBytes(newSalt, sizeof(newSalt)) &&
        luksDeriveKdfKey(P.hash, newPassword, newPasswordLen, newSalt, sizeof(newSalt), iterations,
                         newKey.data(), newKey.size()) &&
        afSplit(P.hash, keyBytes, kLuks1Stripes, masterKey.data(), split.data()) == 0 &&
        areaCrypt(P.cipherSpec, true, newKey.data(), newKey.size(), split.data(), enc.data(), afPadded) &&
        writer(static_cast<uint64_t>(P.slotOffset[target]) * 512, enc.data(), afPadded)) {
        Luks1Phdr hdr = P.phdr;
        Luks1KeySlot& t = hdr.keySlots[target];
        writeBE32(reinterpret_cast<uint8_t*>(&t.active), kLuks1KeyEnabled);
        writeBE32(reinterpret_cast<uint8_t*>(&t.iterations), iterations);
        std::memcpy(t.salt, newSalt, 32);
        if (relocate) {                       // retire the old slot in the SAME header write
            Luks1KeySlot& o = hdr.keySlots[foundSlot];
            writeBE32(reinterpret_cast<uint8_t*>(&o.active), kLuks1KeyDisabled);
            writeBE32(reinterpret_cast<uint8_t*>(&o.iterations), 0);
            std::memset(o.salt, 0, 32);
        }
        if (writer(0, &hdr, sizeof(hdr))) {
            result = LuksChangePasswordResult::kSuccess;
            if (relocate) wipeRandom(writer, static_cast<uint64_t>(P.slotOffset[foundSlot]) * 512, afPadded);
        }
    }
    (void)afLen;
    mbedtls_platform_zeroize(masterKey.data(), masterKey.size());
    mbedtls_platform_zeroize(newKey.data(), newKey.size());
    mbedtls_platform_zeroize(split.data(), split.size());
    return result;
}

// First-fit search for a free, 4096-aligned area of [need] bytes inside the
// keyslots region (same policy as cryptsetup's LUKS2_find_area_gap()).
static bool luks2FindFreeArea(const cJSON* root, uint64_t hdrSize, uint64_t need, uint64_t& outOffset) {
    uint64_t keyslotsSize = 0;
    if (!jsonU64(jget(jget(root, "config"), "keyslots_size"), keyslotsSize)) return false;
    const uint64_t regionStart = 2 * hdrSize;
    const uint64_t regionEnd = regionStart + keyslotsSize;
    std::vector<std::pair<uint64_t, uint64_t>> used;
    for (const cJSON* k = jget(root, "keyslots")->child; k; k = k->next) {
        uint64_t off, size;
        const cJSON* area = jget(k, "area");
        if (jsonU64(jget(area, "offset"), off) && jsonU64(jget(area, "size"), size) && off <= UINT64_MAX - size)
            used.emplace_back(off, size);
    }
    std::sort(used.begin(), used.end());
    uint64_t cand = alignUp(regionStart, kLuks2KeyslotAlign);
    for (const auto& iv : used) {
        if (cand + need <= iv.first) break;
        cand = std::max(cand, alignUp(iv.first + iv.second, kLuks2KeyslotAlign));
    }
    if (cand + need > regionEnd) return false;
    outOffset = cand;
    return true;
}

static LuksChangePasswordResult luks2ChangeKeyslotPassword(
    const LuksByteReader& reader, const LuksByteWriter& writer,
    const uint8_t* oldPassword, size_t oldPasswordLen,
    const uint8_t* newPassword, size_t newPasswordLen) {
    Luks2Meta meta;
    if (!luks2LoadMeta(reader, meta)) return LuksChangePasswordResult::kError;
    Luks2Parsed L;
    if (!luks2ParseAll(*meta.selected, L)) return LuksChangePasswordResult::kError;

    const Luks2Keyslot* target = nullptr;
    std::vector<uint8_t> masterKey;
    bool triedAny = false;
    for (const auto& ks : L.keyslots) {
        const Luks2Digest* digest = luks2DigestForKeyslot(L, ks.info.index);
        if (!digest) continue;
        triedAny = true;
        if (luks2OpenKeyslot(reader, L, ks, *digest, oldPassword, oldPasswordLen, nullptr, masterKey)) {
            target = &ks;
            break;
        }
    }
    if (!target) return triedAny ? LuksChangePasswordResult::kWrongOldPassword : LuksChangePasswordResult::kError;

    LuksChangePasswordResult result = LuksChangePasswordResult::kError;
    std::vector<uint8_t> areaKey, split(target->afPadded, 0), enc(target->afPadded);
    uint8_t newSalt[32];

    // Re-derive under the new password with a fresh salt, same KDF parameters.
    Luks2Keyslot fresh = *target;
    if (randomBytes(newSalt, sizeof(newSalt))) {
        fresh.info.salt.assign(newSalt, newSalt + 32);
        if (luks2DeriveAreaKey(fresh, newPassword, newPasswordLen, areaKey, nullptr) &&
            afSplit(target->afHash, target->volumeKeySize, kLuks2AfStripes, masterKey.data(), split.data()) == 0 &&
            areaCrypt(target->areaSpec, true, areaKey.data(), areaKey.size(), split.data(), enc.data(),
                      target->afPadded)) {
            // Where to put it: a free area (crash-safe) or, failing that, in place.
            const uint64_t need = alignUp(target->afPadded, kLuks2KeyslotAlign);
            uint64_t newOffset = 0;
            const bool relocate = luks2FindFreeArea(meta.selected->root.get(), meta.selected->hdrSize, need, newOffset);
            std::vector<uint8_t> toWrite = enc;
            if (relocate) {                      // pad the area like cryptsetup's format-time wipe does
                toWrite.resize(static_cast<size_t>(need));
                if (need > enc.size()) randomBytes(toWrite.data() + enc.size(), static_cast<size_t>(need - enc.size()));
            }
            const uint64_t writeOffset = relocate ? newOffset : target->info.areaOffset;

            if (writer(writeOffset, toWrite.data(), toWrite.size())) {
                JsonPtr nr(cJSON_Duplicate(meta.selected->root.get(), true));
                cJSON* slotObj = nullptr;
                for (cJSON* k = jget(nr.get(), "keyslots")->child; k; k = k->next) {
                    int idx;
                    if (parseIndexKey(k->string, idx) && idx == target->info.index) { slotObj = k; break; }
                }
                cJSON* kdf = const_cast<cJSON*>(jget(slotObj, "kdf"));
                cJSON* area = const_cast<cJSON*>(jget(slotObj, "area"));
                bool edited = kdf && area &&
                    cJSON_ReplaceItemInObjectCaseSensitive(kdf, "salt", cJSON_CreateString(base64Encode(newSalt, 32).c_str()));
                if (edited && relocate) {
                    edited = cJSON_ReplaceItemInObjectCaseSensitive(area, "offset", cJSON_CreateString(std::to_string(newOffset).c_str())) &&
                             cJSON_ReplaceItemInObjectCaseSensitive(area, "size", cJSON_CreateString(std::to_string(need).c_str()));
                }
                char* printed = edited ? cJSON_PrintUnformatted(nr.get()) : nullptr;
                if (printed) {
                    const std::string text(printed);
                    std::free(printed);
                    if (luks2CommitMeta(writer, nullptr, meta, text)) {
                        result = LuksChangePasswordResult::kSuccess;
                        if (relocate) wipeRandom(writer, target->info.areaOffset, target->info.areaSize);
                    }
                }
            }
        }
    }
    mbedtls_platform_zeroize(masterKey.data(), masterKey.size());
    mbedtls_platform_zeroize(areaKey.data(), areaKey.size());
    mbedtls_platform_zeroize(split.data(), split.size());
    return result;
}

LuksChangePasswordResult luksChangeKeyslotPassword(const LuksByteReader& reader,
                                                    const LuksByteWriter& writer,
                                                    const uint8_t* oldPassword, size_t oldPasswordLen,
                                                    const uint8_t* newPassword, size_t newPasswordLen) {
    if (!reader || !writer || oldPasswordLen == 0 || newPasswordLen == 0) {
        return LuksChangePasswordResult::kError;
    }
    uint8_t head[8];
    if (reader(0, head, sizeof(head)) && std::memcmp(head, LUKS_MAGIC, 6) == 0 && readBE16(head + 6) == 1) {
        return luks1ChangeKeyslotPassword(reader, writer, oldPassword, oldPasswordLen, newPassword, newPasswordLen);
    }
    // LUKS2 (also reached when the primary header is damaged but the secondary is valid).
    return luks2ChangeKeyslotPassword(reader, writer, oldPassword, oldPasswordLen, newPassword, newPasswordLen);
}

LuksChangePasswordResult luksChangeKeyslotPassword(int fd,
                                                    const uint8_t* oldPassword, size_t oldPasswordLen,
                                                    const uint8_t* newPassword, size_t newPasswordLen) {
    if (fd < 0) return LuksChangePasswordResult::kError;
    LuksByteReader reader = [fd](uint64_t offset, void* outData, size_t len) -> bool {
        return pread(fd, outData, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
    };
    LuksByteWriter writer = [fd](uint64_t offset, const void* data, size_t len) -> bool {
        return pwrite(fd, data, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
    };
    return luksChangeKeyslotPassword(reader, writer, oldPassword, oldPasswordLen, newPassword, newPasswordLen);
}

// ── Header integrity / backup-header restore ────────────────────────────
//
// "Valid" below means the copy's checksum verifies over the header plus its
// WHOLE JSON area at the header's own hdr_size (not a fixed 16 KiB), which is
// exactly what cryptsetup checks. The secondary copy is located via the
// primary's hdr_size, or by scanning cryptsetup's nine legal offsets when the
// primary is damaged.

bool luks2CheckHeaderIntegrity(const LuksByteReader& reader, bool& outPrimaryValid, bool& outSecondaryValid) {
    outPrimaryValid = false;
    outSecondaryValid = false;
    if (!reader) return false;

    Luks2Meta meta;
    luks2LoadMeta(reader, meta, /*validateJson=*/false);
    outPrimaryValid = meta.primary.checksumOk;
    outSecondaryValid = meta.secondary.checksumOk;

    // A copy that can't even be recognised (I/O error, truncated file) is
    // neither "valid" nor a failure for the *other* copy -- report what we
    // could determine rather than failing the whole call.
    return meta.primary.magicOk || meta.secondary.magicOk;
}

LuksHeaderProbeResult luksProbeHeader(const LuksByteReader& reader) {
    if (!reader) return LuksHeaderProbeResult::kInvalidHeader;
    uint8_t prefix[8]{};
    if (!reader(0, prefix, sizeof(prefix))) return LuksHeaderProbeResult::kInvalidHeader;
    if (std::memcmp(prefix, LUKS_MAGIC, sizeof(LUKS_MAGIC)) != 0) {
        // A LUKS2 primary header can be damaged while its independently
        // checksummed secondary copy remains usable. Recognize that case
        // (at ANY legal secondary offset) before calling the file unrelated.
        Luks2Meta meta;
        luks2LoadMeta(reader, meta, /*validateJson=*/false);
        if (meta.secondary.magicOk)
            return meta.secondary.checksumOk ? LuksHeaderProbeResult::kValid : LuksHeaderProbeResult::kInvalidHeader;
        return LuksHeaderProbeResult::kNotLuks;
    }

    const uint16_t version = readBE16(prefix + 6);
    if (version == 1) {
        Luks1Parsed P;
        if (!luks1ParseHeader(reader, P) || P.payloadOffset == 0) return LuksHeaderProbeResult::kInvalidHeader;
        for (int i = 0; i < 8; i++) {
            if (P.slotActive[i] == kLuks1KeyEnabled && P.slotIterations[i] > 0)
                return LuksHeaderProbeResult::kValid;
        }
        return LuksHeaderProbeResult::kInvalidHeader;
    }

    if (version == 2) {
        bool primaryValid = false, secondaryValid = false;
        if (luks2CheckHeaderIntegrity(reader, primaryValid, secondaryValid) && (primaryValid || secondaryValid))
            return LuksHeaderProbeResult::kValid;
        return LuksHeaderProbeResult::kInvalidHeader;
    }
    return LuksHeaderProbeResult::kInvalidHeader;
}

bool luks2RestoreHeaderFromBackup(const LuksByteReader& reader, const LuksByteWriter& writer) {
    if (!reader || !writer) return false;

    Luks2Meta meta;
    luks2LoadMeta(reader, meta, /*validateJson=*/false);
    if (!meta.secondary.checksumOk) {
        LOGI("luks2RestoreHeaderFromBackup: backup (secondary) header copy does not verify -- refusing to restore");
        return false;
    }
    if (meta.primary.checksumOk) {
        LOGI("luks2RestoreHeaderFromBackup: primary header already verifies -- nothing to repair");
        return false;
    }

    // Rebuild the primary from the secondary: primary magic, hdr_offset 0,
    // fresh per-copy salt and a recomputed checksum (a raw byte copy would
    // carry the secondary's magic/offset/checksum and fail verification).
    const Luks2Copy& s = meta.secondary;
    std::vector<uint8_t> hdr;
    if (!luks2MakeHeaderBytes(s.bin, 0, s.seqid, s.json.data(), s.json.size(), hdr)) return false;
    if (!writer(kLuks2BinHdrSize, s.json.data(), s.json.size()) || !writer(0, hdr.data(), hdr.size())) {
        LOGI("luks2RestoreHeaderFromBackup: write failed");
        return false;
    }
    LOGI("luks2RestoreHeaderFromBackup: primary header copy restored from backup");
    return true;
}

bool luks2DataSegmentOffset(const LuksByteReader& reader, uint64_t& outOffset) {
    if (!reader) return false;
    // Everything from byte 0 up to the data segment's offset is header + keyslot
    // area, not data. Works with whichever metadata copy is valid.
    Luks2Meta meta;
    if (!luks2LoadMeta(reader, meta)) return false;
    Luks2SegmentInfo seg;
    uint32_t count = 0;
    int idx = 0;
    if (!luks2ParseSegment(meta.selected->root.get(), seg, count, idx) || seg.offset == 0) return false;
    outOffset = seg.offset;
    return true;
}

// ── Safe LUKS2 fixed-size segment expansion ──────────────────────────────

namespace {
struct Luks2ResizeState {
    Luks2Meta meta;
    bool primaryValid = false;
    bool secondaryValid = false;
    uint64_t dataOffset = 0;
    uint64_t oldDataSize = 0;
    uint64_t sectorSize = 512;
    uint64_t ivTweak = 0;
    uint64_t seqid = 0;
    bool dynamic = true;
    bool needsMetadataRepair = false;
};

static bool luks2LoadResizeState(const LuksByteReader& reader, uint64_t oldFileSize,
                                 uint64_t newFileSize, Luks2ResizeState& out) {
    if (!reader || newFileSize < oldFileSize) return false;
    // One valid metadata copy is sufficient for LUKS2 recovery. This also
    // accepts an interrupted update where the copies have split sequence IDs;
    // the commit repairs both copies before applying the next change.
    if (!luks2LoadMeta(reader, out.meta)) return false;
    const Luks2Copy& p = out.meta.primary;
    const Luks2Copy& s = out.meta.secondary;
    out.primaryValid = p.ok;
    out.secondaryValid = s.ok;

    if (p.ok && s.ok) {
        // Refuse to write over two independently valid but diverging states.
        if (p.seqid == s.seqid && p.json != s.json) return false;
        // Two valid copies must belong to the same volume: hdr_size, label,
        // checksum algorithm, uuid and subsystem are identical in both.
        if (p.hdrSize != s.hdrSize) return false;
        for (const auto& range : {std::make_pair(24, 72), std::make_pair(72, 104), std::make_pair(168, 256)}) {
            if (std::memcmp(p.bin.data() + range.first, s.bin.data() + range.first, range.second - range.first) != 0)
                return false;
        }
    }
    const Luks2Copy& base = *out.meta.selected;
    out.seqid = base.seqid;
    if (out.seqid == 0 || out.seqid == UINT64_MAX) return false;

    Luks2SegmentInfo seg;
    uint32_t segCount = 0;
    int segIdx = 0;
    if (!luks2ParseSegment(base.root.get(), seg, segCount, segIdx)) return false;
    // Only expand the layout this app can zero-fill correctly: exactly one
    // plain xts-plain64 crypt segment. Integrity tags are interleaved with
    // ciphertext; segment flags / mandatory requirements may denote
    // reencryption or another data layout. Never rewrite metadata for those.
    if (segCount != 1 || !seg.isCryptSegment || seg.hasIntegrity || seg.hasFlags || seg.hasMandatoryRequirements)
        return false;
    {
        const size_t dash = seg.encryption.find('-');
        if (dash == std::string::npos || seg.encryption.compare(dash + 1, 11, "xts-plain64") != 0) return false;
    }

    const uint64_t dataOffset = seg.offset;
    const uint64_t logicalSectorSize = seg.sectorSize;
    const bool isDynamic = seg.dynamicSize;
    const uint64_t declaredSize = seg.sizeBytes;
    if (dataOffset < 2 * base.hdrSize || dataOffset >= oldFileSize ||
        dataOffset % logicalSectorSize != 0 || newFileSize % logicalSectorSize != 0) return false;
    const uint64_t availableOld = oldFileSize - dataOffset;
    const uint64_t availableNew = newFileSize - dataOffset;
    // A dynamic segment exposes complete logical data sectors only. A file
    // whose physical EOF has a partial sector is still mountable; that tail
    // is not part of the dm-crypt block device.
    const uint64_t oldDataSize = isDynamic ? (availableOld / logicalSectorSize) * logicalSectorSize : declaredSize;
    const uint64_t newDataSize = (availableNew / logicalSectorSize) * logicalSectorSize;
    if (oldDataSize == 0 || oldDataSize > availableOld || oldDataSize % logicalSectorSize != 0 ||
        (newDataSize < oldDataSize) || newDataSize % logicalSectorSize != 0) return false;
    if (!isDynamic && declaredSize > availableNew) return false;

    // Equal valid sequence IDs imply a byte-identical metadata state (checked
    // above). A split sequence ID or one invalid/missing copy needs a repair commit.
    out.needsMetadataRepair = !(p.ok && s.ok && p.seqid == s.seqid);
    out.dataOffset = dataOffset;
    out.oldDataSize = oldDataSize;
    out.sectorSize = logicalSectorSize;
    out.ivTweak = seg.ivTweak;
    out.dynamic = isDynamic;
    return true;
}
} // namespace

bool luks2ValidateResize(const LuksByteReader& reader, uint64_t oldFileSize,
                         uint64_t newFileSize, uint64_t& outDataOffset,
                         uint64_t& outOldDataSize, uint64_t& outIvTweak,
                         bool& outWasDynamic, bool& outNeedsMetadataRepair) {
    Luks2ResizeState state;
    if (!luks2LoadResizeState(reader, oldFileSize, newFileSize, state)) return false;
    outDataOffset = state.dataOffset;
    outOldDataSize = state.oldDataSize;
    outIvTweak = state.ivTweak;
    outWasDynamic = state.dynamic;
    outNeedsMetadataRepair = state.needsMetadataRepair;
    return true;
}

bool luks2ResizeSegmentMetadata(const LuksByteReader& reader, const LuksByteWriter& writer,
                                uint64_t oldFileSize, uint64_t newFileSize,
                                const LuksByteSync& sync) {
    if (!writer) return false;
    Luks2ResizeState state;
    if (!luks2LoadResizeState(reader, oldFileSize, newFileSize, state) || state.dynamic) return false;

    JsonPtr root(cJSON_Duplicate(state.meta.selected->root.get(), true));
    if (!root) return false;
    int segIdx = 0;
    uint32_t segCount = 0;
    cJSON* segment = const_cast<cJSON*>(luks2PickDataSegment(root.get(), segIdx, segCount));
    cJSON* size = segment ? cJSON_GetObjectItemCaseSensitive(segment, "size") : nullptr;
    const std::string newSizeString = std::to_string(newFileSize - state.dataOffset);
    const bool changed = size && cJSON_IsString(size) && cJSON_SetValuestring(size, newSizeString.c_str()) != nullptr;
    char* printed = changed ? cJSON_PrintUnformatted(root.get()) : nullptr;
    if (!printed) return false;
    const std::string text(printed);
    std::free(printed);
    return luks2CommitMeta(writer, sync, state.meta, text);
}
