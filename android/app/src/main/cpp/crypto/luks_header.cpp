#include "luks_header.h"
#include "cipher_shim.h"
#include <cstring>
#include <algorithm>
#include <memory>
#include <unistd.h>
#include <android/log.h>
#include <cJSON.h>

#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/base64.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"

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

// ── AF Diffusion & Merge ───────────────────────────────────────────────────

static int afDiffuse(mbedtls_md_type_t mdType, size_t blocklen, uint8_t* block) {
    size_t digestlen = getDigestSize(mdType);
    if (digestlen == 0) return -1;

    size_t hashcount = blocklen / digestlen;
    size_t finallen = blocklen % digestlen;
    if (finallen) {
        hashcount++;
    } else {
        finallen = digestlen;
    }

    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(mdType);
    if (!mdInfo) return -1;

    for (uint32_t i = 0; i < hashcount; i++) {
        uint32_t iv = i;
        // Big endian conversion for the IV
        uint8_t ivBuf[4];
        ivBuf[0] = (iv >> 24) & 0xFF;
        ivBuf[1] = (iv >> 16) & 0xFF;
        ivBuf[2] = (iv >> 8)  & 0xFF;
        ivBuf[3] = iv         & 0xFF;

        mbedtls_md_context_t ctx;
        mbedtls_md_init(&ctx);
        if (mbedtls_md_setup(&ctx, mdInfo, 0) != 0) {
            mbedtls_md_free(&ctx);
            return -1;
        }

        mbedtls_md_starts(&ctx);
        mbedtls_md_update(&ctx, ivBuf, 4);
        size_t chunkLen = (i == (hashcount - 1)) ? finallen : digestlen;
        mbedtls_md_update(&ctx, block + (i * digestlen), chunkLen);

        uint8_t digest[64];
        mbedtls_md_finish(&ctx, digest);
        mbedtls_md_free(&ctx);

        std::memcpy(block + (i * digestlen), digest, chunkLen);
    }
    return 0;
}

static void afXor(size_t blocklen, const uint8_t* in1, const uint8_t* in2, uint8_t* out) {
    for (size_t i = 0; i < blocklen; i++) {
        out[i] = in1[i] ^ in2[i];
    }
}

static int afMerge(mbedtls_md_type_t mdType, size_t keySize, uint32_t stripes,
                   const uint8_t* src, uint8_t* dst) {
    std::unique_ptr<uint8_t[]> block(new uint8_t[keySize]());
    size_t i;
    for (i = 0; i < (stripes - 1); i++) {
        afXor(keySize, src + (i * keySize), block.get(), block.get());
        if (afDiffuse(mdType, keySize, block.get()) < 0) {
            return -1;
        }
    }
    afXor(keySize, src + (i * keySize), block.get(), dst);
    mbedtls_platform_zeroize(block.get(), keySize);
    return 0;
}

// ── Keyslot PBKDF2 Helper ──────────────────────────────────────────────────

