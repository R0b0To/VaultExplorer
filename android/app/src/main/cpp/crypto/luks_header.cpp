#include "luks_header.h"
#include "cipher_shim.h"
#include "cascade.h"
#include <cstring>
#include <algorithm>
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
// Real LUKS1 and LUKS2 both encrypt a keyslot's AF-split key material with
// the SAME cipher as the volume's data area (LUKS1: the header's
// cipherName/cipherMode; LUKS2: the keyslot's own "area.encryption",
// which cryptsetup sets to match the segment cipher) — never a cipher
// fixed to AES regardless of what the volume actually uses. This app only
// implements the xts-plain64 data mode, so the keyslot area is likewise
// always single-layer XTS here, just keyed to whichever of
// AES/Serpent/Twofish/Camellia/Kuznyechik the container declares.
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

// Encrypts/decrypts a LUKS keyslot AF-area, sector by sector, using
// single-layer XTS with cipher [cipherId] and key material [keyMaterial]
// (must be >= 64 bytes: 32B data key + 32B tweak key, matching
// cascadeSetKeys()'s single-layer requirement — the master-key-length
// PBKDF2/Argon2 output this app always derives for LUKS keyslots). Sector
// tweaks are counted from 0 at the start of [in]/[out] — i.e. relative to
// the keyslot/keyslot-area's own start, not the container's — matching
// where real cryptsetup resets its tweak counter for this region.
// [dataLen] must be a whole multiple of 512.
static bool keyslotAreaCrypt(CascadeId cipherId, bool encrypt,
                              const unsigned char* keyMaterial, size_t keyMaterialLen,
                              const unsigned char* in, unsigned char* out, size_t dataLen) {
    if (dataLen == 0 || dataLen % 512 != 0) return false;
    CascadeContext ctx;
    ctx.aesXtsFastPathReady = false;

    // Fast path: bypass cascadeSetKeys (which enforces a 64-byte minimum) 
    // for standard AES 256/512 keys used by LUKS.
    if (cipherId == CascadeId::kAes && (keyMaterialLen == 32 || keyMaterialLen == 64)) {
        ctx.id = cipherId;
        ctx.layerCount = 1;
        mbedtls_aes_xts_init(&ctx.aesXtsEncCtx);
        mbedtls_aes_xts_init(&ctx.aesXtsDecCtx);
        bool ok = (mbedtls_aes_xts_setkey_enc(&ctx.aesXtsEncCtx, keyMaterial, keyMaterialLen * 8) == 0) &&
                  (mbedtls_aes_xts_setkey_dec(&ctx.aesXtsDecCtx, keyMaterial, keyMaterialLen * 8) == 0);
        ctx.aesXtsFastPathReady = ok;
        if (!ok) return false;
    } else {
        // Use standard VeraCrypt cascade init for other ciphers
        if (!cascadeSetKeys(ctx, cipherId, keyMaterial, keyMaterialLen)) return false;
    }

    const size_t sectorCount = dataLen / 512;
    for (size_t sec = 0; sec < sectorCount; sec++) {
        if (encrypt) cascadeEncryptSector(ctx, sec, in + sec * 512, out + sec * 512);
        else         cascadeDecryptSector(ctx, sec, in + sec * 512, out + sec * 512);
    }

    if (ctx.aesXtsFastPathReady) {
        mbedtls_aes_xts_free(&ctx.aesXtsEncCtx);
        mbedtls_aes_xts_free(&ctx.aesXtsDecCtx);
    }

    return true;
}

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
                             uint8_t* outKey, size_t outKeyLen) {
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
        return pbkdf2Hmac(spec.customId, password, passwordLen, salt, saltLen, iterations, outKey, outKeyLen);
    }
    return false;
}

// ── Master Key Verification PBKDF2 Helper ──────────────────────────────────

