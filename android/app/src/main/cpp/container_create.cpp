#include "container_create.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#include <android/log.h>

#include "mbedtls/platform_util.h"

#include "container_utils.h"
#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "ext_backend.h"
#include "filesystem_paths.h"
#include "session_prepare.h"
#include "volume_state.h"

#include "ff.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

static constexpr int MAX_VOLUMES = FF_VOLUMES;

// mkntfs formatter, embedded under a renamed entry point (see
// MKNTFS_EMBEDDED_SOURCE in CMakeLists.txt) and routed through
// vExplorer_ntfs_ops for its device I/O.
extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);

// Only used while filling a freshly-created container's data area with
// zero-encrypted sectors, in CREATE_FILL_BATCH-sized batches.
static constexpr uint64_t CREATE_FILL_BATCH = 4096;
static constexpr int MKFS_WORK_BUF_SIZE = 4096;

bool createContainer(int fd, const char* password, int pim, int64_t sizeBytes,
                     const char* fileSystem, int cipherId, int hashId) {
    bool success = false;

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
            FILE* urnd = fopen("/dev/urandom", "rb");
            if (!urnd) { LOGI("createContainer: cannot open /dev/urandom"); break; }
            bool ok = (fread(salt,              1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                      (fread(combinedMasterKey, 1, static_cast<size_t>(masterKeyLen), urnd) == static_cast<size_t>(masterKeyLen));
            fclose(urnd);
            if (!ok) { LOGI("createContainer: urandom read failed"); break; }
        }

        const int safePim = clampPim(pim);
        // Derive the complete 192-byte header key. This is mandatory for
        // Argon2id compatibility and harmless for PBKDF2-based headers.
        unsigned char headerKey[192] = {0};
        if (!deriveHeaderKey(createHash,
                             reinterpret_cast<const unsigned char*>(password), strlen(password),
                             salt, safePim, headerKey, sizeof(headerKey))) {
            LOGI("createContainer: header key derivation failed");
            break;
        }


        // Align to 4096 bytes
        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;

        // Truncate file to exact aligned size
        if (static_cast<uint64_t>(sizeBytes) != VOLUME_SIZE) {
            if (ftruncate(fd, VOLUME_SIZE) != 0) {
                LOGI("DEBUG-Ext: ftruncate failed! errno=%d (%s)", errno, strerror(errno));
            } else {
                LOGI("DEBUG-Ext: Successfully truncated file to %llu", (unsigned long long)VOLUME_SIZE);
            }
        }

        // Verify physical file size matches using fstat
        struct stat st;
        if (fstat(fd, &st) == 0) {
            LOGI("DEBUG-Ext: Physical file size on disk: %lld", (long long)st.st_size);
            if (static_cast<uint64_t>(st.st_size) != VOLUME_SIZE) {
                LOGI("DEBUG-Ext: WARNING: Physical size does NOT match VOLUME_SIZE! Android SAF issue?");
            }
        } else {
            LOGI("DEBUG-Ext: fstat failed!");
        }

        const uint64_t DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);
        
        if (DATA_SIZE % 4096 != 0 || DATA_SIZE % 512 != 0) {
            LOGI("DEBUG-Ext: WARNING: DATA_SIZE is NOT aligned correctly!");
        }

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));

        body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
        body[4] = 0x00; body[5] = 0x02;
        body[6] = 0x01; body[7] = 0x0b;

        // Note: For standard (non-hidden) volumes, the official VeraCrypt spec 
        // dictates that VC_HDR_OFF_VOLUME_SIZE holds the size of the decrypted 
        // payload area (DATA_SIZE), NOT the total physical container file size.
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

        uint32_t keyCrc = crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_KEY_CRC]     = (keyCrc >> 24) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 1] = (keyCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 2] = (keyCrc >>  8) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 3] = (keyCrc      ) & 0xFF;

        uint32_t hdrCrc = crc32(body, VC_HDR_CRC_COVERAGE_LEN);
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
            // Header is encrypted as a single "sector 0" with zero tweak
            // We need to handle the 448-byte body (28 blocks of 16 bytes)
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
        memcpy(hdrSector,                  salt,    VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE,   encBody, VC_HEADER_BODY_SIZE);

        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: primary header write failed"); break;
        }
        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE,
                   static_cast<off_t>(VOLUME_SIZE - VC_DATA_AREA_OFFSET)) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: backup header write failed"); break;
        }
        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE,
                   static_cast<off_t>(VOLUME_SIZE - VC_DATA_AREA_OFFSET)) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: backup header write failed"); break;
        }

        // --- NEW FIX START ---
        // Android SAF ignores ftruncate(). Because the backup header is only 512 bytes, 
        // there is a 130,560 byte gap at the end of the file that never gets written to.
        // We MUST force the OS to expand the file to the exact requested VOLUME_SIZE 
        // by writing a single byte at the very end of the file (VOLUME_SIZE - 1).
        unsigned char eofByte = 0;
        if (pwrite(fd, &eofByte, 1, static_cast<off_t>(VOLUME_SIZE - 1)) != 1) {
            LOGI("createContainer: failed to expand file to full VOLUME_SIZE");
        } else {
            LOGI("DEBUG-Ext: Successfully forced physical file size to %llu", (unsigned long long)VOLUME_SIZE);
        }
        // --- NEW FIX END ---

        {
            CascadeContext dataCtx;
            if (!cascadeSetKeys(dataCtx, createCipher, combinedMasterKey, masterKeyLen)) {
                LOGI("createContainer: cascadeSetKeys failed for data");
                break;
            }

            const uint64_t START_SECTOR  = VC_DATA_AREA_OFFSET / 512;
            const uint64_t TOTAL_SECTORS = (VOLUME_SIZE - VC_DATA_AREA_OFFSET) / 512;

            const unsigned char ZERO_SECTOR[512] = {0};
            const size_t batchBufBytes = CREATE_FILL_BATCH * 512;
            std::unique_ptr<unsigned char[]> batch(new unsigned char[batchBufBytes]);
            bool writeOk = true;

            for (uint64_t s = START_SECTOR; s < TOTAL_SECTORS && writeOk; ) {
                const uint64_t rem   = TOTAL_SECTORS - s;
                const uint64_t count = (rem < CREATE_FILL_BATCH) ? rem : CREATE_FILL_BATCH;

                for (uint64_t i = 0; i < count; ++i) {
                    cascadeEncryptSector(dataCtx, s + i, ZERO_SECTOR,
                                        batch.get() + i * 512);
                }

                const ssize_t want = static_cast<ssize_t>(count * 512);
                if (pwrite(fd, batch.get(), want,
                           static_cast<off_t>(s * 512)) != want) {
                    LOGI("createContainer: data fill write failed at sector %llu",
                         (unsigned long long)s);
                    writeOk = false;
                }
                s += count;
            }
            if (!writeOk) break;
        }

        fsync(fd);

        // Format drive
        {
            std::lock_guard<std::mutex> vlock(v.mutex);

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
                // Prepare encryption context state
                v.partitionStartSector = 0;
                v.dataOffset = VC_DATA_AREA_OFFSET;
                v.dataAreaLengthBytes = DATA_SIZE;
                v.isUsbSource = false;
                
                // The keys were already set via cascadeSetKeys(v.cascade...) 
                // in the previous block.
                
                const bool formatted = formatExtVolume(volId, fileSystem);
                
                // Post-format cleanup
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
            mp.n_fat  = 1;
            mp.n_root = 512;
            mp.au_size = 0;
            mp.align   = 0;

            alignas(16) unsigned char mkfsBuf[MKFS_WORK_BUF_SIZE];
            FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf, sizeof(mkfsBuf));

            LOGI("createContainer: f_mkfs result=%d fmt=%d exfat=%d",
                 (int)fr, (int)mp.fmt, (int)useExFat);

            f_mount(nullptr, drivePaths[volId], 0);
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
        LOGI("createContainer: complete – %lld bytes, fs=%s",
             (long long)sizeBytes, fileSystem);

    } while (false);

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));

    if (success) {
        fsync(fd); // Final physical sync
        LOGI("createContainer: SUCCESS.");
    }
    close(fd);

    return success;
}