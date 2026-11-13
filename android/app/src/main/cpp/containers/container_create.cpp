#include "container_create.h"
#include <cerrno>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include <android/log.h>
#include "mbedtls/platform_util.h"
#include "container_format.h"
#include "container_utils.h"
#include "vc_geometry.h"
#include "vc_header_areas.h"
#include "vc_header_build.h"
#include "vc_expand.h"
#include "vc_outer_reader.h"
#include "vc_free_space_fill.h"
#include "crypto/cascade.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/luks_header.h"
#include "crypto/user_entropy.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "ext_backend.h"
#include "filesystem_paths.h"
#include "fs_ops.h"
#include "virtual_block_device.h"
#include "session_prepare.h"
#include "volume_state.h"
#undef min
#undef max
#include "ff.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

static constexpr int MAX_VOLUMES = FF_VOLUMES;
extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);

// Caller holds volumeLifecycleMutex, so no new file-backed session can be
// registered while the identity check and mutation are in progress.
static bool containerFileIsUnlocked(int fd) {
    if (fd < 0) return false;
    struct stat candidate{};
    if (fstat(fd, &candidate) != 0) return false;
    for (int i = 0; i < MAX_VOLUMES; ++i) {
        VolumeState& volume = volumes[i];
        std::shared_lock<std::shared_mutex> lock(volume.mutex);
        // Also catch an fd retained by an emergency purge / incomplete reset;
        // only VolumeState::reset() releases the backing descriptor.
        if (volume.fd < 0) continue;
        struct stat active{};
        if (fstat(volume.fd, &active) == 0 && active.st_dev == candidate.st_dev &&
            active.st_ino == candidate.st_ino) return true;
    }
    return false;
}
static constexpr uint64_t CREATE_FILL_BATCH = 4096;
static constexpr int MKFS_WORK_BUF_SIZE = 1048576;

bool createContainer(int fd, const char* password, int pim, int64_t sizeBytes,
                     const char* fileSystem, int cipherId, int hashId,
                     const int* keyfileFds, int keyfileCount,
                     bool quickFormat) {
    bool success = false;
    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    if (strlen(password) > VC_MAX_PASSWORD_BYTES) {
        // Upstream refuses passwords over 128 UTF-8 bytes (VolumePassword::MaxSize) instead of cutting them.
        LOGI("createContainer: password longer than %zu bytes (UTF-8)", VC_MAX_PASSWORD_BYTES);
        close(fd);
        if (keyfileFds != nullptr) for (int i = 0; i < keyfileCount; i++) if (keyfileFds[i] >= 0) close(keyfileFds[i]);
        return false;
    }
    size_t mixedPasswordLen = strlen(password);
    memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("createContainer: keyfile mixing failed (unreadable/empty keyfile)");
            close(fd);
            return false;
        }
    }
    if (mixedPasswordLen == 0) {
        LOGI("createContainer: empty password and no usable keyfiles");
        close(fd);
        return false;
    }

    CascadeId createCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
    HashId    createHash   = (hashId   != 255) ? static_cast<HashId>(hashId)      : HashId::kSha512;
    CascadeSpec cSpec      = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char salt[VC_SALT_SIZE]   = {0};
    unsigned char combinedMasterKey[192] = {0};

    do {
        if (sizeBytes < static_cast<int64_t>(300 * 1024)) {
            LOGI("createContainer: sizeBytes too small (%lld)", (long long)sizeBytes);
            break;
        }

        int volId = -1;
        {
            std::lock_guard<std::mutex> allocLock(slotAllocMutex);
            for (int i = 0; i < MAX_VOLUMES; i++) {
                if (!volumes[i].dataCtxInitialized) { volId = i; break; }
            }
        }
        if (volId == -1) {
            LOGI("createContainer: no free slots available");
            break;
        }

        VolumeState& v = volumes[volId];

        {
            // /dev/urandom, enriched with the user-collected entropy the JNI
            // entry point installed for this thread (crypto/user_entropy.h).
            bool ok = userentropy::fillRandom(salt, VC_SALT_SIZE) &&
                      userentropy::fillRandom(combinedMasterKey, static_cast<size_t>(masterKeyLen));
            if (!ok) { LOGI("createContainer: random generation failed"); break; }
        }

        const int safePim = clampPim(pim);
        unsigned char headerKey[192] = {0};
        if (!deriveHeaderKey(createHash, mixedPassword, mixedPasswordLen,
                             salt, safePim, headerKey, sizeof(headerKey))) {
            LOGI("createContainer: header key derivation failed");
            break;
        }

        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;
        ftruncate(fd, static_cast<off_t>(VOLUME_SIZE));

        const uint64_t DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);

        // Fill both 128 KiB header groups with random bytes before the real
        // headers go in, as VeraCrypt does. Otherwise the hidden-header slot
        // (and the rest of the reserved areas) of a fresh zero-extended file is
        // all zeros exactly when no hidden volume exists, which tells an
        // observer whether a hidden volume is there without any secret. The
        // last piece also ends at VOLUME_SIZE - 1, so this extends the file
        // even where ftruncate() above is not honoured.
        if (!vcgeom::randomizeHeaderGroups(
                0, VOLUME_SIZE,
                [fd](uint64_t off, const unsigned char* p, size_t n) { return vcgeom::pwriteFully(fd, off, p, n); },
                [](void* out, size_t n) { return userentropy::fillRandom(static_cast<uint8_t*>(out), n); })) {
            LOGI("createContainer: failed to initialise the reserved header areas");
            break;
        }

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));
        vcStampHeaderPreamble(body);

        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;

        body[VC_HDR_OFF_SECTOR_SIZE]     = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02;
        body[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;

        memcpy(&body[VC_KEY_OFFSET_MASTER], combinedMasterKey, masterKeyLen);
        uint32_t keyCrc = container_crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_KEY_CRC]     = (keyCrc >> 24) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 1] = (keyCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 2] = (keyCrc >>  8) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 3] = (keyCrc      ) & 0xFF;

        uint32_t hdrCrc = container_crc32(body, VC_HDR_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_HEADER_CRC]     = (hdrCrc >> 24) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 1] = (hdrCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 2] = (hdrCrc >>  8) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 3] = (hdrCrc      ) & 0xFF;

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext hdrCtx;
            if (!cascadeSetKeys(hdrCtx, createCipher, headerKey, masterKeyLen)) {
                LOGI("createContainer: cascadeSetKeys failed for header");
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

        // The backup header is its own encryption of the same header: fresh
        // salt, fresh KDF run (what VeraCrypt does). A byte-identical copy would
        // fingerprint the container -- see vc_header_build.h.
        unsigned char backupSector[VC_FULL_HEADER_SIZE];
        const bool backupBuilt = vcBuildFreshlySaltedHeaderSector(
            body, createCipher, createHash, mixedPassword, mixedPasswordLen, safePim, backupSector);
        mbedtls_platform_zeroize(body, sizeof(body));
        if (!backupBuilt) { LOGI("createContainer: backup header generation failed"); break; }

        unsigned char hdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hdrSector,                  salt,    VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE,   encBody, VC_HEADER_BODY_SIZE);

        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: primary header write failed"); break;
        }

        if (pwrite(fd, backupSector, VC_FULL_HEADER_SIZE,
                   static_cast<off_t>(VOLUME_SIZE - VC_DATA_AREA_OFFSET)) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: backup header write failed"); break;
        }

        // (No trailing marker byte: the last byte of the container belongs to the
        // random-filled hidden-volume backup header slot and must stay random.)

        if (!quickFormat) {
            // Free space gets encrypted zeros under a TEMPORARY random key, not the
            // real data key (see vc_free_space_fill.h): otherwise untouched space
            // decrypts to zeros under the outer key and a hidden volume stands out.
            if (!vcfill::fillWithRandomizedKey(
                    createCipher, masterKeyLen, VC_DATA_AREA_OFFSET / 512, DATA_SIZE / 512, CREATE_FILL_BATCH,
                    [fd](uint64_t off, const unsigned char* p, size_t n) { return vcgeom::pwriteFully(fd, off, p, n); })) {
                LOGI("createContainer: data fill failed");
                break;
            }
        }

        fsync(fd);

        // Format drive
        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            cascadeSetKeys(v.cascade, createCipher, combinedMasterKey, masterKeyLen);
            v.dataCtxInitialized = true;
            v.fd                 = fd;
            v.dataOffset         = VC_DATA_AREA_OFFSET;
            v.dataAreaLengthBytes = DATA_SIZE;
            v.fileSize           = VOLUME_SIZE;

            const bool useExFat = (strncasecmp(fileSystem, "exfat", 5) == 0);
            const bool useNtfs = (strncasecmp(fileSystem, "ntfs", 4) == 0);
            const bool useExt = strncasecmp(fileSystem, "ext2", 4) == 0 ||
                                strncasecmp(fileSystem, "ext3", 4) == 0 ||
                                strncasecmp(fileSystem, "ext4", 4) == 0;

            if (useExt) {
                v.partitionStartSector = 0;
                v.isUsbSource = false;
                const bool formatted = formatExtVolume(volId, fileSystem);
                v.fsMounted = false;
                v.fd = -1;
                v.dataCtxInitialized = false;
                if (!formatted) {
                    LOGI("createContainer: %s formatter failed", fileSystem);
                    break;
                }
                success = true;
                continue;
            }

            if (useNtfs) {
                char deviceName[16];
                std::snprintf(deviceName, sizeof(deviceName), "ve%d", volId);
                char* args[] = {
                    const_cast<char*>("mkntfs"), const_cast<char*>("-F"),
                    const_cast<char*>("-Q"), const_cast<char*>("-s"),
                    const_cast<char*>("512"), const_cast<char*>("-p"),
                    const_cast<char*>("0"), deviceName, nullptr
                };
                const int result = vaultexplorer_mkntfs_main(8, args);
                v.fsMounted = false;
                v.fsType = VolumeState::FS_UNKNOWN;
                v.fd = -1;
                v.dataOffset = 0;
                v.dataAreaLengthBytes = 0;
                v.fileSize = 0;
                v.cascade.initialized = false;
                v.dataCtxInitialized = false;
                if (result != 0) {
                    LOGI("createContainer: mkntfs failed, code=%d", result);
                    break;
                }
                success = true;
                continue;
            }

            MKFS_PARM mp;
            memset(&mp, 0, sizeof(mp));
            mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
            mp.n_fat  = useExFat ? 1 : 2;
            mp.n_root = 512;
            mp.au_size = useExFat ? 0 : vc_fat_cluster_size(DATA_SIZE);
            mp.align   = 0;

            std::unique_ptr<unsigned char[]> mkfsBuf(new unsigned char[MKFS_WORK_BUF_SIZE]);
            FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf.get(), MKFS_WORK_BUF_SIZE);
            f_mount(nullptr, drivePaths[volId], 0);

            v.fdWriteBuffer.flush(v.fd);
            v.fsMounted          = false;
            v.fd                 = -1;
            v.dataOffset         = 0;
            v.dataAreaLengthBytes = 0;
            v.fileSize           = 0;
            v.cascade.initialized = false;
            v.dataCtxInitialized = false;
            if (fr != FR_OK) {
                LOGI("createContainer: f_mkfs failed, code=%d", (int)fr);
                break;
            }
        }

        success = true;
    } while (false);

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));
    if (success) fsync(fd);
    close(fd);
    return success;
}

