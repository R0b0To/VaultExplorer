#include "crypto/thread_pool.h"
#include "session_prepare.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <functional>
#include <memory>
#include <mutex>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include <android/log.h>

#include "mbedtls/aes.h"

#include "container_format.h"
#include "container_header.h"
#include "container_utils.h"
#include "crypto/cascade.h"
#include "crypto/cipher_shim.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/luks_header.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "jni_callbacks.h"
#include "volume_state.h"

// volume_state.h pulls in NTFS-3G's headers, which #define raw min/max
// macros (support.h) that clobber every std::min/std::max call below.
#undef min
#undef max

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

static constexpr int MAX_VOLUMES = FF_VOLUMES;

static inline long long elapsedMs(const std::chrono::steady_clock::time_point& start) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
}

struct PartitionCandidate {
    uint64_t startSector;
    uint64_t sectorCount;
};

// ── Per-volume unlock cancellation ──────────────────────────────────────

static std::atomic<bool> cancelRequested[MAX_VOLUMES];

static bool _cancelInit = [](){
    for (int i = 0; i < MAX_VOLUMES; i++)
        cancelRequested[i].store(false);
    return true;
}();

bool isUnlockCancelled(int volId) {
    return volId >= 0 && volId < MAX_VOLUMES &&
           cancelRequested[volId].load(std::memory_order_acquire);
}

void clearUnlockCancellation(int volId) {
    if (volId >= 0 && volId < MAX_VOLUMES)
        cancelRequested[volId].store(false, std::memory_order_release);
}

void requestUnlockCancellation(int volId) {
    if (volId >= 0 && volId < MAX_VOLUMES)
        cancelRequested[volId].store(true, std::memory_order_release);
}

