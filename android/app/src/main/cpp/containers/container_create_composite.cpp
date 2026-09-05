#include "container_create_composite.h"
#include "composite_map.h"
#include <cstring>
#include <strings.h>
#include <algorithm>
#include <memory>
#include <cstdio>
#include <android/log.h>
#include "block_io.h"
#include "crypto/cascade.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "crypto/luks_header.h"
#include "session/volume_state.h"
#include "session/session_prepare.h"
#include "filesystems/ext_backend.h"
#include "filesystems/filesystem_paths.h"
#include "containers/container_utils.h"
#include "ff.h"

#undef min
#undef max

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_Composite", __VA_ARGS__)
extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);

namespace {
constexpr uint64_t CREATE_FILL_BATCH = 4096;
constexpr int MKFS_WORK_BUF_SIZE = 4096;
}

CompositeCreateResult createCompositeContainer(
    int volId,
    const std::vector<CarrierTarget>& carriers,
    const std::vector<CarrierExtent>& extents,
    const char* password,
    int pim,
    const char* fileSystem,
    int containerFormat,
    int cipherId,
    int hashId,
    const int* keyfileFds,
    int keyfileCount,
    bool quickFormat,
    const char* operationId
) {
    (void)containerFormat;
    (void)operationId;
    LOGI("[Create] ENTER: volId=%d carriers=%zu extents=%zu fs=%s quickFormat=%d",
         volId, carriers.size(), extents.size(), fileSystem, quickFormat ? 1 : 0);

    if (volId < 0 || volId >= FF_VOLUMES) {
        LOGI("[Create] FAIL: invalid volume id %d", volId);
        return {false, "INVALID_VOLUME_ID", "Volume slot invalid", 0};
    }

    auto fdCache = std::make_shared<CarrierFdCache>(32);
    for (const auto& c : carriers) {
        fdCache->addTarget(c.fd, c.path, c.readOnly, c.closeOnDestruct);
    }

    // Pre-expand each carrier on disk
    for (size_t i = 0; i < extents.size(); ++i) {
        const auto& extent = extents[i];
        int fd = fdCache->acquire(extent.fileIndex);
        if (fd < 0) {
            LOGI("[Create] FAIL: could not acquire carrier %u fd", extent.fileIndex);
            return {false, "CARRIER_OPEN_FAILED", "Could not open carrier file for writing", 0};
        }

        // Write ISO-BMFF (MP4/MOV) box header if applicable
        if (extent.offsetInFile >= 8) {
            unsigned char probe[8] = {0};
            if (::pread64(fd, probe + 4, 4, 4) == 4 && std::memcmp(probe + 4, "ftyp", 4) == 0) {
                uint64_t totalBoxSize = extent.lengthBytes + 8;
                unsigned char boxHdr[8];
                boxHdr[0] = static_cast<unsigned char>((totalBoxSize >> 24) & 0xFF);
                boxHdr[1] = static_cast<unsigned char>((totalBoxSize >> 16) & 0xFF);
                boxHdr[2] = static_cast<unsigned char>((totalBoxSize >> 8) & 0xFF);
                boxHdr[3] = static_cast<unsigned char>(totalBoxSize & 0xFF);
                boxHdr[4] = 'f'; boxHdr[5] = 'r'; boxHdr[6] = 'e'; boxHdr[7] = 'e';

                ::pwrite64(fd, boxHdr, 8, static_cast<off64_t>(extent.offsetInFile - 8));
                LOGI("[Create] Carrier %u: wrote MP4 'free' box header of %llu bytes", extent.fileIndex, (unsigned long long)totalBoxSize);
            }
        }

        // Attempt expansion
        uint64_t endPos = extent.offsetInFile + extent.lengthBytes;
        unsigned char zero = 0;
        if (::pwrite64(fd, &zero, 1, static_cast<off64_t>(endPos - 1)) != 1) {
            LOGI("[Create] Warning: pwrite64 expand carrier %u to %llu failed (errno=%d: %s), trying ftruncate",
                 extent.fileIndex, (unsigned long long)endPos, errno, strerror(errno));
            if (::ftruncate(fd, static_cast<off_t>(endPos)) != 0) {
                LOGI("[Create] Warning: ftruncate also failed (errno=%d: %s), proceeding with direct writes", errno, strerror(errno));
            }
        }

        fdCache->release(extent.fileIndex);
    }

    auto device = std::make_unique<CompositeBlockDevice>(extents, fdCache);
    uint64_t totalBytes = device->totalSize();
    LOGI("[Create] Composite device total logical bytes: %llu", (unsigned long long)totalBytes);
    if (totalBytes < 300 * 1024) {
        LOGI("[Create] FAIL: total bytes %llu < 300 KB", (unsigned long long)totalBytes);
        return {false, "SIZE_TOO_SMALL", "Composite capacity too small for container", totalBytes};
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(std::strlen(password), sizeof(mixedPassword));
    std::memcpy(mixedPassword, password, mixedPasswordLen);

    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("[Create] FAIL: keyfile mixing failed");
            return {false, "KEYFILE_FAILED", "Failed to mix keyfiles", 0};
        }
    }

    CascadeId createCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
    HashId createHash = (hashId != 255) ? static_cast<HashId>(hashId) : HashId::kSha512;
    CascadeSpec cSpec = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char salt[VC_SALT_SIZE] = {0};
    unsigned char combinedMasterKey[192] = {0};
    {
        FILE* urnd = fopen("/dev/urandom", "rb");
        if (!urnd) {
            LOGI("[Create] FAIL: cannot open /dev/urandom");
            return {false, "URANDOM_FAILED", "Cannot open /dev/urandom", 0};
        }
        bool ok = (fread(salt, 1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                  (fread(combinedMasterKey, 1, masterKeyLen, urnd) == static_cast<size_t>(masterKeyLen));
        fclose(urnd);
        if (!ok) {
            LOGI("[Create] FAIL: urandom read failed");
            return {false, "URANDOM_READ_FAILED", "Failed reading random bytes", 0};
        }
    }

    VolumeState& v = volumes[volId];
    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.isCompositeSource = true;
        v.composite = std::move(device);
        v.isUsbSource = false;
        v.fd = -1;
        v.partitionStartSector = 0;
        v.dataCtxInitialized = false;
    }

    const uint64_t VOLUME_SIZE = (totalBytes / 4096) * 4096;
    const uint64_t DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);
    LOGI("[Create] VOLUME_SIZE=%llu, DATA_SIZE=%llu", (unsigned long long)VOLUME_SIZE, (unsigned long long)DATA_SIZE);

    unsigned char headerKey[192] = {0};
    if (!deriveHeaderKey(createHash, mixedPassword, mixedPasswordLen, salt, clampPim(pim), headerKey, sizeof(headerKey))) {
        LOGI("[Create] FAIL: header key derivation failed");
        return {false, "KDF_FAILED", "Header key derivation failed", 0};
    }

    unsigned char body[VC_HEADER_BODY_SIZE] = {0};
    body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
    body[4] = 0x00; body[5] = 0x02; body[6] = 0x01; body[7] = 0x0b;

    for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;
    for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
    for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;
    body[VC_HDR_OFF_SECTOR_SIZE] = 0x00; body[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00;
    body[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02; body[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;
    std::memcpy(&body[VC_KEY_OFFSET_MASTER], combinedMasterKey, masterKeyLen);

    uint32_t keyCrc = container_crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
    body[VC_HDR_OFF_KEY_CRC] = (keyCrc >> 24) & 0xFF; body[VC_HDR_OFF_KEY_CRC + 1] = (keyCrc >> 16) & 0xFF;
    body[VC_HDR_OFF_KEY_CRC + 2] = (keyCrc >> 8) & 0xFF; body[VC_HDR_OFF_KEY_CRC + 3] = keyCrc & 0xFF;

    uint32_t hdrCrc = container_crc32(body, VC_HDR_CRC_COVERAGE_LEN);
    body[VC_HDR_OFF_HEADER_CRC] = (hdrCrc >> 24) & 0xFF; body[VC_HDR_OFF_HEADER_CRC + 1] = (hdrCrc >> 16) & 0xFF;
    body[VC_HDR_OFF_HEADER_CRC + 2] = (hdrCrc >> 8) & 0xFF; body[VC_HDR_OFF_HEADER_CRC + 3] = hdrCrc & 0xFF;

    unsigned char encBody[VC_HEADER_BODY_SIZE];
    {
        CascadeContext hdrCtx;
        if (!cascadeSetKeys(hdrCtx, createCipher, headerKey, masterKeyLen)) {
            LOGI("[Create] FAIL: cascadeSetKeys failed");
            return {false, "CIPHER_INIT_FAILED", "Cascade setup failed", 0};
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
    std::memcpy(hdrSector, salt, VC_SALT_SIZE);
    std::memcpy(hdrSector + VC_SALT_SIZE, encBody, VC_HEADER_BODY_SIZE);

    LOGI("[Create] Writing primary header at offset 0...");
    if (!physicalWrite(volId, 0, hdrSector, VC_FULL_HEADER_SIZE)) {
        LOGI("[Create] FAIL: primary header physicalWrite failed");
        return {false, "HEADER_WRITE_FAILED", "Failed to write primary header", 0};
    }

    uint64_t backupOffset = VOLUME_SIZE - VC_DATA_AREA_OFFSET;
    LOGI("[Create] Writing backup header at offset %llu...", (unsigned long long)backupOffset);
    if (!physicalWrite(volId, backupOffset, hdrSector, VC_FULL_HEADER_SIZE)) {
        LOGI("[Create] FAIL: backup header physicalWrite failed at %llu", (unsigned long long)backupOffset);
        return {false, "BACKUP_HEADER_WRITE_FAILED", "Failed to write backup header", 0};
    }

    if (!quickFormat) {
        LOGI("[Create] Zero-filling data area...");
        CascadeContext dataCtx;
        cascadeSetKeys(dataCtx, createCipher, combinedMasterKey, masterKeyLen);
        const uint64_t START_SECTOR = VC_DATA_AREA_OFFSET / 512;
        const uint64_t TOTAL_SECTORS = (VOLUME_SIZE - VC_DATA_AREA_OFFSET) / 512;
        const unsigned char ZERO_SECTOR[512] = {0};
        std::unique_ptr<unsigned char[]> batch(new unsigned char[CREATE_FILL_BATCH * 512]);

        for (uint64_t s = START_SECTOR; s < TOTAL_SECTORS;) {
            uint64_t count = std::min<uint64_t>(TOTAL_SECTORS - s, CREATE_FILL_BATCH);
            for (uint64_t i = 0; i < count; ++i) {
                cascadeEncryptSector(dataCtx, s + i, ZERO_SECTOR, batch.get() + i * 512);
            }
            if (!physicalWrite(volId, s * 512, batch.get(), count * 512)) {
                LOGI("[Create] FAIL: zero-fill failed at sector %llu", (unsigned long long)s);
                return {false, "FILL_FAILED", "Failed zero-filling data area", 0};
            }
            s += count;
        }
    }

    // Stamp the 16-byte composite trailer onto each carrier for instant recovery
    for (size_t i = 0; i < extents.size(); ++i) {
        const auto& extent = extents[i];
        int fd = fdCache->acquire(extent.fileIndex);
        if (fd >= 0) {
            unsigned char trailer[16];
            uint64_t off = extent.offsetInFile;
            for (int b = 7; b >= 0; --b) { trailer[b] = off & 0xFF; off >>= 8; }
            uint64_t magic = 0x5658434F4D504F53ULL; // "VXCOMPOS"
            for (int b = 15; b >= 8; --b) { trailer[b] = magic & 0xFF; magic >>= 8; }

            uint64_t trailerOffset = extent.offsetInFile + extent.lengthBytes;
            ::pwrite64(fd, trailer, 16, static_cast<off64_t>(trailerOffset));
            fdCache->release(extent.fileIndex);
        }
    }

    // Format the inner filesystem
    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        cascadeSetKeys(v.cascade, createCipher, combinedMasterKey, masterKeyLen);
        v.dataOffset = VC_DATA_AREA_OFFSET;
        v.dataAreaLengthBytes = DATA_SIZE;
        v.fileSize = VOLUME_SIZE;
        v.dataCtxInitialized = true;

        bool formatted = false;
        const bool useExFat = (strncasecmp(fileSystem, "exfat", 5) == 0);
        const bool useNtfs  = (strncasecmp(fileSystem, "ntfs", 4) == 0);
        const bool useExt   = (strncasecmp(fileSystem, "ext", 3) == 0);
        LOGI("[Create] Formatting filesystem: %s (exFat=%d, ntfs=%d, ext=%d)", fileSystem, useExFat, useNtfs, useExt);

        if (useExt) {
            formatted = formatExtVolume(volId, fileSystem);
            LOGI("[Create] formatExtVolume returned %d", formatted ? 1 : 0);
        } else if (useNtfs) {
            char deviceName[16];
            std::snprintf(deviceName, sizeof(deviceName), "ve%d", volId);
            char* args[] = {
                const_cast<char*>("mkntfs"), const_cast<char*>("-F"),
                const_cast<char*>("-Q"), const_cast<char*>("-s"),
                const_cast<char*>("512"), const_cast<char*>("-p"),
                const_cast<char*>("0"), deviceName, nullptr
            };
            int ret = vaultexplorer_mkntfs_main(8, args);
            formatted = (ret == 0);
            LOGI("[Create] mkntfs returned %d", ret);
        } else {
            MKFS_PARM mp{};
            mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
            mp.n_fat = 1; mp.n_root = 512; mp.au_size = 0; mp.align = 0;
            alignas(16) unsigned char mkfsBuf[MKFS_WORK_BUF_SIZE];
            FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf, sizeof(mkfsBuf));
            f_mount(nullptr, drivePaths[volId], 0);
            formatted = (fr == FR_OK);
            LOGI("[Create] f_mkfs returned %d (FR_OK=%d)", (int)fr, FR_OK);
        }

        v.fsMounted = false;
        v.dataCtxInitialized = false;
        if (!formatted) {
            LOGI("[Create] FAIL: filesystem formatting failed");
            return {false, "FORMAT_FAILED", "Filesystem format failed", 0};
        }
    }

    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.reset();
    }
    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));

    LOGI("[Create] SUCCESS: composite container created successfully!");
    return {true, "", "", VOLUME_SIZE};
}

