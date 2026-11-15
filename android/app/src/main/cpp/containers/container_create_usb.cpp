#include "container_create.h"
#include <cstring>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <android/log.h>
#include "block_io.h"
#include "crypto/cascade.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/vc_header_layout.h"
#include "vc_geometry.h"
#include "vc_header_areas.h"
#include "vc_header_build.h"
#include "vc_free_space_fill.h"
#include "crypto/xts_tweak.h"
#include "volume_state.h"
#include "ext_backend.h"
#include "mbedtls/platform_util.h"
#include "session_prepare.h"
#include "container_utils.h"
#include "ff.h"
#include "filesystem_paths.h"
#include <cstdio>
#include "crypto/luks_header.h"
#include "crypto/user_entropy.h"
#include <unistd.h>
#undef min
#undef max
#include <algorithm>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

// Reduced to 256 sectors (128 KB) to guarantee zero endpoint stalls on Android USB bulk transfers
static constexpr uint64_t CREATE_FILL_BATCH = 256;
extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);
static constexpr int MKFS_WORK_BUF_SIZE = 1048576;

UsbCreateResult createUsbContainer(int volId, uint64_t startSector, const char* password, int pim, int64_t sizeBytes,
                        const char* fileSystem, int cipherId, int hashId,
                        const int* keyfileFds, int keyfileCount, bool quickFormat,
                        const char* operationId, uint32_t sectorSize) {
    const char* opId = (operationId && operationId[0]) ? operationId : "-";
    if (sectorSize < VC_MIN_SECTOR_SIZE || sectorSize > VC_MAX_SECTOR_SIZE || sectorSize % VC_ENCRYPTION_DATA_UNIT_SIZE != 0) sectorSize = 512;
    LOGI("[%s] createUsbContainer: ENTER volId=%d startSector=%llu sizeBytes=%lld fs=%s",
         opId, volId, (unsigned long long)startSector, (long long)sizeBytes, fileSystem);

    bool success = false;
    UsbCreateResult result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_CREATE_FAILED", "Unknown failure");
    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    if (strlen(password) > VC_MAX_PASSWORD_BYTES) {
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_PASSWORD_TOO_LONG",
                                      "Password is longer than 128 bytes (UTF-8)");
    }
    size_t mixedPasswordLen = strlen(password);
    memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("[%s] createUsbContainer: keyfile mixing failed", opId);
            return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_KEYFILE_MIX_FAILED", "Failed to mix keyfiles into password");
        }
    }
    if (mixedPasswordLen == 0) {
        LOGI("[%s] createUsbContainer: empty password and no usable keyfiles", opId);
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_EMPTY_PASSWORD", "Password and keyfiles are both empty");
    }

    if (volId < 0 || volId >= FF_VOLUMES) {
        LOGI("[%s] createUsbContainer: invalid volId %d", opId, volId);
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_INVALID_VOLUME_ID", "Invalid internal volume id");
    }

    VolumeState& v = volumes[volId];
    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.isUsbSource = true;
        v.fd = -1;
        v.partitionStartSector = startSector;
        v.dataCtxInitialized = false;
        v.usbCache.clear();
    }

    CascadeId createCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
    HashId    createHash   = (hashId   != 255) ? static_cast<HashId>(hashId)      : HashId::kSha512;
    CascadeSpec cSpec      = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char salt[VC_SALT_SIZE]   = {0};
    unsigned char combinedMasterKey[192] = {0};

    do {
        if (sizeBytes < static_cast<int64_t>(300 * 1024)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_SIZE_TOO_SMALL", "Requested size is too small for a valid container");
            break;
        }

        const bool useExFat = (strncasecmp(fileSystem, "exfat", 5) == 0);
        const bool useNtfs  = (strncasecmp(fileSystem, "ntfs", 4) == 0);
        const bool useFat   = (strncasecmp(fileSystem, "fat", 3) == 0) && !useExFat;
        const bool useExt   = strncasecmp(fileSystem, "ext2", 4) == 0 ||
                              strncasecmp(fileSystem, "ext3", 4) == 0 ||
                              strncasecmp(fileSystem, "ext4", 4) == 0;
        if (!useExFat && !useNtfs && !useFat && !useExt) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_UNSUPPORTED_FILESYSTEM", "Unsupported filesystem requested");
            break;
        }

        {
            // /dev/urandom, enriched with user-collected entropy when the JNI
            // entry point installed some (crypto/user_entropy.h).
            bool ok = userentropy::fillRandom(salt, VC_SALT_SIZE) &&
                      userentropy::fillRandom(combinedMasterKey, static_cast<size_t>(masterKeyLen));
            if (!ok) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_RANDOM_READ_FAILED", "Failed to read enough random bytes");
                break;
            }
        }

        const int safePim = clampPim(pim);
        unsigned char headerKey[192] = {0};
        if (!deriveHeaderKey(createHash, mixedPassword, mixedPasswordLen, salt, safePim, headerKey, sizeof(headerKey))) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_KEY_DERIVATION_FAILED", "Header key derivation failed");
            break;
        }

        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;
        const uint64_t DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));
        vcStampHeaderPreamble(body);

        for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) body[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;

        vcPutBE32(body + VC_HDR_OFF_SECTOR_SIZE, sectorSize);   // the drive's logical sector size, like desktop

        memcpy(&body[VC_KEY_OFFSET_MASTER], combinedMasterKey, masterKeyLen);
        uint32_t keyCrc = container_crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_KEY_CRC] = (keyCrc >> 24) & 0xFF; body[VC_HDR_OFF_KEY_CRC + 1] = (keyCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 2] = (keyCrc >> 8) & 0xFF; body[VC_HDR_OFF_KEY_CRC + 3] = (keyCrc) & 0xFF;

        uint32_t hdrCrc = container_crc32(body, VC_HDR_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_HEADER_CRC] = (hdrCrc >> 24) & 0xFF; body[VC_HDR_OFF_HEADER_CRC + 1] = (hdrCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 2] = (hdrCrc >> 8) & 0xFF; body[VC_HDR_OFF_HEADER_CRC + 3] = (hdrCrc) & 0xFF;

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext hdrCtx;
            if (!cascadeSetKeys(hdrCtx, createCipher, headerKey, masterKeyLen)) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_CASCADE_INIT_FAILED", "Cipher initialization failed for header");
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

        // Backup header = separate salt + KDF run (see vc_header_build.h).
        unsigned char backupSector[VC_FULL_HEADER_SIZE];
        const bool backupBuilt = vcBuildFreshlySaltedHeaderSector(
            body, createCipher, createHash, mixedPassword, mixedPasswordLen, safePim, backupSector);
        mbedtls_platform_zeroize(body, sizeof(body));
        if (!backupBuilt) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_BACKUP_HEADER_BUILD_FAILED",
                                            "Failed to generate the backup volume header");
            break;
        }

        unsigned char hdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hdrSector, salt, VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE, encBody, VC_HEADER_BODY_SIZE);

        uint64_t baseOffset = startSector * 512;

        // Initialise both reserved header groups with random bytes before the real
        // headers go in (as VeraCrypt does). A reused drive otherwise keeps whatever
        // was there before -- old filesystem structures, or zeros -- and the
        // hidden-header slot then reveals whether a hidden volume exists.
        if (!vcgeom::randomizeHeaderGroups(
                baseOffset, VOLUME_SIZE,
                [&](uint64_t off, const unsigned char* p, size_t n) { return physicalWrite(volId, off, p, n); },
                [](void* out, size_t n) { return userentropy::fillRandom(static_cast<uint8_t*>(out), n); })) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWritePrimaryHeader, "USB_HEADER_AREA_FILL_FAILED",
                                            "Failed to initialise the reserved header areas", baseOffset,
                                            baseOffset / 512, VC_DATA_AREA_OFFSET / 512);
            break;
        }

        if (!physicalWrite(volId, baseOffset, hdrSector, VC_FULL_HEADER_SIZE)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWritePrimaryHeader, "USB_HEADER_WRITE_FAILED",
                                            "Failed to write the primary volume header", baseOffset,
                                            baseOffset / 512, VC_FULL_HEADER_SIZE / 512);
            break;
        }

        uint64_t backupOffset = baseOffset + VOLUME_SIZE - VC_DATA_AREA_OFFSET;
        if (!physicalWrite(volId, backupOffset, backupSector, VC_FULL_HEADER_SIZE)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWriteBackupHeader, "USB_BACKUP_HEADER_WRITE_FAILED",
                                            "Failed to write the backup volume header", backupOffset,
                                            backupOffset / 512, VC_FULL_HEADER_SIZE / 512);
            break;
        }

        if (!quickFormat) {
            // Free space gets encrypted zeros under a TEMPORARY random key, not the real
            // data key (see vc_free_space_fill.h), so untouched space decrypts to noise.
            if (!vcfill::fillWithRandomizedKey(
                    createCipher, masterKeyLen, VC_DATA_AREA_OFFSET / 512, DATA_SIZE / 512, CREATE_FILL_BATCH,
                    [&](uint64_t off, const unsigned char* p, size_t n) { return physicalWrite(volId, baseOffset + off, p, n); })) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kFillData, "USB_FILL_WRITE_FAILED",
                                                "Failed to write the data area fill", baseOffset + VC_DATA_AREA_OFFSET,
                                                VC_DATA_AREA_OFFSET / 512, 0);
                break;
            }
        }

        // Format drive
        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            cascadeSetKeys(v.cascade, createCipher, combinedMasterKey, masterKeyLen);

            v.dataOffset = baseOffset + VC_DATA_AREA_OFFSET;
            v.luksSectorSize = sectorSize;   // file systems are formatted with the volume's sector size
            v.dataAreaLengthBytes = DATA_SIZE;
            v.fileSize = VOLUME_SIZE;
            v.dataCtxInitialized = true;

            bool formatted = false;

            if (useExt) {
                formatted = formatExtVolume(volId, fileSystem);
            } else if (useNtfs) {
                char deviceName[16];
                std::snprintf(deviceName, sizeof(deviceName), "ve%d", volId);
                const std::string sectorSizeStr = std::to_string(sectorSize);
                char* args[] = {
                    const_cast<char*>("mkntfs"), const_cast<char*>("-F"),
                    const_cast<char*>("-Q"), const_cast<char*>("-s"),
                    const_cast<char*>(sectorSizeStr.c_str()), const_cast<char*>("-p"),
                    const_cast<char*>("0"), deviceName, nullptr
                };
                const int mkntfsRet = vaultexplorer_mkntfs_main(8, args);
                formatted = (mkntfsRet == 0);
            } else {
                MKFS_PARM mp;
                memset(&mp, 0, sizeof(mp));
                mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
                mp.n_fat  = useExFat ? 1 : 2;
                mp.n_root = 512;
                mp.au_size = useExFat ? 0 : std::max<uint32_t>(vc_fat_cluster_size(DATA_SIZE), sectorSize);
                mp.align   = 0;

                std::unique_ptr<unsigned char[]> mkfsBuf(new unsigned char[MKFS_WORK_BUF_SIZE]);
                FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf.get(), MKFS_WORK_BUF_SIZE);
                f_mount(nullptr, drivePaths[volId], 0);
                formatted = (fr == FR_OK);
            }

            v.fsMounted = false;
            v.dataCtxInitialized = false;

            if (!formatted) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kFormatFilesystem, "USB_FORMAT_FAILED",
                                                std::string("Failed to format filesystem: ") + fileSystem);
                break;
            }
        }

        // Flush software buffers and execute hardware SCSI cache barrier
        if (!usbFlushAndSync(volId)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFlushDevice, "USB_FLUSH_FAILED",
                                            "Failed to flush and sync the device after creating the volume");
            break;
        }
        success = true;
    } while (false);

    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.reset();
    }

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));

    LOGI("[%s] createUsbContainer: EXIT success=%d", opId, success ? 1 : 0);
    return success ? UsbCreateResult::Ok() : result;
}