static bool luksDeriveKeyslotKey(mbedtls_md_type_t mdType,
                                 const uint8_t* password, size_t passwordLen,
                                 const uint8_t* salt, size_t saltLen,
                                 uint32_t iterations,
                                 uint8_t* outKey, size_t outKeyLen) {
    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(mdType);
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

// ── Master Key Verification PBKDF2 Helper ──────────────────────────────────

static bool luksVerifyMasterKey(mbedtls_md_type_t mdType,
                                const uint8_t* candidateKey, size_t keyLen,
                                const uint8_t* salt, size_t saltLen,
                                uint32_t iterations,
                                const uint8_t* expectedDigest, size_t expectedDigestLen) {
    std::vector<uint8_t> derived(expectedDigestLen);
    if (!luksDeriveKeyslotKey(mdType, candidateKey, keyLen, salt, saltLen, iterations, derived.data(), derived.size())) {
        return false;
    }
    bool match = (std::memcmp(derived.data(), expectedDigest, expectedDigestLen) == 0);
    mbedtls_platform_zeroize(derived.data(), derived.size());
    return match;
}

// ── LUKS1 Unlocking ─────────────────────────────────────────────────────────

static bool luks1Unlock(int fd,
                        const uint8_t* password, size_t passwordLen,
                        LuksVolumeInfo& outInfo,
                        int volId,
                        std::function<bool(int)> cancelCheck,
                        std::function<void(int, int, int, int)> progressCallback) {
    Luks1Phdr phdr;
    if (pread(fd, &phdr, sizeof(Luks1Phdr), 0) != sizeof(Luks1Phdr)) {
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
    mbedtls_md_type_t mdType = mapHashSpec(hashSpec);
    if (mdType == MBEDTLS_MD_NONE) {
        LOGI("LUKS1: Unsupported hashSpec: %s", hashSpec.c_str());
        return false;
    }

    // Count active keyslots
    int activeSlotsCount = 0;
    for (int i = 0; i < 8; i++) {
        uint32_t active = readBE32((const uint8_t*)&phdr.keySlots[i].active);
        if (active == 0x00AC71F3) activeSlotsCount++;
    }

    int currentStep = 0;
    for (int i = 0; i < 8; i++) {
        if (cancelCheck && cancelCheck(volId)) {
            LOGI("LUKS1: Unlock cancelled");
            return false;
        }

        uint32_t active = readBE32((const uint8_t*)&phdr.keySlots[i].active);
        if (active != 0x00AC71F3) continue;

        currentStep++;
        if (progressCallback) {
            progressCallback(currentStep, activeSlotsCount, static_cast<int>(mdType), 0);
        }

        uint32_t iterations = readBE32((const uint8_t*)&phdr.keySlots[i].iterations);
        uint32_t stripes = readBE32((const uint8_t*)&phdr.keySlots[i].stripes);
        uint32_t keyMaterialOffset = readBE32((const uint8_t*)&phdr.keySlots[i].keyMaterialOffset);

        // 1. Derive keyslot key
        std::vector<uint8_t> slotKey(keyBytes);
        if (!luksDeriveKeyslotKey(mdType, password, passwordLen, phdr.keySlots[i].salt, 32, iterations, slotKey.data(), slotKey.size())) {
            continue;
        }

        // 2. Read AF key material
        size_t afLen = keyBytes * stripes;
        std::vector<uint8_t> afMaterial(afLen);
        if (pread(fd, afMaterial.data(), afLen, (uint64_t)keyMaterialOffset * 512) != (ssize_t)afLen) {
            continue;
        }

        // 3. Decrypt AF key material using AES-CBC with slotKey (LUKS1 is typically AES-CBC-ESSIV or plain)
        // Note: For LUKS1, keyslots are encrypted with AES-CBC, IV=0.
        // We set up mbedtls aes cbc.
        mbedtls_aes_context aesCtx;
        mbedtls_aes_init(&aesCtx);
        if (mbedtls_aes_setkey_dec(&aesCtx, slotKey.data(), keyBytes * 8) != 0) {
            mbedtls_aes_free(&aesCtx);
            continue;
        }
        uint8_t iv[16] = {0};
        std::vector<uint8_t> afDecrypted(afLen);
        if (mbedtls_aes_crypt_cbc(&aesCtx, MBEDTLS_AES_DECRYPT, afLen, iv, afMaterial.data(), afDecrypted.data()) != 0) {
            mbedtls_aes_free(&aesCtx);
            continue;
        }
        mbedtls_aes_free(&aesCtx);

        // 4. Merge AF stripes to candidate master key
        std::vector<uint8_t> candidateKey(keyBytes);
        if (afMerge(mdType, keyBytes, stripes, afDecrypted.data(), candidateKey.data()) != 0) {
            continue;
        }

        // 5. Verify master key candidate
        if (luksVerifyMasterKey(mdType, candidateKey.data(), keyBytes, phdr.mkDigestSalt, 32, mkDigestIter, phdr.mkDigest, 20)) {
            // Success!
            outInfo.version = 1;
            outInfo.cipherName = phdr.cipherName;
            outInfo.cipherMode = phdr.cipherMode;
            outInfo.keyBytes = keyBytes;
            outInfo.dataOffsetBytes = (uint64_t)payloadOffset * 512;
            outInfo.dataSectorSize = 512;
            outInfo.masterKey = candidateKey;

            mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            return true;
        }

        mbedtls_platform_zeroize(slotKey.data(), slotKey.size());
        mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
        mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
        mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
    }

    return false;
}

// ── LUKS2 Unlocking ─────────────────────────────────────────────────────────

static bool luks2Unlock(int fd,
                        const uint8_t* password, size_t passwordLen,
                        LuksVolumeInfo& outInfo,
                        int volId,
                        std::function<bool(int)> cancelCheck,
                        std::function<void(int, int, int, int)> progressCallback) {
    LOGI("LUKS2: Starting unlock...");
    // Read the binary header area (4096 bytes)
    uint8_t hdr[4096];
    if (pread(fd, hdr, 4096, 0) != 4096) {
        LOGI("LUKS2: pread of binary header failed");
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
    ssize_t readLen = pread(fd, jsonBuf.data(), jsonLen, 4096);
    LOGI("LUKS2: JSON readLen = %zd, expected = %zu", readLen, jsonLen);
    if (readLen != (ssize_t)jsonLen) {
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

    int activeSlotsCount = keyslots.size();
    int currentStep = 0;
    bool unlocked = false;

    for (const auto& ks : keyslots) {
        if (cancelCheck && cancelCheck(volId)) {
            LOGI("LUKS2: Unlock cancelled");
            break;
        }

        // Find digest associated with this keyslot
        const Luks2DigestInfo* matchDigest = nullptr;
        for (const auto& d : digests) {
            if (std::find(d.keyslots.begin(), d.keyslots.end(), ks.index) != d.keyslots.end()) {
                matchDigest = &d;
                break;
            }
        }
        if (!matchDigest) {
            LOGI("LUKS2: Keyslot %d has no matching digest", ks.index);
            continue;
        }

        currentStep++;
        mbedtls_md_type_t mdType = mapHashSpec(ks.hashName);
        if (progressCallback) {
            progressCallback(currentStep, activeSlotsCount, static_cast<int>(mdType), 1);
        }

        // 1. Derive keyslot key
        size_t derivedKeyLen = ks.areaKeySize;
        if (derivedKeyLen == 0) derivedKeyLen = 64; // Default/Fallback
        std::vector<uint8_t> derivedKey(derivedKeyLen);

        bool kdfSuccess = false;
        LOGI("LUKS2: Keyslot %d KDF start: type=%s, hash=%s, iter=%u, memory=%u, cpus=%u, saltSize=%zu, outLen=%zu",
             ks.index, ks.kdfType.c_str(), ks.hashName.c_str(), ks.iterations, ks.memory, ks.parallelism, ks.salt.size(), derivedKeyLen);
        
        if (ks.kdfType == "pbkdf2") {
            kdfSuccess = luksDeriveKeyslotKey(mdType, password, passwordLen, ks.salt.data(), ks.salt.size(), ks.iterations, derivedKey.data(), derivedKeyLen);
        } else if (ks.kdfType == "argon2id" || ks.kdfType == "argon2i") {
            uint32_t memoryKiB = ks.memory;
            if (memoryKiB > 1048576) {
                LOGI("LUKS2: Capping memory cost from %u KiB to 1048576 KiB", memoryKiB);
                memoryKiB = 1048576;
            }
            kdfSuccess = argon2idDeriveKey(password, passwordLen, ks.salt.data(), ks.salt.size(), memoryKiB, ks.iterations, ks.parallelism, derivedKey.data(), derivedKeyLen);
        }

        LOGI("LUKS2: Keyslot %d KDF done: success=%d", ks.index, kdfSuccess);
        if (!kdfSuccess) {
            mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
            continue;
        }

        // 2. Read AF key material
        std::vector<uint8_t> afMaterial(ks.areaSize);
        ssize_t afReadLen = pread(fd, afMaterial.data(), ks.areaSize, ks.areaOffset);
        LOGI("LUKS2: Keyslot %d AF read: offset=%llu, expectedSize=%llu, readSize=%zd",
             ks.index, (unsigned long long)ks.areaOffset, (unsigned long long)ks.areaSize, afReadLen);
        if (afReadLen != (ssize_t)ks.areaSize) {
            LOGI("LUKS2: Keyslot %d AF read failed", ks.index);
            mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
            continue;
        }

        // 3. Decrypt AF key material using AES-XTS.
        mbedtls_aes_xts_context decCtx;
        mbedtls_aes_xts_init(&decCtx);
        int setkeyRet = mbedtls_aes_xts_setkey_dec(&decCtx, derivedKey.data(), derivedKeyLen * 8);
        LOGI("LUKS2: Keyslot %d setkey_dec return=%d", ks.index, setkeyRet);
        if (setkeyRet != 0) {
            mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
            mbedtls_aes_xts_free(&decCtx);
            continue;
        }

        std::vector<uint8_t> afDecrypted(ks.areaSize);
        int decRet = 0;
        for (size_t sec = 0; sec < ks.areaSize / 512; sec++) {
            unsigned char tweakBuf[16] = {0};
            for (int b = 0; b < 8; b++) {
                tweakBuf[b] = (sec >> (b * 8)) & 0xFF;
            }
            int ret = mbedtls_aes_crypt_xts(&decCtx, MBEDTLS_AES_DECRYPT, 512, tweakBuf,
                                            afMaterial.data() + (sec * 512),
                                            afDecrypted.data() + (sec * 512));
            if (ret != 0) {
                decRet = ret;
                break;
            }
        }
        LOGI("LUKS2: Keyslot %d crypt_xts return=%d", ks.index, decRet);

        mbedtls_platform_zeroize(derivedKey.data(), derivedKey.size());
        mbedtls_aes_xts_free(&decCtx);

        if (decRet != 0) {
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            continue;
        }

        // 4. Merge AF stripes to get candidate master key
        size_t masterKeySize = ks.areaKeySize;
        std::vector<uint8_t> candidateKey(masterKeySize);
        mbedtls_md_type_t afMd = mapHashSpec(ks.afHash);
        LOGI("LUKS2: Keyslot %d merging AF stripes: masterKeySize=%zu, stripes=%d, hash=%s",
             ks.index, masterKeySize, ks.afStripes, ks.afHash.c_str());
        
        int afMergeRet = afMerge(afMd, masterKeySize, ks.afStripes, afDecrypted.data(), candidateKey.data());
        LOGI("LUKS2: Keyslot %d afMerge return=%d", ks.index, afMergeRet);
        if (afMergeRet != 0) {
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
            continue;
        }

        // 5. Verify candidate master key using Digest
        mbedtls_md_type_t digestMd = mapHashSpec(matchDigest->hashName);
        LOGI("LUKS2: Keyslot %d verifying candidate key: digestHash=%s, digestIterations=%u, digestSaltSize=%zu, digestExpectedSize=%zu",
             ks.index, matchDigest->hashName.c_str(), matchDigest->iterations, matchDigest->salt.size(), matchDigest->digest.size());
        
        bool verified = luksVerifyMasterKey(digestMd, candidateKey.data(), masterKeySize, matchDigest->salt.data(), matchDigest->salt.size(), matchDigest->iterations, matchDigest->digest.data(), matchDigest->digest.size());
        LOGI("LUKS2: Keyslot %d verifyMasterKey return=%d", ks.index, verified);
        
        if (verified) {
            // Found the master key!
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

            outInfo.keyBytes = masterKeySize;
            outInfo.dataOffsetBytes = segment.offset;
            outInfo.dataSectorSize = segment.sectorSize;
            outInfo.ivTweak = segment.ivTweak;
            outInfo.masterKey = candidateKey;

            unlocked = true;
            mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
            mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
            break;
        }

        mbedtls_platform_zeroize(afMaterial.data(), afMaterial.size());
        mbedtls_platform_zeroize(afDecrypted.data(), afDecrypted.size());
        mbedtls_platform_zeroize(candidateKey.data(), candidateKey.size());
    }

    cJSON_Delete(root);
    LOGI("LUKS2: Unlock finished. Success=%d", unlocked);
    return unlocked;
}

// ── Main Entry Point ────────────────────────────────────────────────────────

bool luksRecoverMasterKey(int fd,
                          const uint8_t* password,
                          size_t passwordLen,
                          LuksVolumeInfo& outInfo,
                          int volId,
                          std::function<bool(int)> cancelCheck,
                          std::function<void(int, int, int, int)> progressCallback) {
    if (fd < 0 || !password) return false;

    // Read the version to determine path
    uint8_t verBuf[2];
    if (pread(fd, verBuf, 2, 6) != 2) return false;

    uint16_t version = (uint16_t(verBuf[0]) << 8) | verBuf[1];
    if (version == 1) {
        LOGI("luksRecoverMasterKey: detected LUKS1 container");
        return luks1Unlock(fd, password, passwordLen, outInfo, volId, cancelCheck, progressCallback);
    } else if (version == 2) {
        LOGI("luksRecoverMasterKey: detected LUKS2 container");
        return luks2Unlock(fd, password, passwordLen, outInfo, volId, cancelCheck, progressCallback);
    }

    LOGI("luksRecoverMasterKey: unknown LUKS version %u", version);
    return false;
}