bool createLuksContainer(int fd, const char* password, int pim, int64_t sizeBytes,
                         const char* fileSystem, int luksVersion, int cipherId, int hashId,
                         const int* keyfileFds, int keyfileCount,
                         bool quickFormat) {
    bool success = false;
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
            LOGI("createLuksContainer: keyfile unreadable or empty");
            close(fd);
            return false;
        }
        effectivePassword = keyfileBuf.data();
        effectivePasswordLen = keyfileBuf.size();
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    if (effectivePasswordLen == 0) {
        LOGI("createLuksContainer: empty password and no usable keyfiles");
        close(fd);
        return false;
    }

    do {
        if (sizeBytes < static_cast<int64_t>(2 * 1024 * 1024)) {
            LOGI("createLuksContainer: sizeBytes too small (%lld)", (long long)sizeBytes);
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
            LOGI("createLuksContainer: unsupported filesystem '%s'", fileSystem);
            break;
        }

        if (luksVersion != 1 && luksVersion != 2) {
            LOGI("createLuksContainer: unsupported luksVersion %d", luksVersion);
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
            LOGI("createLuksContainer: unsupported cipherId %d", cipherId);
            break;
        }

        HashId createHash = static_cast<HashId>(hashId);
        LuksCreateParams params;
        params.version = luksVersion;
        params.cipherName = cipherName;
        const int safePim = clampPim(pim);

        if (createHash == HashId::kArgon2id) {
            if (luksVersion == 1) {
                LOGI("createLuksContainer: LUKS1 does not support Argon2id");
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
            LOGI("createLuksContainer: unsupported hashId %d for LUKS", hashId);
            break;
        }

        int volId = -1;
        {
            std::lock_guard<std::mutex> allocLock(slotAllocMutex);
            for (int i = 0; i < MAX_VOLUMES; i++) {
                if (!volumes[i].dataCtxInitialized) { volId = i; break; }
            }
        }
        if (volId == -1) {
            LOGI("createLuksContainer: no free slots available");
            break;
        }

        VolumeState& v = volumes[volId];
        LuksVolumeInfo info;
        if (!luksCreateHeader(fd, effectivePassword, effectivePasswordLen, sizeBytes, params, info)) {
            LOGI("createLuksContainer: luksCreateHeader failed");
            break;
        }

        unsigned char eofByte = 0;
        pwrite(fd, &eofByte, 1, static_cast<off_t>(sizeBytes - 1));

        const uint64_t partitionStartSector = info.dataOffsetBytes / 512;
        const uint64_t dataAreaLengthBytes = static_cast<uint64_t>(sizeBytes) - info.dataOffsetBytes;

        bool fillOk = true;
        if (!quickFormat) {
            CascadeContext fillCtx;
            if (!cascadeSetKeys(fillCtx, dataCipher, info.masterKey.data(), info.masterKey.size())) {
                LOGI("createLuksContainer: cascadeSetKeys failed for zero-fill");
                fillOk = false;
            } else {
                const uint64_t totalSectors = dataAreaLengthBytes / 512;
                const uint64_t startSectorAbs = info.dataOffsetBytes / 512;
                const unsigned char ZERO_SECTOR[512] = {0};
                const size_t batchBufBytes = CREATE_FILL_BATCH * 512;
                std::unique_ptr<unsigned char[]> batch(new unsigned char[batchBufBytes]);

                for (uint64_t s = 0; s < totalSectors && fillOk; ) {
                    const uint64_t rem = totalSectors - s;
                    const uint64_t count = (rem < CREATE_FILL_BATCH) ? rem : CREATE_FILL_BATCH;
                    for (uint64_t i = 0; i < count; ++i) {
                        const uint64_t tweak = (startSectorAbs + s + i) - partitionStartSector;
                        cascadeEncryptSector(fillCtx, tweak, ZERO_SECTOR, batch.get() + i * 512);
                    }
                    const ssize_t want = static_cast<ssize_t>(count * 512);
                    if (pwrite(fd, batch.get(), want, static_cast<off_t>((startSectorAbs + s) * 512)) != want) {
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

        fsync(fd);

        bool keySetupOk;
        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            LuksCipherSpec createSpec;
            keySetupOk = luksParseCipherSpec(info.cipherName, info.cipherMode,
                                             static_cast<uint32_t>(info.masterKey.size()), createSpec) &&
                         luksCipherInit(v.luksCipher, createSpec, info.masterKey.data(), info.masterKey.size());
            if (keySetupOk) {
                v.fd = fd;
                v.dataOffset = info.dataOffsetBytes;
                v.dataAreaLengthBytes = dataAreaLengthBytes;
                v.isHiddenVolume = false;
                v.fileSize = static_cast<uint64_t>(sizeBytes);
                v.luksSectorSize = 512;
                v.partitionStartSector = partitionStartSector;
                v.containerFormat = (luksVersion == 1) ? ContainerFormat::kLuks1 : ContainerFormat::kLuks2;
                v.dataCtxInitialized = true;
            }
        }

        mbedtls_platform_zeroize(info.masterKey.data(), info.masterKey.size());

        if (!keySetupOk) {
            LOGI("createLuksContainer: data cipher key setup failed");
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

        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            v.fdWriteBuffer.flush(v.fd);
            v.fsMounted = false;
            v.fd = -1;
            v.dataCtxInitialized = false;
            v.luksGenericCascade.initialized = false;
            luksCipherWipe(v.luksCipher);
        }

        if (!formatted) {
            LOGI("createLuksContainer: %s formatter failed", fileSystem);
            break;
        }

        success = true;
    } while (false);

    if (success) fsync(fd);
    close(fd);
    return success;
}

// The hidden-volume half of creation -- hidden header at 64 KiB plus its backup, data area at the end of the
// outer volume, hidden file system -- shared by "create outer + hidden volume" and by "add a hidden volume to an
// existing volume" (createHiddenVolumeInExisting). [sizeBytes] is the container size. Takes ownership of [fd] and
// of the hidden keyfile fds.
static bool createHiddenVolumePhase(int fd, int64_t sizeBytes,
                                    const char* hiddenPassword, int hiddenPim,
                                    const char* hiddenFileSystem, int64_t hiddenSizeBytes,
                                    int hiddenCipherId, int hiddenHashId,
                                    const int* hiddenKeyfileFds, int hiddenKeyfileCount,
                                    bool quickFormat) {
    const int64_t truncatedSizeBytes = (sizeBytes / 4096) * 4096;
    bool success = false;
    unsigned char hiddenMixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize hiddenMixedPasswordGuard(hiddenMixedPassword, sizeof(hiddenMixedPassword));
    if (strlen(hiddenPassword) > VC_MAX_PASSWORD_BYTES) {
        LOGI("createContainerWithHidden: hidden password longer than %zu bytes (UTF-8)", VC_MAX_PASSWORD_BYTES);
        close(fd);
        if (hiddenKeyfileFds) for (int i = 0; i < hiddenKeyfileCount; i++) if (hiddenKeyfileFds[i] >= 0) close(hiddenKeyfileFds[i]);
        return false;
    }
    size_t hiddenMixedPasswordLen = strlen(hiddenPassword);
    memcpy(hiddenMixedPassword, hiddenPassword, hiddenMixedPasswordLen);

    if (hiddenKeyfileCount > 0 && hiddenKeyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(hiddenKeyfileFds, hiddenKeyfileCount, hiddenMixedPassword, &hiddenMixedPasswordLen)) {
            close(fd);
            return false;
        }
    }
    if (hiddenMixedPasswordLen == 0) {
        close(fd);
        return false;
    }

    CascadeId createCipher = (hiddenCipherId != 255) ? static_cast<CascadeId>(hiddenCipherId) : CascadeId::kAes;
    HashId    createHash   = (hiddenHashId   != 255) ? static_cast<HashId>(hiddenHashId)      : HashId::kSha512;
    CascadeSpec cSpec      = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char hiddenSalt[VC_SALT_SIZE] = {0};
    unsigned char hiddenCombinedMasterKey[192] = {0};

    do {
        const uint64_t VOLUME_SIZE = static_cast<uint64_t>(truncatedSizeBytes);
        uint64_t hiddenDataSize = static_cast<uint64_t>(hiddenSizeBytes);
        hiddenDataSize = (hiddenDataSize / 512) * 512;

        if (hiddenDataSize == 0 || VOLUME_SIZE <= (2 * VC_DATA_AREA_OFFSET) + hiddenDataSize) {
            LOGI("createContainerWithHidden: invalid hidden size");
            break;
        }

        // CRITICAL BUG FIX: subtract VC_DATA_AREA_OFFSET so hidden data does not
        // overwrite the outer container's backup headers at the tail of the file!
        uint64_t hiddenDataStartAbsolute = VOLUME_SIZE - VC_DATA_AREA_OFFSET - hiddenDataSize;

        int volId = -1;
        {
            std::lock_guard<std::mutex> allocLock(slotAllocMutex);
            for (int i = 0; i < MAX_VOLUMES; i++) {
                if (!volumes[i].dataCtxInitialized) { volId = i; break; }
            }
        }
        if (volId < 0) break;

        VolumeState& v = volumes[volId];
        // Own keystream bytes (the stream never rewinds), so the hidden
        // volume's salt/key share nothing with the outer volume's.
        if (!userentropy::fillRandom(hiddenSalt, sizeof(hiddenSalt)) ||
            !userentropy::fillRandom(hiddenCombinedMasterKey, static_cast<size_t>(masterKeyLen))) {
            LOGI("createContainerWithHidden: random generation failed");
            break;
        }

        int clampedPim = clampPim(hiddenPim);
        unsigned char hiddenHeaderKey[192] = {0};
        ScopeZeroize hiddenHeaderKeyGuard(hiddenHeaderKey, sizeof(hiddenHeaderKey));
        if (!deriveHeaderKey(createHash, hiddenMixedPassword, hiddenMixedPasswordLen,
                             hiddenSalt, clampedPim, hiddenHeaderKey, sizeof(hiddenHeaderKey))) {
            break;
        }

        unsigned char body[VC_HEADER_BODY_SIZE] = {0};
        vcStampHeaderPreamble(body);

        auto writeBE64 = [](unsigned char* buf, int offset, uint64_t val) {
            for (int i = 7; i >= 0; --i) { buf[offset + i] = val & 0xFF; val >>= 8; }
        };
        auto writeBE32 = [](unsigned char* buf, int offset, uint32_t val) {
            for (int i = 3; i >= 0; --i) { buf[offset + i] = val & 0xFF; val >>= 8; }
        };

        writeBE64(body, VC_HDR_OFF_HIDDEN_VOL_SIZE, hiddenDataSize);
        writeBE64(body, VC_HDR_OFF_VOLUME_SIZE, hiddenDataSize);
        writeBE64(body, VC_HDR_OFF_KEY_SCOPE_START, hiddenDataStartAbsolute);
        writeBE64(body, VC_HDR_OFF_KEY_SCOPE_SIZE, hiddenDataSize);
        writeBE32(body, VC_HDR_OFF_SECTOR_SIZE, VC_SUPPORTED_SECTOR_SIZE);

        memcpy(&body[VC_KEY_OFFSET_MASTER], hiddenCombinedMasterKey, masterKeyLen);
        uint32_t keyCrc = container_crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        writeBE32(body, VC_HDR_OFF_KEY_CRC, keyCrc);

        uint32_t hdrCrc = container_crc32(body, VC_HDR_CRC_COVERAGE_LEN);
        writeBE32(body, VC_HDR_OFF_HEADER_CRC, hdrCrc);

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext hdrCtx;
            if (!cascadeSetKeys(hdrCtx, createCipher, hiddenHeaderKey, masterKeyLen)) break;
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

        // Separate salt + KDF run for the hidden backup header. Two identical
        // copies (64 KiB and V-64 KiB) would reveal that a hidden volume exists
        // to anyone who compares them -- no password needed.
        unsigned char backupSector[VC_FULL_HEADER_SIZE];
        const bool backupBuilt = vcBuildFreshlySaltedHeaderSector(
            body, createCipher, createHash, hiddenMixedPassword, hiddenMixedPasswordLen, clampedPim, backupSector);
        mbedtls_platform_zeroize(body, sizeof(body));
        if (!backupBuilt) { LOGI("createContainerWithHidden: backup header generation failed"); break; }

        unsigned char hdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hdrSector,                  hiddenSalt,    VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE,   encBody, VC_HEADER_BODY_SIZE);

        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE, VC_HIDDEN_HEADER_OFFSET) != VC_FULL_HEADER_SIZE) break;

        // VeraCrypt keeps a backup of the hidden header too, at the very end of
        // the container (after the outer backup header). Without it a damaged
        // primary hidden header cannot be recovered, and a later password
        // change would have no second copy to keep in step. The slot lies in the
        // trailing header group, clear of the hidden data area [V-A-H, V-A).
        {
            uint64_t hiddenBackupOffset = 0;
            if (!vcgeom::backupHeaderOffset(VOLUME_SIZE, true, &hiddenBackupOffset) ||
                !vcgeom::headerClearOfDataArea(hiddenBackupOffset, hiddenDataStartAbsolute, hiddenDataSize)) {
                LOGI("createContainerWithHidden: no valid hidden backup header slot");
                break;
            }
            if (pwrite(fd, backupSector, VC_FULL_HEADER_SIZE, static_cast<off_t>(hiddenBackupOffset)) !=
                VC_FULL_HEADER_SIZE) {
                LOGI("createContainerWithHidden: hidden backup header write failed");
                break;
            }
        }

        if (!quickFormat) {
            if (!vcfill::fillWithRandomizedKey(
                    createCipher, masterKeyLen, hiddenDataStartAbsolute / 512, hiddenDataSize / 512, CREATE_FILL_BATCH,
                    [fd](uint64_t off, const unsigned char* p, size_t n) { return vcgeom::pwriteFully(fd, off, p, n); })) {
                LOGI("createContainerWithHidden: data fill failed");
                break;
            }
        }

        fsync(fd);

        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            cascadeSetKeys(v.cascade, createCipher, hiddenCombinedMasterKey, masterKeyLen);
            v.dataCtxInitialized = true;
            v.fd                 = fd;
            v.dataOffset         = hiddenDataStartAbsolute;
            v.dataAreaLengthBytes = hiddenDataSize;
            v.fileSize           = VOLUME_SIZE;
            v.isHiddenVolume     = true;

            const bool useExFat = (strncasecmp(hiddenFileSystem, "exfat", 5) == 0);
            const bool useNtfs = (strncasecmp(hiddenFileSystem, "ntfs", 4) == 0);
            const bool useExt = strncasecmp(hiddenFileSystem, "ext2", 4) == 0 ||
                                strncasecmp(hiddenFileSystem, "ext3", 4) == 0 ||
                                strncasecmp(hiddenFileSystem, "ext4", 4) == 0;

            if (useExt) {
                v.partitionStartSector = 0;
                v.isUsbSource = false;
                if (!formatExtVolume(volId, hiddenFileSystem)) {
                    v.dataCtxInitialized = false;
                    break;
                }
            } else if (useNtfs) {
                char deviceName[16];
                std::snprintf(deviceName, sizeof(deviceName), "ve%d", volId);
                char* args[] = {
                    const_cast<char*>("mkntfs"), const_cast<char*>("-F"),
                    const_cast<char*>("-Q"), const_cast<char*>("-s"),
                    const_cast<char*>("512"), const_cast<char*>("-p"),
                    const_cast<char*>("0"), deviceName, nullptr
                };
                if (vaultexplorer_mkntfs_main(8, args) != 0) {
                    v.dataCtxInitialized = false;
                    break;
                }
            } else {
                std::unique_ptr<BYTE[]> workBuf(new BYTE[MKFS_WORK_BUF_SIZE]);
                MKFS_PARM opt = {0};
                opt.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
                opt.n_fat = useExFat ? 1 : 2;
                opt.align = 0;
                opt.n_root = 512;
                opt.au_size = useExFat ? 0 : vc_fat_cluster_size(hiddenDataSize);
                if (f_mkfs(drivePaths[volId], &opt, workBuf.get(), MKFS_WORK_BUF_SIZE) != FR_OK) {
                    v.dataCtxInitialized = false;
                    break;
                }
            }
        }

        {
            std::unique_lock<std::shared_mutex> vlock(v.mutex);
            v.fdWriteBuffer.flush(v.fd);
            v.fsMounted = false;
            v.fd = -1;
            v.dataCtxInitialized = false;
        }

        success = true;
    } while (false);

    mbedtls_platform_zeroize(hiddenCombinedMasterKey, sizeof(hiddenCombinedMasterKey));
    mbedtls_platform_zeroize(hiddenSalt, sizeof(hiddenSalt));
    if (success) fsync(fd);
    close(fd);
    return success;
}