UsbCreateResult createUsbLuksContainer(int volId, uint64_t startSector, const char* password, int pim, int64_t sizeBytes,
                            const char* fileSystem, int luksVersion, int cipherId, int hashId,
                            const int* keyfileFds, int keyfileCount, bool quickFormat,
                            const char* operationId) {
    const char* opId = (operationId && operationId[0]) ? operationId : "-";
    LOGI("[%s] createUsbLuksContainer: ENTER volId=%d startSector=%llu sizeBytes=%lld fs=%s luksVersion=%d",
         opId, volId, (unsigned long long)startSector, (long long)sizeBytes, fileSystem, luksVersion);

    if (volId < 0 || volId >= FF_VOLUMES) {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_INVALID_VOLUME_ID", "Invalid internal volume id");
    }

    std::vector<unsigned char> keyfileBuf;
    const unsigned char* effectivePassword = reinterpret_cast<const unsigned char*>(password);
    size_t effectivePasswordLen = strlen(password);

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
            return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_KEYFILE_MIX_FAILED", "Keyfile was unreadable or empty");
        }
        effectivePassword = keyfileBuf.data();
        effectivePasswordLen = keyfileBuf.size();
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    if (effectivePasswordLen == 0) {
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_EMPTY_PASSWORD", "Password and keyfiles are both empty");
    }

    VolumeState& v = volumes[volId];
    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.isUsbSource = true;
        v.fd = -1;
        v.partitionStartSector = startSector;
        v.dataCtxInitialized = false;
        v.usbCache.clear();
    }

    bool success = false;
    UsbCreateResult result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_CREATE_FAILED", "Unknown failure");
    do {
        if (sizeBytes < static_cast<int64_t>(2 * 1024 * 1024)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_SIZE_TOO_SMALL", "Requested size is too small for a valid container");
            break;
        }

        const bool useExt = strncasecmp(fileSystem, "ext2", 4) == 0 ||
                            strncasecmp(fileSystem, "ext3", 4) == 0 ||
                            strncasecmp(fileSystem, "ext4", 4) == 0;
        const bool useExFat = (strncasecmp(fileSystem, "exfat", 5) == 0);
        const bool useNtfs  = (strncasecmp(fileSystem, "ntfs", 4) == 0);
        const bool useFat   = !useExt && !useExFat && !useNtfs &&
                              (strncasecmp(fileSystem, "fat", 3) == 0);
        if (!useExt && !useExFat && !useNtfs && !useFat) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_UNSUPPORTED_FILESYSTEM", "Unsupported filesystem requested");
            break;
        }
        if (luksVersion != 1 && luksVersion != 2) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_UNSUPPORTED_LUKS_VERSION", "Unsupported LUKS version");
            break;
        }

        CascadeId dataCipher = static_cast<CascadeId>(cipherId);
        std::string cipherName;
        if (dataCipher == CascadeId::kAes) cipherName = "aes";
        else if (dataCipher == CascadeId::kSerpent) cipherName = "serpent";
        else if (dataCipher == CascadeId::kTwofish) cipherName = "twofish";
        else if (dataCipher == CascadeId::kCamellia) cipherName = "camellia";
        else if (dataCipher == CascadeId::kKuznyechik) cipherName = "kuznyechik";
        else {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_UNSUPPORTED_CIPHER", "Unsupported cipher id");
            break;
        }

        HashId createHash = static_cast<HashId>(hashId);
        LuksCreateParams params;
        params.version = luksVersion;
        params.cipherName = cipherName;
        const int safePim = clampPim(pim);

        if (createHash == HashId::kArgon2id) {
            if (luksVersion == 1) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_UNSUPPORTED_HASH", "LUKS1 does not support Argon2id");
                break;
            }
            params.useArgon2id = true;
            params.hashName = "sha256";
            argon2ParamsForPim(safePim, params.argon2MemoryKiB, params.argon2TimeCost, params.argon2Parallelism);
        } else if (createHash == HashId::kSha256) {
            params.hashName = "sha256";
            params.pbkdf2Iterations = static_cast<uint32_t>(iterationsForHash(HashId::kSha256, safePim));
        } else if (createHash == HashId::kSha512) {
            params.hashName = "sha512";
            params.pbkdf2Iterations = static_cast<uint32_t>(iterationsForHash(HashId::kSha512, safePim));
        } else {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_UNSUPPORTED_HASH", "Unsupported hash id for LUKS");
            break;
        }

        const uint64_t baseOffset = startSector * 512;
        LuksByteWriter writer = [volId, baseOffset](uint64_t offset, const void* data, size_t len) -> bool {
            return physicalWrite(volId, baseOffset + offset, static_cast<const unsigned char*>(data), len);
        };

        LuksVolumeInfo info;
        if (!luksCreateHeader(writer, effectivePassword, effectivePasswordLen, sizeBytes, params, info)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWritePrimaryHeader, "USB_HEADER_WRITE_FAILED",
                                            "Failed to write the LUKS header", baseOffset, startSector, 0);
            break;
        }

        const uint64_t partitionStartSectorAbs = startSector + (info.dataOffsetBytes / 512);
        const uint64_t dataAreaLengthBytes = static_cast<uint64_t>(sizeBytes) - info.dataOffsetBytes;

        bool fillOk = true;
        if (!quickFormat) {
            CascadeContext fillCtx;
            if (!cascadeSetKeys(fillCtx, dataCipher, info.masterKey.data(), info.masterKey.size())) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kFillData, "USB_CASCADE_INIT_FAILED", "Cipher initialization failed for data area");
                fillOk = false;
            } else {
                const uint64_t totalSectors = dataAreaLengthBytes / 512;
                const uint64_t startSectorRel = info.dataOffsetBytes / 512;
                const unsigned char ZERO_SECTOR[512] = {0};
                std::unique_ptr<unsigned char[]> batch(new unsigned char[CREATE_FILL_BATCH * 512]);

                for (uint64_t s = 0; s < totalSectors && fillOk; ) {
                    const uint64_t count = std::min<uint64_t>(totalSectors - s, CREATE_FILL_BATCH);
                    for (uint64_t i = 0; i < count; ++i) {
                        cascadeEncryptSector(fillCtx, s + i, ZERO_SECTOR, batch.get() + i * 512);
                    }
                    const size_t want = static_cast<size_t>(count) * 512;
                    if (!physicalWrite(volId, baseOffset + (startSectorRel + s) * 512, batch.get(), want)) {
                        result = UsbCreateResult::Fail(UsbCreatePhase::kFillData, "USB_FILL_WRITE_FAILED",
                                                        "Failed to write the zero-fill data area",
                                                        baseOffset + (startSectorRel + s) * 512,
                                                        startSectorRel + s, static_cast<uint32_t>(count));
                        fillOk = false;
                    }
                    s += count;
                }
            }
        }
        if (!fillOk) {
            mbedtls_platform_zeroize(info.masterKey.data(), info.masterKey.size());
            break;
        }

        bool keySetupOk;
        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            LuksCipherSpec createSpec;
            keySetupOk = luksParseCipherSpec(info.cipherName, info.cipherMode,
                                             static_cast<uint32_t>(info.masterKey.size()), createSpec) &&
                         luksCipherInit(v.luksCipher, createSpec, info.masterKey.data(), info.masterKey.size());
            if (keySetupOk) {
                v.isUsbSource = true;
                v.fd = -1;
                v.dataOffset = baseOffset + info.dataOffsetBytes;
                v.dataAreaLengthBytes = dataAreaLengthBytes;
                v.isHiddenVolume = false;
                v.fileSize = static_cast<uint64_t>(sizeBytes);
                v.luksSectorSize = 512;
                v.partitionStartSector = partitionStartSectorAbs;
                v.containerFormat = (luksVersion == 1) ? ContainerFormat::kLuks1 : ContainerFormat::kLuks2;
                v.dataCtxInitialized = true;
            }
        }

        mbedtls_platform_zeroize(info.masterKey.data(), info.masterKey.size());

        if (!keySetupOk) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFormatFilesystem, "USB_CASCADE_INIT_FAILED", "Data cipher key setup failed before formatting");
            break;
        }

        bool formatted = false;
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
            MKFS_PARM mp;
            memset(&mp, 0, sizeof(mp));
            mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
            mp.n_fat = useExFat ? 1 : 2;
            mp.n_root = 512;
            mp.au_size = useExFat ? 0 : vc_fat_cluster_size(dataAreaLengthBytes);
            mp.align = 0;
            std::unique_ptr<unsigned char[]> mkfsBuf(new unsigned char[MKFS_WORK_BUF_SIZE]);
            formatted = (f_mkfs(drivePaths[volId], &mp, mkfsBuf.get(), MKFS_WORK_BUF_SIZE) == FR_OK);
            f_mount(nullptr, drivePaths[volId], 0);
        }

        if (!formatted) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFormatFilesystem, "USB_FORMAT_FAILED",
                                            std::string("Failed to format filesystem: ") + fileSystem);
            break;
        }

        if (!usbFlushAndSync(volId)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFlushDevice, "USB_FLUSH_FAILED",
                                            "Failed to flush and sync the device after creating the volume");
            break;
        }
        success = true;
    } while (false);

    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.reset();
    }

    LOGI("[%s] createUsbLuksContainer: EXIT success=%d", opId, success ? 1 : 0);
    return success ? UsbCreateResult::Ok() : result;
}

