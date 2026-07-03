#include <jni.h>
#include <string>
#include <fstream>
#include <vector>
#include <android/log.h>
#include <iomanip>
#include <sstream>
#include <cstring>
#include <unistd.h>
#include <sys/stat.h>
#include <memory>
#include <algorithm>
#include <mutex>
#include <atomic>  // std::atomic<bool> derivationInProgress[] below relies on this directly,
                   // not on a transitive include from <mutex>/<memory>.
#include <ctime>   // mktime, struct tm, time_t

#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/aes.h"

#include "ff.h"
#include "diskio.h"
#include "crypto/cascade.h"
#include <thread>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

#define MAX_VOLUMES FF_VOLUMES

// ── VeraCrypt on-disk format constants ───────────────────────────────────────
//
// All offsets refer to the primary volume header at byte 0 of the container
// file. The backup header is a byte-for-byte copy stored at
// (volume_size - 131072). Spec ref: VeraCrypt source, Common/Volumes.h and
// Format/VolumeCreator.cpp.
//
//  VC_SALT_SIZE (64)
//      PKCS#5 salt occupying bytes [0, 63] of the header sector. Fed directly
//      to PBKDF2-SHA512 together with the user password.
//
//  VC_HEADER_BODY_SIZE (448)
//      The encrypted portion of the header, bytes [64, 511]. Decrypted with
//      AES-XTS using a key derived from PBKDF2 output at offset 0 of the key
//      material (the "header key"). After decryption the first four bytes
//      must equal ASCII "VERA" to confirm the correct password was used.
//
//  VC_FULL_HEADER_SIZE (512)
//      One full 512-byte sector: salt (64) + encrypted body (448).
//
//  VC_DATA_AREA_OFFSET (131072 = 256 × 512)
//      The data area begins 256 sectors into the file. The first 256 sectors
//      hold the primary header (sector 0) plus reserved/hidden-volume space.
//      The backup header occupies the last 256 sectors of the file.
//
//  VC_KEY_OFFSET_MASTER (192, body-relative == absolute header offset 256)
//      Byte offset inside the *decrypted* header body where the master key
//      material starts. Used directly as the AES-256-XTS key (32-byte data
//      key + 32-byte tweak key, concatenated = 64 bytes) for encrypting and
//      decrypting the actual volume contents.
//
//      This is the ONLY master-key position for a single-cipher (AES)
//      VeraCrypt volume. It's confirmed independently by the key-data CRC
//      field (VC_HDR_OFF_KEY_CRC): per spec that CRC covers absolute header
//      bytes 256–511, i.e. body[192..447] — 256 bytes starting exactly here.
//      (A previous revision of this code also tried a second candidate at
//      body offset 252, on the theory that "primary" and "secondary" keys
//      lived at different offsets. That offset isn't spec-defined — real
//      cascade-cipher key slots start at 192/256/320, and 252 doesn't land
//      on any of those boundaries. It was harmless only because unlock
//      always fell through to try 192 as well, which is the real position.)
//
//  VC_KEY_MATERIAL_LEN (64)
//      Length of the master key in bytes (512 bits, as required by
//      mbedtls_aes_xts_setkey_*). Only single-cipher AES-256-XTS volumes are
//      supported; cascaded ciphers (Serpent, Twofish, ...) would need
//      additional 64-byte keys at body offsets 256 and 320.
//
static constexpr size_t VC_SALT_SIZE            = 64;
static constexpr size_t VC_HEADER_BODY_SIZE     = 448;
static constexpr size_t VC_FULL_HEADER_SIZE     = 512;
static constexpr uint64_t VC_DATA_AREA_OFFSET   = 131072ULL;
static constexpr size_t IO_BUFFER_SIZE          = 262144;   // 256 KB
static constexpr int    VC_KEY_OFFSET_MASTER    = 192;
static constexpr int    VC_KEY_MATERIAL_LEN     = 64;
static constexpr size_t MAX_DIR_ENTRIES         = 50000;
static constexpr uint64_t SCAN_SECTORS          = 2048;
static constexpr uint64_t SCAN_BATCH            = 64;
static constexpr int    MKFS_WORK_BUF_SIZE      = 4096;
static constexpr size_t MAX_CHUNK_SIZE          = 64 * 1024 * 1024; // 64 MB safety cap
static constexpr uint64_t FALLBACK_SECTOR_COUNT_UNINITIALIZED = 1000000; // see disk_ioctl GET_SECTOR_COUNT

// Named positions of the remaining header fields written by
// createContainerNative(). All offsets are body-relative (body[0] ==
// absolute header byte 64, i.e. the first byte after the 64-byte salt).
static constexpr int VC_HDR_OFF_KEY_CRC          = 8;    // 4 bytes: CRC-32 of the key-data area
static constexpr int VC_HDR_OFF_VOLUME_SIZE      = 36;   // 8 bytes: total volume size
static constexpr int VC_HDR_OFF_KEY_SCOPE_START  = 44;   // 8 bytes: byte offset of encrypted data area
static constexpr int VC_HDR_OFF_KEY_SCOPE_SIZE   = 52;   // 8 bytes: size of encrypted data area
static constexpr int VC_HDR_OFF_SECTOR_SIZE      = 64;   // 4 bytes: sector size
static constexpr int VC_HDR_OFF_HEADER_CRC       = 188;  // 4 bytes: CRC-32 of body[0..187]
static constexpr int VC_HDR_CRC_COVERAGE_LEN     = 188;  // bytes [0,188) covered by the header CRC
static constexpr int VC_HDR_KEY_CRC_COVERAGE_LEN = 256;  // bytes [192,448) covered by the key-data CRC

// FIX P14: Use a much larger batch for container creation to reduce pwrite()
// syscall count. 4096 sectors = 2 MB per write vs 32 KB — 64× fewer syscalls
// for a 1 GB container (512 writes vs 32,768).
static constexpr uint64_t CREATE_FILL_BATCH     = 4096;

// FIX P12: Per-volume persistent IO buffer to avoid allocating a fresh heap
// buffer on every large disk_read/disk_write call (which FatFs can issue up to
// 4 MB at once during sequential file access). Now lives on VolumeState
// (see below) instead of as a standalone parallel array.
static constexpr size_t   IO_VOL_BUF_SECTORS    = 512;    // 256 KB per volume
static constexpr size_t   IO_VOL_BUF_SIZE       = IO_VOL_BUF_SECTORS * 512;

// ----------------------------------------------------------------====
// RAII WRAPPERS
// ----------------------------------------------------------------====

struct XtsContextPair {
    mbedtls_aes_xts_context dec;
    mbedtls_aes_xts_context enc;
    bool initialized = false;

    XtsContextPair() {
        mbedtls_aes_xts_init(&dec);
        mbedtls_aes_xts_init(&enc);
    }
    ~XtsContextPair() {
        mbedtls_aes_xts_free(&dec);
        mbedtls_aes_xts_free(&enc);
    }
    XtsContextPair(const XtsContextPair&) = delete;
    XtsContextPair& operator=(const XtsContextPair&) = delete;
};

struct MdContextGuard {
    mbedtls_md_context_t ctx;
    MdContextGuard() { mbedtls_md_init(&ctx); }
    ~MdContextGuard() { mbedtls_md_free(&ctx); }
};

// ----------------------------------------------------------------====
// PER-VOLUME STATE
//
// FIX: previously this was ~9 separate parallel arrays (activeFd[],
// activeDataOffset[], activeIsRelTweak[], isDataCtxInitialized[],
// activeFileSize[], fsMounted[], isUsbSource[], activePartitionStartSector[],
// plus the IO buffer and open-stream arrays), each indexed by volId. Every
// teardown site (lockNative, every failure branch in createContainerNative)
// had to manually reset 6–8 of them in the right order — a missed reset on
// a new exit path silently corrupts that volume's session. Collapsing them
// into one struct per volume makes "reset this volume" a single call and
// makes it structurally impossible to update one field's array but not
// another's.
// ----------------------------------------------------------------====

struct VolumeState {
    std::mutex mutex;
    int        fd = -1;
    uint64_t   dataOffset = 0;
    bool       relTweak = false;
    bool       dataCtxInitialized = false;
    uint64_t   fileSize = 0;
    bool       fsMounted = false;
    bool       isUsbSource = false;
    uint64_t   partitionStartSector = 0;

