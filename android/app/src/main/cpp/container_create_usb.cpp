#include "container_create.h"
#include <cstring>
#include <memory>
#include <android/log.h>
#include "block_io.h"
#include "crypto/cascade.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "volume_state.h"
#include "ext_backend.h"
#include "mbedtls/platform_util.h"
#include "session_prepare.h"
#include "container_utils.h"
#include "ff.h"
#include "filesystem_paths.h"
#include <cstdio>
#undef min
#undef max
#include <algorithm>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

static constexpr uint64_t CREATE_FILL_BATCH = 4096;
extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);

static constexpr int MKFS_WORK_BUF_SIZE = 4096;

bool createUsbContainer(int volId, uint64_t startSector, const char* password, int pim, int64_t sizeBytes,
                        const char* fileSystem, int cipherId, int hashId,
                        const int* keyfileFds, int keyfileCount, bool quickFormat) {
    LOGI("createUsbContainer: ENTER volId=%d startSector=%llu sizeBytes=%lld fs=%s",
         volId, (unsigned long long)startSector, (long long)sizeBytes, fileSystem);

    bool success = false;
    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(strlen(password), sizeof(mixedPassword));
    memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("createUsbContainer: keyfile mixing failed");
            return false;
        }
    }
    if (mixedPasswordLen == 0) {
        LOGI("createUsbContainer: empty password and no usable keyfiles");
        return false;
    }

    if (volId < 0 || volId >= FF_VOLUMES) {
        LOGI("createUsbContainer: invalid volId %d", volId);
        return false;
    }

    // ── CRITICAL: mark this VolumeState as USB-backed BEFORE any
    // physicalWrite() call. physicalWrite() branches on v.isUsbSource to
    // decide between usbWriteSectors() and pwrite(v.fd, ...) — a fresh
    // VolumeState defaults isUsbSource=false and fd=-1, so every write
    // below would previously fall into pwrite(-1, ...) and fail silently,
    // aborting creation before a single byte reached the device. ──
    VolumeState& v = volumes[volId];
    {
        std::lock_guard<std::mutex> vlock(v.mutex);
        v.isUsbSource = true;
        v.fd = -1;
        v.partitionStartSector = startSector;
        v.dataCtxInitialized = false; // not ready for I/O via disk_read/disk_write yet, just physicalWrite
    }

    CascadeId createCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
    HashId    createHash   = (hashId   != 255) ? static_cast<HashId>(hashId)      : HashId::kSha512;
    CascadeSpec cSpec      = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char salt[VC_SALT_SIZE]   = {0};
    unsigned char combinedMasterKey[192] = {0};

    do {
        if (sizeBytes < static_cast<int64_t>(300 * 1024)) {
            LOGI("createUsbContainer: sizeBytes too small (%lld)", (long long)sizeBytes);
            break;
        }

        const bool useExFat = (strncasecmp(fileSystem, "exfat", 5) == 0);
const bool useNtfs  = (strncasecmp(fileSystem, "ntfs", 4) == 0);
const bool useFat   = (strncasecmp(fileSystem, "fat", 3) == 0) && !useExFat;
const bool useExt   = strncasecmp(fileSystem, "ext2", 4) == 0 ||
                      strncasecmp(fileSystem, "ext3", 4) == 0 ||
                      strncasecmp(fileSystem, "ext4", 4) == 0;
    if (!useExFat && !useNtfs && !useFat && !useExt) {
    LOGI("createUsbContainer: unsupported filesystem '%s'", fileSystem);
    break;
        }

        {
            FILE* urnd = fopen("/dev/urandom", "rb");
            if (!urnd) { LOGI("createUsbContainer: cannot open /dev/urandom"); break; }
            bool ok = (fread(salt, 1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                      (fread(combinedMasterKey, 1, static_cast<size_t>(masterKeyLen), urnd) == static_cast<size_t>(masterKeyLen));
            fclose(urnd);
            if (!ok) { LOGI("createUsbContainer: urandom read failed"); break; }
        }

        const int safePim = clampPim(pim);
        unsigned char headerKey[192] = {0};
        if (!deriveHeaderKey(createHash, mixedPassword, mixedPasswordLen, salt, safePim, headerKey, sizeof(headerKey))) {
            LOGI("createUsbContainer: header key derivation failed");
            break;
        }

        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;
        const uint64_t DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);
        LOGI("createUsbContainer: VOLUME_SIZE=%llu DATA_SIZE=%llu",
             (unsigned long long)VOLUME_SIZE, (unsigned long long)DATA_SIZE);

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));
        body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
        body[4] = 0x00; body[5] = 0x02;
        body[6] = 0x01; body[7] = 0x0b;

        for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;

        body[VC_HDR_OFF_SECTOR_SIZE]     = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02;
        body[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;

        memcpy(&body[VC_KEY_OFFSET_MASTER], combinedMasterKey, masterKeyLen);
        uint32_t keyCrc = crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_KEY_CRC] = (keyCrc >> 24) & 0xFF; body[VC_HDR_OFF_KEY_CRC + 1] = (keyCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 2] = (keyCrc >> 8) & 0xFF; body[VC_HDR_OFF_KEY_CRC + 3] = (keyCrc) & 0xFF;

        uint32_t hdrCrc = crc32(body, VC_HDR_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_HEADER_CRC] = (hdrCrc >> 24) & 0xFF; body[VC_HDR_OFF_HEADER_CRC + 1] = (hdrCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 2] = (hdrCrc >> 8) & 0xFF; body[VC_HDR_OFF_HEADER_CRC + 3] = (hdrCrc) & 0xFF;

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext hdrCtx;
            if (!cascadeSetKeys(hdrCtx, createCipher, headerKey, masterKeyLen)) {
                LOGI("createUsbContainer: cascadeSetKeys failed for header");
                break;
            }
            std::memcpy(encBody, body, VC_HEADER_BODY_SIZE);
            for (int layer = cSpec.layerCount - 1; layer >= 0; layer--) {
                const XtsLayerKey& lk = hdrCtx.layers[layer];
                unsigned char T[16] = {0};
                blockCipherEncryptBlock(lk.tweakKey, T, T);
                for (int blk = 0; blk < 28; blk++) {
                    unsigned char* bp = encBody + blk * 16;
                    unsigned char tmp[16];
                    for (int j = 0; j < 16; j++) tmp[j] = bp[j] ^ T[j];
                    blockCipherEncryptBlock(lk.dataKeyEnc, tmp, tmp);
                    for (int j = 0; j < 16; j++) bp[j] = tmp[j] ^ T[j];
                    xtsMultiplyTweak(T);
                }
            }
        }

        mbedtls_platform_zeroize(headerKey, sizeof(headerKey));
        mbedtls_platform_zeroize(body, sizeof(body));

        unsigned char hdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hdrSector, salt, VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE, encBody, VC_HEADER_BODY_SIZE);

        uint64_t baseOffset = startSector * 512;
        LOGI("createUsbContainer: writing primary header at byteOffset=%llu",
             (unsigned long long)baseOffset);
        if (!physicalWrite(volId, baseOffset, hdrSector, VC_FULL_HEADER_SIZE)) {
            LOGI("createUsbContainer: primary header write FAILED");
            break;
        }
        LOGI("createUsbContainer: writing backup header at byteOffset=%llu",
             (unsigned long long)(baseOffset + VOLUME_SIZE - VC_DATA_AREA_OFFSET));
        if (!physicalWrite(volId, baseOffset + VOLUME_SIZE - VC_DATA_AREA_OFFSET, hdrSector, VC_FULL_HEADER_SIZE)) {
            LOGI("createUsbContainer: backup header write FAILED");
            break;
        }

        {
            CascadeContext dataCtx;
            if (!cascadeSetKeys(dataCtx, createCipher, combinedMasterKey, masterKeyLen)) {
                LOGI("createUsbContainer: cascadeSetKeys failed for data");
                break;
            }

            const uint64_t START_SECTOR  = VC_DATA_AREA_OFFSET / 512;
            const uint64_t TOTAL_SECTORS = (VOLUME_SIZE - VC_DATA_AREA_OFFSET) / 512;
            
            if (quickFormat) {
                // SKIP THE FILL LOOP
                LOGI("createUsbContainer: skipping zero-fill data area (quick format)");
            } else {
                LOGI("createUsbContainer: zero-filling %llu sectors starting at relative sector %llu",
                     (unsigned long long)TOTAL_SECTORS, (unsigned long long)START_SECTOR);

                const unsigned char ZERO_SECTOR[512] = {0};
                const size_t batchBufBytes = CREATE_FILL_BATCH * 512;
                std::unique_ptr<unsigned char[]> batch(new unsigned char[batchBufBytes]);
                bool writeOk = true;

                for (uint64_t s = START_SECTOR; s < TOTAL_SECTORS && writeOk; ) {
                    const uint64_t rem   = TOTAL_SECTORS - s;
                    const uint64_t count = (rem < CREATE_FILL_BATCH) ? rem : CREATE_FILL_BATCH;
                    for (uint64_t i = 0; i < count; ++i) {
                        cascadeEncryptSector(dataCtx, s + i, ZERO_SECTOR, batch.get() + i * 512);
                    }
                    const size_t want = count * 512;
                    if (!physicalWrite(volId, baseOffset + s * 512, batch.get(), want)) {
                        LOGI("createUsbContainer: data fill write FAILED at relative sector %llu",
                             (unsigned long long)s);
                        writeOk = false;
                    }
                    s += count;
                }
                if (!writeOk) break;
                LOGI("createUsbContainer: zero-fill complete");
            }
        }

        // Format drive
{
    std::lock_guard<std::mutex> vlock(v.mutex);
    cascadeSetKeys(v.cascade, createCipher, combinedMasterKey, masterKeyLen);

    v.dataOffset = baseOffset + VC_DATA_AREA_OFFSET;
    v.dataAreaLengthBytes = DATA_SIZE;
    v.fileSize = VOLUME_SIZE;
    v.dataCtxInitialized = true; // now safe for disk_read/disk_write

    bool formatted = false;

    if (useExt) {
        LOGI("createUsbContainer: formatting %s (absolute dataOffset=%llu, partitionStartSector=%llu)",
             fileSystem, (unsigned long long)v.dataOffset, (unsigned long long)v.partitionStartSector);
        formatted = formatExtVolume(volId, fileSystem);

    } else if (useNtfs) {
        char deviceName[16];
        std::snprintf(deviceName, sizeof(deviceName), "ve%d", volId);
        char* args[] = {
            const_cast<char*>("mkntfs"), const_cast<char*>("-F"),
            const_cast<char*>("-Q"), const_cast<char*>("-s"),
            const_cast<char*>("512"), const_cast<char*>("-p"),
            const_cast<char*>("0"), deviceName, nullptr
        };
        LOGI("createUsbContainer: running mkntfs on %s", deviceName);
        const int mkntfsRet = vaultexplorer_mkntfs_main(8, args);
        formatted = (mkntfsRet == 0);
        if (!formatted) {
            LOGI("createUsbContainer: mkntfs failed (%d)", mkntfsRet);
        }

    } else { // useFat || useExFat
        MKFS_PARM mp;
        memset(&mp, 0, sizeof(mp));
        mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
        mp.n_fat  = 1;
        mp.n_root = 512;
        mp.au_size = 0;
        mp.align   = 0;

        alignas(16) unsigned char mkfsBuf[MKFS_WORK_BUF_SIZE];
        FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf, sizeof(mkfsBuf));
        LOGI("createUsbContainer: f_mkfs result=%d exfat=%d", (int)fr, (int)useExFat);
        f_mount(nullptr, drivePaths[volId], 0);
        formatted = (fr == FR_OK);
    }

    v.fsMounted = false;
    v.dataCtxInitialized = false;

    if (!formatted) {
        LOGI("createUsbContainer: %s formatter failed", fileSystem);
        break;
    }
    LOGI("createUsbContainer: format SUCCESS");
}