bool prepareCompositeSession(
    int volId,
    const std::vector<CarrierTarget>& carriers,
    const std::vector<CarrierExtent>& extents,
    const unsigned char* password,
    size_t passwordLen,
    int pim,
    int cipherId,
    int hashId,
    const int* keyfileFds,
    int keyfileCount,
    bool readOnly
) {
    LOGI("[Unlock] ENTER: volId=%d carriers=%zu extents=%zu readOnly=%d",
         volId, carriers.size(), extents.size(), readOnly ? 1 : 0);

    if (volId < 0 || volId >= FF_VOLUMES) return false;

    auto fdCache = std::make_shared<CarrierFdCache>(32);
    for (const auto& c : carriers) {
        fdCache->addTarget(c.fd, c.path, readOnly, c.closeOnDestruct);
    }

    auto device = std::make_unique<CompositeBlockDevice>(extents, fdCache);
    uint64_t totalBytes = device->totalSize();
    LOGI("[Unlock] Composite device size: %llu bytes", (unsigned long long)totalBytes);
    if (totalBytes < 512) return false;

    unsigned char headerSector[VC_FULL_HEADER_SIZE];
    if (!device->pread(0, headerSector, VC_FULL_HEADER_SIZE)) {
        LOGI("[Unlock] FAIL: pread(0) header sector failed");
        return false;
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
    std::memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
        LOGI("[Unlock] FAIL: keyfile mixing failed");
        return false;
    }

    unsigned char dKey[192];
    unsigned char decH[VC_HEADER_BODY_SIZE];
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;

    LOGI("[Unlock] Trying primary header...");
    bool matched = deriveAndValidateHeader(
        headerSector, mixedPassword, mixedPasswordLen, pim, cipherId, hashId,
        dKey, decH, matchedCipher, matchedHash, fields, volId, nullptr, 0
    );

    if (!matched) {
        LOGI("[Unlock] Primary header didn't match, trying backup header...");
        if (totalBytes >= VC_DATA_AREA_OFFSET + VC_FULL_HEADER_SIZE) {
            uint64_t backupOffset = totalBytes - VC_DATA_AREA_OFFSET;
            if (device->pread(backupOffset, headerSector, VC_FULL_HEADER_SIZE)) {
                matched = deriveAndValidateHeader(
                    headerSector, mixedPassword, mixedPasswordLen, pim, cipherId, hashId,
                    dKey, decH, matchedCipher, matchedHash, fields, volId, nullptr, 1
                );
            }
        }
    }

    if (!matched) {
        LOGI("[Unlock] FAIL: no header verified");
        return false;
    }

    LOGI("[Unlock] Header verified successfully (cipher=%d, hash=%d)", (int)matchedCipher, (int)matchedHash);

    CascadeContext candidateCascade;
    CascadeSpec spec = cascadeSpecFor(matchedCipher);
    const unsigned char* masterKeyPtr = &decH[VC_KEY_OFFSET_MASTER];
    if (!cascadeSetKeys(candidateCascade, matchedCipher, masterKeyPtr, spec.layerCount * 64)) {
        LOGI("[Unlock] FAIL: cascadeSetKeys failed");
        return false;
    }

    VolumeState& v = volumes[volId];
    {
        std::unique_lock<std::shared_mutex> lock(v.mutex);
        v.isCompositeSource = true;
        v.composite = std::move(device);
        v.fd = -1;
        v.isUsbSource = false;
        v.cascade = candidateCascade;
        v.dataOffset = fields.encryptedAreaStart;
        v.dataAreaLengthBytes = fields.encryptedAreaLength;
        v.isHiddenVolume = fields.isHiddenVolume();
        v.fileSize = fields.volumeSize;
        v.matchedCipherId = static_cast<int>(matchedCipher);
        v.matchedHashId = static_cast<int>(matchedHash);
        v.partitionStartSector = 0;
        v.readOnly = readOnly;
        v.dataCtxInitialized = true;

        if (v.preservedDerivedKey) {
            mbedtls_platform_zeroize(v.preservedDerivedKey, v.preservedDerivedKeyLen);
            delete[] v.preservedDerivedKey;
        }
        v.preservedDerivedKey = new unsigned char[192];
        std::memcpy(v.preservedDerivedKey, dKey, 192);
        v.preservedDerivedKeyLen = 192;
    }

    LOGI("[Unlock] SUCCESS: composite session prepared for volId=%d", volId);
    return true;
}