    // FIX (perf, fix #1): remembers which cipher/hash combo actually
    // unlocked this volume, so Kotlin can persist it and pass it back
    // as an explicit cipherId/hashId on the NEXT unlock of the same
    // container — collapsing the 5x8 auto-detect search space to
    // exactly one PBKDF2 run. -1 = unknown / not yet unlocked.
    int matchedCipherId = -1;
    int matchedHashId = -1;

    CascadeContext cascade;
    FATFS fatfs{};

    std::unique_ptr<unsigned char[]> ioBuf;
    size_t     ioBufSize = 0;
    std::mutex ioBufMutex;

    std::vector<FIL*> openStreams;

    VolumeState() {}
    ~VolumeState() {}
    VolumeState(const VolumeState&) = delete;
    VolumeState& operator=(const VolumeState&) = delete;

    void reset() {
        if (fd >= 0) close(fd);
        fd = -1;
        dataOffset = 0;
        relTweak = false;
        fileSize = 0;
        isUsbSource = false;
        partitionStartSector = 0;
        dataCtxInitialized = false;
        cascade.initialized = false;
        matchedCipherId = -1;
        matchedHashId = -1;
    }
};

static VolumeState volumes[MAX_VOLUMES];
static std::mutex  slotAllocMutex;

// ── USB backing-store support ────────────────────────────────────────────
//
// A volume's physical bytes come from one of two places:
//   - a container file's fd (existing path, pread/pwrite)
//   - a USB mass-storage device, reached only through a Kotlin upcall
//     (UsbBlockBridge.readSectors/writeSectors), since raw block-device
//     access on unrooted Android only exists via the USB Host API.
//
// volumes[volId].isUsbSource selects which path physRead/physWrite below use.
// volumes[volId].fd stays -1 for USB volumes; only isUsbSource matters.

static JavaVM*   g_vm             = nullptr;
static jclass    g_usbBridgeClass = nullptr;
static jmethodID g_usbReadMethod  = nullptr;  // static byte[]  readSectors(int, long, int)
static jmethodID g_usbWriteMethod = nullptr;  // static boolean writeSectors(int, long, int, byte[])

static bool isValidBootSector(const unsigned char* decS) {
    // End of sector signature must be 0x55AA
    if (decS[510] != 0x55 || decS[511] != 0xAA) {
        return false;
    }

    // Check for exFAT jump instruction (EB 76 90) and OEM name "EXFAT   "
    if (decS[0] == 0xEB && decS[1] == 0x76 && decS[2] == 0x90) {
        if (memcmp(&decS[3], "EXFAT   ", 8) == 0) {
            return true;
        }
    }

    // Check for FAT12/FAT16/FAT32 jump instruction (EB xx 90 or E9 xx xx)
    if (decS[0] == 0xEB || decS[0] == 0xE9) {
        // FAT/FAT32 volumes have a valid sector size of 512 bytes at offset 11
        // Safely read the little-endian 16-bit value byte-by-byte to prevent unaligned crashes on ARM
        uint16_t bytesPerSector = static_cast<uint16_t>(decS[11]) | (static_cast<uint16_t>(decS[12]) << 8);
        if (bytesPerSector == 512) {
            return true;
        }
    }

    return false;
}

extern "C" jint JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;

    jclass localClass = env->FindClass("com/aeidolon/vaultexplorer/UsbBlockBridge");
    if (!localClass) {
        LOGI("JNI_OnLoad: UsbBlockBridge class not found");
        return JNI_ERR;
    }
    g_usbBridgeClass = reinterpret_cast<jclass>(env->NewGlobalRef(localClass));
    env->DeleteLocalRef(localClass);

    g_usbReadMethod  = env->GetStaticMethodID(g_usbBridgeClass, "readSectors",  "(IJI)[B");
    g_usbWriteMethod = env->GetStaticMethodID(g_usbBridgeClass, "writeSectors", "(IJI[B)Z");
    if (!g_usbReadMethod || !g_usbWriteMethod) {
        LOGI("JNI_OnLoad: UsbBlockBridge methods not found");
        return JNI_ERR;
    }
    return JNI_VERSION_1_6;
}

// disk_read/disk_write can run on any thread FatFs happens to be driven
// from, not necessarily one already attached to the JVM. Attach on demand,
// detach only if we were the ones who attached.
struct ScopedJniEnv {
    JNIEnv* env = nullptr;
    bool attached = false;
    ScopedJniEnv() {
        if (!g_vm) return;
        if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) return;
        if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) attached = true;
        else env = nullptr;
    }
    ~ScopedJniEnv() { if (attached) g_vm->DetachCurrentThread(); }
};

static bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount, unsigned char* outBuf) {
    ScopedJniEnv scope;
    if (!scope.env) return false;
    JNIEnv* env = scope.env;

    jbyteArray result = static_cast<jbyteArray>(env->CallStaticObjectMethod(
        g_usbBridgeClass, g_usbReadMethod,
        static_cast<jint>(volId), static_cast<jlong>(startSector), static_cast<jint>(sectorCount)));

    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    if (!result) return false;

    const jsize len = env->GetArrayLength(result);
    const size_t expected = static_cast<size_t>(sectorCount) * 512;
    if (static_cast<size_t>(len) != expected) { env->DeleteLocalRef(result); return false; }

    env->GetByteArrayRegion(result, 0, len, reinterpret_cast<jbyte*>(outBuf));
    env->DeleteLocalRef(result);
    return true;
}

static bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount, const unsigned char* inBuf) {
    ScopedJniEnv scope;
    if (!scope.env) return false;
    JNIEnv* env = scope.env;

    const jsize len = static_cast<jsize>(static_cast<size_t>(sectorCount) * 512);
    jbyteArray data = env->NewByteArray(len);
    if (!data) return false;
    env->SetByteArrayRegion(data, 0, len, reinterpret_cast<const jbyte*>(inBuf));

    const jboolean ok = env->CallStaticBooleanMethod(
        g_usbBridgeClass, g_usbWriteMethod,
        static_cast<jint>(volId), static_cast<jlong>(startSector), static_cast<jint>(sectorCount), data);

    env->DeleteLocalRef(data);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    return ok == JNI_TRUE;
}

// Unified physical-IO dispatch used by disk_read/disk_write. [physByteOffset]
// and [totalBytes] must both be multiples of 512 (true for every call site
// in this file — sectors in, sectors out).
static bool physRead(int pdrv, uint64_t physByteOffset, unsigned char* buf, size_t totalBytes) {
    if (volumes[pdrv].isUsbSource) {
        return usbReadSectors(pdrv, physByteOffset / 512,
                               static_cast<uint32_t>(totalBytes / 512), buf);
    }
    const ssize_t got = pread(volumes[pdrv].fd, buf, totalBytes, static_cast<off_t>(physByteOffset));
    return got == static_cast<ssize_t>(totalBytes);
}

static bool physWrite(int pdrv, uint64_t physByteOffset, const unsigned char* buf, size_t totalBytes) {
    if (volumes[pdrv].isUsbSource) {
        return usbWriteSectors(pdrv, physByteOffset / 512,
                                static_cast<uint32_t>(totalBytes / 512), buf);
    }
    const ssize_t written = pwrite(volumes[pdrv].fd, buf, totalBytes, static_cast<off_t>(physByteOffset));
    return written == static_cast<ssize_t>(totalBytes);
}

static const char* drivePaths[MAX_VOLUMES] = {
    "0:", "1:", "2:", "3:", "4:", "5:", "6:", "7:"
};

// Returns true only if volId already has an active, unlocked session.
// Stateless natives (list/read/write/size/etc.) call this FIRST and bail
// with a clear log line instead of silently falling through into
// prepareSession's derivation path with an empty password.
static inline bool requireActiveSession(int volId, const char* callerName) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    auto& v = volumes[volId];
    std::lock_guard<std::mutex> lock(v.mutex);

    // Allow fd to be < 0 only if this is an active USB session
    if (!v.dataCtxInitialized || (v.fd < 0 && !v.isUsbSource)) {
        LOGI("%s: volume %d has no active session (not unlocked)", callerName, volId);
        return false;
    }
    return true;
}

// Throws a Kotlin-catchable IllegalStateException with a machine-readable
// reason code, then returns. Callers must `return` immediately after this —
// JNI does not unwind the C++ stack, it just marks a pending exception that
// fires when control returns to the JVM.
static void throwNotUnlocked(JNIEnv* env, int volId, const char* callerName) {
    jclass exClass = env->FindClass("java/lang/IllegalStateException");
    char msg[160];
    snprintf(msg, sizeof(msg), "NOT_UNLOCKED: volume %d has no active session (%s)",
             volId, callerName);
    env->ThrowNew(exClass, msg);
}