bool createContainerWithHidden(int fd,
                               const char* outerPassword, const char* hiddenPassword,
                               int outerPim, int hiddenPim,
                               int64_t sizeBytes,
                               const char* outerFileSystem, const char* hiddenFileSystem,
                               int64_t hiddenSizeBytes,
                               int outerCipherId, int outerHashId,
                               int hiddenCipherId, int hiddenHashId,
                               const int* outerKeyfileFds, int outerKeyfileCount,
                               const int* hiddenKeyfileFds, int hiddenKeyfileCount,
                               bool quickFormat) {
    int fdOuter = dup(fd);
    if (fdOuter < 0) {
        close(fd);
        if (outerKeyfileFds) for (int i = 0; i < outerKeyfileCount; i++) if (outerKeyfileFds[i] >= 0) close(outerKeyfileFds[i]);
        if (hiddenKeyfileFds) for (int i = 0; i < hiddenKeyfileCount; i++) if (hiddenKeyfileFds[i] >= 0) close(hiddenKeyfileFds[i]);
        return false;
    }

    bool outerSuccess = createContainer(fdOuter, outerPassword, outerPim, sizeBytes, outerFileSystem,
                                        outerCipherId, outerHashId, outerKeyfileFds, outerKeyfileCount,
                                        quickFormat);
    if (!outerSuccess) {
        close(fd);
        if (hiddenKeyfileFds) for (int i = 0; i < hiddenKeyfileCount; i++) if (hiddenKeyfileFds[i] >= 0) close(hiddenKeyfileFds[i]);
        return false;
    }

    return createHiddenVolumePhase(fd, sizeBytes, hiddenPassword, hiddenPim, hiddenFileSystem, hiddenSizeBytes,
                                   hiddenCipherId, hiddenHashId, hiddenKeyfileFds, hiddenKeyfileCount, quickFormat);
}

