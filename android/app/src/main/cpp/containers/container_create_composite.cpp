#include "container_create_composite.h"
#include "composite_map.h"
#include <cstring>
#include <strings.h>
#include <algorithm>
#include <memory>
#include <cstdio>
#include <vector>
#include <sys/stat.h>
#include <openssl/sha.h>
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
constexpr uint64_t CREATE_FILL_BATCH = 256;
constexpr int MKFS_WORK_BUF_SIZE = 4096;
constexpr uint64_t kBlindTagConstA = 0xBF58476D1CE4E5B9ULL;
constexpr uint64_t kBlindTagConstB = 0x94D049BB133111EBULL;

uint64_t readBe64(const unsigned char* p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | p[i];
    return v;
}

void computeHeaderDigest(int fd, unsigned char outDigest[SHA256_DIGEST_LENGTH]) {
    unsigned char buffer[4096] = {0};
    ssize_t n = ::pread64(fd, buffer, sizeof(buffer), 0);
    SHA256(buffer, n > 0 ? static_cast<size_t>(n) : 0, outDigest);
}

bool verifyExistingBlindTrailer(int fd, uint64_t curSize, uint64_t& outOffset) {
    if (curSize < 16 + 512) return false;
    unsigned char tr[16] = {0};
    if (::pread64(fd, tr, 16, static_cast<off_t>(curSize - 16)) != 16) return false;

    unsigned char digest[SHA256_DIGEST_LENGTH];
    computeHeaderDigest(fd, digest);

    uint64_t maskKey1 = readBe64(digest);
    uint64_t maskKey2 = readBe64(digest + 8);

    uint64_t encOff = readBe64(tr);
    uint64_t encTag = readBe64(tr + 8);

    uint64_t candOff = encOff ^ maskKey1;
    uint64_t expectedTag = (candOff * kBlindTagConstA + kBlindTagConstB) ^ maskKey2;

    if (encTag == expectedTag && candOff < curSize - 16) {
        outOffset = candOff;
        return true;
    }
    return false;
}
} // namespace

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
        return {false, "INVALID_VOLUME_ID", "Volume slot invalid", 0};
    }

    auto fdCache = std::make_shared<CarrierFdCache>(32);
    for (const auto& c : carriers) {
        fdCache->addTarget(c.fd, c.path, c.readOnly, c.closeOnDestruct);
    }

    for (size_t i = 0; i < extents.size(); ++i) {
        const auto& extent = extents[i];
        int fd = fdCache->acquire(extent.fileIndex);
        if (fd < 0) {
            return {false, "CARRIER_OPEN_FAILED", "Could not open carrier file for writing", 0};
        }

        // Hard Guard: Ensure extent never begins inside the host carrier's pre-existing content!
        struct stat st{};
        if (::fstat(fd, &st) == 0 && st.st_size > 0) {
            uint64_t curSize = static_cast<uint64_t>(st.st_size);

            if (extent.offsetInFile < curSize) {
                uint64_t existingOffset = 0;
                bool isRealloc = verifyExistingBlindTrailer(fd, curSize, existingOffset) &&
                                 (extent.offsetInFile >= existingOffset);

                if (!isRealloc) {
                    LOGI("[Create] CORRUPTION GUARD PREVENTED WRITE: extent.offsetInFile (%llu) < carrier fileSize (%llu)",
                         (unsigned long long)extent.offsetInFile, (unsigned long long)curSize);
                    fdCache->release(extent.fileIndex);
                    return {false, "CARRIER_CORRUPTION_GUARD", "Extent starts inside host carrier content", 0};
                }
            }
        }

        unsigned char probe[16] = {0};
        ::pread64(fd, probe, 16, 0);

        // ISO-BMFF: format 'free' box header
        if (extent.offsetInFile >= 16 && std::memcmp(probe + 4, "ftyp", 4) == 0) {
            uint64_t totalBoxSize = extent.lengthBytes + 16;
            unsigned char boxHdr[16];
            boxHdr[0] = 0x00; boxHdr[1] = 0x00; boxHdr[2] = 0x00; boxHdr[3] = 0x01;
            boxHdr[4] = 'f'; boxHdr[5] = 'r'; boxHdr[6] = 'e'; boxHdr[7] = 'e';
            for (int b = 7; b >= 0; --b) {
                boxHdr[8 + b] = static_cast<unsigned char>(totalBoxSize & 0xFF);
                totalBoxSize >>= 8;
            }
            ::pwrite64(fd, boxHdr, 16, static_cast<off_t>(extent.offsetInFile - 16));
        }

        uint64_t endPos = extent.offsetInFile + extent.lengthBytes;
        unsigned char zero = 0;
        if (::pwrite64(fd, &zero, 1, static_cast<off_t>(endPos - 1)) != 1) {
            ::ftruncate(fd, static_cast<off_t>(endPos));
        }
        fdCache->release(extent.fileIndex);
    }

    auto device = std::make_unique<CompositeBlockDevice>(extents, fdCache);
    uint64_t totalBytes = device->totalSize();

    if (totalBytes < 300 * 1024) {
        return {false, "SIZE_TOO_SMALL", "Composite capacity too small for container", totalBytes};
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(std::strlen(password), sizeof(mixedPassword));
    std::memcpy(mixedPassword, password, mixedPasswordLen);

    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
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
        if (!urnd) return {false, "URANDOM_FAILED", "Cannot open /dev/urandom", 0};
        bool ok = (fread(salt, 1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                  (fread(combinedMasterKey, 1, masterKeyLen, urnd) == static_cast<size_t>(masterKeyLen));
        fclose(urnd);
        if (!ok) return {false, "URANDOM_READ_FAILED", "Failed reading random bytes", 0};
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

    unsigned char headerKey[192] = {0};
    if (!deriveHeaderKey(createHash, mixedPassword, mixedPasswordLen, salt, clampPim(pim), headerKey, sizeof(headerKey))) {
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

    if (!physicalWrite(volId, 0, hdrSector, VC_FULL_HEADER_SIZE)) {
        return {false, "HEADER_WRITE_FAILED", "Failed to write primary header", 0};
    }

    uint64_t backupOffset = VOLUME_SIZE - VC_DATA_AREA_OFFSET;
    if (!physicalWrite(volId, backupOffset, hdrSector, VC_FULL_HEADER_SIZE)) {
        return {false, "BACKUP_HEADER_WRITE_FAILED", "Failed to write backup header", 0};
    }

    if (!quickFormat) {
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
                return {false, "FILL_FAILED", "Failed zero-filling data area", 0};
            }
            s += count;
        }
    }

    // ── Stamp Cryptographic Blind Trailer (Maximal Entropy, Zero Plaintext Signatures) ──
    for (size_t i = 0; i < extents.size(); ++i) {
        const auto& extent = extents[i];
        int fd = fdCache->acquire(extent.fileIndex);
        if (fd >= 0) {
            unsigned char digest[SHA256_DIGEST_LENGTH];
            computeHeaderDigest(fd, digest);
            uint64_t maskKey1 = readBe64(digest);
            uint64_t maskKey2 = readBe64(digest + 8);

            uint64_t off = extent.offsetInFile;
            uint64_t encOff = off ^ maskKey1;
            uint64_t tag = (off * kBlindTagConstA + kBlindTagConstB) ^ maskKey2;

            unsigned char tr[16];
            for (int b = 7; b >= 0; --b) { tr[b] = encOff & 0xFF; encOff >>= 8; }
            for (int b = 15; b >= 8; --b) { tr[b] = tag & 0xFF; tag >>= 8; }

            uint64_t trailerOffset = extent.offsetInFile + extent.lengthBytes;
            ::pwrite64(fd, tr, 16, static_cast<off_t>(trailerOffset));
            ::ftruncate(fd, static_cast<off_t>(trailerOffset + 16));
            fdCache->release(extent.fileIndex);
        }
    }
    fdCache->syncAll();

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

        if (useExt) {
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
            formatted = (vaultexplorer_mkntfs_main(8, args) == 0);
        } else {
            MKFS_PARM mp{};
            mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
            mp.n_fat = useExFat ? 1 : 2;
            mp.n_root = 512;
            mp.au_size = useExFat ? 0 : vc_fat_cluster_size(DATA_SIZE);
            mp.align = 0;
            alignas(16) unsigned char mkfsBuf[MKFS_WORK_BUF_SIZE];
            FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf, sizeof(mkfsBuf));
            f_mount(nullptr, drivePaths[volId], 0);
            formatted = (fr == FR_OK);
        }

        v.fsMounted = false;
        v.dataCtxInitialized = false;

        if (!formatted) {
            return {false, "FORMAT_FAILED", "Filesystem format failed", 0};
        }
    }

    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.reset();
    }

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));
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
    if (volId < 0 || volId >= FF_VOLUMES) return false;
    clearUnlockCancellation(volId);

    auto fdCache = std::make_shared<CarrierFdCache>(32);
    for (const auto& c : carriers) {
        fdCache->addTarget(c.fd, c.path, readOnly, c.closeOnDestruct);
    }

    auto device = std::make_unique<CompositeBlockDevice>(extents, fdCache);
    uint64_t totalBytes = device->totalSize();
    if (totalBytes < 512) return false;

    unsigned char headerSector[VC_FULL_HEADER_SIZE];
    if (!device->pread(0, headerSector, VC_FULL_HEADER_SIZE)) {
        return false;
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
    std::memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
        return false;
    }

    unsigned char dKey[192];
    unsigned char decH[VC_HEADER_BODY_SIZE];
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;

    bool matched = deriveAndValidateHeader(
        headerSector, mixedPassword, mixedPasswordLen, pim, cipherId, hashId,
        dKey, decH, matchedCipher, matchedHash, fields, volId, nullptr, 0
    );
    if (!matched) {
        const uint64_t volumeSize = (totalBytes / 4096) * 4096;
        if (volumeSize >= VC_DATA_AREA_OFFSET + VC_FULL_HEADER_SIZE) {
            uint64_t backupOffset = volumeSize - VC_DATA_AREA_OFFSET;
            if (device->pread(backupOffset, headerSector, VC_FULL_HEADER_SIZE)) {
                matched = deriveAndValidateHeader(
                    headerSector, mixedPassword, mixedPasswordLen, pim, cipherId, hashId,
                    dKey, decH, matchedCipher, matchedHash, fields, volId, nullptr, 1
                );
            }
        }
    }
    if (!matched) return false;

    CascadeContext candidateCascade;
    CascadeSpec spec = cascadeSpecFor(matchedCipher);
    const unsigned char* masterKeyPtr = &decH[VC_KEY_OFFSET_MASTER];
    if (!cascadeSetKeys(candidateCascade, matchedCipher, masterKeyPtr, spec.layerCount * 64)) {
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
    return true;
}