// ----------------------------------------------------------------====
// MOUNT CACHE HELPERS
// ----------------------------------------------------------------====

static bool ensureMounted(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    auto& v = volumes[volId];
    if (v.fsMounted) return true;

    FRESULT fr = f_mount(&v.fatfs, drivePaths[volId], 1);
    if (fr == FR_OK) {
        v.fsMounted = true;
        return true;
    }
    LOGI("ensureMounted: f_mount failed for volume %d, code=%d", volId, (int)fr);
    return false;
}

static void unmountVolume(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return;
    auto& v = volumes[volId];
    if (v.fsMounted) {
        f_mount(nullptr, drivePaths[volId], 0);
        v.fsMounted = false;
    }
    // Release persistent IO buffer when volume is locked.
    std::lock_guard<std::mutex> bufLock(v.ioBufMutex);
    v.ioBuf.reset();
    v.ioBufSize = 0;
}

// ----------------------------------------------------------------====
// INLINE HELPERS
// ----------------------------------------------------------------====

// FIX P13: Fast check before paying the full replace_if scan cost.
// The vast majority of filenames from FAT filesystems are clean ASCII —
// checking first avoids a full byte scan on every directory entry.
static inline bool hasControlChar(const std::string& s) {
    for (unsigned char c : s) {
        if (c < 32 || c == 127) return true;
    }
    return false;
}

static void sanitizeString(std::string& s) {
    if (!hasControlChar(s)) return;   // FIX P13: skip replace_if when clean
    std::replace_if(s.begin(), s.end(),
        [](unsigned char c){ return c < 32 || c == 127; }, '?');
}

static inline void setTweak(unsigned char* tweak, uint64_t sectorNum) {
    *reinterpret_cast<uint64_t*>(tweak)   = sectorNum;
    *reinterpret_cast<uint64_t*>(tweak+8) = 0ULL;
}

static inline int clampPim(int pim) {
    if (pim < 0) return 0;
    if (pim > 2000) return 2000;
    return pim;
}

struct PartitionCandidate {
    uint64_t startSector;
    uint64_t sectorCount;
};

static uint32_t readUint32LE(const unsigned char* p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

static uint64_t readUint64LE(const unsigned char* p) {
    return static_cast<uint64_t>(p[0]) |
           (static_cast<uint64_t>(p[1]) << 8) |
           (static_cast<uint64_t>(p[2]) << 16) |
           (static_cast<uint64_t>(p[3]) << 24) |
           (static_cast<uint64_t>(p[4]) << 32) |
           (static_cast<uint64_t>(p[5]) << 40) |
           (static_cast<uint64_t>(p[6]) << 48) |
           (static_cast<uint64_t>(p[7]) << 56);
}

// ── FAT date/time → Unix timestamp ─────────────────────────────────────────

static uint64_t fatToUnixTimestamp(WORD fdate, WORD ftime) {
    // FatFs stores dates as FAT-epoch (1980-01-01).
    // fdate: bits[15:9]=year-1980  bits[8:5]=month  bits[4:0]=day
    // ftime: bits[15:11]=hour  bits[10:5]=minute  bits[4:0]=second/2
    if (fdate == 0) return 0; // no RTC data (FF_FS_NORTC=1 new files)
    struct tm t = {};
    t.tm_year  = ((fdate >> 9) & 0x7F) + 80; // FAT epoch 1980, tm epoch 1900
    t.tm_mon   = ((fdate >> 5) & 0x0F) - 1;  // FAT 1-12  →  tm 0-11
    t.tm_mday  =  (fdate)       & 0x1F;
    t.tm_hour  = (ftime >> 11)  & 0x1F;
    t.tm_min   = (ftime >>  5)  & 0x3F;
    t.tm_sec   = (ftime  & 0x1F) * 2;
    t.tm_isdst = -1;
    const time_t ts = mktime(&t);
    return (ts < 0) ? 0 : static_cast<uint64_t>(ts);
}

// ----------------------------------------------------------------====
// CRC-32 (standard IEEE 802.3 polynomial, reflected).
//
// FIX: previously an unnamed lambda declared locally inside
// createContainerNative(), used only when writing the header CRCs and
// never called anywhere else — meaning the CRCs it wrote were never
// actually verified at unlock time. Now a single named, file-scope
// function shared by createContainerNative() (write path) and
// deriveAndValidateHeader() (read/verify path), so there's exactly one
// implementation for both directions.
// ----------------------------------------------------------------====
static uint32_t crc32(const unsigned char* data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b)
            crc = (crc >> 1) ^ (0xEDB88320u & ~((crc & 1) - 1));
    }
    return crc ^ 0xFFFFFFFFu;
}

// (Old encryptSector/decryptSector helpers removed — replaced by
// cascadeEncryptSector/cascadeDecryptSector in cascade.cpp.)

// ----------------------------------------------------------------====
// FIX P12: Per-volume IO buffer accessor
// Returns a pointer to a buffer of at least `neededBytes` for `v`.
// The buffer is allocated once and grown if needed; never shrunk during an
// active session (it IS released entirely on lock, via unmountVolume()).
// This is bounded and intentional, not a leak: disk_read/disk_write cap a
// single batch at MAX_SECTORS_PER_BATCH (8192 sectors = 4MB), so this
// buffer never exceeds 4MB per volume regardless of how much I/O flows
// through it — shrinking mid-session would just cause repeated realloc
// churn on the next large read for no real memory benefit.
// MUST be called with v.ioBufMutex held.
// ----------------------------------------------------------------====
static unsigned char* getVolIoBuf(VolumeState& v, size_t neededBytes) {
    if (v.ioBufSize < neededBytes) {
        v.ioBuf.reset(new unsigned char[neededBytes]);
        v.ioBufSize = neededBytes;
    }
    return v.ioBuf.get();
}

// ----------------------------------------------------------------====
// FATFS LOW-LEVEL DISK HOOKS
// ----------------------------------------------------------------====

extern "C" DSTATUS disk_initialize(BYTE pdrv) { return 0; }
extern "C" DSTATUS disk_status(BYTE pdrv)     { return 0; }

extern "C" DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !volumes[pdrv].dataCtxInitialized)
        return RES_NOTRDY;
    if (!volumes[pdrv].isUsbSource && volumes[pdrv].fd < 0)
        return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    VolumeState& v = volumes[pdrv];
    const uint64_t basePhysical = v.dataOffset / 512;
    const bool relTweak = v.relTweak;

    static constexpr UINT MAX_SECTORS_PER_BATCH = 8192; // 4 MB/batch — unchanged tuning, no longer a hard limit
    UINT remaining   = count;
    LBA_t curSector  = sector;
    BYTE* curBuf     = buff;

    alignas(16) unsigned char stackBuf[65536];

    // FIX: previously this loop duplicated the pread+decrypt body once for
    // the "fits on the stack" case and again (with an early `continue`) for
    // the "needs the persistent volume buffer" case. Two copies of the same
    // logic is exactly the trap the tryKeyCandidate() comment above warns
    // about elsewhere in this file — easy to silently diverge on a future
    // edit. disk_write() already uses the single-path form below; mirror it
    // here so both hooks share one code path.
    while (remaining > 0) {
        const UINT batchCount = std::min(remaining, MAX_SECTORS_PER_BATCH);
        const uint64_t firstPhysical = basePhysical + curSector;
        const size_t   totalBytes    = static_cast<size_t>(batchCount) * 512;

        unsigned char* encBuf;
        bool usedPersistent = (totalBytes > sizeof(stackBuf));

        std::unique_lock<std::mutex> bufLock;
        if (usedPersistent) {
            bufLock = std::unique_lock<std::mutex>(v.ioBufMutex);
            encBuf = getVolIoBuf(v, totalBytes);
        } else {
            encBuf = stackBuf;
        }

        if (!physRead(pdrv, firstPhysical * 512, encBuf, totalBytes)) return RES_ERROR;

        for (UINT i = 0; i < batchCount; i++) {
            const uint64_t physSector = firstPhysical + i;
            const uint64_t sectorInPartition = physSector - v.partitionStartSector;
            const uint64_t tweak = relTweak ? (physSector - basePhysical) : sectorInPartition;
            cascadeDecryptSector(v.cascade, tweak, encBuf + (i*512), curBuf + (i*512));
        }

        remaining -= batchCount;
        curSector += batchCount;
        curBuf    += batchCount * 512;
    }
    return RES_OK;
}