bool changeContainerPassword(int fd,
                             const char* oldPassword, const char* newPassword,
                             int oldPim, int newPim,
                             int cipherId, int hashId,
                             const int* oldKeyfileFds, int oldKeyfileCount,
                             const int* newKeyfileFds, int newKeyfileCount,
                             int newHashId) {
    bool success = false;
    unsigned char oldMixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize oldMixedPasswordGuard(oldMixedPassword, sizeof(oldMixedPassword));
    // The OLD password keeps the lenient truncation (a volume made by an older build of this
    // app from a >128-byte password was keyed from its first 128 bytes). The NEW password
    // must fit, like upstream requires.
    size_t oldMixedPasswordLen = std::min(strlen(oldPassword), sizeof(oldMixedPassword));
    memcpy(oldMixedPassword, oldPassword, oldMixedPasswordLen);

    if (oldKeyfileCount > 0 && oldKeyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(oldKeyfileFds, oldKeyfileCount, oldMixedPassword, &oldMixedPasswordLen)) {
            close(fd);
            if (newKeyfileFds) for (int i = 0; i < newKeyfileCount; i++) if (newKeyfileFds[i] >= 0) close(newKeyfileFds[i]);
            return false;
        }
    }

    unsigned char newMixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize newMixedPasswordGuard(newMixedPassword, sizeof(newMixedPassword));
    if (strlen(newPassword) > VC_MAX_PASSWORD_BYTES) {
        LOGI("changeContainerPassword: new password longer than %zu bytes (UTF-8)", VC_MAX_PASSWORD_BYTES);
        close(fd);
        if (newKeyfileFds) for (int i = 0; i < newKeyfileCount; i++) if (newKeyfileFds[i] >= 0) close(newKeyfileFds[i]);
        return false;
    }
    size_t newMixedPasswordLen = strlen(newPassword);
    memcpy(newMixedPassword, newPassword, newMixedPasswordLen);

    if (newKeyfileCount > 0 && newKeyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(newKeyfileFds, newKeyfileCount, newMixedPassword, &newMixedPasswordLen)) {
            close(fd);
            return false;
        }
    }

    do {
        uint64_t targetOffset = 0;
        bool foundMatch = false;
        unsigned char recoveredKeyMaterial[192] = {0};
        unsigned char decryptedBody[VC_HEADER_BODY_SIZE] = {0};
        CascadeId matchedCipher{};
        HashId matchedHash{};
        ParsedHeaderFields fields;
        struct HeaderSlot { uint64_t fileOffset; };
        static constexpr HeaderSlot kHeaderSlots[] = { { 0 }, { VC_HIDDEN_HEADER_OFFSET } };

        for (const auto& slot : kHeaderSlots) {
            unsigned char primaryHeaderSector[VC_FULL_HEADER_SIZE];
            if (pread(fd, primaryHeaderSector, VC_FULL_HEADER_SIZE, slot.fileOffset) != VC_FULL_HEADER_SIZE) continue;
            if (deriveAndValidateHeader(primaryHeaderSector, oldMixedPassword, oldMixedPasswordLen, oldPim,
                                        cipherId, hashId,
                                        recoveredKeyMaterial, decryptedBody,
                                        matchedCipher, matchedHash, fields, -1, nullptr, slot.fileOffset > 0 ? 1 : 0)) {
                foundMatch = true;
                targetOffset = slot.fileOffset;
                break;
            }
        }

        if (!foundMatch) break;

        mbedtls_platform_zeroize(recoveredKeyMaterial, sizeof(recoveredKeyMaterial));

        // Like upstream (VolumeHeader::EncryptNew writes the current header
        // version on every re-encryption): a header written by an older build of
        // this app carries format version 2, which upstream treats as a legacy
        // header without CRC protection. Bring it to version 5 and refresh the
        // header CRC. Headers that are already version >= 5 are left untouched.
        {
            const unsigned oldVersion = (static_cast<unsigned>(decryptedBody[VC_HDR_OFF_VERSION]) << 8) |
                                         decryptedBody[VC_HDR_OFF_VERSION + 1];
            if (oldVersion < VC_HEADER_FORMAT_VERSION) {
                vcStampHeaderPreamble(decryptedBody);
                const uint32_t crc = container_crc32(decryptedBody, VC_HDR_CRC_COVERAGE_LEN);
                for (int i = 0; i < 4; i++) {
                    decryptedBody[VC_HDR_OFF_HEADER_CRC + i] = static_cast<unsigned char>(crc >> (24 - 8 * i));
                }
            }
        }

        unsigned char newSalt[VC_SALT_SIZE];
        if (!userentropy::fillRandom(newSalt, sizeof(newSalt))) break;

        int clampedNewPim = clampPim(newPim);
        unsigned char newHeaderKey[192] = {0};
        ScopeZeroize newHeaderKeyGuard(newHeaderKey, sizeof(newHeaderKey));
        // PRF for the re-encrypted header (both copies): the caller's choice, otherwise the one this
        // header was found with. An id outside the known range is refused before anything is written
        // instead of being silently replaced -- the caller asked for a specific algorithm.
        HashId newHash = matchedHash;
        if (newHashId != 255) {
            if (newHashId < 0 || newHashId > static_cast<int>(HashId::kArgon2id)) {
                LOGI("changeContainerPassword: unknown PRF id %d", newHashId);
                break;
            }
            newHash = static_cast<HashId>(newHashId);
        }

        if (!deriveHeaderKey(newHash, newMixedPassword, newMixedPasswordLen,
                             newSalt, clampedNewPim, newHeaderKey, sizeof(newHeaderKey))) {
            break;
        }

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            CascadeSpec cSpec = cascadeSpecFor(matchedCipher);
            int masterKeyLen = cSpec.layerCount * 64;
            CascadeContext hdrCtx;
            if (!cascadeSetKeys(hdrCtx, matchedCipher, newHeaderKey, masterKeyLen)) break;
            std::memcpy(encBody, decryptedBody, VC_HEADER_BODY_SIZE);
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

        // Primary and backup each get their own salt and KDF run, as in
        // upstream's CoreBase::ChangePassword (one pass per header copy).
        unsigned char backupSector[VC_FULL_HEADER_SIZE];
        const bool backupBuilt = vcBuildFreshlySaltedHeaderSector(
            decryptedBody, matchedCipher, newHash, newMixedPassword, newMixedPasswordLen,
            clampedNewPim, backupSector);
        mbedtls_platform_zeroize(decryptedBody, sizeof(decryptedBody));
        if (!backupBuilt) break;

        unsigned char hdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hdrSector,                  newSalt, VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE,   encBody, VC_HEADER_BODY_SIZE);

        // Locate the backup copy of this header slot from the real size of the
        // container, the way VeraCrypt does (relative to its END). The header's
        // volume-size field is the size of the data area, i.e. 2*A smaller than
        // the container, so it cannot be used for this -- doing so used to put
        // the "backup" 2*A too early, inside user data, and leave the genuine
        // backup holding the old credentials. Everything is validated before
        // the first byte is written so a refusal leaves the container untouched.
        const bool hiddenSlot = (targetOffset != 0);
        uint64_t containerSize = 0;
        {
            struct stat st;
            if (fstat(fd, &st) == 0 && st.st_size > 0) {
                containerSize = static_cast<uint64_t>(st.st_size);
            } else {
                const off_t end = lseek(fd, 0, SEEK_END);
                if (end > 0) containerSize = static_cast<uint64_t>(end);
            }
        }
        uint64_t backupOffset = 0;
        if (!vcgeom::backupHeaderOffset(containerSize, hiddenSlot, &backupOffset)) {
            LOGI("changeContainerPassword: cannot determine container size");
            break;
        }
        const uint64_t dataAreaLen =
            fields.encryptedAreaLength != 0 ? fields.encryptedAreaLength : fields.volumeSize;
        const bool backupClearOfData =
            vcgeom::headerClearOfDataArea(backupOffset, fields.encryptedAreaStart, dataAreaLen);
        bool writeBackup = true;
        if (!backupClearOfData) {
            if (!hiddenSlot) {
                // A normal volume whose data area reaches its own backup header
                // is not a layout we understand; never write over user data.
                LOGI("changeContainerPassword: backup header would overlap the data area");
                break;
            }
            // Hidden volume laid out by an older version of this app: its data
            // extends over the hidden backup slot, so there is none to update.
            writeBackup = false;
        }

        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE, static_cast<off_t>(targetOffset)) != VC_FULL_HEADER_SIZE) break;
        if (writeBackup &&
            pwrite(fd, backupSector, VC_FULL_HEADER_SIZE, static_cast<off_t>(backupOffset)) != VC_FULL_HEADER_SIZE) {
            break;
        }

        // Read both copies back: a header that did not land where intended must
        // not be reported as a successful password change.
        {
            unsigned char verify[VC_FULL_HEADER_SIZE];
            if (pread(fd, verify, VC_FULL_HEADER_SIZE, static_cast<off_t>(targetOffset)) != VC_FULL_HEADER_SIZE ||
                memcmp(verify, hdrSector, VC_FULL_HEADER_SIZE) != 0) {
                break;
            }
            if (writeBackup &&
                (pread(fd, verify, VC_FULL_HEADER_SIZE, static_cast<off_t>(backupOffset)) != VC_FULL_HEADER_SIZE ||
                 memcmp(verify, backupSector, VC_FULL_HEADER_SIZE) != 0)) {
                break;
            }
        }

        success = true;
    } while(false);

    if (success) fsync(fd);
    close(fd);
    return success;
}