static bool tryDecryptHeader(
    const unsigned char encH[VC_HEADER_BODY_SIZE],
    CascadeId cipherId,
    const unsigned char* derivedKeyMaterial,
    unsigned char decH[VC_HEADER_BODY_SIZE],
    ParsedHeaderFields* outFields = nullptr
) {
    CascadeContext tempCtx;
    CascadeSpec spec = cascadeSpecFor(cipherId);
    if (!cascadeSetKeys(tempCtx, cipherId, derivedKeyMaterial, spec.layerCount * 64)) {
        return false;
    }

    std::memcpy(decH, encH, VC_HEADER_BODY_SIZE);

    for (int i = 0; i < spec.layerCount; i++) {
        const XtsLayerKey& layer = tempCtx.layers[i];
        unsigned char T[16] = {0};
        blockCipherEncryptBlock(layer.tweakKey, T, T);
        for (int block = 0; block < 28; block++) {
            unsigned char* blockPtr = decH + block * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = blockPtr[j] ^ T[j];
            blockCipherDecryptBlock(layer.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) blockPtr[j] = tmp[j] ^ T[j];
            xtsMultiplyTweak(T);
        }
    }

    if (decH[0] != 'V' || decH[1] != 'E' || decH[2] != 'R' || decH[3] != 'A') {
        return false;
    }

    const uint32_t computedHdrCrc = crc32(decH, VC_HDR_CRC_COVERAGE_LEN);
    const uint32_t storedHdrCrc   = readHeaderBE32(decH, VC_HDR_OFF_HEADER_CRC);
    if (computedHdrCrc != storedHdrCrc) {
        return false;
    }

    const uint32_t computedKeyCrc = crc32(&decH[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
    const uint32_t storedKeyCrc = readHeaderBE32(decH, VC_HDR_OFF_KEY_CRC);
    if (computedKeyCrc != storedKeyCrc) {
        return false;
    }


    if (outFields) {
        outFields->volumeSize          = readHeaderBE64(decH, VC_HDR_OFF_VOLUME_SIZE);
        outFields->hiddenVolumeSize    = readHeaderBE64(decH, VC_HDR_OFF_HIDDEN_VOL_SIZE);
        outFields->encryptedAreaStart  = readHeaderBE64(decH, VC_HDR_OFF_KEY_SCOPE_START);
        outFields->encryptedAreaLength = readHeaderBE64(decH, VC_HDR_OFF_KEY_SCOPE_SIZE);
        outFields->sectorSize          = readHeaderBE32(decH, VC_HDR_OFF_SECTOR_SIZE);
    }

    return true;
}

// VeraCrypt's Argon2id header KDF always emits 192 bytes.  Argon2 output is
// length-sensitive, so deriving only a cascade's first 64/128 bytes would not
// match an official VeraCrypt volume.
bool deriveHeaderKey(HashId hash,
                            const unsigned char* password, size_t passwordLen,
                            const unsigned char* salt, int clampedPim,
                            unsigned char* out, size_t outLen,
                            const std::atomic<bool>* abortFlag) {
    if (hash == HashId::kArgon2id) {
        if (outLen != 192) return false;
        uint32_t memoryKiB = 0;
        uint32_t timeCost = 0;
        uint32_t parallelism = 0;
        argon2ParamsForPim(clampedPim, memoryKiB, timeCost, parallelism);
        return argon2idDeriveKey(password, passwordLen, salt, VC_SALT_SIZE,
                                 memoryKiB, timeCost, parallelism, out, outLen);
    }
    return pbkdf2Hmac(hash, password, passwordLen, salt, VC_SALT_SIZE,
                       iterationsForHash(hash, clampedPim), out, outLen, abortFlag);
}

std::mutex derivationMutexes[MAX_VOLUMES];
bool deriveAndValidateHeader(
    const unsigned char headerSector[VC_FULL_HEADER_SIZE],
    const unsigned char* password, size_t passwordLen, int pim,
    int cipherIdParam, int hashIdParam,
    unsigned char outKeyMaterial[192],
    unsigned char outDecryptedHeader[VC_HEADER_BODY_SIZE], // Out parameter filled with the decrypted header body on success.
    CascadeId& outMatchedCipher,
    HashId& outMatchedHash,
    ParsedHeaderFields& outFields,
    int volId

) {
    const auto timingStart = std::chrono::steady_clock::now();
    const unsigned char* salt = headerSector;
    const unsigned char* encH = headerSector + VC_SALT_SIZE;
    const int safePim = clampPim(pim);

    std::vector<HashId> hashesToTry;
    if (hashIdParam != 255) {
        hashesToTry.push_back(static_cast<HashId>(hashIdParam));
    } else {
        hashesToTry = { HashId::kSha512, HashId::kSha256, HashId::kWhirlpool,
                        HashId::kStreebog, HashId::kBlake2s256, HashId::kArgon2id };
    }

    std::vector<CascadeId> ciphersToTry;
    if (cipherIdParam != 255) {
        ciphersToTry.push_back(static_cast<CascadeId>(cipherIdParam));
    } else {
        ciphersToTry = {
            CascadeId::kAes,
            CascadeId::kSerpent,
            CascadeId::kTwofish,
            CascadeId::kAesTwofish,
            CascadeId::kSerpentAes,
            CascadeId::kTwofishSerpent,
            CascadeId::kAesTwofishSerpent,
            CascadeId::kSerpentTwofishAes,
            CascadeId::kCamellia,
            CascadeId::kKuznyechik,
            CascadeId::kCamelliaKuznyechik,
            CascadeId::kCamelliaSerpent,
            CascadeId::kKuznyechikAes,
            CascadeId::kKuznyechikSerpentCamellia,
            CascadeId::kKuznyechikTwofish,
        };
    }
    const int totalHashSteps = static_cast<int>(hashesToTry.size());

    if (isUnlockCancelled(volId)) return false;

    // Optimistic check: try a 64-byte Fast Path (AES + SHA-512) directly to avoid trying all combinations if default is used.
    if (cipherIdParam == 255 && hashIdParam == 255) {
        reportUnlockProgress(volId, 0, totalHashSteps,
                              static_cast<int>(HashId::kSha512), static_cast<int>(CascadeId::kAes));
        const int fastIter = iterationsForHash(HashId::kSha512, safePim);
        
        unsigned char fastKey[64]; 
        if (pbkdf2Hmac(HashId::kSha512, password, passwordLen,
                        salt, VC_SALT_SIZE, fastIter, fastKey, 64)) {
            unsigned char decH[VC_HEADER_BODY_SIZE];
            ParsedHeaderFields fastFields;
            if (tryDecryptHeader(encH, CascadeId::kAes, fastKey, decH, &fastFields)) {
                std::memcpy(outKeyMaterial, &decH[VC_KEY_OFFSET_MASTER], 64);
                std::memcpy(outDecryptedHeader, decH, VC_HEADER_BODY_SIZE);
                outMatchedCipher = CascadeId::kAes;
                outMatchedHash   = HashId::kSha512;
                outFields        = fastFields;
                mbedtls_platform_zeroize(decH, sizeof(decH));
                mbedtls_platform_zeroize(fastKey, sizeof(fastKey));
                return true;
            }
            mbedtls_platform_zeroize(decH, sizeof(decH));
        }
        mbedtls_platform_zeroize(fastKey, sizeof(fastKey));
        
    }

    if (isUnlockCancelled(volId)) return false;

    std::atomic<bool> found{false};
    std::atomic<int> combinationsAttempted{0};
    std::mutex resultMutex;
    unsigned char resultKeyMaterial[192] = {0};
    CascadeId resultCipher{};
    HashId resultHash{};
    ParsedHeaderFields resultFields;

    int maxLayersToTry = 1;
    for (CascadeId c : ciphersToTry) {
        maxLayersToTry = std::max(maxLayersToTry, cascadeSpecFor(c).layerCount);
    }
    const size_t neededKeyBytes = static_cast<size_t>(maxLayersToTry) * 64;

    auto worker = [&](HashId h) {
        if (found.load(std::memory_order_acquire) || isUnlockCancelled(volId)) return;

        unsigned char derivedKeyMaterial[192] = {0};

        // Argon2id's 192-byte header key is intentionally derived in full;
        // PBKDF2 only needs the longest selected cascade's key material.
        const size_t outputBytes = h == HashId::kArgon2id ? 192 : neededKeyBytes;
        if (!deriveHeaderKey(h, password, passwordLen, salt, safePim,
                             derivedKeyMaterial, outputBytes, &found)) {
            reportUnlockProgress(volId, combinationsAttempted.fetch_add(1) + 1, totalHashSteps,
                                 static_cast<int>(h), -1);
            return;
        }

        if (found.load(std::memory_order_acquire) || isUnlockCancelled(volId)) {
            mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
            return;
        }

        unsigned char decH[VC_HEADER_BODY_SIZE];
        int lastCipherTried = -1;
        for (CascadeId c : ciphersToTry) {
            if (found.load(std::memory_order_acquire) || isUnlockCancelled(volId)) break;
            lastCipherTried = static_cast<int>(c);
            ParsedHeaderFields candidateFields;
            if (tryDecryptHeader(encH, c, derivedKeyMaterial, decH, &candidateFields)) {
                bool expected = false;
                if (found.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
                    std::lock_guard<std::mutex> lock(resultMutex);
                    std::memcpy(resultKeyMaterial, derivedKeyMaterial, 192); 
                    std::memcpy(outDecryptedHeader, decH, VC_HEADER_BODY_SIZE);
                    resultCipher = c;
                    resultHash = h;
                    resultFields = candidateFields;
                }
                mbedtls_platform_zeroize(decH, sizeof(decH));
                mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
                reportUnlockProgress(volId, combinationsAttempted.fetch_add(1) + 1, totalHashSteps,
                                     static_cast<int>(h), lastCipherTried);
                return;
            }
        }
        mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
        reportUnlockProgress(volId, combinationsAttempted.fetch_add(1) + 1, totalHashSteps,
                             static_cast<int>(h), lastCipherTried);
    };

    if (hashesToTry.size() <= 1) {
        worker(hashesToTry[0]);
    } else {
        std::vector<std::future<void>> futures;
        futures.reserve(hashesToTry.size());
        for (HashId h : hashesToTry) {
            futures.push_back(ThreadPool::getInstance().enqueue(worker, h));
        }
        for (auto& f : futures) f.get();
    }

    if (!found.load(std::memory_order_acquire)) {
        if (isUnlockCancelled(volId)) {
            LOGI("deriveAndValidateHeader: cancelled after %lld ms (vol=%d)", elapsedMs(timingStart), volId);
        } else {
            LOGI("deriveAndValidateHeader: failed after %lld ms (cipher=%d hash=%d)",
                 elapsedMs(timingStart), cipherIdParam, hashIdParam);
        }
        return false;
    }

    std::memcpy(outKeyMaterial, resultKeyMaterial, sizeof(resultKeyMaterial));
    outMatchedCipher = resultCipher;
    outMatchedHash = resultHash;
    outFields = resultFields;
    mbedtls_platform_zeroize(resultKeyMaterial, sizeof(resultKeyMaterial));
    LOGI("deriveAndValidateHeader: success in %lld ms (cipher=%d hash=%d hidden=%d)",
         elapsedMs(timingStart), static_cast<int>(resultCipher), static_cast<int>(resultHash),
         resultFields.isHiddenVolume() ? 1 : 0);
    return true;
}

static bool prepareLuksSession(int fd, const unsigned char* password, size_t passwordLen, int volId,
                                const unsigned char* preservedKey, size_t preservedKeyLen,
                                const int* keyfileFds, int keyfileCount) {
    if (volId < 0 || volId >= MAX_VOLUMES) { if (fd >= 0) close(fd); closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }
    if (fd < 0) { closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }

    VolumeState& v = volumes[volId];

    // ── Passphrase resolution. Real LUKS (cryptsetup) treats a keyfile as a
    // *replacement* for the typed passphrase, not an additive mix-in the way
    // VeraCrypt's keyfile pool works here — a keyslot is unlocked by EITHER
    // a password OR a keyfile, never both combined. If a keyfile is
    // attached, its raw bytes become the passphrase and the typed password
    // is ignored, matching `cryptsetup --key-file`. Only the first attached
    // keyfile is used. ──
    std::vector<unsigned char> keyfileBuf;
    const unsigned char* effectivePassword = password;
    size_t effectivePasswordLen = passwordLen;

    if (keyfileCount > 0 && keyfileFds != nullptr && keyfileFds[0] >= 0) {
        constexpr size_t kMaxKeyfileBytes = 1024 * 1024;
        keyfileBuf.resize(kMaxKeyfileBytes);
        ssize_t total = 0, n;
        while (total < static_cast<ssize_t>(kMaxKeyfileBytes) &&
               (n = read(keyfileFds[0], keyfileBuf.data() + total, kMaxKeyfileBytes - total)) > 0) {
            total += n;
        }
        keyfileBuf.resize(total > 0 ? total : 0);
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        if (keyfileBuf.empty()) {
            LOGI("prepareLuksSession(vol=%d): keyfile unreadable or empty", volId);
            close(fd);
            return false;
        }
        effectivePassword = keyfileBuf.data();
        effectivePasswordLen = keyfileBuf.size();
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    uint64_t fileSize = 0;
    struct stat st;
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    LuksVolumeInfo luksInfo;

    auto cancelCheck = [volId](int) -> bool {
        return isUnlockCancelled(volId);
    };
    auto progressCb = [volId](int step, int total, int hashId, int cipherId) {
        int format = (cipherId == 1) ? 2 : 1; // 1 = FMT_LUKS1, 2 = FMT_LUKS2
        reportUnlockProgress(volId, step, total, hashId, 0, format);
    };

    const bool usingPreservedKey = (preservedKey != nullptr && preservedKeyLen > 0);
    if (!luksRecoverMasterKey(fd,
                              usingPreservedKey ? nullptr : effectivePassword,
                              usingPreservedKey ? 0 : effectivePasswordLen,
                              luksInfo, volId, cancelCheck, progressCb,
                              usingPreservedKey ? preservedKey : nullptr,
                              usingPreservedKey ? preservedKeyLen : 0)) {
        close(fd);
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        return false;
    }

    // Only xts-plain64 is implemented on the sector-crypto side below —
    // refuse rather than silently mounting something we'd decrypt wrong.
    if (luksInfo.cipherMode.rfind("xts-plain64", 0) != 0) {
        LOGI("prepareLuksSession(vol=%d): unsupported cipher mode '%s'", volId, luksInfo.cipherMode.c_str());
        mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        close(fd);
        return false;
    }

    // Maps the LUKS header's plain-text cipher name to this app's CascadeId
    // — the same canonical numbering Dart's CipherAlgo/crypto_algorithms.dart
    // uses, so matchedCipherId reports consistently whether the session
    // came from VeraCrypt or LUKS. Only single-layer ciphers make sense
    // here: dm-crypt/LUKS has no concept of a cascade (one segment maps to
    // exactly one dm-crypt cipher spec), unlike VeraCrypt's
    // AES-Twofish-Serpent-style stacks — cryptsetup itself has no way to
    // express those, so they were never real LUKS options to begin with.
    CascadeId dataCipher;
    if (luksInfo.cipherName == "aes") dataCipher = CascadeId::kAes;
    else if (luksInfo.cipherName == "serpent") dataCipher = CascadeId::kSerpent;
    else if (luksInfo.cipherName == "twofish") dataCipher = CascadeId::kTwofish;
    else if (luksInfo.cipherName == "camellia") dataCipher = CascadeId::kCamellia;
    else if (luksInfo.cipherName == "kuznyechik") dataCipher = CascadeId::kKuznyechik;
    else {
        LOGI("prepareLuksSession(vol=%d): unsupported cipher '%s'", volId, luksInfo.cipherName.c_str());
        mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        close(fd);
        return false;
    }
    int mappedHash = 0; // kSha512, display-only for LUKS

    // Cipher dispatch: AES gets mbedTLS's accelerated XTS directly (as
    // before); every other single-layer cipher cryptsetup commonly pairs
    // with xts-plain64 — Serpent/Twofish/Camellia/Kuznyechik — goes through
    // the same single-layer CascadeContext machinery the VeraCrypt cascade
    // path already uses, via cascadeSetKeys(..., dataCipher, ...).
    const bool isGenericCipher = (dataCipher != CascadeId::kAes);
    CascadeContext genericCascade;

    bool keySetupOk;
    if (!isGenericCipher) {
        const size_t xtsKeyBits = luksInfo.keyBytes * 8;
        keySetupOk = (mbedtls_aes_xts_setkey_dec(&v.luksXts.dec, luksInfo.masterKey.data(), xtsKeyBits) == 0 &&
                      mbedtls_aes_xts_setkey_enc(&v.luksXts.enc, luksInfo.masterKey.data(), xtsKeyBits) == 0);
    } else {
        CascadeSpec spec = cascadeSpecFor(dataCipher);
        if (spec.layerCount != 1 || luksInfo.masterKey.size() != static_cast<size_t>(spec.layerCount) * 64) {
            LOGI("prepareLuksSession(vol=%d): unsupported key size for %s (need %zu bytes, got %zu)",
                 volId, luksInfo.cipherName.c_str(), static_cast<size_t>(spec.layerCount) * 64,
                 luksInfo.masterKey.size());
            keySetupOk = false;
        } else {
            keySetupOk = cascadeSetKeys(genericCascade, dataCipher,
                                         luksInfo.masterKey.data(), luksInfo.masterKey.size());
        }
    }
    if (!keySetupOk) {
        mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        close(fd);
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.fd = fd;
        v.dataOffset = luksInfo.dataOffsetBytes;
        v.dataAreaLengthBytes = fileSize - luksInfo.dataOffsetBytes;
        v.isHiddenVolume = false;
        v.fileSize = fileSize;
        v.matchedCipherId = static_cast<int>(dataCipher);
        v.matchedHashId = mappedHash;
        v.luksSectorSize = (luksInfo.dataSectorSize >= 512) ? luksInfo.dataSectorSize : 512;
        v.luksUsesGenericCipher = isGenericCipher;
        
        // Both LUKS1 and LUKS2 use segment-relative tweak counters on Linux (iv_offset == 0).
        // The segment's "iv_tweak" (always 0 for LUKS1) is added to a counter that starts at 0
        // at the FIRST sector of the payload. Folding both the payload offset and iv_tweak
        // into partitionStartSector lets disk_read/disk_write's existing
        // "physSector - partitionStartSector" arithmetic land on the correct dm-crypt sector value:
        //   (physSector - segmentStartSector) / sectorsPerUnit + ivTweak
        const uint64_t segmentStartSector = luksInfo.dataOffsetBytes / 512;
        const uint64_t sectorsPerUnit = v.luksSectorSize / 512;
        v.partitionStartSector = segmentStartSector - (luksInfo.ivTweak * sectorsPerUnit);
        
        v.containerFormat = luksInfo.version == 1

            ? ContainerFormat::kLuks1 : ContainerFormat::kLuks2;
        if (isGenericCipher) {
            v.luksGenericCascade = genericCascade;
            v.luksXts.initialized = false;
        } else {
            v.luksXts.initialized = true;
            v.luksGenericCascade.initialized = false;
        }
        v.dataCtxInitialized = true;

        // Cache the recovered master key for quick-unlock — same
        // preservedDerivedKey slot VeraCrypt uses, read by
        // getLastDerivedKeyMaterialNative() and reused via
        // luksRecoverMasterKey's candidateMasterKey fast path above.
        if (v.preservedDerivedKey) delete[] v.preservedDerivedKey;
        v.preservedDerivedKey = new unsigned char[luksInfo.masterKey.size()];
        memcpy(v.preservedDerivedKey, luksInfo.masterKey.data(), luksInfo.masterKey.size());
        v.preservedDerivedKeyLen = luksInfo.masterKey.size();
    }

    mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
    if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());

    LOGI("prepareLuksSession(vol=%d): LUKS%d unlocked, cipher=%s, dataOffset=%llu, keyBytes=%u, "
         "sectorSize=%u, ivTweak=%llu, partitionStartSector=%llu, cachedKey=%d",
         volId, luksInfo.version, luksInfo.cipherName.c_str(),
         (unsigned long long)luksInfo.dataOffsetBytes, luksInfo.keyBytes,
         v.luksSectorSize, (unsigned long long)luksInfo.ivTweak,
         (unsigned long long)v.partitionStartSector, usingPreservedKey ? 1 : 0);
    return true;
}

bool prepareSession(int fd, const unsigned char* password, size_t passwordLen, int pim, int volId, bool forceDerive, int cipherId, int hashId, const unsigned char* preservedKey, size_t preservedKeyLen, const int* keyfileFds, int keyfileCount) {
    const auto opStart = std::chrono::steady_clock::now();
    if (volId < 0 || volId >= MAX_VOLUMES) { if (fd >= 0) close(fd); closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }
    VolumeState& v = volumes[volId];

    if (!forceDerive) {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.dataCtxInitialized && v.fd >= 0) { if (fd >= 0) close(fd); closeUnusedKeyfileFds(keyfileFds, keyfileCount); return true; }
    }
    if (fd < 0) { closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }

    std::lock_guard<std::mutex> derivationLock(derivationMutexes[volId]);
    
    uint64_t fileSize = 0;
    struct stat st;
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    // ── LUKS detection ────────────────────────────────────────────────────
    {
        unsigned char magicBuf[6];
        if (pread(fd, magicBuf, 6, 0) == 6 && isLuksContainer(magicBuf, 6)) {
            return prepareLuksSession(fd, password, passwordLen, volId,
                                       preservedKey, preservedKeyLen,
                                       keyfileFds, keyfileCount);
        }
    }

    struct HeaderSlot { uint64_t fileOffset; };
    static constexpr HeaderSlot kHeaderSlots[] = { { 0 }, { VC_HIDDEN_HEADER_OFFSET } };

    unsigned char dKey[192];           // PBKDF2 result (Key to Header)
    unsigned char decH[VC_HEADER_BODY_SIZE]; // Decrypted Header Body
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;
    bool matched = false;

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = 0;
    const bool usingPreservedKey = (preservedKey != nullptr && preservedKeyLen > 0);
    if (!usingPreservedKey) {
        mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
        memcpy(mixedPassword, password, mixedPasswordLen);
        if (keyfileCount > 0 && !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("prepareSession(vol=%d): keyfile mixing failed (unreadable/empty keyfile)", volId);
            close(fd);
            return false;
        }
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    for (const auto& slot : kHeaderSlots) {
        unsigned char headerSector[VC_FULL_HEADER_SIZE];
        if (pread(fd, headerSector, VC_FULL_HEADER_SIZE, static_cast<off_t>(slot.fileOffset)) != VC_FULL_HEADER_SIZE) continue;

        if (usingPreservedKey) {
            CascadeId candidateCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
            unsigned char candidateKey[192];
            memset(candidateKey, 0, 192);
            memcpy(candidateKey, preservedKey, std::min(preservedKeyLen, (size_t)192));

            if (tryDecryptHeader(headerSector + VC_SALT_SIZE, candidateCipher, candidateKey, decH, &fields)) {
                memcpy(dKey, candidateKey, 192);
                matchedCipher = candidateCipher;
                matchedHash = (hashId != 255) ? static_cast<HashId>(hashId) : HashId::kSha512;
                matched = true;
                break;
            }
        } else {
            if (deriveAndValidateHeader(headerSector, mixedPassword, mixedPasswordLen, pim, cipherId, hashId, dKey, decH, matchedCipher, matchedHash, fields, volId)) {
                matched = true;
                break;
            }
        }
    }

    if (!matched) { close(fd); return false; }


    CascadeContext candidateCascade;
    CascadeSpec spec = cascadeSpecFor(matchedCipher);
    const unsigned char* masterKeyPtr = &decH[VC_KEY_OFFSET_MASTER]; 


    if (!cascadeSetKeys(candidateCascade, matchedCipher, masterKeyPtr, spec.layerCount * 64)) {
        close(fd); return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.preservedDerivedKey) delete[] v.preservedDerivedKey;
        v.preservedDerivedKey = new unsigned char[192];
        memcpy(v.preservedDerivedKey, dKey, 192); // Store PBKDF2 for future "preserved" unlocks
        v.preservedDerivedKeyLen = 192;

        v.cascade = candidateCascade;
        v.dataCtxInitialized = true;
        v.fd = fd;
        v.dataOffset = fields.encryptedAreaStart;
        v.dataAreaLengthBytes = fields.encryptedAreaLength;
        v.isHiddenVolume = fields.isHiddenVolume();
        v.fileSize = fileSize;
        v.matchedCipherId = (int)matchedCipher;
        v.matchedHashId = (int)matchedHash;
        v.partitionStartSector = 0; // For files, absolute tweak = physical sector
    }
    return true;
}


bool prepareUsbSession(const unsigned char* password, size_t passwordLen, int pim, int volId, int cipherId, int hashId, const unsigned char* preservedKey, size_t preservedKeyLen, int64_t partitionOffsetHint, const int* keyfileFds, int keyfileCount) {
    if (volId < 0 || volId >= MAX_VOLUMES) { closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }
    VolumeState& v = volumes[volId];
    std::lock_guard<std::mutex> derivationLock(derivationMutexes[volId]);
    {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.dataCtxInitialized && v.isUsbSource) {
            LOGI("prepareUsbSession(vol=%d): session prepared by another thread", volId);
            closeUnusedKeyfileFds(keyfileFds, keyfileCount);
            return true;
        }
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = 0;
    const bool usingPreservedKey = (preservedKey != nullptr && preservedKeyLen > 0);
    if (!usingPreservedKey) {
        mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
        memcpy(mixedPassword, password, mixedPasswordLen);
        if (keyfileCount > 0 && !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("prepareUsbSession(vol=%d): keyfile mixing failed (unreadable/empty keyfile)", volId);
            return false;
        }
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    std::vector<PartitionCandidate> partitions;

    std::unique_ptr<unsigned char[]> diskBuf(new unsigned char[34 * 512]);
    if (usbReadSectors(volId, 0, 34, diskBuf.get())) {
        const unsigned char* sector0 = diskBuf.get();
        const unsigned char* sector1 = diskBuf.get() + 512;
        const unsigned char* gptEntries = diskBuf.get() + 1024;

        if (sector0[510] == 0x55 && sector0[511] == 0xAA) {
            bool isGpt = false;
            
            for (int i = 0; i < 4; i++) {
                const unsigned char* entry = &sector0[446 + i * 16];
                uint8_t type = entry[4];
                if (type == 0xEE) {
                    isGpt = true;
                    break;
                }
                uint32_t startLba = readUint32LE(&entry[8]);
                uint32_t numSectors = readUint32LE(&entry[12]);
                if (startLba > 0 && numSectors > 0) {
                    partitions.push_back({startLba, numSectors});
                }
            }

            if (isGpt && memcmp(sector1, "EFI PART", 8) == 0) {
                uint32_t numEntries = readUint32LE(&sector1[80]);
                uint32_t entrySize = readUint32LE(&sector1[84]);
                
                if (entrySize >= 128 && numEntries <= 128) {
                    for (uint32_t i = 0; i < numEntries; i++) {
                        const unsigned char* entry = gptEntries + (i * entrySize);
                        
                        bool unused = true;
                        for (int g = 0; g < 16; g++) {
                            if (entry[g] != 0) { unused = false; break; }
                        }
                        if (unused) continue;

                        uint64_t startLba = readUint64LE(&entry[32]);
                        uint64_t endLba = readUint64LE(&entry[40]);
                        if (startLba > 0 && endLba >= startLba) {
                            partitions.push_back({startLba, endLba - startLba + 1});
                        }
                    }
                }
            }
        }
    }

    partitions.push_back({0, 0});

    if (partitionOffsetHint >= 0) {
        const uint64_t hint = static_cast<uint64_t>(partitionOffsetHint);
        auto hintIt = std::find_if(partitions.begin(), partitions.end(),
            [hint](const PartitionCandidate& p) { return p.startSector == hint; });
        if (hintIt != partitions.end()) {
            std::iter_swap(partitions.begin(), hintIt);
        } else {
            partitions.insert(partitions.begin(), {hint, 0});
        }
    }

    struct HeaderSlot { uint64_t sectorOffset; };
    static constexpr HeaderSlot kHeaderSlots[] = {
        { 0 },
        { VC_HIDDEN_HEADER_OFFSET / 512 },
    };

    bool fsFound = false;
    uint64_t foundDataOffset = 0;
    uint64_t foundDataLength = 0;
    bool foundIsHidden = false;
    CascadeContext candidateCascade;
    uint64_t matchedPartitionStart = 0;
    CascadeId matchedCipherFound{};
    HashId matchedHashFound{};
    std::vector<unsigned char> derivedKeyBytes;

    for (const auto& part : partitions) {
        for (const auto& slot : kHeaderSlots) {
            const uint64_t headerSector = part.startSector + slot.sectorOffset;

            unsigned char dKey[192]{};
            unsigned char decH[VC_HEADER_BODY_SIZE]; // Holds the decrypted header fields on successful decryption.
            CascadeId matchedCipher{};
            HashId matchedHash{};
            ParsedHeaderFields fields;
            bool derivedSuccessfully = false;

            if (usingPreservedKey) {
                unsigned char headerBuf[VC_FULL_HEADER_SIZE];
                if (!usbReadSectors(volId, headerSector, 1, headerBuf)) continue;

                CascadeId candidateCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
                const size_t bytesToCopy = std::min(preservedKeyLen, (size_t)192);
                memcpy(dKey, preservedKey, bytesToCopy);
                

                if (tryDecryptHeader(headerBuf + VC_SALT_SIZE, candidateCipher, dKey, decH, &fields)) {
                    matchedCipher = candidateCipher;
                    matchedHash = (hashId != 255) ? static_cast<HashId>(hashId) : HashId::kSha512;
                    derivedSuccessfully = true;
                }
            } else {
                unsigned char headerBuf[VC_FULL_HEADER_SIZE];
                if (!usbReadSectors(volId, headerSector, 1, headerBuf)) continue;


                derivedSuccessfully = deriveAndValidateHeader(headerBuf, mixedPassword, mixedPasswordLen, pim, cipherId, hashId,
                                         dKey, decH, matchedCipher, matchedHash, fields, volId);
            }

            if (!derivedSuccessfully) {
                mbedtls_platform_zeroize(dKey, sizeof(dKey));
                continue;
            }

            // Extract Master Key from decH
            CascadeSpec spec = cascadeSpecFor(matchedCipher);
            const unsigned char* masterKeyPtr = &decH[VC_KEY_OFFSET_MASTER]; // Point to the master key material inside the decrypted header body.
            
            if (!cascadeSetKeys(candidateCascade, matchedCipher, masterKeyPtr, spec.layerCount * 64)) {
                mbedtls_platform_zeroize(dKey, sizeof(dKey));
                continue;
            }

            fsFound = true;
            foundDataOffset = part.startSector * 512 + fields.encryptedAreaStart;
            foundDataLength = fields.encryptedAreaLength;
            foundIsHidden   = fields.isHiddenVolume();
            matchedPartitionStart = part.startSector;
            matchedCipherFound = matchedCipher;
            matchedHashFound = matchedHash;
            derivedKeyBytes.assign(dKey, dKey + sizeof(dKey));
            mbedtls_platform_zeroize(dKey, sizeof(dKey));
            break;
        }
        if (fsFound) break;
    }

    if (!fsFound) {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (preservedKey == nullptr || preservedKeyLen == 0) {
            if (v.preservedDerivedKey != nullptr) {
                mbedtls_platform_zeroize(v.preservedDerivedKey, v.preservedDerivedKeyLen);
                delete[] v.preservedDerivedKey;
            }
            v.preservedDerivedKey = new unsigned char[derivedKeyBytes.size()];
            std::memcpy(v.preservedDerivedKey, derivedKeyBytes.data(), derivedKeyBytes.size());
            v.preservedDerivedKeyLen = derivedKeyBytes.size();
        }
        v.cascade = candidateCascade;
        v.isUsbSource          = true;
        v.dataCtxInitialized   = true;
        v.fd                   = -1;
        v.dataOffset           = foundDataOffset;
        v.dataAreaLengthBytes  = foundDataLength;
        v.isHiddenVolume       = foundIsHidden;
        v.partitionStartSector = matchedPartitionStart;
        v.matchedCipherId      = static_cast<int>(matchedCipherFound);
        v.matchedHashId        = static_cast<int>(matchedHashFound);
    }
    return true;
}