extern "C" DRESULT disk_write(BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !volumes[pdrv].dataCtxInitialized)
        return RES_NOTRDY;
    if (!volumes[pdrv].isUsbSource && volumes[pdrv].fd < 0)
        return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    VolumeState& v = volumes[pdrv];
    const uint64_t basePhysical = v.dataOffset / 512;
    const bool     relTweak     = v.relTweak;

    static constexpr UINT MAX_SECTORS_PER_BATCH = 8192;
    UINT remaining        = count;
    LBA_t curSector       = sector;
    const BYTE* curBuf    = buff;

    alignas(16) unsigned char stackBuf[65536];

    while (remaining > 0) {
        const UINT batchCount = std::min(remaining, MAX_SECTORS_PER_BATCH);
        const uint64_t firstPhysical = basePhysical + curSector;
        const size_t   totalBytes    = static_cast<size_t>(batchCount) * 512;

        unsigned char* encBuf;
        bool usedPersistent = false;
        if (totalBytes <= sizeof(stackBuf)) {
            encBuf = stackBuf;
        } else {
            usedPersistent = true;
        }

        std::unique_lock<std::mutex> bufLock;
        if (usedPersistent) {
            bufLock = std::unique_lock<std::mutex>(v.ioBufMutex);
            encBuf = getVolIoBuf(v, totalBytes);
        }

        for (UINT i = 0; i < batchCount; i++) {
            const uint64_t physSector = firstPhysical + i;
            const uint64_t sectorInPartition = physSector - v.partitionStartSector;
            const uint64_t tweak = relTweak ? (physSector - basePhysical) : sectorInPartition;
            cascadeEncryptSector(v.cascade, tweak,
                          curBuf + (i * 512), encBuf + (i * 512));
        }

        if (!physWrite(pdrv, firstPhysical * 512, encBuf, totalBytes)) return RES_ERROR;

        remaining -= batchCount;
        curSector += batchCount;
        curBuf    += batchCount * 512;
    }
    return RES_OK;
}

extern "C" DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void* buff) {
    switch (cmd) {
        case CTRL_SYNC:
            return RES_OK;

        case GET_SECTOR_COUNT:
            if (pdrv < MAX_VOLUMES && volumes[pdrv].fileSize > VC_DATA_AREA_OFFSET * 2) {
                *(LBA_t*)buff = static_cast<LBA_t>(
                    (volumes[pdrv].fileSize - VC_DATA_AREA_OFFSET * 2) / 512);
            } else {
                *(LBA_t*)buff = FALLBACK_SECTOR_COUNT_UNINITIALIZED;
            }
            return RES_OK;

        case GET_SECTOR_SIZE:
            *(WORD*)buff  = 512;
            return RES_OK;

        case GET_BLOCK_SIZE:
            *(DWORD*)buff = 1;
            return RES_OK;
    }
    return RES_PARERR;
}

extern "C" DWORD get_fattime() {
    time_t now = time(nullptr);
    struct tm t{};
    localtime_r(&now, &t);

    WORD fdate = static_cast<WORD>(
        (((t.tm_year + 1900 - 1980) & 0x7F) << 9) |
        (((t.tm_mon + 1)            & 0x0F) << 5) |
        ( t.tm_mday                 & 0x1F));

    WORD ftime = static_cast<WORD>(
        ((t.tm_hour & 0x1F) << 11) |
        ((t.tm_min  & 0x3F) << 5)  |
        ((t.tm_sec / 2) & 0x1F));

    return (static_cast<DWORD>(fdate) << 16) | ftime;
}

// ----------------------------------------------------------------====
// CRYPTO SESSION BUILDER
//
// FIX P11: PBKDF2 runs for ~2 s (500k iterations). The original code held
// volumeMutex for the entire derivation, blocking ALL reads/writes on that
// volume slot while the key was being computed.
//
// The fix: derive the key with NO lock held, then acquire the mutex only for
// the brief header-decrypt + context-swap phase (~microseconds). A secondary
// "derivation in progress" atomic flag prevents two threads from deriving
// simultaneously for the same volume without blocking readers.
// ----------------------------------------------------------------====

static std::atomic<bool> derivationInProgress[MAX_VOLUMES];

static bool _derivationInit = [](){
    for (int i = 0; i < MAX_VOLUMES; i++)
        derivationInProgress[i].store(false);
    return true;
}();

// Result of trying one candidate key against the early sectors of the
// container, searching for a valid FAT/exFAT boot-sector signature (0x55AA)
// under either tweak convention (absolute physical sector vs. relative to
// the data-area start). VeraCrypt volumes can use either depending on
// version/format, so both must be tried per candidate key.
struct FsScanResult {
    bool found = false;
    uint64_t dataOffset = 0;
    bool relTweak = false;
};

// ----------------------------------------------------------------====
// FIX: previously the PBKDF2-derive + header-decrypt + magic-byte-check
// block below was duplicated near-verbatim inside both prepareSession()
// (container-file backed) and prepareUsbSession() (USB block-device
// backed) — ~40 lines each, differing only in how the raw header sector
// was obtained. A crypto fix applied to one path (e.g. adding the CRC
// checks below) was trivially easy to forget in the other.
//
// This function is now the single implementation both call. It also adds
// verification of both header CRCs, which the previous code computed and
// wrote on create but never checked on unlock — password correctness was
// previously inferred solely from the "VERA" magic bytes matching, which
// works but is weaker than the validation VeraCrypt's own format provides
// for free.
//
// Deliberately takes no volId/globals as input — a pure function of the
// header bytes, password, and pim — so it has no dependency on JNI or any
// of the VolumeState machinery.
// ----------------------------------------------------------------====
static void localMultiplyTweak(unsigned char T[16]) {
    unsigned char carry = 0;
    for (int i = 0; i < 16; i++) {
        unsigned char nextCarry = (T[i] & 0x80) ? 1 : 0;
        T[i] = (T[i] << 1) | carry;
        carry = nextCarry;
    }
    if (carry) {
        T[0] ^= 0x87;
    }
}