int changeLuksContainerPassword(int fd,
                                const char* oldPassword, const char* newPassword,
                                const int* oldKeyfileFds, int oldKeyfileCount,
                                const int* newKeyfileFds, int newKeyfileCount) {
    auto resolveEffectivePassword = [](const char* typedPassword,
                                        const int* keyfileFds, int keyfileCount,
                                        std::vector<unsigned char>& keyfileBuf) -> const unsigned char* {
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
            return keyfileBuf.empty() ? nullptr : keyfileBuf.data();
        }
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        return reinterpret_cast<const unsigned char*>(typedPassword);
    };

    std::vector<unsigned char> oldKeyfileBuf;
    const unsigned char* oldEffective = resolveEffectivePassword(oldPassword, oldKeyfileFds, oldKeyfileCount, oldKeyfileBuf);
    size_t oldEffectiveLen = oldKeyfileBuf.empty() ? strlen(oldPassword) : oldKeyfileBuf.size();
    if (oldEffective == nullptr) {
        closeUnusedKeyfileFds(newKeyfileFds, newKeyfileCount);
        close(fd);
        return 2;
    }

    std::vector<unsigned char> newKeyfileBuf;
    const unsigned char* newEffective = resolveEffectivePassword(newPassword, newKeyfileFds, newKeyfileCount, newKeyfileBuf);
    size_t newEffectiveLen = newKeyfileBuf.empty() ? strlen(newPassword) : newKeyfileBuf.size();
    if (newEffective == nullptr || newEffectiveLen == 0) {
        close(fd);
        return 2;
    }

    if (oldEffectiveLen == 0) {
        close(fd);
        return 2;
    }

    LuksChangePasswordResult result = luksChangeKeyslotPassword(
        fd, oldEffective, oldEffectiveLen, newEffective, newEffectiveLen);
    if (!oldKeyfileBuf.empty()) mbedtls_platform_zeroize(oldKeyfileBuf.data(), oldKeyfileBuf.size());
    if (!newKeyfileBuf.empty()) mbedtls_platform_zeroize(newKeyfileBuf.data(), newKeyfileBuf.size());
    if (result == LuksChangePasswordResult::kSuccess) fsync(fd);
    close(fd);

    switch (result) {
        case LuksChangePasswordResult::kSuccess: return 0;
        case LuksChangePasswordResult::kWrongOldPassword: return 1;
        default: return 2;
    }
}


// Grows the file system inside an UNLOCKED standard volume into the space an expand added, on a temporary
// volume slot (the same way container creation borrows one to format): no session, no UI, nothing else sees
// the slot. [masterKeys] is the volume's key material, [fileSize] the (new) host size.
static void growFileSystemOfStandardVolume(int fd, CascadeId cipher, const unsigned char* masterKeys,
                                           uint64_t fileSize, uint32_t sectorSize, FsGrowReport* report) {
    report->attempted = true;
    report->status = FsGrowStatus::kFailed;
    int volId = -1;
    {
        std::lock_guard<std::mutex> allocLock(slotAllocMutex);
        for (int i = 0; i < MAX_VOLUMES; i++) {
            if (!volumes[i].dataCtxInitialized) { volumes[i].dataCtxInitialized = true; volId = i; break; }
        }
    }
    if (volId < 0) { LOGI("growFileSystem: no free slots available"); return; }
    VolumeState& v = volumes[volId];
    std::unique_lock<std::shared_mutex> vlock(v.mutex);
    if (cascadeSetKeys(v.cascade, cipher, masterKeys, cascadeSpecFor(cipher).layerCount * 64)) {
        v.fd = fd;                                   // not owned by the slot: detached again before reset()
        v.dataOffset = VC_DATA_AREA_OFFSET;
        v.dataAreaLengthBytes = fileSize - 2 * VC_DATA_AREA_OFFSET;
        v.fileSize = fileSize;
        v.luksSectorSize = sectorSize >= 512 ? sectorSize : 512;
        v.partitionStartSector = 0;
        v.matchedCipherId = static_cast<int>(cipher);
        v.readOnly = false;
        v.isUsbSource = false;
        if (ensureMounted(volId)) {
            const std::string label = fsGetFilesystemLabel(volId);
            std::snprintf(report->fsLabel, sizeof(report->fsLabel), "%s", label.c_str());
            report->status = fsGrowToFit(volId);
            LOGI("growFileSystem: %s -> status %d", report->fsLabel, static_cast<int>(report->status));
        } else {
            report->status = FsGrowStatus::kUnsupported;   // no file system we recognise (raw, or unformatted)
        }
        unmountVolume(volId);                        // flushes the write buffer and fsyncs the container
    }
    v.fd = -1;
    v.reset();
}

ExpandOutcome expandVeraCryptContainer(int fd, const char* password, int pim, int cipherId, int hashId,
                                       const int* keyfileFds, int keyfileCount,
                                       int64_t newSizeBytes, bool initFreeSpace,
                                       bool growFileSystem, FsGrowReport* fsReport) {
    std::lock_guard<std::mutex> lifecycleLock(volumeLifecycleMutex);
    if (containerFileIsUnlocked(fd)) {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        if (fd >= 0) close(fd);
        return ExpandOutcome::kContainerInUse;
    }
    ExpandOutcome outcome = ExpandOutcome::kIoError;
    unsigned char mixedPassword[MAX_PASSWORD_LEN];
    size_t mixedLen = std::min(strlen(password), sizeof(mixedPassword));
    memcpy(mixedPassword, password, mixedLen);
    unsigned char keyMaterial[192];
    unsigned char body[VC_HEADER_BODY_SIZE];
    do {
        if (keyfileCount > 0 && keyfileFds != nullptr) {
            if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedLen)) {
                outcome = ExpandOutcome::kBadKeyfile;
                break;
            }
        }
        struct stat st;
        if (fstat(fd, &st) != 0 || newSizeBytes <= 0) break;
        unsigned char sector[VC_FULL_HEADER_SIZE];
        if (pread(fd, sector, sizeof(sector), 0) != static_cast<ssize_t>(sizeof(sector))) break;
        CascadeId matchedCipher{};
        HashId matchedHash{};
        ParsedHeaderFields fields;
        if (!deriveAndValidateHeader(sector, mixedPassword, mixedLen, pim, cipherId, hashId,
                                     keyMaterial, body, matchedCipher, matchedHash, fields)) {
            outcome = ExpandOutcome::kWrongPassword;
            break;
        }
        VcExpandIo io;
        io.setSize = [fd](uint64_t n) { return ftruncate(fd, static_cast<off_t>(n)) == 0; };
        io.writeAt = [fd](uint64_t off, const unsigned char* data, size_t len) {
            size_t done = 0;
            while (done < len) {
                const ssize_t w = pwrite(fd, data + done, len - done, static_cast<off_t>(off + done));
                if (w <= 0) return false;
                done += static_cast<size_t>(w);
            }
            return true;
        };
        io.random = [](unsigned char* p, size_t n) { return userentropy::fillRandom(p, n); };
        const VcExpandResult r = vcExpandVolume(body, matchedCipher, matchedHash, mixedPassword, mixedLen, pim,
                                                static_cast<uint64_t>(st.st_size),
                                                static_cast<uint64_t>(newSizeBytes), initFreeSpace, io);
        switch (r) {
            case VcExpandResult::kOk:
                fsync(fd);
                outcome = ExpandOutcome::kOk;
                // The container is expanded and its header rewritten whatever happens next; the file system
                // grow is a separate step whose result is reported on its own.
                if (growFileSystem && fsReport != nullptr) {
                    growFileSystemOfStandardVolume(fd, matchedCipher, body + VC_KEY_OFFSET_MASTER,
                                                   (static_cast<uint64_t>(newSizeBytes) / 4096) * 4096,
                                                   fields.sectorSize, fsReport);
                }
                break;
            case VcExpandResult::kHiddenHeader:
            case VcExpandResult::kInconsistentHeader: outcome = ExpandOutcome::kNotExpandable; break;
            case VcExpandResult::kNotLarger:          outcome = ExpandOutcome::kNotLarger; break;
            default:                                  outcome = ExpandOutcome::kIoError; break;
        }
    } while (false);
    mbedtls_platform_zeroize(mixedPassword, sizeof(mixedPassword));
    mbedtls_platform_zeroize(keyMaterial, sizeof(keyMaterial));
    mbedtls_platform_zeroize(body, sizeof(body));
    close(fd);
    return outcome;
}