static bool luksVerifyMasterKey(const DigestSpec& spec,
                                const uint8_t* candidateKey, size_t keyLen,
                                const uint8_t* salt, size_t saltLen,
                                uint32_t iterations,
                                const uint8_t* expectedDigest, size_t expectedDigestLen) {
    std::vector<uint8_t> derived(expectedDigestLen);
    if (!luksDeriveKdfKey(spec, candidateKey, keyLen, salt, saltLen, iterations, derived.data(), derived.size())) {
        return false;
    }
    bool match = (std::memcmp(derived.data(), expectedDigest, expectedDigestLen) == 0);
    mbedtls_platform_zeroize(derived.data(), derived.size());
    return match;
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
    Luks1Phdr phdr;
    if (!reader(0, &phdr, sizeof(Luks1Phdr))) {
        LOGI("LUKS1: Failed to read phdr");
        return false;
    }

    // Verify version and endianness
    uint16_t version = readBE16((const uint8_t*)&phdr.version);
    if (version != 1) return false;

    uint32_t keyBytes = readBE32((const uint8_t*)&phdr.keyBytes);
    uint32_t payloadOffset = readBE32((const uint8_t*)&phdr.payloadOffset);
    uint32_t mkDigestIter = readBE32((const uint8_t*)&phdr.mkDigestIter);

    std::string hashSpec = phdr.hashSpec;
    DigestSpec hashDigest = resolveHashSpec(hashSpec);
    if (hashDigest.backend == HashBackend::kNone) {
        LOGI("LUKS1: Unsupported hashSpec: %s", hashSpec.c_str());
        return false;
    }

    // ── Fast path: verify a cached master key directly against the header
    // digest. Skips every keyslot's PBKDF2-AF derivation entirely — this is
    // the whole point of quick-unlock. ──
    if (candidateMasterKey != nullptr) {
        if (candidateMasterKeyLen == keyBytes &&
            luksVerifyMasterKey(hashDigest, candidateMasterKey, keyBytes,
                                 phdr.mkDigestSalt, 32, mkDigestIter,
                                 phdr.mkDigest, 20)) {
            outInfo.version = 1;
            outInfo.cipherName = phdr.cipherName;
            outInfo.cipherMode = phdr.cipherMode;
            outInfo.keyBytes = keyBytes;
            outInfo.dataOffsetBytes = (uint64_t)payloadOffset * 512;
            outInfo.dataSectorSize = 512;
            outInfo.masterKey.assign(candidateMasterKey, candidateMasterKey + candidateMasterKeyLen);
            LOGI("LUKS1: quick-unlock candidate key verified");
            return true;
        }
        LOGI("LUKS1: quick-unlock candidate key stale/invalid");
        return false; // stale cached key — caller falls back to password/keyfile
    }

    // Keyslot AF-area decryption uses the same cipher as the data area
    // (see keyslotAreaCrypt()'s doc comment) — resolve it once up front so
    // every keyslot-try thread below can reuse it.
    std::string cipherNameStr = phdr.cipherName;
    CascadeId slotCipher;
    if (!cascadeIdForCipherName(cipherNameStr, slotCipher)) {
        LOGI("LUKS1: Unsupported cipher: %s", cipherNameStr.c_str());
        return false;
    }

    // Collect active keyslot indices, then try them concurrently — one
    // thread per active slot, first one to verify against mkDigest wins.
    // Real containers overwhelmingly have exactly one active passphrase
    // slot, so the single-slot case below skips thread-spawn overhead
    // entirely; this only matters for multi-user LUKS1 volumes.
    std::vector<int> activeSlotIndices;
    for (int i = 0; i < 8; i++) {
        uint32_t active = readBE32((const uint8_t*)&phdr.keySlots[i].active);
        if (active == 0x00AC71F3) activeSlotIndices.push_back(i);
    }
    const int activeSlotsCount = static_cast<int>(activeSlotIndices.size());

    std::atomic<bool> found{false};
    std::atomic<int> attemptedCount{0};
    std::mutex resultMutex;
    std::vector<uint8_t> resultMasterKey;

    auto tryOneSlot = [&](int i) {
        if (found.load(std::memory_order_acquire) || (cancelCheck && cancelCheck(volId))) return;

        if (progressCallback) {
            // Display-only ID: mbedTLS's own type enum for the four
            // mbedTLS-backed hashes, or 1000+HashId for the three custom
            // ones, so the two spaces never collide.
            int displayHashId = (hashDigest.backend == HashBackend::kMbedtls)
                                     ? static_cast<int>(hashDigest.mbedtlsType)
                                     : (1000 + static_cast<int>(hashDigest.customId));
            progressCallback(attemptedCount.fetch_add(1) + 1, activeSlotsCount, displayHashId, 0);
        }

        uint32_t iterations = readBE32((const uint8_t*)&phdr.keySlots[i].iterations);
        uint32_t stripes = readBE32((const uint8_t*)&phdr.keySlots[i].stripes);
        uint32_t keyMaterialOffset = readBE32((const uint8_t*)&phdr.keySlots[i].keyMaterialOffset);

        // 1. Derive keyslot key
        std::vector<uint8_t> slotKey(keyBytes);
        if (!luksDeriveKdfKey(hashDigest, password, passwordLen, phdr.keySlots[i].salt, 32, iterations, slotKey.data(), slotKey.size())) {
            return;
        }

        if (found.load(std::memory_order_acquire)) {
            mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
            return;
        }

        // 2. Read AF key material
        size_t afLen = keyBytes * stripes;
        std::vector<uint8_t> afMaterial(afLen);
        if (!reader((uint64_t)keyMaterialOffset * 512, afMaterial.data(), afLen)) {
            mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
            return;
        }

        // 3. Decrypt AF key material with the same cipher as the data area
        // (single-layer XTS, sector tweaks counted from 0 at the start of
        // this keyslot's AF material) — see keyslotAreaCrypt()'s doc
        // comment.
        std::vector<uint8_t> afDecrypted(afLen);
        if (!keyslotAreaCrypt(slotCipher, false, slotKey.data(), slotKey.size(),
                              afMaterial.data(), afDecrypted.data(), afLen)) {
            mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            return;
        }

        // 4. Merge AF stripes to candidate master key
        std::vector<uint8_t> candidateKey(keyBytes);
        if (afMerge(hashDigest, keyBytes, stripes, afDecrypted.data(), candidateKey.data()) != 0) {
            mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            return;
        }

        // 5. Verify master key candidate
        bool verified = luksVerifyMasterKey(hashDigest, candidateKey.data(), keyBytes, phdr.mkDigestSalt, 32, mkDigestIter, phdr.mkDigest, 20);
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
        if (!verified) {
            mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
        }
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

    outInfo.version = 1;
    outInfo.cipherName = phdr.cipherName;
    outInfo.cipherMode = phdr.cipherMode;
    outInfo.keyBytes = keyBytes;
    outInfo.dataOffsetBytes = (uint64_t)payloadOffset * 512;
    outInfo.dataSectorSize = 512;
    outInfo.masterKey = resultMasterKey;
    return true;
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
    // Read the binary header area (4096 bytes)
    uint8_t hdr[4096];
    if (!reader(0, hdr, 4096)) {
        LOGI("LUKS2: header read failed");
        return false;
    }

    uint64_t hdrSize = readBE64(hdr + 8);
    LOGI("LUKS2: hdrSize = %llu", (unsigned long long)hdrSize);
    if (hdrSize < 4096 || hdrSize > 8 * 1024 * 1024) {
        LOGI("LUKS2: hdrSize check failed");
        return false;
    }

    // Read the JSON metadata. It starts at offset 4096, and has length (hdrSize - 4096).
    size_t jsonLen = hdrSize - 4096;
    std::vector<char> jsonBuf(jsonLen + 1, 0);
    if (!reader(4096, jsonBuf.data(), jsonLen)) {
        LOGI("LUKS2: JSON read failed");
        return false;
    }

    cJSON* root = cJSON_Parse(jsonBuf.data());
    for (size_t i = 0; i < jsonLen; i += 2000) {
        LOGI("LUKS2 JSON chunk: %.*s", (int)std::min((size_t)2000, jsonLen - i), jsonBuf.data() + i);
    }
    if (!root) {
        LOGI("LUKS2: cJSON parse failed. Buffer preview: %.100s", jsonBuf.data());
        return false;
    }

    cJSON* keyslotsObj = cJSON_GetObjectItemCaseSensitive(root, "keyslots");
    cJSON* digestsObj = cJSON_GetObjectItemCaseSensitive(root, "digests");
    cJSON* segmentsObj = cJSON_GetObjectItemCaseSensitive(root, "segments");

    if (!keyslotsObj || !digestsObj || !segmentsObj) {
        LOGI("LUKS2: missing keyslots (%p), digests (%p) or segments (%p)", keyslotsObj, digestsObj, segmentsObj);
        cJSON_Delete(root);
        return false;
    }

    // Parse Segments (just use the first segment)
    Luks2SegmentInfo segment;
    cJSON* segmentKey = segmentsObj->child;
    if (segmentKey) {
        cJSON* enc = cJSON_GetObjectItemCaseSensitive(segmentKey, "encryption");
        cJSON* off = cJSON_GetObjectItemCaseSensitive(segmentKey, "offset");
        cJSON* ss = cJSON_GetObjectItemCaseSensitive(segmentKey, "sector_size");
        cJSON* sz = cJSON_GetObjectItemCaseSensitive(segmentKey, "size");
        cJSON* ivt = cJSON_GetObjectItemCaseSensitive(segmentKey, "iv_tweak");

        if (enc && enc->valuestring) segment.encryption = enc->valuestring;
        if (off && off->valuestring) {
            segment.offset = std::strtoull(off->valuestring, nullptr, 10);
        }
        if (ss) segment.sectorSize = ss->valueint;
        if (ivt && ivt->valuestring) {
            segment.ivTweak = std::strtoull(ivt->valuestring, nullptr, 10);
        }
        LOGI("LUKS2: Parsed segment: encryption=%s, offset=%llu, sector_size=%u, iv_tweak=%llu",
             segment.encryption.c_str(), (unsigned long long)segment.offset, segment.sectorSize,
             (unsigned long long)segment.ivTweak);
    } else {
        LOGI("LUKS2: no segments found");
    }

    // Parse Digests into list
    std::vector<Luks2DigestInfo> digests;
    cJSON* digestItem = digestsObj->child;
    while (digestItem) {
        Luks2DigestInfo d;
        cJSON* type = cJSON_GetObjectItemCaseSensitive(digestItem, "type");
        cJSON* keyslots = cJSON_GetObjectItemCaseSensitive(digestItem, "keyslots");
        cJSON* segments = cJSON_GetObjectItemCaseSensitive(digestItem, "segments");
        cJSON* hash = cJSON_GetObjectItemCaseSensitive(digestItem, "hash");
        cJSON* iters = cJSON_GetObjectItemCaseSensitive(digestItem, "iterations");
        cJSON* salt = cJSON_GetObjectItemCaseSensitive(digestItem, "salt");
        cJSON* digest = cJSON_GetObjectItemCaseSensitive(digestItem, "digest");

        if (type && type->valuestring) d.type = type->valuestring;
        if (hash && hash->valuestring) d.hashName = hash->valuestring;
        if (iters) d.iterations = iters->valueint;
        if (salt && salt->valuestring) d.salt = base64Decode(salt->valuestring);
        if (digest && digest->valuestring) d.digest = base64Decode(digest->valuestring);

        if (keyslots) {
            int sz = cJSON_GetArraySize(keyslots);
            for (int i = 0; i < sz; i++) {
                cJSON* ks = cJSON_GetArrayItem(keyslots, i);
                if (ks && ks->valuestring) d.keyslots.push_back(std::atoi(ks->valuestring));
            }
        }
        if (segments) {
            int sz = cJSON_GetArraySize(segments);
            for (int i = 0; i < sz; i++) {
                cJSON* sg = cJSON_GetArrayItem(segments, i);
                if (sg && sg->valuestring) d.segments.push_back(std::atoi(sg->valuestring));
            }
        }

        LOGI("LUKS2: Parsed digest %s: type=%s, hash=%s, keyslotsCount=%zu, digestSize=%zu",
             digestItem->string, d.type.c_str(), d.hashName.c_str(), d.keyslots.size(), d.digest.size());
        digests.push_back(d);
        digestItem = digestItem->next;
    }

    // ── Fast path: verify a cached master key against whichever digest
    // covers it. LUKS2 keys the master key to a digest, not a keyslot, so
    // this can run before a single keyslot's KDF/AF area is even read. ──
    if (candidateMasterKey != nullptr) {
        bool verified = false;
        for (const auto& d : digests) {
            DigestSpec digestSpec = resolveHashSpec(d.hashName);
            if (digestSpec.backend == HashBackend::kNone) continue;
            if (luksVerifyMasterKey(digestSpec, candidateMasterKey, candidateMasterKeyLen,
                                     d.salt.data(), d.salt.size(), d.iterations,
                                     d.digest.data(), d.digest.size())) {
                outInfo.version = 2;
                std::string segmentEnc = segment.encryption;
                size_t firstDash = segmentEnc.find('-');
                if (firstDash != std::string::npos) {
                    outInfo.cipherName = segmentEnc.substr(0, firstDash);
                    outInfo.cipherMode = segmentEnc.substr(firstDash + 1);
                } else {
                    outInfo.cipherName = "aes";
                    outInfo.cipherMode = "xts-plain64";
                }
                outInfo.keyBytes = static_cast<uint32_t>(candidateMasterKeyLen);
                outInfo.dataOffsetBytes = segment.offset;
                outInfo.dataSectorSize = segment.sectorSize;
                outInfo.ivTweak = segment.ivTweak;
                outInfo.masterKey.assign(candidateMasterKey, candidateMasterKey + candidateMasterKeyLen);
                verified = true;
                break;
            }
        }
        LOGI("LUKS2: quick-unlock candidate key verified=%d", verified);
        cJSON_Delete(root);
        return verified; // false → caller falls back to password/keyfile
    }

    // Parse Keyslots
    std::vector<Luks2KeyslotInfo> keyslots;
    cJSON* keyslotItem = keyslotsObj->child;
    while (keyslotItem) {
        Luks2KeyslotInfo ks;
        ks.index = std::atoi(keyslotItem->string);

        cJSON* type = cJSON_GetObjectItemCaseSensitive(keyslotItem, "type");
        if (type && type->valuestring && std::strcmp(type->valuestring, "luks2") == 0) {
            cJSON* kdf = cJSON_GetObjectItemCaseSensitive(keyslotItem, "kdf");
            cJSON* area = cJSON_GetObjectItemCaseSensitive(keyslotItem, "area");
            cJSON* af = cJSON_GetObjectItemCaseSensitive(keyslotItem, "af");

            if (kdf) {
                cJSON* kdfType = cJSON_GetObjectItemCaseSensitive(kdf, "type");
                cJSON* hash = cJSON_GetObjectItemCaseSensitive(kdf, "hash");
                cJSON* iters = cJSON_GetObjectItemCaseSensitive(kdf, "iterations");
                cJSON* time = cJSON_GetObjectItemCaseSensitive(kdf, "time");
                cJSON* memory = cJSON_GetObjectItemCaseSensitive(kdf, "memory");
                cJSON* cpus = cJSON_GetObjectItemCaseSensitive(kdf, "cpus");
                cJSON* salt = cJSON_GetObjectItemCaseSensitive(kdf, "salt");

                if (kdfType && kdfType->valuestring) ks.kdfType = kdfType->valuestring;
                if (hash && hash->valuestring) ks.hashName = hash->valuestring;
                if (iters) ks.iterations = iters->valueint;
                if (time) ks.iterations = time->valueint;
                if (memory) ks.memory = memory->valueint;
                if (cpus) ks.parallelism = cpus->valueint;
                if (salt && salt->valuestring) ks.salt = base64Decode(salt->valuestring);
            }

            if (area) {
                cJSON* off = cJSON_GetObjectItemCaseSensitive(area, "offset");
                cJSON* sz = cJSON_GetObjectItemCaseSensitive(area, "size");
                cJSON* enc = cJSON_GetObjectItemCaseSensitive(area, "encryption");
                cJSON* ksz = cJSON_GetObjectItemCaseSensitive(area, "key_size");

                if (off && off->valuestring) ks.areaOffset = std::strtoull(off->valuestring, nullptr, 10);
                if (sz && sz->valuestring) ks.areaSize = std::strtoull(sz->valuestring, nullptr, 10);
                if (enc && enc->valuestring) ks.areaEncryption = enc->valuestring;
                if (ksz) ks.areaKeySize = ksz->valueint;
            }

            if (af) {
                cJSON* stripes = cJSON_GetObjectItemCaseSensitive(af, "stripes");
                cJSON* hash = cJSON_GetObjectItemCaseSensitive(af, "hash");

                if (stripes) ks.afStripes = stripes->valueint;
                if (hash && hash->valuestring) ks.afHash = hash->valuestring;
            }

            LOGI("LUKS2: Parsed keyslot %d: kdfType=%s, hashName=%s, iterations=%u, areaOffset=%llu, areaSize=%llu, areaKeySize=%u",
                 ks.index, ks.kdfType.c_str(), ks.hashName.c_str(), ks.iterations,
                 (unsigned long long)ks.areaOffset, (unsigned long long)ks.areaSize, ks.areaKeySize);
            keyslots.push_back(ks);
        } else {
            LOGI("LUKS2: Ignored keyslot %s (type=%s)", keyslotItem->string, type ? type->valuestring : "null");
        }
        keyslotItem = keyslotItem->next;
    }

    const int activeSlotsCount = static_cast<int>(keyslots.size());

    std::atomic<bool> found{false};
    std::atomic<int> attemptedCount{0};
    std::mutex resultMutex;
    LuksVolumeInfo resultInfo;

    // One thread per parsed keyslot, first one to verify against its digest
    // wins. Keyslots with no matching digest bail immediately without
    // counting toward attemptedCount/progressCallback, matching the
    // original sequential scan's behavior.
    auto tryOneKeyslot = [&](size_t idx) {
        const Luks2KeyslotInfo& ks = keyslots[idx];
        if (found.load(std::memory_order_acquire) || (cancelCheck && cancelCheck(volId))) return;

        const Luks2DigestInfo* matchDigest = nullptr;
        for (const auto& d : digests) {
            if (std::find(d.keyslots.begin(), d.keyslots.end(), ks.index) != d.keyslots.end()) {
                matchDigest = &d;
                break;
            }
        }
        if (!matchDigest) return;

        DigestSpec kdfSpec = resolveHashSpec(ks.hashName);
        if (progressCallback) {
            // Display-only ID, same collision-avoidance scheme as LUKS1's.
            int displayHashId = (kdfSpec.backend == HashBackend::kMbedtls)
                                     ? static_cast<int>(kdfSpec.mbedtlsType)
                                     : (1000 + static_cast<int>(kdfSpec.customId));
            progressCallback(attemptedCount.fetch_add(1) + 1, activeSlotsCount, displayHashId, 1);
        }

        // 1. Derive keyslot key
        size_t derivedKeyLen = ks.areaKeySize;
        if (derivedKeyLen == 0) derivedKeyLen = 64; // Default/Fallback
        std::vector<uint8_t> derivedKey(derivedKeyLen);

        bool kdfSuccess = false;
        if (ks.kdfType == "pbkdf2") {
            if (kdfSpec.backend == HashBackend::kNone) {
                LOGI("LUKS2: keyslot %d has unsupported kdf hash '%s'", ks.index, ks.hashName.c_str());
            } else {
                kdfSuccess = luksDeriveKdfKey(kdfSpec, password, passwordLen, ks.salt.data(), ks.salt.size(), ks.iterations, derivedKey.data(), derivedKeyLen);
            }
        } else if (ks.kdfType == "argon2id" || ks.kdfType == "argon2i") {
            uint32_t memoryKiB = ks.memory;
            if (memoryKiB > 1048576) memoryKiB = 1048576;
            kdfSuccess = argon2idDeriveKey(password, passwordLen, ks.salt.data(), ks.salt.size(), memoryKiB, ks.iterations, ks.parallelism, derivedKey.data(), derivedKeyLen);
        }

        if (!kdfSuccess) {
            mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
            return;
        }

        if (found.load(std::memory_order_acquire)) {
            mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
            return;
        }

        // 2. Read AF key material
        std::vector<uint8_t> afMaterial(ks.areaSize);
        if (!reader(ks.areaOffset, afMaterial.data(), ks.areaSize)) {
            mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
            return;
        }

        // 3. Decrypt AF key material using this keyslot's own declared
        // area cipher (ks.areaEncryption, e.g. "aes-xts-plain64", "serpent-
        // xts-plain64", ...) rather than a fixed AES-XTS — sector tweaks
        // counted from 0 at the start of the keyslot area. See
        // keyslotAreaCrypt()'s doc comment.
        CascadeId slotCipher;
        {
            std::string areaCipherName = ks.areaEncryption;
            const size_t dash = areaCipherName.find('-');
            if (dash != std::string::npos) areaCipherName = areaCipherName.substr(0, dash);
            if (areaCipherName.empty() || !cascadeIdForCipherName(areaCipherName, slotCipher)) {
                mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
                return;
            }
        }

        std::vector<uint8_t> afDecrypted(ks.areaSize);
        const bool decOk = keyslotAreaCrypt(slotCipher, false, derivedKey.data(), derivedKeyLen,
                                            afMaterial.data(), afDecrypted.data(), ks.areaSize);

        mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());

        if (!decOk) {
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            return;
        }

        // 4. Merge AF stripes to get candidate master key
        size_t masterKeySize = ks.areaKeySize;
        std::vector<uint8_t> candidateKey(masterKeySize);
        DigestSpec afSpec = resolveHashSpec(ks.afHash);
        if (afMerge(afSpec, masterKeySize, ks.afStripes, afDecrypted.data(), candidateKey.data()) != 0) {
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
            return;
        }

        // 5. Verify candidate master key using Digest
        DigestSpec digestSpec = resolveHashSpec(matchDigest->hashName);
        bool verified = luksVerifyMasterKey(digestSpec, candidateKey.data(), masterKeySize, matchDigest->salt.data(), matchDigest->salt.size(), matchDigest->iterations, matchDigest->digest.data(), matchDigest->digest.size());

        if (verified) {
            bool expected = false;
            if (found.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
                std::lock_guard<std::mutex> lock(resultMutex);
                resultInfo.version = 2;

                std::string segmentEnc = segment.encryption;
                size_t firstDash = segmentEnc.find('-');
                if (firstDash != std::string::npos) {
                    resultInfo.cipherName = segmentEnc.substr(0, firstDash);
                    resultInfo.cipherMode = segmentEnc.substr(firstDash + 1);
                } else {
                    resultInfo.cipherName = "aes";
                    resultInfo.cipherMode = "xts-plain64";
                }

                resultInfo.keyBytes = static_cast<uint32_t>(masterKeySize);
                resultInfo.dataOffsetBytes = segment.offset;
                resultInfo.dataSectorSize = segment.sectorSize;
                resultInfo.ivTweak = segment.ivTweak;
                resultInfo.masterKey = candidateKey;
            }
        }

        mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
        mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
        if (!verified) {
            mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
        }
    };

    if (keyslots.size() <= 1) {
        if (!keyslots.empty()) tryOneKeyslot(0);
    } else {
        std::vector<std::future<void>> futures;
        futures.reserve(keyslots.size());
        for (size_t idx = 0; idx < keyslots.size(); idx++) futures.push_back(ThreadPool::getInstance().enqueue(tryOneKeyslot, idx));
        for (auto& f : futures) f.get();
    }

    const bool unlocked = found.load(std::memory_order_acquire);
    if (unlocked) {
        outInfo = resultInfo;
    } else if (cancelCheck && cancelCheck(volId)) {
        LOGI("LUKS2: Unlock cancelled");
    }

    cJSON_Delete(root);
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

    // Read the version to determine path
    uint8_t verBuf[2];
    if (!reader(6, verBuf, 2)) return false;

    uint16_t version = (uint16_t(verBuf[0]) << 8) | verBuf[1];
    if (version == 1) {
        LOGI("luksRecoverMasterKey: detected LUKS1 container");
        return luks1Unlock(reader, password, passwordLen, outInfo, volId, cancelCheck, progressCallback,
                            candidateMasterKey, candidateMasterKeyLen);
    } else if (version == 2) {
        LOGI("luksRecoverMasterKey: detected LUKS2 container");
        return luks2Unlock(reader, password, passwordLen, outInfo, volId, cancelCheck, progressCallback,
                            candidateMasterKey, candidateMasterKeyLen);
    }

    LOGI("luksRecoverMasterKey: unknown LUKS version %u", version);
    return false;
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

static bool randomBytes(uint8_t* buf, size_t len) {
    FILE* urnd = fopen("/dev/urandom", "rb");
    if (!urnd) return false;
    bool ok = (fread(buf, 1, len, urnd) == len);
    fclose(urnd);
    return ok;
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

// Real cryptsetup's LUKS1 default: 4000 AF stripes, keyslots 4096-byte
// aligned, integrity-check-only master-key-digest iteration count (not
// security critical — see luks2CreateHeader()'s digest comment below for
// why a fixed, modest count is fine here).
static constexpr uint32_t kLuks1Stripes = 4000;
static constexpr uint64_t kLuks1AlignBytes = 4096;
static constexpr uint64_t kLuks1PayloadAlign = 1024 * 1024;
static constexpr uint32_t kLuks1MkDigestIter = 100000;
static constexpr uint64_t kLuksMinExtraSpace = 300 * 1024; // headroom for a usable ext2/3/4 fs

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
    
    // We must reserve space for all 8 contiguous keyslots (even if disabled)
    // so that payloadOffsetBytes starts safely after keyslot 7's ending sector.
    uint64_t payloadOffsetBytes = slot0Offset + 8 * afMaterialLen;
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
        uint64_t slotOffset = slot0Offset + i * afMaterialLen;
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

// ── LUKS2 binary header (4096 bytes) — see the real cryptsetup on-disk
// format spec. Multi-byte integer fields are written big-endian via the
// writeBE* helpers directly into these raw byte buffers, mirroring how
// Luks1Phdr's fields are read elsewhere in this file, rather than relying
// on the struct's declared integer types (which would depend on host
// endianness). ──
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
static constexpr uint64_t kLuks2HdrCopySize = 16384;                             // one header copy (bin + JSON)
static constexpr uint64_t kLuks2JsonAreaSize = kLuks2HdrCopySize - kLuks2BinHdrSize; // 12288
static constexpr uint64_t kLuks2HeadersTotal = 2 * kLuks2HdrCopySize;            // primary + secondary copy
static constexpr uint32_t kLuks2AfStripes = 4000;
static constexpr uint64_t kLuks2KeyslotAlign = 4096;
static constexpr uint64_t kLuks2DataAlign = 1024 * 1024;
static constexpr uint32_t kLuks2DigestIter = 100000; // integrity check only, not security critical

static bool luks2CreateHeader(const LuksByteWriter& writer, const uint8_t* password, size_t passwordLen,
                              int64_t sizeBytes, const LuksCreateParams& params,
                              LuksVolumeInfo& outInfo) {
    if (params.cipherName != "aes" && params.cipherName != "serpent" && params.cipherName != "twofish") {
        LOGI("luks2CreateHeader: unsupported cipher %s", params.cipherName.c_str());
        return false;
    }
    mbedtls_md_type_t digestMd = mapHashSpec(params.hashName);
    if (digestMd == MBEDTLS_MD_NONE) {
        LOGI("luks2CreateHeader: unsupported hash %s", params.hashName.c_str());
        return false;
    }
    DigestSpec digestSpec = digestSpecForMbedtls(digestMd);

    constexpr uint32_t keyBytes = 64;           // *-xts-plain64, 512-bit key — all 3 supported ciphers
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
        std::memcpy(hdr.magic, LUKS_MAGIC, 6);
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