static bool tryDecryptHeader(
    const unsigned char encH[VC_HEADER_BODY_SIZE],
    CascadeId cipherId,
    const unsigned char* derivedKeyMaterial,
    unsigned char decH[VC_HEADER_BODY_SIZE]
) {
    CascadeContext tempCtx;
    CascadeSpec spec = cascadeSpecFor(cipherId);
    if (!cascadeSetKeys(tempCtx, cipherId, derivedKeyMaterial, spec.layerCount * 64)) {
        return false;
    }

    std::memcpy(decH, encH, VC_HEADER_BODY_SIZE);

    for (int i = spec.layerCount - 1; i >= 0; i--) {
        const XtsLayerKey& layer = tempCtx.layers[i];
        unsigned char T[16] = {0};
        blockCipherEncryptBlock(layer.tweakKey, T, T);

        for (int block = 0; block < 28; block++) {
            unsigned char* blockPtr = decH + block * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = blockPtr[j] ^ T[j];
            blockCipherDecryptBlock(layer.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) blockPtr[j] = tmp[j] ^ T[j];

            localMultiplyTweak(T);
        }
    }

    if (decH[0] != 'V' || decH[1] != 'E' || decH[2] != 'R' || decH[3] != 'A') {
        return false;
    }

    auto readBE32 = [&decH](int off) -> uint32_t {
        return (static_cast<uint32_t>(decH[off])     << 24) |
               (static_cast<uint32_t>(decH[off + 1]) << 16) |
               (static_cast<uint32_t>(decH[off + 2]) <<  8) |
                static_cast<uint32_t>(decH[off + 3]);
    };

    const uint32_t computedHdrCrc = crc32(decH, VC_HDR_CRC_COVERAGE_LEN);
    const uint32_t storedHdrCrc   = readBE32(VC_HDR_OFF_HEADER_CRC);
    if (computedHdrCrc != storedHdrCrc) {
        return false;
    }

    const uint32_t computedKeyCrc = crc32(&decH[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
    const uint32_t storedKeyCrc = readBE32(VC_HDR_OFF_KEY_CRC);
    if (computedKeyCrc != storedKeyCrc) {
        return false;
    }

    return true;
}

static bool deriveAndValidateHeader(
    const unsigned char headerSector[VC_FULL_HEADER_SIZE],
    const char* password, int pim,
    int cipherIdParam, int hashIdParam,
    unsigned char outKeyMaterial[192],
    CascadeId& outMatchedCipher,
    HashId& outMatchedHash
) {
    const unsigned char* salt = headerSector;
    const unsigned char* encH = headerSector + VC_SALT_SIZE;

    const int safePim = clampPim(pim);

    // FIX (perf): AES + SHA-512 is VeraCrypt's default combo and covers the
    // large majority of real-world containers. Try it once, serially, before
    // falling back to the full parallel multi-hash search — this avoids
    // paying for thread spawn + N-way KDF CPU/thermal contention in the
    // common case, and is strictly cheaper than the parallel path whenever
    // it succeeds. Only applies to true auto-detect (both unknown); if the
    // caller already narrowed one axis (e.g. remembered hashId but not
    // cipherId), the search space is already small enough that this
    // fast path wouldn't save anything meaningful.
    if (cipherIdParam == 255 && hashIdParam == 255) {
        const int fastIter = iterationsForHash(HashId::kSha512, safePim);
        unsigned char fastKey[192];
        if (pbkdf2Hmac(HashId::kSha512,
                        reinterpret_cast<const unsigned char*>(password), strlen(password),
                        salt, VC_SALT_SIZE, fastIter, fastKey, 192)) {
            unsigned char decH[VC_HEADER_BODY_SIZE];
            if (tryDecryptHeader(encH, CascadeId::kAes, fastKey, decH)) {
                std::memcpy(outKeyMaterial, &decH[VC_KEY_OFFSET_MASTER], 64);
                outMatchedCipher = CascadeId::kAes;
                outMatchedHash   = HashId::kSha512;
                mbedtls_platform_zeroize(decH, sizeof(decH));
                mbedtls_platform_zeroize(fastKey, sizeof(fastKey));
                return true;
            }
            mbedtls_platform_zeroize(decH, sizeof(decH));
        }
        mbedtls_platform_zeroize(fastKey, sizeof(fastKey));
        // Not AES/SHA-512 — fall through to the full parallel search below.
    }

    std::vector<HashId> hashesToTry;
    // ... rest unchanged ...
    if (hashIdParam != 255) {
        hashesToTry.push_back(static_cast<HashId>(hashIdParam));
    } else {
        hashesToTry = { HashId::kSha512, HashId::kSha256, HashId::kWhirlpool, HashId::kStreebog, HashId::kBlake2s256 };
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
            CascadeId::kSerpentTwofishAes
        };
    }

    // FIX (perf): the 5 (or fewer) PBKDF2 derivations below are fully
    // independent of each other — they share no state until a candidate
    // matches. Previously they ran serially, so an auto-detect unlock paid
    // for 5x the PBKDF2 cost even though only one hash is ever correct.
    // Run one worker thread per candidate hash; each worker tries its own
    // derived key against every candidate cipher (cipher trials are cheap —
    // one XTS header-block decrypt each — so those stay serial inside the
    // worker). First worker to find a valid header wins; others notice via
    // the `found` flag and stop starting new expensive work, but we still
    // join all threads before returning so no dangling work continues after
    // this function returns (mbedtls contexts are stack-local per thread).
    std::atomic<bool> found{false};
    std::mutex resultMutex;
    unsigned char resultKeyMaterial[192];
    CascadeId resultCipher{};
    HashId resultHash{};

    auto worker = [&](HashId h) {
        if (found.load(std::memory_order_acquire)) return;

        int iter = iterationsForHash(h, safePim);
        unsigned char derivedKeyMaterial[192];
        if (!pbkdf2Hmac(h, reinterpret_cast<const unsigned char*>(password), strlen(password),
                       salt, VC_SALT_SIZE, iter, derivedKeyMaterial, 192)) {
            return;
        }

        if (found.load(std::memory_order_acquire)) {
            mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
            return;
        }

        unsigned char decH[VC_HEADER_BODY_SIZE];
        for (CascadeId c : ciphersToTry) {
            if (found.load(std::memory_order_acquire)) break;
            if (tryDecryptHeader(encH, c, derivedKeyMaterial, decH)) {
                bool expected = false;
                if (found.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
                    std::lock_guard<std::mutex> lock(resultMutex);
                    CascadeSpec spec = cascadeSpecFor(c);
                    std::memcpy(resultKeyMaterial, &decH[VC_KEY_OFFSET_MASTER], spec.layerCount * 64);
                    resultCipher = c;
                    resultHash = h;
                }
                mbedtls_platform_zeroize(decH, sizeof(decH));
                mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
                return;
            }
        }
        mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
    };

    if (hashesToTry.size() <= 1) {
        // Single explicit hash (the common re-unlock case, see fix #1) —
        // no thread overhead needed.
        worker(hashesToTry[0]);
    } else {
        std::vector<std::thread> threads;
        threads.reserve(hashesToTry.size());
        for (HashId h : hashesToTry) threads.emplace_back(worker, h);
        for (auto& t : threads) t.join();
    }

    if (!found.load(std::memory_order_acquire)) {
        return false;
    }

    std::memcpy(outKeyMaterial, resultKeyMaterial, sizeof(resultKeyMaterial));
    outMatchedCipher = resultCipher;
    outMatchedHash = resultHash;
    mbedtls_platform_zeroize(resultKeyMaterial, sizeof(resultKeyMaterial));
    return true;
}

static FsScanResult tryKeyCandidate(
    int fd,
    const CascadeContext& candidateCascade
) {
    FsScanResult result;
    std::unique_ptr<unsigned char[]> encBatch(new unsigned char[SCAN_BATCH * 512]);
    unsigned char decS[512];

    uint64_t s = 0;
    while (s < SCAN_SECTORS) {
        const uint64_t batchCount = std::min(SCAN_BATCH, SCAN_SECTORS - s);
        const ssize_t  batchBytes = static_cast<ssize_t>(batchCount * 512);

        if (pread(fd, encBatch.get(), batchBytes,
                  static_cast<off_t>(s * 512)) != batchBytes) {
            break;
        }

        for (uint64_t i = 0; i < batchCount; i++) {
            const uint64_t sectorIdx = s + i;
            const unsigned char* enc = encBatch.get() + (i * 512);

            cascadeDecryptSector(candidateCascade, sectorIdx, enc, decS);
            if (isValidBootSector(decS)) {
                result.found      = true;
                result.dataOffset = sectorIdx * 512;
                result.relTweak   = false;
                return result;
            }

            cascadeDecryptSector(candidateCascade, 0, enc, decS);
            if (isValidBootSector(decS)) {
                result.found      = true;
                result.dataOffset = sectorIdx * 512;
                result.relTweak   = true;
                return result;
            }
        }
        s += batchCount;
    }
    return result; // found == false
}


// ----------------------------------------------------------------====
// LOCK DOMAIN CONTRACT (read before touching prepareSession/disk_read/disk_write)
//
// There are TWO independent lock domains protecting volume state, and they
// are NOT composable — neither one alone is sufficient:
//
//   1. Kotlin: `synchronized(VeraCryptSession.locks[volId])`
//      Serializes JNI *call entry* per volume from the Kotlin side. Ensures
//      two Kotlin threads never call into native for the same volId at once.
//
//   2. C++: `volumes[volId].mutex`
//      Protects the per-volume state (fd, dataCtxDec/Enc, dataCtxInitialized,
//      dataOffset, ...) directly.
//
// prepareSession() DELIBERATELY derives the PBKDF2 key (the slow ~2s step)
// WITHOUT holding volumes[volId].mutex (see FIX P11) so that disk_read/disk_write
// on an *already-unlocked* volume aren't blocked by a concurrent unlock of
// that SAME volume. This is safe only because:
//   - disk_read/disk_write require volumes[pdrv].dataCtxInitialized == true,
//     which is set exclusively inside the mutex-guarded block at the
//     end of prepareSession — so a reader either sees the fully-swapped
//     context or the previous one, never a half-written one.
//   - The Kotlin-side `locks[volId]` still prevents two *unlock* calls (the
//     only callers that pass forceDerive=true) from racing each other for
//     the same volId, via derivationInProgress[] as a secondary guard.
//
// DO NOT remove the Kotlin `synchronized(VeraCryptSession.locks[volId])`
// wrapper believing the C++ mutex already covers it — they guard different
// invariants (call ordering vs. memory state), and the safety argument above
// depends on both being present.
// ----------------------------------------------------------------====
bool prepareSession(int fd, const char* password, int pim, int volId, bool forceDerive, int cipherId, int hashId) {
    if (volId < 0 || volId >= MAX_VOLUMES) {
        if (fd >= 0) close(fd);
        return false;
    }
    VolumeState& v = volumes[volId];

    // Fast path: session already established, no derivation needed.
    if (!forceDerive) {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.dataCtxInitialized && v.fd >= 0) {
            if (fd >= 0) close(fd);
            return true;
        }
        if (v.dataCtxInitialized) {
            if (fd >= 0) {
                struct stat st;
                if (fstat(fd, &st) == 0)
                    v.fileSize = static_cast<uint64_t>(st.st_size);
                v.fd = fd;
                return true;
            }
            return false;
        }
    }

    if (fd < 0) return false;

    // FIX P11: Prevent two threads from deriving simultaneously for the same
    // volume (e.g., rapid double-tap unlock). Second thread waits via spinlock.
    bool expected = false;
    while (!derivationInProgress[volId].compare_exchange_weak(
               expected, true, std::memory_order_acquire)) {
        expected = false;
        // Re-check: the first thread may have finished by now.
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.dataCtxInitialized) {
            if (fd >= 0) close(fd);
            derivationInProgress[volId].store(false, std::memory_order_release);
            return true;
        }
    }

    LOGI("Running PBKDF2 Key Derivation for Volume %d (mutex NOT held)...", volId);

    // --- Read header WITHOUT holding the volume mutex ---
    unsigned char headerBuf[VC_FULL_HEADER_SIZE];
    if (pread(fd, headerBuf, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
        close(fd);
        derivationInProgress[volId].store(false, std::memory_order_release);
        return false;
    }

    uint64_t fileSize = 0;
    {
        struct stat st;
        if (fstat(fd, &st) == 0)
            fileSize = static_cast<uint64_t>(st.st_size);
    }

    unsigned char dKey[192];
    CascadeId matchedCipher;
    HashId matchedHash;
    if (!deriveAndValidateHeader(headerBuf, password, pim, cipherId, hashId, dKey, matchedCipher, matchedHash)) {
        close(fd);
        derivationInProgress[volId].store(false, std::memory_order_release);
        return false;
    }

    CascadeContext candidateCascade;
    CascadeSpec spec = cascadeSpecFor(matchedCipher);
    if (!cascadeSetKeys(candidateCascade, matchedCipher, dKey, spec.layerCount * 64)) {
        mbedtls_platform_zeroize(dKey, sizeof(dKey));
        close(fd);
        derivationInProgress[volId].store(false, std::memory_order_release);
        return false;
    }
    mbedtls_platform_zeroize(dKey, sizeof(dKey));

    FsScanResult scan = tryKeyCandidate(fd, candidateCascade);
    if (!scan.found) {
        close(fd);
        derivationInProgress[volId].store(false, std::memory_order_release);
        return false;
    }

    // FIX P11: Now acquire the mutex ONLY for the brief context swap.
    // All the slow crypto work is already done above.
    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.cascade            = candidateCascade;
        v.dataCtxInitialized = true;
        v.fd                 = fd;
        v.dataOffset         = scan.dataOffset;
        v.relTweak           = scan.relTweak;
        v.fileSize           = fileSize;
        v.matchedCipherId    = static_cast<int>(matchedCipher);
        v.matchedHashId      = static_cast<int>(matchedHash);
    }

    derivationInProgress[volId].store(false, std::memory_order_release);
    return true;
}