static void closeFds(const int* fds, int count) {
    if (fds != nullptr) for (int i = 0; i < count; i++) if (fds[i] >= 0) close(fds[i]);
}

// Decrypts the standard volume's header, validates it is a plain full-size standard volume and measures the
// free tail of its file system. [fd] stays open.
static HiddenHostOutcome inspectOuterVolume(int fd, const unsigned char* password, size_t passwordLen, int pim,
                                            int cipherId, int hashId, HiddenHostAnalysis* out, uint64_t* containerSize) {
    struct stat st;
    if (fstat(fd, &st) != 0) return HiddenHostOutcome::kIoError;
    unsigned char sector[VC_FULL_HEADER_SIZE];
    if (pread(fd, sector, sizeof(sector), 0) != static_cast<ssize_t>(sizeof(sector))) return HiddenHostOutcome::kIoError;
    unsigned char keyMaterial[192];
    unsigned char body[VC_HEADER_BODY_SIZE];
    ScopeZeroize keyGuard(keyMaterial, sizeof(keyMaterial));
    ScopeZeroize bodyGuard(body, sizeof(body));
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;
    if (!deriveAndValidateHeader(sector, password, passwordLen, pim, cipherId, hashId,
                                 keyMaterial, body, matchedCipher, matchedHash, fields)) {
        return HiddenHostOutcome::kWrongPassword;
    }
    const uint64_t size = static_cast<uint64_t>(st.st_size);
    if (fields.isHiddenVolume() || size < 2 * VC_DATA_AREA_OFFSET + 4096 || size % 4096 != 0 ||
        fields.encryptedAreaStart != VC_DATA_AREA_OFFSET || fields.volumeSize != size - 2 * VC_DATA_AREA_OFFSET) {
        return HiddenHostOutcome::kInvalid;   // not a plain, full-size standard volume
    }
    CascadeContext ctx;
    if (!cascadeSetKeys(ctx, matchedCipher, body + VC_KEY_OFFSET_MASTER, cascadeSpecFor(matchedCipher).layerCount * 64)) {
        return HiddenHostOutcome::kIoError;
    }
    VcReadFn reader = vcMakeOuterReader(&ctx, fields.encryptedAreaStart, fields.volumeSize,
        [fd](uint64_t off, unsigned char* buf, size_t len) {
            size_t done = 0;
            while (done < len) {
                const ssize_t r = pread(fd, buf + done, len - done, static_cast<off_t>(off + done));
                if (r <= 0) return false;
                done += static_cast<size_t>(r);
            }
            return true;
        });
    VcFsTail tail;
    if (!vcAnalyzeFsTail(reader, &tail)) return HiddenHostOutcome::kUnsupportedFs;
    out->fsKind = static_cast<int>(tail.kind);
    out->clusterSize = tail.clusterSize;
    out->maxHiddenBytes = vcMaxHiddenVolumeSize(tail, fields.volumeSize);
    *containerSize = size;
    return HiddenHostOutcome::kOk;
}

ExpandOutcome growVeraCryptFileSystem(int fd, const char* password, int pim, int cipherId, int hashId,
                                      const int* keyfileFds, int keyfileCount, FsGrowReport* fsReport) {
    std::lock_guard<std::mutex> lifecycleLock(volumeLifecycleMutex);
    if (containerFileIsUnlocked(fd)) {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        if (fd >= 0) close(fd);
        return ExpandOutcome::kContainerInUse;
    }
    ExpandOutcome outcome = ExpandOutcome::kIoError;
    unsigned char mixedPassword[MAX_PASSWORD_LEN];
    size_t mixedLen = std::min(strlen(password), sizeof(mixedPassword));
    memcpy(mixedPassword, password, mixedLen);
    unsigned char keyMaterial[192];
    unsigned char body[VC_HEADER_BODY_SIZE];
    do {
        if (keyfileCount > 0 && keyfileFds != nullptr &&
            !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedLen)) {
            outcome = ExpandOutcome::kBadKeyfile;
            break;
        }
        struct stat st;
        unsigned char sector[VC_FULL_HEADER_SIZE];
        if (fstat(fd, &st) != 0 || pread(fd, sector, sizeof(sector), 0) != static_cast<ssize_t>(sizeof(sector))) break;
        CascadeId matchedCipher{};
        HashId matchedHash{};
        ParsedHeaderFields fields;
        if (!deriveAndValidateHeader(sector, mixedPassword, mixedLen, pim, cipherId, hashId,
                                     keyMaterial, body, matchedCipher, matchedHash, fields)) {
            outcome = ExpandOutcome::kWrongPassword;
            break;
        }
        const uint64_t size = static_cast<uint64_t>(st.st_size);
        if (fields.isHiddenVolume() || size < 2 * VC_DATA_AREA_OFFSET + 4096 || size % 4096 != 0 ||
            fields.encryptedAreaStart != VC_DATA_AREA_OFFSET || fields.volumeSize != size - 2 * VC_DATA_AREA_OFFSET) {
            outcome = ExpandOutcome::kNotExpandable;   // not a plain, full-size standard volume
            break;
        }
        growFileSystemOfStandardVolume(fd, matchedCipher, body + VC_KEY_OFFSET_MASTER, size, fields.sectorSize, fsReport);
        outcome = ExpandOutcome::kOk;
    } while (false);
    mbedtls_platform_zeroize(mixedPassword, sizeof(mixedPassword));
    mbedtls_platform_zeroize(keyMaterial, sizeof(keyMaterial));
    mbedtls_platform_zeroize(body, sizeof(body));
    close(fd);
    return outcome;
}