UsbCreateResult createUsbContainerWithHidden(
    int volId, uint64_t startSector,
    const char* outerPassword, const char* hiddenPassword,
    int outerPim, int hiddenPim, int64_t sizeBytes,
    const char* outerFileSystem, const char* hiddenFileSystem,
    int64_t hiddenSizeBytes,
    int outerCipherId, int outerHashId,
    int hiddenCipherId, int hiddenHashId,
    const int* outerKeyfileFds, int outerKeyfileCount,
    const int* hiddenKeyfileFds, int hiddenKeyfileCount,
    bool quickFormat, const char* operationId,
    uint32_t sectorSize
) {
    const char* opId = (operationId && operationId[0]) ? operationId : "-";
    if (sectorSize < VC_MIN_SECTOR_SIZE || sectorSize > VC_MAX_SECTOR_SIZE || sectorSize % VC_ENCRYPTION_DATA_UNIT_SIZE != 0) sectorSize = 512;
    LOGI("[%s] createUsbContainerWithHidden: ENTER volId=%d", opId, volId);

    unsigned char mixedOuterPass[MAX_PASSWORD_LEN] = {0};
    unsigned char mixedHiddenPass[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize outerPassGuard(mixedOuterPass, sizeof(mixedOuterPass));
    ScopeZeroize hiddenPassGuard(mixedHiddenPass, sizeof(mixedHiddenPass));

    if (strlen(outerPassword) > VC_MAX_PASSWORD_BYTES || strlen(hiddenPassword) > VC_MAX_PASSWORD_BYTES) {
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_PASSWORD_TOO_LONG",
                                      "Password is longer than 128 bytes (UTF-8)");
    }
    size_t mixedOuterLen = strlen(outerPassword);
    memcpy(mixedOuterPass, outerPassword, mixedOuterLen);
    size_t mixedHiddenLen = strlen(hiddenPassword);
    memcpy(mixedHiddenPass, hiddenPassword, mixedHiddenLen);

    if (outerKeyfileCount > 0 && outerKeyfileFds) {
        if (!applyKeyfilesToPassword(outerKeyfileFds, outerKeyfileCount, mixedOuterPass, &mixedOuterLen)) {
            return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_KEYFILE_MIX_FAILED", "Failed to mix outer keyfiles into password");
        }
    }
    if (hiddenKeyfileCount > 0 && hiddenKeyfileFds) {
        if (!applyKeyfilesToPassword(hiddenKeyfileFds, hiddenKeyfileCount, mixedHiddenPass, &mixedHiddenLen)) {
            return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_KEYFILE_MIX_FAILED", "Failed to mix hidden keyfiles into password");
        }
    }
    if (mixedOuterLen == 0 || mixedHiddenLen == 0) {
        return UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_EMPTY_PASSWORD", "Outer or hidden password and keyfiles are both empty");
    }

    VolumeState& v = volumes[volId];
    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.isUsbSource = true;
        v.fd = -1;
        v.partitionStartSector = startSector;
        v.dataCtxInitialized = false;
        v.usbCache.clear();
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
    UsbCreateResult result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_CREATE_FAILED", "Unknown failure");
    do {
        if (sizeBytes < static_cast<int64_t>(300 * 1024)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_SIZE_TOO_SMALL", "Requested size is too small for a valid container");
            break;
        }

        {
            bool ok = userentropy::fillRandom(oSalt, VC_SALT_SIZE) &&
                      userentropy::fillRandom(oMasterKey, static_cast<size_t>(oMasterKeyLen)) &&
                      userentropy::fillRandom(hSalt, VC_SALT_SIZE) &&
                      userentropy::fillRandom(hMasterKey, static_cast<size_t>(hMasterKeyLen));
            if (!ok) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_RANDOM_READ_FAILED", "Failed to read enough random bytes");
                break;
            }
        }

        unsigned char oHeaderKey[192] = {0};
        unsigned char hHeaderKey[192] = {0};
        ScopeZeroize ohkGuard(oHeaderKey, sizeof(oHeaderKey));
        ScopeZeroize hhkGuard(hHeaderKey, sizeof(hHeaderKey));

        if (!deriveHeaderKey(oHash, mixedOuterPass, mixedOuterLen, oSalt, clampPim(outerPim), oHeaderKey, sizeof(oHeaderKey))) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_KEY_DERIVATION_FAILED", "Outer header key derivation failed");
            break;
        }
        if (!deriveHeaderKey(hHash, mixedHiddenPass, mixedHiddenLen, hSalt, clampPim(hiddenPim), hHeaderKey, sizeof(hHeaderKey))) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_KEY_DERIVATION_FAILED", "Hidden header key derivation failed");
            break;
        }

        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;
        const uint64_t OUTER_DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);
        const uint64_t HIDDEN_DATA_SIZE = static_cast<uint64_t>(hiddenSizeBytes);
        const uint64_t HIDDEN_AREA_START = VOLUME_SIZE - VC_DATA_AREA_OFFSET - HIDDEN_DATA_SIZE;

        // --- Generate Outer Header (Field 28 left as 0 for plausible deniability) ---
        unsigned char oBody[VC_HEADER_BODY_SIZE];
        memset(oBody, 0, sizeof(oBody));
        vcStampHeaderPreamble(oBody);
        for (int i = 7; i >= 0; --i) oBody[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (OUTER_DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) oBody[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) oBody[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (OUTER_DATA_SIZE >> (i * 8)) & 0xFF;
        vcPutBE32(oBody + VC_HDR_OFF_SECTOR_SIZE, sectorSize);
        memcpy(&oBody[VC_KEY_OFFSET_MASTER], oMasterKey, oMasterKeyLen);
        uint32_t oKeyCrc = container_crc32(&oBody[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        oBody[VC_HDR_OFF_KEY_CRC] = (oKeyCrc >> 24) & 0xFF; oBody[VC_HDR_OFF_KEY_CRC + 1] = (oKeyCrc >> 16) & 0xFF;
        oBody[VC_HDR_OFF_KEY_CRC + 2] = (oKeyCrc >> 8) & 0xFF; oBody[VC_HDR_OFF_KEY_CRC + 3] = (oKeyCrc) & 0xFF;
        uint32_t oHdrCrc = container_crc32(oBody, VC_HDR_CRC_COVERAGE_LEN);
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
        // SPEC FIX: Populate Field 28 (hiddenVolSize) so Windows/Linux VeraCrypt can mount it!
        unsigned char hBody[VC_HEADER_BODY_SIZE];
        memset(hBody, 0, sizeof(hBody));
        vcStampHeaderPreamble(hBody);
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_HIDDEN_VOL_SIZE + (7 - i)] = (HIDDEN_DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (HIDDEN_DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (HIDDEN_AREA_START >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i) hBody[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (HIDDEN_DATA_SIZE >> (i * 8)) & 0xFF;
        vcPutBE32(hBody + VC_HDR_OFF_SECTOR_SIZE, sectorSize);
        memcpy(&hBody[VC_KEY_OFFSET_MASTER], hMasterKey, hMasterKeyLen);
        uint32_t hKeyCrc = container_crc32(&hBody[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        hBody[VC_HDR_OFF_KEY_CRC] = (hKeyCrc >> 24) & 0xFF; hBody[VC_HDR_OFF_KEY_CRC + 1] = (hKeyCrc >> 16) & 0xFF;
        hBody[VC_HDR_OFF_KEY_CRC + 2] = (hKeyCrc >> 8) & 0xFF; hBody[VC_HDR_OFF_KEY_CRC + 3] = (hKeyCrc) & 0xFF;
        uint32_t hHdrCrc = container_crc32(hBody, VC_HDR_CRC_COVERAGE_LEN);
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
        
        // Backup copies get their own salts and KDF runs. Identical hidden
        // header copies (64 KiB vs V-64 KiB) would betray the hidden volume.
        unsigned char oBackupSector[VC_FULL_HEADER_SIZE];
        unsigned char hBackupSector[VC_FULL_HEADER_SIZE];
        const bool backupsBuilt =
            vcBuildFreshlySaltedHeaderSector(oBody, oCipher, oHash, mixedOuterPass, mixedOuterLen,
                                             clampPim(outerPim), oBackupSector) &&
            vcBuildFreshlySaltedHeaderSector(hBody, hCipher, hHash, mixedHiddenPass, mixedHiddenLen,
                                             clampPim(hiddenPim), hBackupSector);
        mbedtls_platform_zeroize(oBody, sizeof(oBody));
        mbedtls_platform_zeroize(hBody, sizeof(hBody));
        if (!backupsBuilt) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kPrepareHeader, "USB_BACKUP_HEADER_BUILD_FAILED",
                                            "Failed to generate the backup volume headers");
            break;
        }

        unsigned char oHdrSector[VC_FULL_HEADER_SIZE];
        memcpy(oHdrSector, oSalt, VC_SALT_SIZE);
        memcpy(oHdrSector + VC_SALT_SIZE, oEncBody, VC_HEADER_BODY_SIZE);

        unsigned char hHdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hHdrSector, hSalt, VC_SALT_SIZE);
        memcpy(hHdrSector + VC_SALT_SIZE, hEncBody, VC_HEADER_BODY_SIZE);

        uint64_t baseOffset = startSector * 512;

        // Initialise both reserved header groups with random bytes before the real
        // headers go in (as VeraCrypt does). A reused drive otherwise keeps whatever
        // was there before -- old filesystem structures, or zeros -- and the
        // hidden-header slot then reveals whether a hidden volume exists.
        if (!vcgeom::randomizeHeaderGroups(
                baseOffset, VOLUME_SIZE,
                [&](uint64_t off, const unsigned char* p, size_t n) { return physicalWrite(volId, off, p, n); },
                [](void* out, size_t n) { return userentropy::fillRandom(static_cast<uint8_t*>(out), n); })) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWritePrimaryHeader, "USB_HEADER_AREA_FILL_FAILED",
                                            "Failed to initialise the reserved header areas", baseOffset,
                                            baseOffset / 512, VC_DATA_AREA_OFFSET / 512);
            break;
        }

        // Write Outer Headers
        if (!physicalWrite(volId, baseOffset, oHdrSector, VC_FULL_HEADER_SIZE)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWritePrimaryHeader, "USB_HEADER_WRITE_FAILED",
                                            "Failed to write the outer primary volume header", baseOffset,
                                            baseOffset / 512, VC_FULL_HEADER_SIZE / 512);
            break;
        }
        const uint64_t outerBackupOffset = baseOffset + VOLUME_SIZE - VC_DATA_AREA_OFFSET;
        if (!physicalWrite(volId, outerBackupOffset, oBackupSector, VC_FULL_HEADER_SIZE)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWriteBackupHeader, "USB_BACKUP_HEADER_WRITE_FAILED",
                                            "Failed to write the outer backup volume header", outerBackupOffset,
                                            outerBackupOffset / 512, VC_FULL_HEADER_SIZE / 512);
            break;
        }

        // Write Hidden Header
        const uint64_t hiddenHeaderOffset = baseOffset + VC_HIDDEN_HEADER_OFFSET;
        if (!physicalWrite(volId, hiddenHeaderOffset, hHdrSector, VC_FULL_HEADER_SIZE)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kWriteBackupHeader, "USB_HIDDEN_HEADER_WRITE_FAILED",
                                            "Failed to write the hidden volume header", hiddenHeaderOffset,
                                            hiddenHeaderOffset / 512, VC_FULL_HEADER_SIZE / 512);
            break;
        }

        // Backup copy of the hidden header at the end of the container, as
        // VeraCrypt keeps one. It lies in the trailing header group, clear of the
        // hidden data area [V-A-H, V-A).
        {
            uint64_t hiddenBackupRel = 0;
            if (!vcgeom::backupHeaderOffset(VOLUME_SIZE, true, &hiddenBackupRel) ||
                !vcgeom::headerClearOfDataArea(hiddenBackupRel, HIDDEN_AREA_START, HIDDEN_DATA_SIZE)) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kWriteBackupHeader, "USB_HIDDEN_BACKUP_HEADER_INVALID",
                                                "No valid slot for the hidden backup header");
                break;
            }
            const uint64_t hiddenBackupOffset = baseOffset + hiddenBackupRel;
            if (!physicalWrite(volId, hiddenBackupOffset, hBackupSector, VC_FULL_HEADER_SIZE)) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kWriteBackupHeader, "USB_HIDDEN_BACKUP_HEADER_WRITE_FAILED",
                                                "Failed to write the hidden backup volume header", hiddenBackupOffset,
                                                hiddenBackupOffset / 512, VC_FULL_HEADER_SIZE / 512);
                break;
            }
        }

        // Zero Fill
        if (!quickFormat) {
            // Temporary random key for the free-space fill (see vc_free_space_fill.h): under
            // the outer key the hidden volume's area must look like the rest of the free space.
            if (!vcfill::fillWithRandomizedKey(
                    oCipher, oMasterKeyLen, VC_DATA_AREA_OFFSET / 512, OUTER_DATA_SIZE / 512, CREATE_FILL_BATCH,
                    [&](uint64_t off, const unsigned char* p, size_t n) { return physicalWrite(volId, baseOffset + off, p, n); })) {
                result = UsbCreateResult::Fail(UsbCreatePhase::kFillData, "USB_FILL_WRITE_FAILED",
                                                "Failed to write the data area fill", baseOffset + VC_DATA_AREA_OFFSET,
                                                VC_DATA_AREA_OFFSET / 512, 0);
                break;
            }
        }

        // Format filesystems
        auto formatFS = [&](const char* fs, uint64_t dOffset, uint64_t dLen, CascadeId cId, const unsigned char* mKey, int mkLen) -> bool {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            cascadeSetKeys(v.cascade, cId, mKey, mkLen);
            v.dataOffset = baseOffset + dOffset;
            v.luksSectorSize = sectorSize;
            v.dataAreaLengthBytes = dLen;
            v.fileSize = VOLUME_SIZE;
            v.dataCtxInitialized = true;
            bool ok = false;
            
            if (strncasecmp(fs, "ext", 3) == 0) ok = formatExtVolume(volId, fs);
            else if (strncasecmp(fs, "ntfs", 4) == 0) {
                char devName[16]; std::snprintf(devName, sizeof(devName), "ve%d", volId);
                const std::string sectorSizeStr = std::to_string(sectorSize);
                char* args[] = { (char*)"mkntfs", (char*)"-F", (char*)"-Q", (char*)"-s", (char*)sectorSizeStr.c_str(), (char*)"-p", (char*)"0", devName, nullptr };
                ok = (vaultexplorer_mkntfs_main(8, args) == 0);
            } else {
                MKFS_PARM mp; memset(&mp, 0, sizeof(mp));
                const bool isExFat = (strncasecmp(fs, "exfat", 5) == 0);
                mp.fmt = (isExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
                mp.n_fat = isExFat ? 1 : 2;
                mp.n_root = 512;
                mp.au_size = isExFat ? 0 : std::max<uint32_t>(vc_fat_cluster_size(dLen), sectorSize);
                mp.align = 0;
                std::unique_ptr<unsigned char[]> mkfsBuf(new unsigned char[MKFS_WORK_BUF_SIZE]);
                ok = (f_mkfs(drivePaths[volId], &mp, mkfsBuf.get(), MKFS_WORK_BUF_SIZE) == FR_OK);
                f_mount(nullptr, drivePaths[volId], 0);
            }
            v.dataCtxInitialized = false;
            return ok;
        };

        if (!formatFS(outerFileSystem, VC_DATA_AREA_OFFSET, OUTER_DATA_SIZE, oCipher, oMasterKey, oMasterKeyLen)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFormatFilesystem, "USB_FORMAT_FAILED",
                                            std::string("Failed to format outer filesystem: ") + outerFileSystem);
            break;
        }
        
        if (!formatFS(hiddenFileSystem, HIDDEN_AREA_START, HIDDEN_DATA_SIZE, hCipher, hMasterKey, hMasterKeyLen)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFormatFilesystem, "USB_FORMAT_FAILED",
                                            std::string("Failed to format hidden filesystem: ") + hiddenFileSystem);
            break;
        }

        if (!usbFlushAndSync(volId)) {
            result = UsbCreateResult::Fail(UsbCreatePhase::kFlushDevice, "USB_FLUSH_FAILED",
                                            "Failed to flush and sync the device after creating the volume");
            break;
        }
        success = true;
    } while (false);

    {
        std::unique_lock<std::shared_mutex> vlock(v.mutex);
        v.reset();
    }

    LOGI("[%s] createUsbContainerWithHidden: EXIT success=%d", opId, success ? 1 : 0);
    return success ? UsbCreateResult::Ok() : result;
}