// USB-backed equivalent of tryKeyCandidate(): scans via the USB upcall
// instead of pread on a container fd. Kept as a separate function rather
// than parameterizing the fd-based version above, since the two read paths
// (pread vs JNI upcall) are different enough that folding them into one
// function would make the already-delicate unlock flow harder to reason
// about, not easier.
static FsScanResult tryKeyCandidateUsb(int volId, uint64_t partitionStartSector, const CascadeContext& candidateCascade) {
    FsScanResult result;
    std::unique_ptr<unsigned char[]> encBatch(new unsigned char[SCAN_BATCH * 512]);
    unsigned char decS[512];

    uint64_t s = 0;
    while (s < SCAN_SECTORS) {
        const uint64_t batchCount = std::min(SCAN_BATCH, SCAN_SECTORS - s);
        if (!usbReadSectors(volId, partitionStartSector + s, static_cast<uint32_t>(batchCount), encBatch.get())) break;

        for (uint64_t i = 0; i < batchCount; i++) {
            const uint64_t sectorIdx = s + i;
            const unsigned char* enc = encBatch.get() + (i * 512);

            cascadeDecryptSector(candidateCascade, sectorIdx, enc, decS);
            if (isValidBootSector(decS)) {
                result.found = true; 
                result.dataOffset = (partitionStartSector + sectorIdx) * 512;
                result.relTweak = false;
                return result;
            }

            cascadeDecryptSector(candidateCascade, 0, enc, decS);
            if (isValidBootSector(decS)) {
                result.found = true; 
                result.dataOffset = (partitionStartSector + sectorIdx) * 512;
                result.relTweak = true;
                return result;
            }
        }
        s += batchCount;
    }
    return result; // found == false
}

static bool prepareUsbSession(const char* password, int pim, int volId, int cipherId, int hashId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    VolumeState& v = volumes[volId];

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

    bool fsFound = false;
    uint64_t foundDataOffset = 0;
    bool foundRelTweak = false;
    CascadeContext candidateCascade;
    uint64_t matchedPartitionStart = 0;
    CascadeId matchedCipherFound{};
    HashId matchedHashFound{};

    for (const auto& part : partitions) {
        unsigned char headerBuf[VC_FULL_HEADER_SIZE];
        if (!usbReadSectors(volId, part.startSector, 1, headerBuf)) {
            continue;
        }

        unsigned char dKey[192];
        CascadeId matchedCipher;
        HashId matchedHash;
        if (!deriveAndValidateHeader(headerBuf, password, pim, cipherId, hashId, dKey, matchedCipher, matchedHash)) {
            continue;
        }

        CascadeSpec spec = cascadeSpecFor(matchedCipher);
        if (!cascadeSetKeys(candidateCascade, matchedCipher, dKey, spec.layerCount * 64)) {
            mbedtls_platform_zeroize(dKey, sizeof(dKey));
            continue;
        }

        FsScanResult scan = tryKeyCandidateUsb(volId, part.startSector, candidateCascade);
        if (scan.found) {
            fsFound = true;
            foundDataOffset = scan.dataOffset;
            foundRelTweak = scan.relTweak;
            matchedPartitionStart = part.startSector;
            matchedCipherFound = matchedCipher;
            matchedHashFound = matchedHash;
            mbedtls_platform_zeroize(dKey, sizeof(dKey));
            break;
        }
        mbedtls_platform_zeroize(dKey, sizeof(dKey));
    }

    if (!fsFound) {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.cascade = candidateCascade;
        v.isUsbSource          = true;
        v.dataCtxInitialized   = true;
        v.fd                   = -1;
        v.dataOffset           = foundDataOffset;
        v.relTweak             = foundRelTweak;
        v.partitionStartSector = matchedPartitionStart;
        v.matchedCipherId      = static_cast<int>(matchedCipherFound);
        v.matchedHashId        = static_cast<int>(matchedHashFound);
    }
    return true;
}
// ----------------------------------------------------------------====
// SHARED: Directory listing
// ----------------------------------------------------------------====

// Returns the total byte size of all files under [fatPath] (recursive).
// Called from getFolderSizeNative; also usable for progress reporting later.
static uint64_t recursiveFolderSize(int volId, const std::string& fatPath) {
    std::string fullPath = drivePaths[volId];
    if (!fatPath.empty()) { fullPath += '/'; fullPath += fatPath; }

    uint64_t total = 0;
    DIR dir; FILINFO fno;
    if (f_opendir(&dir, fullPath.c_str()) == FR_OK) {
        while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
            if (fno.fattrib & AM_DIR) {
                const std::string child = fatPath.empty()
                    ? std::string(fno.fname)
                    : fatPath + '/' + fno.fname;
                total += recursiveFolderSize(volId, child);
            } else {
                total += fno.fsize;
            }
        }
        f_closedir(&dir);
    }
    return total;
}