HiddenHostOutcome analyzeHiddenVolumeHost(int fd, const char* password, int pim, int cipherId, int hashId,
                                          const int* keyfileFds, int keyfileCount, HiddenHostAnalysis* out) {
    unsigned char mixed[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedGuard(mixed, sizeof(mixed));
    size_t mixedLen = std::min(strlen(password), sizeof(mixed));
    memcpy(mixed, password, mixedLen);
    HiddenHostOutcome outcome = HiddenHostOutcome::kBadKeyfile;
    if (keyfileCount <= 0 || keyfileFds == nullptr || applyKeyfilesToPassword(keyfileFds, keyfileCount, mixed, &mixedLen)) {
        uint64_t containerSize = 0;
        outcome = inspectOuterVolume(fd, mixed, mixedLen, pim, cipherId, hashId, out, &containerSize);
    }
    close(fd);
    return outcome;
}

HiddenHostOutcome createHiddenVolumeInExisting(int fd,
                                               const char* outerPassword, int outerPim, int outerCipherId, int outerHashId,
                                               const int* outerKeyfileFds, int outerKeyfileCount,
                                               const char* hiddenPassword, int hiddenPim,
                                               const char* hiddenFileSystem, int64_t hiddenSizeBytes,
                                               int hiddenCipherId, int hiddenHashId,
                                               const int* hiddenKeyfileFds, int hiddenKeyfileCount,
                                               bool quickFormat) {
    unsigned char mixed[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedGuard(mixed, sizeof(mixed));
    size_t mixedLen = std::min(strlen(outerPassword), sizeof(mixed));
    memcpy(mixed, outerPassword, mixedLen);
    HiddenHostOutcome outcome = HiddenHostOutcome::kBadKeyfile;
    HiddenHostAnalysis analysis;
    uint64_t containerSize = 0;
    if (outerKeyfileCount <= 0 || outerKeyfileFds == nullptr ||
        applyKeyfilesToPassword(outerKeyfileFds, outerKeyfileCount, mixed, &mixedLen)) {
        outcome = inspectOuterVolume(fd, mixed, mixedLen, outerPim, outerCipherId, outerHashId, &analysis, &containerSize);
    }
    if (outcome == HiddenHostOutcome::kOk) {
        if (strlen(hiddenPassword) > VC_MAX_PASSWORD_BYTES ||
            (outerKeyfileCount <= 0 && hiddenKeyfileCount <= 0 && strcmp(outerPassword, hiddenPassword) == 0)) {
            outcome = HiddenHostOutcome::kInvalid;   // too long, or identical to the outer password (it could never be told apart)
        } else if (hiddenSizeBytes <= 0 || static_cast<uint64_t>(hiddenSizeBytes) > analysis.maxHiddenBytes) {
            outcome = HiddenHostOutcome::kNoSpace;
        }
    }
    if (outcome != HiddenHostOutcome::kOk) {
        close(fd);
        closeFds(hiddenKeyfileFds, hiddenKeyfileCount);
        return outcome;
    }
    const bool created = createHiddenVolumePhase(fd, static_cast<int64_t>(containerSize), hiddenPassword, hiddenPim,
                                                 hiddenFileSystem, hiddenSizeBytes, hiddenCipherId, hiddenHashId,
                                                 hiddenKeyfileFds, hiddenKeyfileCount, quickFormat);
    return created ? HiddenHostOutcome::kOk : HiddenHostOutcome::kIoError;
}

// Encrypt a range of plaintext zeroes as LUKS XTS data units. LUKS
// iv_tweak is in 512-byte sectors, while each data unit advances by
// sectorSize/512 sectors. Therefore the tweak is unitIndex * sectorsPerUnit
// + ivTweak (not (unitIndex + ivTweak) * sectorsPerUnit).
static bool fillLuksZeroRange(int fd, uint64_t fileOffset, uint64_t length,
                              CascadeContext& dataCipher, uint64_t sectorSize,
                              uint64_t firstUnitIndex, uint64_t ivTweak) {
    if (fd < 0 || !dataCipher.initialized || sectorSize < 512 || sectorSize > 4096 ||
        (sectorSize & (sectorSize - 1)) != 0 || length == 0 ||
        length % sectorSize != 0 || fileOffset % sectorSize != 0) return false;

    constexpr uint64_t kBatchBytes = 1024 * 1024;
    const size_t unitsPerBatch = static_cast<size_t>(std::max<uint64_t>(1, kBatchBytes / sectorSize));
    const size_t batchBytes = unitsPerBatch * static_cast<size_t>(sectorSize);
    std::vector<unsigned char> plaintext(batchBytes, 0);
    std::vector<unsigned char> encrypted(batchBytes, 0);
    const uint64_t sectorsPerUnit = sectorSize / 512;
    const uint64_t unitCount = length / sectorSize;

    for (uint64_t unit = 0; unit < unitCount;) {
        const size_t count = static_cast<size_t>(std::min<uint64_t>(unitsPerBatch, unitCount - unit));
        const size_t bytes = count * static_cast<size_t>(sectorSize);
        for (size_t i = 0; i < count; ++i) {
            if (firstUnitIndex > UINT64_MAX - (unit + i)) return false;
            const uint64_t logicalUnit = firstUnitIndex + unit + i;
            if (logicalUnit > (UINT64_MAX - ivTweak) / sectorsPerUnit) return false;
            const uint64_t tweak = logicalUnit * sectorsPerUnit + ivTweak;
            if (!cascadeCryptLuksXtsUnit(dataCipher, true, tweak, static_cast<size_t>(sectorSize),
                                         plaintext.data() + i * sectorSize,
                                         encrypted.data() + i * sectorSize)) return false;
        }

        size_t written = 0;
        const uint64_t offset = fileOffset + unit * sectorSize;
        while (written < bytes) {
            const ssize_t n = pwrite(fd, encrypted.data() + written, bytes - written,
                                     static_cast<off_t>(offset + written));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) return false;
            written += static_cast<size_t>(n);
        }
        unit += count;
    }
    mbedtls_platform_zeroize(plaintext.data(), plaintext.size());
    mbedtls_platform_zeroize(encrypted.data(), encrypted.size());
    return true;
}

static bool luksCipherId(const std::string& name, CascadeId& out) {
    if (name == "aes") { out = CascadeId::kAes; return true; }
    if (name == "serpent") { out = CascadeId::kSerpent; return true; }
    if (name == "twofish") { out = CascadeId::kTwofish; return true; }
    if (name == "camellia") { out = CascadeId::kCamellia; return true; }
    if (name == "kuznyechik") { out = CascadeId::kKuznyechik; return true; }
    return false;
}

static void growFileSystemOfLuksVolume(int fd, const LuksVolumeInfo& info,
                                       CascadeContext& dataCipher, uint64_t fileSize,
                                       uint64_t dataAreaLengthBytes, FsGrowReport* report) {
    if (!report) return;
    if (info.dataSectorSize < 512 || info.dataSectorSize % 512 != 0 ||
        info.dataOffsetBytes % 512 != 0 || dataAreaLengthBytes == 0 ||
        dataAreaLengthBytes % info.dataSectorSize != 0 ||
        info.ivTweak > info.dataOffsetBytes / 512) {
        report->attempted = true;
        report->status = FsGrowStatus::kUnsupported;
        return;
    }
    report->attempted = true;
    report->status = FsGrowStatus::kFailed;

    int volId = -1;
    {
        std::lock_guard<std::mutex> allocLock(slotAllocMutex);
        for (int i = 0; i < MAX_VOLUMES; ++i) {
            if (!volumes[i].dataCtxInitialized) {
                volumes[i].dataCtxInitialized = true;
                volId = i;
                break;
            }
        }
    }
    if (volId < 0) {
        LOGI("growFileSystemOfLuksVolume: no free volume slots");
        return;
    }

    VolumeState& v = volumes[volId];
    std::unique_lock<std::shared_mutex> vlock(v.mutex);
    v.fd = fd; // borrowed; detached before reset() below
    v.dataOffset = info.dataOffsetBytes;
    v.dataAreaLengthBytes = dataAreaLengthBytes;
    v.fileSize = fileSize;
    v.luksSectorSize = static_cast<uint32_t>(info.dataSectorSize >= 512 ? info.dataSectorSize : 512);
    {
        // The data area was just zero-filled with this exact cipher (XTS-plain64, validated by
        // luksInfoSupportsDataArea); build the same context for the filesystem grow.
        LuksCipherSpec growSpec;
        if (!luksParseCipherSpec(info.cipherName, info.cipherMode,
                                 static_cast<uint32_t>(info.masterKey.size()), growSpec) ||
            !luksCipherInit(v.luksCipher, growSpec, info.masterKey.data(), info.masterKey.size())) {
            LOGI("growFileSystemOfLuksVolume: cipher setup failed");
            v.fd = -1;
            v.reset();
            return;
        }
    }
    const uint64_t segmentStartSector = info.dataOffsetBytes / 512;
    v.partitionStartSector = segmentStartSector - info.ivTweak; // validated before the slot is created
    v.matchedCipherId = -1;
    v.readOnly = false;
    v.isUsbSource = false;
    v.isCompositeSource = false;
    v.containerFormat = info.version == 1 ? ContainerFormat::kLuks1 : ContainerFormat::kLuks2;
    v.dataCtxInitialized = true;

    if (ensureMounted(volId)) {
        const std::string label = fsGetFilesystemLabel(volId);
        std::snprintf(report->fsLabel, sizeof(report->fsLabel), "%s", label.c_str());
        report->status = fsGrowToFit(volId);
        LOGI("growFileSystemOfLuksVolume: %s -> status %d", report->fsLabel,
             static_cast<int>(report->status));
    } else {
        report->status = FsGrowStatus::kUnsupported;
    }
    unmountVolume(volId);
    v.fd = -1;
    v.reset();
}

static LuksByteReader makeLuksFdReader(int fd) {
    return [fd](uint64_t offset, void* out, size_t len) {
        size_t done = 0;
        while (done < len) {
            const ssize_t n = pread(fd, static_cast<unsigned char*>(out) + done,
                                    len - done, static_cast<off_t>(offset + done));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) return false;
            done += static_cast<size_t>(n);
        }
        return true;
    };
}

static LuksByteWriter makeLuksFdWriter(int fd) {
    return [fd](uint64_t offset, const void* data, size_t len) {
        size_t done = 0;
        while (done < len) {
            const ssize_t n = pwrite(fd, static_cast<const unsigned char*>(data) + done,
                                     len - done, static_cast<off_t>(offset + done));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) return false;
            done += static_cast<size_t>(n);
        }
        return true;
    };
}

static bool readLuksKeyfilePassword(const int* keyfileFds, int keyfileCount,
                                    std::vector<unsigned char>& keyfileBuf,
                                    std::unique_ptr<ScopeZeroize>& keyfileWiper,
                                    const unsigned char*& effectivePassword,
                                    size_t& effectivePasswordLen) {
    if (keyfileCount <= 0 || keyfileFds == nullptr || keyfileFds[0] < 0) {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        return true;
    }
    keyfileBuf.resize(KEYFILE_MAX_READ_LEN);
    ssize_t total = 0;
    while (total < static_cast<ssize_t>(keyfileBuf.size())) {
        const ssize_t n = read(keyfileFds[0], keyfileBuf.data() + total,
                               keyfileBuf.size() - static_cast<size_t>(total));
        if (n < 0) {
            if (errno == EINTR) continue;
            mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
            closeUnusedKeyfileFds(keyfileFds, keyfileCount);
            return false;
        }
        if (n == 0) break;
        total += n;
    }
    keyfileBuf.resize(total > 0 ? static_cast<size_t>(total) : 0);
    closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    if (keyfileBuf.empty()) return false;
    keyfileWiper = std::make_unique<ScopeZeroize>(keyfileBuf.data(), keyfileBuf.size());
    effectivePassword = keyfileBuf.data();
    effectivePasswordLen = keyfileBuf.size();
    return true;
}

static bool luksInfoSupportsDataArea(const LuksVolumeInfo& info, CascadeId& cipherId) {
    if ((info.version != 1 && info.version != 2) ||
        (info.version == 2 && !info.dataIsCryptSegment) ||
        info.dataSegmentCount != 1 || info.dataHasIntegrity ||
        info.dataSegmentHasFlags || info.hasMandatoryRequirements ||
        info.cipherMode.rfind("xts-plain64", 0) != 0 ||
        !luksCipherId(info.cipherName, cipherId) || info.masterKey.size() != 64 ||
        info.dataOffsetBytes == 0 || info.dataSectorSize < 512 ||
        info.dataSectorSize > 4096 ||
        (info.dataSectorSize & (info.dataSectorSize - 1)) != 0 ||
        info.dataOffsetBytes % info.dataSectorSize != 0 ||
        info.ivTweak > info.dataOffsetBytes / 512) return false;
    return true;
}