success = true;
    } while (false);

    // Leave the slot fully clean either way — this is a one-shot creation
    // call, not a persistent unlocked session. Previously only the failure
    // path reset the slot; do it unconditionally now so a stray future
    // create/unlock attempt on this volId never inherits half-set fields
    // (isUsbSource/dataOffset/cascade) from a prior successful creation.
    {
        std::lock_guard<std::mutex> vlock(v.mutex);
        v.reset();
    }

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));

    LOGI("createUsbContainer: EXIT success=%d", success ? 1 : 0);
    return success;
}

bool createUsbLuksContainer(int volId, uint64_t startSector, const char* password, int pim, int64_t sizeBytes,
                            const char* fileSystem, int luksVersion, int cipherId, int hashId,
                            const int* keyfileFds, int keyfileCount, bool quickFormat) {
    LOGI("createUsbLuksContainer: not implemented yet");
    return false;
}

bool createUsbContainerWithHidden(
    int volId, uint64_t startSector,
    const char* outerPassword, const char* hiddenPassword,
    int outerPim, int hiddenPim, int64_t sizeBytes,
    const char* outerFileSystem, const char* hiddenFileSystem,
    int64_t hiddenSizeBytes,
    int outerCipherId, int outerHashId,
    int hiddenCipherId, int hiddenHashId,
    const int* outerKeyfileFds, int outerKeyfileCount,
    const int* hiddenKeyfileFds, int hiddenKeyfileCount,
    bool quickFormat
) {
    LOGI("createUsbContainerWithHidden: volId=%d", volId);

    unsigned char mixedOuterPass[MAX_PASSWORD_LEN] = {0};
    unsigned char mixedHiddenPass[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize outerPassGuard(mixedOuterPass, sizeof(mixedOuterPass));
    ScopeZeroize hiddenPassGuard(mixedHiddenPass, sizeof(mixedHiddenPass));
    
    size_t mixedOuterLen = std::min(strlen(outerPassword), sizeof(mixedOuterPass));
    memcpy(mixedOuterPass, outerPassword, mixedOuterLen);
    size_t mixedHiddenLen = std::min(strlen(hiddenPassword), sizeof(mixedHiddenPass));
    memcpy(mixedHiddenPass, hiddenPassword, mixedHiddenLen);

    if (outerKeyfileCount > 0 && outerKeyfileFds) {
        if (!applyKeyfilesToPassword(outerKeyfileFds, outerKeyfileCount, mixedOuterPass, &mixedOuterLen)) return false;
    }
    if (hiddenKeyfileCount > 0 && hiddenKeyfileFds) {
        if (!applyKeyfilesToPassword(hiddenKeyfileFds, hiddenKeyfileCount, mixedHiddenPass, &mixedHiddenLen)) return false;
    }
    if (mixedOuterLen == 0 || mixedHiddenLen == 0) return false;

    VolumeState& v = volumes[volId];
    {
        std::lock_guard<std::mutex> vlock(v.mutex);
        v.isUsbSource = true;
        v.fd = -1;
        v.partitionStartSector = startSector;
        v.dataCtxInitialized = false;
    }

    CascadeId oCipher = (outerCipherId != 255) ? static_cast<CascadeId>(outerCipherId) : CascadeId::kAes;
    HashId    oHash   = (outerHashId   != 255) ? static_cast<HashId>(outerHashId)      : HashId::kSha512;
    CascadeSpec oSpec = cascadeSpecFor(oCipher);
    const int oMasterKeyLen = oSpec.layerCount * 64;

    CascadeId hCipher = (hiddenCipherId != 255) ? static_cast<CascadeId>(hiddenCipherId) : CascadeId::kAes;
    HashId    hHash   = (hiddenHashId   != 255) ? static_cast<HashId>(hiddenHashId)      : HashId::kSha512;
    CascadeSpec hSpec = cascadeSpecFor(hCipher);
    const int hMasterKeyLen = hSpec.layerCount * 64;

    unsigned char oSalt[VC_SALT_SIZE] = {0};
    unsigned char hSalt[VC_SALT_SIZE] = {0};
    unsigned char oMasterKey[192] = {0};
    unsigned char hMasterKey[192] = {0};
    ScopeZeroize omkGuard(oMasterKey, sizeof(oMasterKey));
    ScopeZeroize hmkGuard(hMasterKey, sizeof(hMasterKey));

    bool success = false;
    do {
        if (sizeBytes < static_cast<int64_t>(300 * 1024)) break;

        {
            FILE* urnd = fopen("/dev/urandom", "rb");
            if (!urnd) break;
            bool ok = (fread(oSalt, 1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                      (fread(oMasterKey, 1, oMasterKeyLen, urnd) == static_cast<size_t>(oMasterKeyLen)) &&
                      (fread(hSalt, 1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                      (fread(hMasterKey, 1, hMasterKeyLen, urnd) == static_cast<size_t>(hMasterKeyLen));
            fclose(urnd);
            if (!ok) break;
        }

        unsigned char oHeaderKey[192] = {0};
        unsigned char hHeaderKey[192] = {0};
        ScopeZeroize ohkGuard(oHeaderKey, sizeof(oHeaderKey));
        ScopeZeroize hhkGuard(hHeaderKey, sizeof(hHeaderKey));

        if (!deriveHeaderKey(oHash, mixedOuterPass, mixedOuterLen, oSalt, clampPim(outerPim), oHeaderKey, sizeof(oHeaderKey))) break;
        if (!deriveHeaderKey(hHash, mixedHiddenPass, mixedHiddenLen, hSalt, clampPim(hiddenPim), hHeaderKey, sizeof(hHeaderKey))) break;

        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;
        const uint64_t OUTER_DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);
        const uint64_t HIDDEN_DATA_SIZE = static_cast<uint64_t>(hiddenSizeBytes);
        const uint64_t HIDDEN_AREA_START = VOLUME_SIZE - VC_DATA_AREA_OFFSET - HIDDEN_DATA_SIZE;

        // --- Generate Outer Header ---
        unsigned char oBody[VC_HEADER_BODY_SIZE];
        memset(oBody, 0, sizeof(oBody));
        oBody[0] = 'V'; oBody[1] = 'E'; oBody[2] = 'R'; oBody[3] = 'A';
        oBody[4] = 0x00; oBody[5] = 0x02; oBody[6] = 0x01; oBody[7] = 0x0b;
        for (int i = 7; i >= 0; --i) oBody[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (OUTER_DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) oBody[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) oBody[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (OUTER_DATA_SIZE >> (i * 8)) & 0xFF;
        oBody[VC_HDR_OFF_SECTOR_SIZE] = 0x00; oBody[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00; oBody[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02; oBody[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;
        memcpy(&oBody[VC_KEY_OFFSET_MASTER], oMasterKey, oMasterKeyLen);
        uint32_t oKeyCrc = crc32(&oBody[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        oBody[VC_HDR_OFF_KEY_CRC] = (oKeyCrc >> 24) & 0xFF; oBody[VC_HDR_OFF_KEY_CRC + 1] = (oKeyCrc >> 16) & 0xFF;
        oBody[VC_HDR_OFF_KEY_CRC + 2] = (oKeyCrc >> 8) & 0xFF; oBody[VC_HDR_OFF_KEY_CRC + 3] = (oKeyCrc) & 0xFF;
        uint32_t oHdrCrc = crc32(oBody, VC_HDR_CRC_COVERAGE_LEN);
        oBody[VC_HDR_OFF_HEADER_CRC] = (oHdrCrc >> 24) & 0xFF; oBody[VC_HDR_OFF_HEADER_CRC + 1] = (oHdrCrc >> 16) & 0xFF;
        oBody[VC_HDR_OFF_HEADER_CRC + 2] = (oHdrCrc >> 8) & 0xFF; oBody[VC_HDR_OFF_HEADER_CRC + 3] = (oHdrCrc) & 0xFF;

        unsigned char oEncBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext ctx;
            cascadeSetKeys(ctx, oCipher, oHeaderKey, oMasterKeyLen);
            memcpy(oEncBody, oBody, VC_HEADER_BODY_SIZE);
            for (int layer = oSpec.layerCount - 1; layer >= 0; layer--) {
                unsigned char T[16] = {0}; blockCipherEncryptBlock(ctx.layers[layer].tweakKey, T, T);
                for (int blk = 0; blk < 28; blk++) {
                    unsigned char* bp = oEncBody + blk * 16;
                    unsigned char tmp[16]; for (int j=0; j<16; j++) tmp[j] = bp[j] ^ T[j];
                    blockCipherEncryptBlock(ctx.layers[layer].dataKeyEnc, tmp, tmp);
                    for (int j=0; j<16; j++) bp[j] = tmp[j] ^ T[j];
                    xtsMultiplyTweak(T);
                }
            }
        }

        // --- Generate Hidden Header ---
        unsigned char hBody[VC_HEADER_BODY_SIZE];
        memset(hBody, 0, sizeof(hBody));
        hBody[0] = 'V'; hBody[1] = 'E'; hBody[2] = 'R'; hBody[3] = 'A';
        hBody[4] = 0x00; hBody[5] = 0x02; hBody[6] = 0x01; hBody[7] = 0x0b;
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (HIDDEN_DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (HIDDEN_AREA_START >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (HIDDEN_DATA_SIZE >> (i * 8)) & 0xFF;
        hBody[VC_HDR_OFF_SECTOR_SIZE] = 0x00; hBody[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00; hBody[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02; hBody[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;
        memcpy(&hBody[VC_KEY_OFFSET_MASTER], hMasterKey, hMasterKeyLen);
        uint32_t hKeyCrc = crc32(&hBody[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        hBody[VC_HDR_OFF_KEY_CRC] = (hKeyCrc >> 24) & 0xFF; hBody[VC_HDR_OFF_KEY_CRC + 1] = (hKeyCrc >> 16) & 0xFF;
        hBody[VC_HDR_OFF_KEY_CRC + 2] = (hKeyCrc >> 8) & 0xFF; hBody[VC_HDR_OFF_KEY_CRC + 3] = (hKeyCrc) & 0xFF;
        uint32_t hHdrCrc = crc32(hBody, VC_HDR_CRC_COVERAGE_LEN);
        hBody[VC_HDR_OFF_HEADER_CRC] = (hHdrCrc >> 24) & 0xFF; hBody[VC_HDR_OFF_HEADER_CRC + 1] = (hHdrCrc >> 16) & 0xFF;
        hBody[VC_HDR_OFF_HEADER_CRC + 2] = (hHdrCrc >> 8) & 0xFF; hBody[VC_HDR_OFF_HEADER_CRC + 3] = (hHdrCrc) & 0xFF;

        unsigned char hEncBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext ctx;
            cascadeSetKeys(ctx, hCipher, hHeaderKey, hMasterKeyLen);
            memcpy(hEncBody, hBody, VC_HEADER_BODY_SIZE);
            for (int layer = hSpec.layerCount - 1; layer >= 0; layer--) {
                unsigned char T[16] = {0}; blockCipherEncryptBlock(ctx.layers[layer].tweakKey, T, T);
                for (int blk = 0; blk < 28; blk++) {
                    unsigned char* bp = hEncBody + blk * 16;
                    unsigned char tmp[16]; for (int j=0; j<16; j++) tmp[j] = bp[j] ^ T[j];
                    blockCipherEncryptBlock(ctx.layers[layer].dataKeyEnc, tmp, tmp);
                    for (int j=0; j<16; j++) bp[j] = tmp[j] ^ T[j];
                    xtsMultiplyTweak(T);
                }
            }
        }
        
        mbedtls_platform_zeroize(oBody, sizeof(oBody));
        mbedtls_platform_zeroize(hBody, sizeof(hBody));

        unsigned char oHdrSector[VC_FULL_HEADER_SIZE];
        memcpy(oHdrSector, oSalt, VC_SALT_SIZE);
        memcpy(oHdrSector + VC_SALT_SIZE, oEncBody, VC_HEADER_BODY_SIZE);

        unsigned char hHdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hHdrSector, hSalt, VC_SALT_SIZE);
        memcpy(hHdrSector + VC_SALT_SIZE, hEncBody, VC_HEADER_BODY_SIZE);

        uint64_t baseOffset = startSector * 512;
        
        // Write Outer Headers
        if (!physicalWrite(volId, baseOffset, oHdrSector, VC_FULL_HEADER_SIZE)) break;
        if (!physicalWrite(volId, baseOffset + VOLUME_SIZE - VC_DATA_AREA_OFFSET, oHdrSector, VC_FULL_HEADER_SIZE)) break;

        // Write Hidden Header
        if (!physicalWrite(volId, baseOffset + VC_HIDDEN_HEADER_OFFSET, hHdrSector, VC_FULL_HEADER_SIZE)) break;

        // Zero Fill
        if (!quickFormat) {
            LOGI("createUsbContainerWithHidden: filling with outer-encrypted noise");
            CascadeContext dataCtx;
            cascadeSetKeys(dataCtx, oCipher, oMasterKey, oMasterKeyLen);
            const uint64_t START_SECTOR  = VC_DATA_AREA_OFFSET / 512;
            const uint64_t TOTAL_SECTORS = (VOLUME_SIZE - VC_DATA_AREA_OFFSET) / 512;
            const unsigned char ZERO_SECTOR[512] = {0};
            std::unique_ptr<unsigned char[]> batch(new unsigned char[CREATE_FILL_BATCH * 512]);
            bool writeOk = true;

            for (uint64_t s = START_SECTOR; s < TOTAL_SECTORS && writeOk; ) {
                const uint64_t count = std::min<uint64_t>(TOTAL_SECTORS - s, CREATE_FILL_BATCH);
                for (uint64_t i = 0; i < count; ++i) cascadeEncryptSector(dataCtx, s + i, ZERO_SECTOR, batch.get() + i * 512);
                if (!physicalWrite(volId, baseOffset + s * 512, batch.get(), count * 512)) writeOk = false;
                s += count;
            }
            if (!writeOk) break;
        } else {
            LOGI("createUsbContainerWithHidden: skipping noise generation (quick format)");
        }

        // Format filesystems
        auto formatFS = [&](const char* fs, uint64_t dOffset, uint64_t dLen, CascadeId cId, const unsigned char* mKey, int mkLen) -> bool {
            std::lock_guard<std::mutex> vlock(v.mutex);
            cascadeSetKeys(v.cascade, cId, mKey, mkLen);
            v.dataOffset = baseOffset + dOffset;
            v.dataAreaLengthBytes = dLen;
            v.fileSize = VOLUME_SIZE;
            v.dataCtxInitialized = true;
            bool ok = false;
            
            if (strncasecmp(fs, "ext", 3) == 0) ok = formatExtVolume(volId, fs);
            else if (strncasecmp(fs, "ntfs", 4) == 0) {
                char devName[16]; std::snprintf(devName, sizeof(devName), "ve%d", volId);
                char* args[] = { (char*)"mkntfs", (char*)"-F", (char*)"-Q", (char*)"-s", (char*)"512", (char*)"-p", (char*)"0", devName, nullptr };
                ok = (vaultexplorer_mkntfs_main(8, args) == 0);
            } else {
                MKFS_PARM mp; memset(&mp, 0, sizeof(mp));
                mp.fmt = (strncasecmp(fs, "exfat", 5) == 0 ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
                mp.n_fat = 1; mp.n_root = 512; mp.au_size = 0; mp.align = 0;
                alignas(16) unsigned char mkfsBuf[MKFS_WORK_BUF_SIZE];
                ok = (f_mkfs(drivePaths[volId], &mp, mkfsBuf, sizeof(mkfsBuf)) == FR_OK);
                f_mount(nullptr, drivePaths[volId], 0);
            }
            v.dataCtxInitialized = false;
            return ok;
        };

        LOGI("createUsbContainerWithHidden: Formatting outer %s", outerFileSystem);
        if (!formatFS(outerFileSystem, VC_DATA_AREA_OFFSET, OUTER_DATA_SIZE, oCipher, oMasterKey, oMasterKeyLen)) break;
        
        LOGI("createUsbContainerWithHidden: Formatting hidden %s", hiddenFileSystem);
        if (!formatFS(hiddenFileSystem, HIDDEN_AREA_START, HIDDEN_DATA_SIZE, hCipher, hMasterKey, hMasterKeyLen)) break;

        success = true;
    } while (false);

    {
        std::lock_guard<std::mutex> vlock(v.mutex);
        v.reset();
    }

    return success;
}