static jobjectArray buildDirectoryListing(JNIEnv* env, int volId, const char* pathSuffix) {
    std::vector<std::string> results;
    std::string fullPath = drivePaths[volId];
    if (pathSuffix && pathSuffix[0] != '\0') {
        fullPath += '/';
        fullPath += pathSuffix;
    }

    DIR dir;
    FILINFO fno;
    if (f_opendir(&dir, fullPath.c_str()) == FR_OK) {
        while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
            if (results.size() >= MAX_DIR_ENTRIES) {
                results.push_back("System:TRUNCATED");
                LOGI("buildDirectoryListing: truncated at %zu entries", MAX_DIR_ENTRIES);
                break;
            }
            const char* name = fno.fname;
            if (strcmp(name, "SYSTEM~1") == 0 || strcmp(name, "$RECYCLE.BIN") == 0)
                continue;

            const uint64_t ts = fatToUnixTimestamp(fno.fdate, fno.ftime);
            if (fno.fattrib & AM_DIR) {
                std::string entry = "[DIR] ";
                entry += name;
                entry += "|0|";
                entry += std::to_string(ts);
                results.push_back(std::move(entry));
            } else {
                std::string entry = name;
                entry += '|';
                entry += std::to_string(fno.fsize);
                entry += '|';
                entry += std::to_string(ts);
                results.push_back(std::move(entry));
            }
        }
        f_closedir(&dir);
    }

    jclass strClass = env->FindClass("java/lang/String");
    jobjectArray retArr = env->NewObjectArray(
        static_cast<jsize>(results.size()), strClass, nullptr);
    for (size_t i = 0; i < results.size(); i++) {
        sanitizeString(results[i]);
        jstring js = env->NewStringUTF(results[i].c_str());
        env->SetObjectArrayElement(retArr, i, js);
        env->DeleteLocalRef(js);
    }
    return retArr;
}

// ----------------------------------------------------------------====
// JNI API
// ----------------------------------------------------------------====

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMaxVolumesNative(JNIEnv*, jobject) {
    // FIX: previously MAX_VOLUMES had to be manually kept in sync across
    // THREE places — FF_VOLUMES in ffconf.h, the MAX_VOLUMES macro here
    // (which does derive from FF_VOLUMES already), and a hardcoded literal
    // in Kotlin's VeraCryptSession.MAX_VOLUMES. Exposing the real value via
    // JNI and having Kotlin read it here removes the third, easy-to-forget
    // copy — now there's exactly one place a human edits this (FF_VOLUMES).
    return static_cast<jint>(MAX_VOLUMES);
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_unlockAndListNative(
        JNIEnv* env, jobject, jint fd, jstring password, jint pim, jint volId, jint cipherId, jint hashId) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    if (!prepareSession(fd, nativePass, pim, volId, true, cipherId, hashId)) {
        env->ReleaseStringUTFChars(password, nativePass);
        return nullptr;
    }

    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            result = buildDirectoryListing(env, volId, nullptr);
        } else {
            LOGI("FATFS Mount failed on volume %d", volId);
        }
    }

    env->ReleaseStringUTFChars(password, nativePass);
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_lockNative(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return;

    VolumeState& v = volumes[volId];
    std::lock_guard<std::mutex> lock(v.mutex);

    // FIX: invalidate any FIL* streams handed out via openStream() before we
    // tear down the fd/crypto context they read through. Without this, a
    // stream left open across a lock() call becomes a dangling handle into
    // freed/zeroized crypto state.
    for (FIL* f : v.openStreams) {
        f_close(f);
        delete f;
    }
    v.openStreams.clear();

    v.reset();

    unmountVolume(volId);  // also clears the persistent IO buffer
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint cipherId, jint hashId) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success = false;

    // Resolve selected cipher and hash (255 = auto, default to AES + SHA-512 for creation)
    CascadeId createCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
    HashId    createHash   = (hashId   != 255) ? static_cast<HashId>(hashId)      : HashId::kSha512;
    CascadeSpec cSpec      = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char salt[VC_SALT_SIZE]   = {0};
    unsigned char combinedMasterKey[192] = {0};

    do {
        if (sizeBytes < static_cast<jlong>(300 * 1024)) {
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
        const int iter = iterationsForHash(createHash, safePim);

        // Derive 192 bytes of header key material (enough for any cascade)
        unsigned char headerKey[192] = {0};
        if (!pbkdf2Hmac(createHash,
                        reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
                        salt, VC_SALT_SIZE, iter, headerKey, 192)) {
            LOGI("createContainer: PBKDF2 failed");
            break;
        }

        const uint64_t VOLUME_SIZE = static_cast<uint64_t>(sizeBytes);
        const uint64_t DATA_SIZE   = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));

        body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
        body[4] = 0x00; body[5] = 0x02;
        body[6] = 0x01; body[7] = 0x0b;

        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (VOLUME_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;

        body[VC_HDR_OFF_SECTOR_SIZE]     = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02;
        body[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;

        // FIX: was VC_KEY_OFFSET_SECONDARY (192) — same numeric value, now
        // correctly named VC_KEY_OFFSET_MASTER since this is the ONLY
        // master-key position for a single-cipher AES volume, not one of
        // two candidates. See the constant's doc comment at the top of
        // this file for the full explanation.
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

        // Encrypt header body using the selected cascade cipher (XTS with zero tweak)
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
                    localMultiplyTweak(T);
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
            v.relTweak           = false;
            v.fileSize           = VOLUME_SIZE;

            const bool useExFat = (strncasecmp(nativeFS, "exfat", 5) == 0);

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
            v.relTweak           = false;
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
             (long long)sizeBytes, nativeFS);

    } while (false);

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);
    close(fd);

    return success ? JNI_TRUE : JNI_FALSE;
}

// ----------------------------------------------------------------====
// PBKDF2-SHA512
// ----------------------------------------------------------------====

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_hashPasswordNative(
        JNIEnv* env, jobject,
        jstring password, jbyteArray salt, jint iterations) {

    if (password == nullptr || salt == nullptr) return nullptr;

    const jsize saltLen = env->GetArrayLength(salt);
    if (saltLen == 0) return nullptr;

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    jbyte* saltData        = env->GetByteArrayElements(salt, nullptr);

    unsigned char out[64] = {0};
    jbyteArray result     = nullptr;

    const unsigned int safeIter =
        (iterations > 0) ? static_cast<unsigned int>(iterations) : 200000u;

    MdContextGuard mdGuard;
    if (mbedtls_md_setup(&mdGuard.ctx,
            mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1) == 0) {
        int rc = mbedtls_pkcs5_pbkdf2_hmac(
            &mdGuard.ctx,
            reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
            reinterpret_cast<const unsigned char*>(saltData), static_cast<size_t>(saltLen),
            safeIter, 64, out);

        if (rc == 0) {
            result = env->NewByteArray(64);
            env->SetByteArrayRegion(result, 0, 64, reinterpret_cast<jbyte*>(out));
        } else {
            LOGI("hashPasswordNative: PBKDF2 failed, rc=%d", rc);
        }
    }

    mbedtls_platform_zeroize(out, sizeof(out));

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);

    return result;
}