ExpandOutcome expandLuksContainer(int fd, const char* password,
                                 const int* keyfileFds, int keyfileCount,
                                 int64_t newSizeBytes, bool initFreeSpace,
                                 bool growFileSystem, FsGrowReport* fsReport) {
    std::lock_guard<std::mutex> lifecycleLock(volumeLifecycleMutex);
    if (containerFileIsUnlocked(fd)) {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        if (fd >= 0) close(fd);
        return ExpandOutcome::kContainerInUse;
    }

    ExpandOutcome outcome = ExpandOutcome::kIoError;
    std::vector<unsigned char> keyfileBuf;
    std::unique_ptr<ScopeZeroize> keyfileWiper;
    const unsigned char* effectivePassword = reinterpret_cast<const unsigned char*>(password ? password : "");
    size_t effectivePasswordLen = password ? std::strlen(password) : 0;

    do {
        struct stat st{};
        if (fd < 0 || fstat(fd, &st) != 0 || st.st_size <= 0 || newSizeBytes <= 0) break;
        const uint64_t oldFileSize = static_cast<uint64_t>(st.st_size);
        const uint64_t newFileSize = (static_cast<uint64_t>(newSizeBytes) / 4096) * 4096;
        if (newFileSize < oldFileSize) {
            outcome = ExpandOutcome::kNotLarger;
            break;
        }

        const LuksByteReader reader = makeLuksFdReader(fd);
        const LuksHeaderProbeResult probe = luksProbeHeader(reader);
        if (probe == LuksHeaderProbeResult::kNotLuks) {
            outcome = ExpandOutcome::kNotLuks;
            break;
        }
        if (probe != LuksHeaderProbeResult::kValid) {
            outcome = ExpandOutcome::kInvalidHeader;
            break;
        }
        if (!readLuksKeyfilePassword(keyfileFds, keyfileCount, keyfileBuf, keyfileWiper,
                                     effectivePassword, effectivePasswordLen)) {
            outcome = ExpandOutcome::kBadKeyfile;
            break;
        }
        if (effectivePasswordLen == 0) {
            outcome = ExpandOutcome::kWrongPassword;
            break;
        }

        LuksVolumeInfo info;
        if (!luksRecoverMasterKey(fd, effectivePassword, effectivePasswordLen, info)) {
            outcome = ExpandOutcome::kWrongPassword;
            break;
        }
        ScopeZeroize masterKeyWiper(info.masterKey.data(), info.masterKey.size());

        CascadeId cipherId;
        if (!luksInfoSupportsDataArea(info, cipherId) || info.dataOffsetBytes >= oldFileSize) {
            outcome = ExpandOutcome::kNotExpandable;
            break;
        }

        const uint64_t dataSectorSize = info.dataSectorSize;
        const uint64_t availableOld = oldFileSize - info.dataOffsetBytes;
        const bool wasDynamic = info.version == 1 || info.dynamicSize;
        uint64_t oldDataSize = wasDynamic
            ? (availableOld / dataSectorSize) * dataSectorSize
            : info.dataSizeBytes;
        bool needsMetadataRepair = false;

        if (info.version == 2 && !info.dynamicSize) {
            uint64_t metadataOffset = 0, metadataOldSize = 0, metadataIvTweak = 0;
            bool metadataDynamic = true;
            if (!luks2ValidateResize(reader, oldFileSize, newFileSize,
                                     metadataOffset, metadataOldSize, metadataIvTweak,
                                     metadataDynamic, needsMetadataRepair) ||
                metadataOffset != info.dataOffsetBytes || metadataIvTweak != info.ivTweak ||
                metadataDynamic || info.dataSizeBytes != metadataOldSize) {
                outcome = ExpandOutcome::kNotExpandable;
                break;
            }
            oldDataSize = metadataOldSize;
        }

        if (oldDataSize == 0 || oldDataSize > availableOld ||
            oldDataSize % dataSectorSize != 0 || newFileSize < info.dataOffsetBytes) {
            outcome = ExpandOutcome::kNotExpandable;
            break;
        }
        const uint64_t newDataSize = newFileSize - info.dataOffsetBytes;
        if (newDataSize % dataSectorSize != 0 || newDataSize < oldDataSize) {
            outcome = ExpandOutcome::kNotLarger;
            break;
        }
        if (wasDynamic && newDataSize == oldDataSize) {
            outcome = ExpandOutcome::kNotLarger;
            break;
        }
        if (!wasDynamic && newDataSize == oldDataSize && !needsMetadataRepair) {
            outcome = ExpandOutcome::kNotLarger;
            break;
        }

        CascadeContext dataCipher;
        if (!cascadeSetKeys(dataCipher, cipherId, info.masterKey.data(), info.masterKey.size())) {
            outcome = ExpandOutcome::kNotExpandable;
            break;
        }

        const bool fileWasExtendedNow = newFileSize > oldFileSize;
        if (fileWasExtendedNow && ftruncate(fd, static_cast<off_t>(newFileSize)) != 0) {
            mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
            break;
        }
        const uint64_t oldDataEnd = info.dataOffsetBytes + oldDataSize;
        if (initFreeSpace && newDataSize > oldDataSize &&
            !fillLuksZeroRange(fd, oldDataEnd, newDataSize - oldDataSize,
                               dataCipher, dataSectorSize, oldDataSize / dataSectorSize, info.ivTweak)) {
            // Only roll back a file extension performed by this invocation.
            // A retry may be operating on a file already extended by an
            // earlier interrupted attempt; leave that physical size intact.
            if (fileWasExtendedNow) {
                ftruncate(fd, static_cast<off_t>(oldFileSize));
                fsync(fd);
            }
            mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
            break;
        }
        if (fsync(fd) != 0) {
            if (fileWasExtendedNow) {
                ftruncate(fd, static_cast<off_t>(oldFileSize));
                fsync(fd);
            }
            mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
            break;
        }

        if (info.version == 2 && !wasDynamic &&
            (newDataSize > oldDataSize || needsMetadataRepair)) {
            const LuksByteWriter writer = makeLuksFdWriter(fd);
            if (!luks2ResizeSegmentMetadata(reader, writer, oldFileSize, newFileSize,
                                             [fd]() { return fsync(fd) == 0; })) {
                // Never truncate after metadata writes begin: either copy may
                // now be the newest valid recovery header.
                mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
                break;
            }
        }
        if (fsync(fd) != 0) {
            mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
            break;
        }

        outcome = ExpandOutcome::kOk;
        if (growFileSystem && fsReport != nullptr) {
            growFileSystemOfLuksVolume(fd, info, dataCipher, newFileSize, newDataSize, fsReport);
        }
        mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
    } while (false);

    close(fd);
    return outcome;
}

ExpandOutcome growLuksFileSystem(int fd, const char* password,
                                 const int* keyfileFds, int keyfileCount,
                                 FsGrowReport* fsReport) {
    std::lock_guard<std::mutex> lifecycleLock(volumeLifecycleMutex);
    if (containerFileIsUnlocked(fd)) {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        if (fd >= 0) close(fd);
        return ExpandOutcome::kContainerInUse;
    }
    ExpandOutcome outcome = ExpandOutcome::kIoError;
    std::vector<unsigned char> keyfileBuf;
    std::unique_ptr<ScopeZeroize> keyfileWiper;
    const unsigned char* effectivePassword = reinterpret_cast<const unsigned char*>(password ? password : "");
    size_t effectivePasswordLen = password ? std::strlen(password) : 0;

    do {
        struct stat st{};
        if (fd < 0 || fstat(fd, &st) != 0 || st.st_size <= 0) break;
        const uint64_t fileSize = static_cast<uint64_t>(st.st_size);
        const LuksByteReader reader = makeLuksFdReader(fd);
        const LuksHeaderProbeResult probe = luksProbeHeader(reader);
        if (probe == LuksHeaderProbeResult::kNotLuks) {
            outcome = ExpandOutcome::kNotLuks;
            break;
        }
        if (probe != LuksHeaderProbeResult::kValid) {
            outcome = ExpandOutcome::kInvalidHeader;
            break;
        }
        if (!readLuksKeyfilePassword(keyfileFds, keyfileCount, keyfileBuf, keyfileWiper,
                                     effectivePassword, effectivePasswordLen)) {
            outcome = ExpandOutcome::kBadKeyfile;
            break;
        }
        if (effectivePasswordLen == 0) {
            outcome = ExpandOutcome::kWrongPassword;
            break;
        }

        LuksVolumeInfo info;
        if (!luksRecoverMasterKey(fd, effectivePassword, effectivePasswordLen, info)) {
            outcome = ExpandOutcome::kWrongPassword;
            break;
        }
        ScopeZeroize masterKeyWiper(info.masterKey.data(), info.masterKey.size());
        CascadeId cipherId;
        if (!luksInfoSupportsDataArea(info, cipherId) || info.dataOffsetBytes >= fileSize) {
            outcome = ExpandOutcome::kNotExpandable;
            break;
        }
        const uint64_t available = fileSize - info.dataOffsetBytes;
        const uint64_t dataAreaLength = info.dynamicSize
            ? (available / info.dataSectorSize) * info.dataSectorSize
            : info.dataSizeBytes;
        if (dataAreaLength == 0 || dataAreaLength > available ||
            dataAreaLength % info.dataSectorSize != 0) {
            outcome = ExpandOutcome::kNotExpandable;
            break;
        }
        CascadeContext dataCipher;
        if (!cascadeSetKeys(dataCipher, cipherId, info.masterKey.data(), info.masterKey.size())) {
            outcome = ExpandOutcome::kNotExpandable;
            break;
        }
        if (!fsReport) {
            mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
            break;
        }
        growFileSystemOfLuksVolume(fd, info, dataCipher, fileSize, dataAreaLength, fsReport);
        outcome = ExpandOutcome::kOk;
        mbedtls_platform_zeroize(&dataCipher, sizeof(dataCipher));
    } while (false);

    close(fd);
    return outcome;
}