// ----------------------------------------------------------------====
// JNI API — Tier 2: stateless (volId-only)
//
// No fd, password, or pim. requireActiveSession() is the first thing
// every function calls; it throws IllegalStateException("NOT_UNLOCKED:…")
// so Kotlin catches it as a typed signal rather than a silent null/0/false.
// ----------------------------------------------------------------====

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMatchedCipherId(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::lock_guard<std::mutex> lock(volumes[volId].mutex);
    return volumes[volId].matchedCipherId;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMatchedHashId(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::lock_guard<std::mutex> lock(volumes[volId].mutex);
    return volumes[volId].matchedHashId;
}


extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_listDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "listDirectory")) {
        throwNotUnlocked(env, volId, "listDirectory"); return nullptr;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jobjectArray result = nullptr;
    {
        // FIX: FF_FS_REENTRANT is 0, so concurrent FatFs calls on the same
        // volume (e.g. this listDirectory racing a writeFileChunk or
        // deleteFile on another thread) can corrupt FAT/directory state.
        // volumes[volId].mutex is the only lock the codebase uses to protect
        // this instance, so serialize FatFs access through it.
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId))
            result = buildDirectoryListing(env, volId, nativePath);
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return result;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFileSize(
        JNIEnv* env, jobject, jstring fileName, jint volId) {
    if (!requireActiveSession(volId, "getFileSize")) {
        throwNotUnlocked(env, volId, "getFileSize"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jlong size = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                size = static_cast<jlong>(f_size(&f));
                f_close(&f);
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return size;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFolderSize(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "getFolderSize")) {
        throwNotUnlocked(env, volId, "getFolderSize"); return 0L;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jlong total = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId))
            total = static_cast<jlong>(recursiveFolderSize(volId, nativePath));
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return total;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jint length, jint volId) {
    if (length <= 0 || static_cast<size_t>(length) > MAX_CHUNK_SIZE) return nullptr;
    if (!requireActiveSession(volId, "readFileChunk")) {
        throwNotUnlocked(env, volId, "readFileChunk"); return nullptr;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyteArray retArray = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                f_lseek(&f, static_cast<FSIZE_t>(offset));
                std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                UINT br = 0;
                if (f_read(&f, buffer.get(), static_cast<UINT>(length), &br) == FR_OK && br > 0) {
                    retArray = env->NewByteArray(static_cast<jsize>(br));
                    env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(br),
                                            reinterpret_cast<jbyte*>(buffer.get()));
                }
                f_close(&f);
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return retArray;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jbyteArray data, jint volId) {
    jsize len = env->GetArrayLength(data);
    if (len <= 0 || static_cast<size_t>(len) > MAX_CHUNK_SIZE) return JNI_FALSE;
    if (!requireActiveSession(volId, "writeFileChunk")) {
        throwNotUnlocked(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyte* body = env->GetByteArrayElements(data, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            BYTE openMode = (offset == 0)
                ? (FA_WRITE | FA_CREATE_ALWAYS)
                : (FA_WRITE | FA_OPEN_ALWAYS);
            if (f_open(&f, fatPath.c_str(), openMode) == FR_OK) {
                if (f_lseek(&f, static_cast<FSIZE_t>(offset)) == FR_OK) {
                    UINT bw = 0;
                    if (f_write(&f, body, static_cast<UINT>(len), &bw) == FR_OK &&
                        bw == static_cast<UINT>(len))
                        success = true;
                }
                f_close(&f);
            }
        }
    }
    env->ReleaseByteArrayElements(data, body, JNI_ABORT);
    env->ReleaseStringUTFChars(fileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeBackFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring sourcePath, jint volId) {
    if (!requireActiveSession(volId, "writeBackFile")) {
        throwNotUnlocked(env, volId, "writeBackFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    const char* source     = env->GetStringUTFChars(sourcePath, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            if (f_open(&f, fatPath.c_str(), FA_WRITE | FA_CREATE_ALWAYS) == FR_OK) {
                std::ifstream inFile(source, std::ios::binary);
                if (inFile.is_open()) {
                    std::unique_ptr<char[]> buf(new char[IO_BUFFER_SIZE]);
                    UINT bw;
                    while (inFile) {
                        inFile.read(buf.get(), IO_BUFFER_SIZE);
                        std::streamsize n = inFile.gcount();
                        if (n > 0) f_write(&f, buf.get(), static_cast<UINT>(n), &bw);
                    }
                    success = true;
                }
                f_close(&f);
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(sourcePath, source);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_extractFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring destPath, jint volId) {
    if (!requireActiveSession(volId, "extractFile")) {
        throwNotUnlocked(env, volId, "extractFile"); return JNI_FALSE;
    }
    const char* targetName  = env->GetStringUTFChars(targetFileName, nullptr);
    const char* destination = env->GetStringUTFChars(destPath, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                std::ofstream outFile(destination, std::ios::binary);
                if (outFile.is_open()) {
                    std::unique_ptr<unsigned char[]> buf(new unsigned char[IO_BUFFER_SIZE]);
                    UINT br;
                    while (f_read(&f, buf.get(), IO_BUFFER_SIZE, &br) == FR_OK && br > 0)
                        outFile.write(reinterpret_cast<char*>(buf.get()), br);
                    success = true;
                }
                f_close(&f);
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(destPath, destination);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_deleteFile(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "deleteFile")) {
        throwNotUnlocked(env, volId, "deleteFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            success = (f_unlink(fatPath.c_str()) == FR_OK);
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "createDirectory")) {
        throwNotUnlocked(env, volId, "createDirectory"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            std::string fullPath = std::string(drivePaths[volId]) + "/" + nativePath;
            success = (f_mkdir(fullPath.c_str()) == FR_OK);
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_renameFile(
        JNIEnv* env, jobject,
        jstring oldPath, jstring newPath, jint volId) {
    if (!requireActiveSession(volId, "renameFile")) {
        throwNotUnlocked(env, volId, "renameFile"); return JNI_FALSE;
    }
    const char* nativeOld = env->GetStringUTFChars(oldPath, nullptr);
    const char* nativeNew = env->GetStringUTFChars(newPath, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            std::string fullOld = std::string(drivePaths[volId]) + "/" + nativeOld;
            std::string fullNew = std::string(drivePaths[volId]) + "/" + nativeNew;
            success = (f_rename(fullOld.c_str(), fullNew.c_str()) == FR_OK);
        }
    }
    env->ReleaseStringUTFChars(oldPath, nativeOld);
    env->ReleaseStringUTFChars(newPath, nativeNew);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getSpaceInfo(
        JNIEnv* env, jobject, jint volId) {
    if (!requireActiveSession(volId, "getSpaceInfo")) {
        throwNotUnlocked(env, volId, "getSpaceInfo");
        return nullptr; // Return nullptr immediately; JNI will safely propagate the exception to Kotlin
    }
    jlong totalBytes = 0, freeBytes = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FATFS* fs;
            DWORD fre_clust;
            if (f_getfree(drivePaths[volId], &fre_clust, &fs) == FR_OK) {
                totalBytes = static_cast<jlong>(fs->n_fatent - 2) * fs->csize * 512;
                freeBytes  = static_cast<jlong>(fre_clust)        * fs->csize * 512;
            }
        }
    }
    jlongArray ret = env->NewLongArray(2);
    if (!ret) return nullptr; // Guard against allocation failures
    
    const jlong tmp[2] = {totalBytes, freeBytes};
    env->SetLongArrayRegion(ret, 0, 2, tmp);
    return ret;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_openStream(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "openStream")) {
        throwNotUnlocked(env, volId, "openStream"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    jlong streamPtr = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            FIL* f = new FIL();
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            if (f_open(f, fatPath.c_str(), FA_READ) == FR_OK) {
                streamPtr = reinterpret_cast<jlong>(f);
                volumes[volId].openStreams.push_back(f);
            } else {
                delete f;
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return streamPtr;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readStream(
        JNIEnv* env, jobject,
        jlong streamPtr, jlong offset, jbyteArray outBuffer, jint length, jint volId) {
    if (streamPtr == 0 || length <= 0) return -1;
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    FIL* f = reinterpret_cast<FIL*>(streamPtr);
    jint bytesRead = -1;

    // FIX: previously volId was unused here, so a stream pointer left over
    // from a volume that has since been locked (fd closed, crypto context
    // freed) would still be read through — UB / stale-context decryption.
    // Take the volume mutex and confirm the pointer is still a stream we
    // handed out for THIS volume before touching it. lockNative() removes
    // entries from openStreams when it invalidates them, so this check
    // fails safely once a lock has happened.
    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    auto& streams = volumes[volId].openStreams;
    if (std::find(streams.begin(), streams.end(), f) == streams.end()) {
        LOGI("readStream: stale/unknown stream pointer for volume %d", volId);
        return -1;
    }

    f_lseek(f, static_cast<FSIZE_t>(offset));
    jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
    if (destBuf != nullptr) {
        UINT br = 0;
        if (f_read(f, destBuf, static_cast<UINT>(length), &br) == FR_OK)
            bytesRead = static_cast<jint>(br);
        env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
    }
    return bytesRead;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_closeStream(
        JNIEnv* env, jobject, jlong streamPtr, jint volId) {
    if (streamPtr == 0) return;
    if (volId < 0 || volId >= MAX_VOLUMES) return;
    FIL* f = reinterpret_cast<FIL*>(streamPtr);

    // FIX: guard against double-close / closing a pointer lockNative() has
    // already torn down (which would double-free / close an invalid fd).
    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    auto& streams = volumes[volId].openStreams;
    auto it = std::find(streams.begin(), streams.end(), f);
    if (it == streams.end()) {
        LOGI("closeStream: stale/unknown stream pointer for volume %d, ignoring", volId);
        return;
    }
    streams.erase(it);
    f_close(f);
    delete f;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_unlockUsbAndListNative(
        JNIEnv* env, jobject, jstring password, jint pim, jint volId, jlong deviceSizeBytes, jint cipherId, jint hashId) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const bool ok = prepareUsbSession(nativePass, pim, volId, cipherId, hashId);
    env->ReleaseStringUTFChars(password, nativePass);
    if (!ok) return nullptr;

    {
        std::lock_guard<std::mutex> lock(volumes[volId].mutex);
        volumes[volId].fileSize = static_cast<uint64_t>(deviceSizeBytes);
    }

    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            result = buildDirectoryListing(env, volId, nullptr);
        } else {
            LOGI("FATFS Mount failed on USB volume %d", volId);
        }
    }
    return result;
}