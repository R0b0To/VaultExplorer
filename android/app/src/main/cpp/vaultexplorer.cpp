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
//  VC_KEY_OFFSET_PRIMARY (252)
//      Byte offset inside the *decrypted* header body where the primary
//      master key material starts (64 bytes). Used for AES-XTS data
//      encryption/decryption of the actual volume contents.
//
//  VC_KEY_OFFSET_SECONDARY (192)
//      Byte offset of the secondary (XTS tweak) key inside the decrypted
//      header body (also 64 bytes). AES-XTS requires two equal-length keys;
//      primary and secondary together form the 512-bit key passed to
//      mbedtls_aes_xts_setkey_*.
//
//  VC_KEY_MATERIAL_LEN (64)
//      Length of each individual key in bytes (512 bits). Both primary and
//      secondary keys are this size; the PBKDF2 output buffer must therefore
//      be at least 2 × 64 = 128 bytes when deriving both at once, but the
//      current implementation derives only 64 bytes and picks the two keys
//      from fixed offsets inside the decrypted header body.
//
static constexpr size_t VC_SALT_SIZE            = 64;
static constexpr size_t VC_HEADER_BODY_SIZE     = 448;
static constexpr size_t VC_FULL_HEADER_SIZE     = 512;
static constexpr uint64_t VC_DATA_AREA_OFFSET   = 131072ULL;
static constexpr size_t IO_BUFFER_SIZE          = 262144;   // 256 KB
static constexpr int    VC_KEY_OFFSET_PRIMARY   = 252;
static constexpr int    VC_KEY_OFFSET_SECONDARY = 192;
static constexpr int    VC_KEY_MATERIAL_LEN     = 64;
static constexpr size_t MAX_DIR_ENTRIES         = 50000;
static constexpr uint64_t SCAN_SECTORS          = 2048;
static constexpr uint64_t SCAN_BATCH            = 64;
static constexpr int    MKFS_WORK_BUF_SIZE      = 4096;
static constexpr size_t MAX_CHUNK_SIZE          = 64 * 1024 * 1024; // 64 MB safety cap

// FIX P14: Use a much larger batch for container creation to reduce pwrite()
// syscall count. 4096 sectors = 2 MB per write vs 32 KB — 64× fewer syscalls
// for a 1 GB container (512 writes vs 32,768).
static constexpr uint64_t CREATE_FILL_BATCH     = 4096;

// FIX P12: Per-volume persistent IO buffer to avoid allocating a fresh heap
// buffer on every large disk_read/disk_write call (which FatFs can issue up to
// 4 MB at once during sequential file access).
static constexpr size_t   IO_VOL_BUF_SECTORS    = 512;    // 256 KB per volume
static constexpr size_t   IO_VOL_BUF_SIZE       = IO_VOL_BUF_SECTORS * 512;

static uint64_t activePartitionStartSector[MAX_VOLUMES];

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
// GLOBAL STATE
// ----------------------------------------------------------------====

static std::mutex    volumeMutex[MAX_VOLUMES];
static std::mutex    slotAllocMutex;

static int           activeFd[MAX_VOLUMES];
static uint64_t      activeDataOffset[MAX_VOLUMES];
static bool          activeIsRelTweak[MAX_VOLUMES];
static bool          isDataCtxInitialized[MAX_VOLUMES];
static uint64_t      activeFileSize[MAX_VOLUMES];
static bool          fsMounted[MAX_VOLUMES];

static mbedtls_aes_xts_context activeDataCtxDec[MAX_VOLUMES];
static mbedtls_aes_xts_context activeDataCtxEnc[MAX_VOLUMES];

// FIX P12: Per-volume persistent IO buffers. Allocated once on first use,
// reused for every subsequent disk_read/disk_write on that volume, eliminating
// per-call heap churn for large sequential reads (video, export, copy).
static std::unique_ptr<unsigned char[]> ioVolBuf[MAX_VOLUMES];
static size_t                           ioVolBufSize[MAX_VOLUMES];
static std::mutex                       ioVolBufMutex[MAX_VOLUMES];

// FIX: openStream() hands Kotlin a raw FIL* that outlives the JNI call. If
// lockNative() runs while that stream is still open, the underlying fd is
// closed and the crypto context is freed/zeroized out from under it — a
// subsequent readStream() would decrypt through a dead context (UB / stale
// data) or read from a closed fd. Track live streams per volume, guarded by
// volumeMutex[volId], so lockNative() can close and invalidate them, and
// readStream()/closeStream() can reject pointers that are no longer valid
// for that volume's current session.
static std::vector<FIL*> openStreams[MAX_VOLUMES];

// ── USB backing-store support ────────────────────────────────────────────
//
// A volume's physical bytes come from one of two places:
//   - a container file's fd (existing path, pread/pwrite)
//   - a USB mass-storage device, reached only through a Kotlin upcall
//     (UsbBlockBridge.readSectors/writeSectors), since raw block-device
//     access on unrooted Android only exists via the USB Host API.
//
// isUsbSource[volId] selects which path physRead/physWrite below use.
// activeFd[volId] stays -1 for USB volumes; only isUsbSource matters.

static bool isUsbSource[MAX_VOLUMES];

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
    if (isUsbSource[pdrv]) {
        return usbReadSectors(pdrv, physByteOffset / 512,
                               static_cast<uint32_t>(totalBytes / 512), buf);
    }
    const ssize_t got = pread(activeFd[pdrv], buf, totalBytes, static_cast<off_t>(physByteOffset));
    return got == static_cast<ssize_t>(totalBytes);
}

static bool physWrite(int pdrv, uint64_t physByteOffset, const unsigned char* buf, size_t totalBytes) {
    if (isUsbSource[pdrv]) {
        return usbWriteSectors(pdrv, physByteOffset / 512,
                                static_cast<uint32_t>(totalBytes / 512), buf);
    }
    const ssize_t written = pwrite(activeFd[pdrv], buf, totalBytes, static_cast<off_t>(physByteOffset));
    return written == static_cast<ssize_t>(totalBytes);
}

static const char* drivePaths[MAX_VOLUMES] = {
    "0:", "1:", "2:", "3:", "4:", "5:", "6:", "7:"
};
static FATFS globalFs[MAX_VOLUMES];

static bool _globalInit = [](){
    for (int i = 0; i < MAX_VOLUMES; i++) {
        activeFd[i]               = -1;
        activeDataOffset[i]       = 0;
        activeIsRelTweak[i]       = false;
        isDataCtxInitialized[i]   = false;
        activeFileSize[i]         = 0;
        fsMounted[i]              = false;
        ioVolBufSize[i]           = 0;
        isUsbSource[i] = false; 
        activePartitionStartSector[i] = 0;
    }
    return true;
}();

// Returns true only if volId already has an active, unlocked session.
// Stateless natives (list/read/write/size/etc.) call this FIRST and bail
// with a clear log line instead of silently falling through into
// prepareSession's derivation path with an empty password.
static inline bool requireActiveSession(int volId, const char* callerName) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    std::lock_guard<std::mutex> lock(volumeMutex[volId]);
    
    // Allow activeFd to be < 0 only if this is an active USB session
    if (!isDataCtxInitialized[volId] || (activeFd[volId] < 0 && !isUsbSource[volId])) {
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
    if (fsMounted[volId]) return true;

    FRESULT fr = f_mount(&globalFs[volId], drivePaths[volId], 1);
    if (fr == FR_OK) {
        fsMounted[volId] = true;
        return true;
    }
    LOGI("ensureMounted: f_mount failed for volume %d, code=%d", volId, (int)fr);
    return false;
}

static void unmountVolume(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return;
    if (fsMounted[volId]) {
        f_mount(nullptr, drivePaths[volId], 0);
        fsMounted[volId] = false;
    }
    // Release persistent IO buffer when volume is locked.
    std::lock_guard<std::mutex> bufLock(ioVolBufMutex[volId]);
    ioVolBuf[volId].reset();
    ioVolBufSize[volId] = 0;
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
// CRYPTO HELPERS
// ----------------------------------------------------------------====

static void encryptSector(mbedtls_aes_xts_context* ctx, uint64_t sectorNum,
                           const unsigned char* in, unsigned char* out) {
    unsigned char tweak[16];
    setTweak(tweak, sectorNum);
    mbedtls_aes_crypt_xts(ctx, MBEDTLS_AES_ENCRYPT, 512, tweak, in, out);
}

static void decryptSector(mbedtls_aes_xts_context* ctx, uint64_t sectorNum,
                           const unsigned char* in, unsigned char* out) {
    unsigned char tweak[16];
    setTweak(tweak, sectorNum);
    mbedtls_aes_crypt_xts(ctx, MBEDTLS_AES_DECRYPT, 512, tweak, in, out);
}

// ----------------------------------------------------------------====
// FIX P12: Per-volume IO buffer accessor
// Returns a pointer to a buffer of at least `neededBytes` for `volId`.
// The buffer is allocated once and grown if needed; never shrunk.
// MUST be called with ioVolBufMutex[volId] held.
// ----------------------------------------------------------------====
static unsigned char* getVolIoBuf(int volId, size_t neededBytes) {
    if (ioVolBufSize[volId] < neededBytes) {
        ioVolBuf[volId].reset(new unsigned char[neededBytes]);
        ioVolBufSize[volId] = neededBytes;
    }
    return ioVolBuf[volId].get();
}

// ----------------------------------------------------------------====
// FATFS LOW-LEVEL DISK HOOKS
// ----------------------------------------------------------------====

extern "C" DSTATUS disk_initialize(BYTE pdrv) { return 0; }
extern "C" DSTATUS disk_status(BYTE pdrv)     { return 0; }

extern "C" DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !isDataCtxInitialized[pdrv])
    return RES_NOTRDY;
if (!isUsbSource[pdrv] && activeFd[pdrv] < 0)
    return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    const uint64_t basePhysical = activeDataOffset[pdrv] / 512;
    const bool relTweak = activeIsRelTweak[pdrv];


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
            bufLock = std::unique_lock<std::mutex>(ioVolBufMutex[pdrv]);
            encBuf = getVolIoBuf(pdrv, totalBytes);
        } else {
            encBuf = stackBuf;
        }

        if (!physRead(pdrv, firstPhysical * 512, encBuf, totalBytes)) return RES_ERROR;

        for (UINT i = 0; i < batchCount; i++) {
            const uint64_t physSector = firstPhysical + i;
            const uint64_t sectorInPartition = physSector - activePartitionStartSector[pdrv];
            const uint64_t tweak = relTweak ? (physSector - basePhysical) : sectorInPartition;
            decryptSector(&activeDataCtxDec[pdrv], tweak,
                          encBuf + (i * 512), curBuf + (i * 512));
        }

        remaining -= batchCount;
        curSector += batchCount;
        curBuf    += batchCount * 512;
    }
    return RES_OK;
}

extern "C" DRESULT disk_write(BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !isDataCtxInitialized[pdrv])
    return RES_NOTRDY;
if (!isUsbSource[pdrv] && activeFd[pdrv] < 0)
    return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    const uint64_t basePhysical = activeDataOffset[pdrv] / 512;
    const bool     relTweak     = activeIsRelTweak[pdrv];

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
            bufLock = std::unique_lock<std::mutex>(ioVolBufMutex[pdrv]);
            encBuf = getVolIoBuf(pdrv, totalBytes);
        }

        for (UINT i = 0; i < batchCount; i++) {
            const uint64_t physSector = firstPhysical + i;
            const uint64_t sectorInPartition = physSector - activePartitionStartSector[pdrv];
            const uint64_t tweak = relTweak ? (physSector - basePhysical) : sectorInPartition;
            encryptSector(&activeDataCtxEnc[pdrv], tweak,
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
            if (pdrv < MAX_VOLUMES && activeFileSize[pdrv] > VC_DATA_AREA_OFFSET * 2) {
                *(LBA_t*)buff = static_cast<LBA_t>(
                    (activeFileSize[pdrv] - VC_DATA_AREA_OFFSET * 2) / 512);
            } else {
                *(LBA_t*)buff = 1000000;
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

// Tries one 64-byte key candidate (primary or secondary key offset from the
// decrypted header) against up to SCAN_SECTORS sectors, looking for the
// 0x55AA boot-sector signature. Returns immediately on first hit.
//
// Factored out of prepareSession() so the dual-tweak-check inner body exists
// in exactly one place — previously this logic was correct but implicitly
// duplicated by virtue of being inside a `for (int kOff : keyOffsets)` loop
// with no named boundary, making it easy to accidentally diverge the two
// iterations during a future edit.
static FsScanResult tryKeyCandidate(
    int fd,
    const unsigned char* keyMaterial, // 64 bytes, VC_KEY_MATERIAL_LEN
    mbedtls_aes_xts_context& candidateDecCtx // already keyed via setkey_dec
) {
    FsScanResult result;

    std::unique_ptr<unsigned char[]> encBatch(new unsigned char[SCAN_BATCH * 512]);
    unsigned char decS[512];
    unsigned char tweak[16];

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

            // Convention A: tweak = absolute physical sector index.
            setTweak(tweak, sectorIdx);
            mbedtls_aes_crypt_xts(&candidateDecCtx, MBEDTLS_AES_DECRYPT,
                                  512, tweak, enc, decS);
            if (isValidBootSector(decS)) {
                result.found      = true;
                result.dataOffset = sectorIdx * 512;
                result.relTweak   = false;
                return result;
            }

            // Convention B: tweak = sector index relative to the data area
            // (i.e. zero at the first scanned sector).
            memset(tweak, 0, 16);
            mbedtls_aes_crypt_xts(&candidateDecCtx, MBEDTLS_AES_DECRYPT,
                                  512, tweak, enc, decS);
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
//   2. C++: `volumeMutex[volId]`
//      Protects the C++ globals (activeFd, activeDataCtxDec/Enc,
//      isDataCtxInitialized, activeDataOffset) directly.
//
// prepareSession() DELIBERATELY derives the PBKDF2 key (the slow ~2s step)
// WITHOUT holding volumeMutex[volId] (see FIX P11) so that disk_read/disk_write
// on an *already-unlocked* volume aren't blocked by a concurrent unlock of
// that SAME volume. This is safe only because:
//   - disk_read/disk_write require isDataCtxInitialized[pdrv] == true,
//     which is set exclusively inside the volumeMutex-guarded block at the
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
bool prepareSession(int fd, const char* password, int pim, int volId, bool forceDerive) {
    if (volId < 0 || volId >= MAX_VOLUMES) {
        if (fd >= 0) close(fd);
        return false;
    }

    // Fast path: session already established, no derivation needed.
    if (!forceDerive) {
        std::lock_guard<std::mutex> lock(volumeMutex[volId]);
        if (isDataCtxInitialized[volId] && activeFd[volId] >= 0) {
            if (fd >= 0) close(fd);
            return true;
        }
        if (isDataCtxInitialized[volId]) {
            if (fd >= 0) {
                struct stat st;
                if (fstat(fd, &st) == 0)
                    activeFileSize[volId] = static_cast<uint64_t>(st.st_size);
                activeFd[volId] = fd;
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
        std::lock_guard<std::mutex> lock(volumeMutex[volId]);
        if (isDataCtxInitialized[volId]) {
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

    const unsigned char* salt = headerBuf;
    const unsigned char* encH = headerBuf + VC_SALT_SIZE;

    const int safePim = clampPim(pim);
    const int iter = (safePim > 0) ? (15000 + (safePim * 1000)) : 500000;

    // FIX P11: PBKDF2 runs here — completely outside the volume mutex.
    // Other volume operations (reads on an already-unlocked volume, operations
    // on different volumes) are entirely unaffected.
    MdContextGuard mdGuard;
    mbedtls_md_setup(&mdGuard.ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1);

    unsigned char hKey[VC_KEY_MATERIAL_LEN];
    mbedtls_pkcs5_pbkdf2_hmac(&mdGuard.ctx,
        reinterpret_cast<const unsigned char*>(password), strlen(password),
        salt, VC_SALT_SIZE, iter, VC_KEY_MATERIAL_LEN, hKey);

    unsigned char decH[VC_HEADER_BODY_SIZE];
    {
        XtsContextPair hdrXts;
        mbedtls_aes_xts_setkey_dec(&hdrXts.dec, hKey, 512);
        const unsigned char zTw[16] = {0};
        mbedtls_aes_crypt_xts(&hdrXts.dec, MBEDTLS_AES_DECRYPT,
                               VC_HEADER_BODY_SIZE, zTw, encH, decH);
    }

    mbedtls_platform_zeroize(hKey, sizeof(hKey));

    if (decH[0] != 'V' || decH[1] != 'E' || decH[2] != 'R' || decH[3] != 'A') {
        mbedtls_platform_zeroize(decH, sizeof(decH));
        close(fd);
        derivationInProgress[volId].store(false, std::memory_order_release);
        return false;
    }

    const int keyOffsets[] = {VC_KEY_OFFSET_PRIMARY, VC_KEY_OFFSET_SECONDARY};
    // NOTE on ordering: VeraCrypt's header layout places the primary
    // data-encryption key before the secondary (XTS tweak) key in the
    // decrypted header body. We try primary first since the overwhelming
    // majority of volumes are formatted with the primary key in that slot;
    // trying secondary first would just cost one extra failed scan pass for
    // every successful primary-key volume. There is no correctness
    // difference — both are tried regardless, only the average-case cost
    // changes.
    unsigned char dKey[VC_KEY_MATERIAL_LEN];
    bool fsFound = false;
    uint64_t foundDataOffset = 0;
    bool     foundRelTweak   = false;

    XtsContextPair candidate;

    for (int kOff : keyOffsets) {
        memcpy(dKey, &decH[kOff], VC_KEY_MATERIAL_LEN);
        mbedtls_aes_xts_setkey_dec(&candidate.dec, dKey, 512);

        FsScanResult scan = tryKeyCandidate(fd, dKey, candidate.dec);
        if (scan.found) {
            fsFound         = true;
            foundDataOffset = scan.dataOffset;
            foundRelTweak   = scan.relTweak;
            break;
        }
    }

    mbedtls_platform_zeroize(decH, sizeof(decH));

    if (!fsFound) {
        mbedtls_platform_zeroize(dKey, sizeof(dKey));
        close(fd);
        derivationInProgress[volId].store(false, std::memory_order_release);
        return false;
    }

    mbedtls_aes_xts_setkey_enc(&candidate.enc, dKey, 512);
    mbedtls_platform_zeroize(dKey, sizeof(dKey));

    // FIX P11: Now acquire the mutex ONLY for the brief context swap.
    // All the slow crypto work is already done above.
    {
        std::lock_guard<std::mutex> lock(volumeMutex[volId]);

        if (isDataCtxInitialized[volId]) {
            mbedtls_aes_xts_free(&activeDataCtxDec[volId]);
            mbedtls_aes_xts_free(&activeDataCtxEnc[volId]);
        }
        activeDataCtxDec[volId] = candidate.dec;
        activeDataCtxEnc[volId] = candidate.enc;
        mbedtls_aes_xts_init(&candidate.dec);
        mbedtls_aes_xts_init(&candidate.enc);

        isDataCtxInitialized[volId] = true;
        activeFd[volId]             = fd;
        activeDataOffset[volId]     = foundDataOffset;
        activeIsRelTweak[volId]     = foundRelTweak;
        activeFileSize[volId]       = fileSize;
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
static FsScanResult tryKeyCandidateUsb(int volId, uint64_t partitionStartSector, mbedtls_aes_xts_context& candidateDecCtx) {
    FsScanResult result;
    std::unique_ptr<unsigned char[]> encBatch(new unsigned char[SCAN_BATCH * 512]);
    unsigned char decS[512];
    unsigned char tweak[16];

    uint64_t s = 0;
    while (s < SCAN_SECTORS) {
        const uint64_t batchCount = std::min(SCAN_BATCH, SCAN_SECTORS - s);
        if (!usbReadSectors(volId, partitionStartSector + s, static_cast<uint32_t>(batchCount), encBatch.get())) break;

        for (uint64_t i = 0; i < batchCount; i++) {
            const uint64_t sectorIdx = s + i;
            const unsigned char* enc = encBatch.get() + (i * 512);

            // Absolute physical sector tweak (relative to partition start)
            setTweak(tweak, sectorIdx);
            mbedtls_aes_crypt_xts(&candidateDecCtx, MBEDTLS_AES_DECRYPT, 512, tweak, enc, decS);
            if (isValidBootSector(decS)) {
                result.found = true; 
                result.dataOffset = (partitionStartSector + sectorIdx) * 512;
                result.relTweak = false;
                return result;
            }

            // Zero relative tweak
            memset(tweak, 0, 16);
            mbedtls_aes_crypt_xts(&candidateDecCtx, MBEDTLS_AES_DECRYPT, 512, tweak, enc, decS);
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

// USB-backed equivalent of prepareSession(). There is no fd — Kotlin must
// already have opened the USB device, granted permission, run READ CAPACITY,
// and called UsbBlockBridge.register(volId, device) BEFORE this is invoked,
// since PBKDF2 + the header/boot-sector reads below both go through the
// upcall immediately.
static bool prepareUsbSession(const char* password, int pim, int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;

    // Collect partition candidates. Start with raw disk (LBA 0)
    std::vector<PartitionCandidate> partitions;
    partitions.push_back({0, 0});

    // Read the first 34 sectors to scan MBR and primary GPT entries (17 KB)
    std::unique_ptr<unsigned char[]> diskBuf(new unsigned char[34 * 512]);
    if (usbReadSectors(volId, 0, 34, diskBuf.get())) {
        const unsigned char* sector0 = diskBuf.get();
        const unsigned char* sector1 = diskBuf.get() + 512;
        const unsigned char* gptEntries = diskBuf.get() + 1024;

        if (sector0[510] == 0x55 && sector0[511] == 0xAA) {
            bool isGpt = false;
            
            // 1. Scan MBR entries
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

            // 2. Scan GPT partition table (if protective MBR is detected)
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

    bool fsFound = false;
    uint64_t foundDataOffset = 0;
    bool foundRelTweak = false;
    XtsContextPair candidate;
    uint64_t matchedPartitionStart = 0;

    // Loop through candidates; the first one that successfully validates with the password wins
    for (const auto& part : partitions) {
        unsigned char headerBuf[VC_FULL_HEADER_SIZE];
        if (!usbReadSectors(volId, part.startSector, 1, headerBuf)) {
            continue;
        }

        const unsigned char* salt = headerBuf;
        const unsigned char* encH = headerBuf + VC_SALT_SIZE;

        const int safePim = clampPim(pim);
        const int iter = (safePim > 0) ? (15000 + (safePim * 1000)) : 500000;

        MdContextGuard mdGuard;
        mbedtls_md_setup(&mdGuard.ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1);

        unsigned char hKey[VC_KEY_MATERIAL_LEN];
        mbedtls_pkcs5_pbkdf2_hmac(&mdGuard.ctx,
            reinterpret_cast<const unsigned char*>(password), strlen(password),
            salt, VC_SALT_SIZE, iter, VC_KEY_MATERIAL_LEN, hKey);

        unsigned char decH[VC_HEADER_BODY_SIZE];
        {
            XtsContextPair hdrXts;
            mbedtls_aes_xts_setkey_dec(&hdrXts.dec, hKey, 512);
            const unsigned char zTw[16] = {0};
            mbedtls_aes_crypt_xts(&hdrXts.dec, MBEDTLS_AES_DECRYPT, VC_HEADER_BODY_SIZE, zTw, encH, decH);
        }
        mbedtls_platform_zeroize(hKey, sizeof(hKey));

        if (decH[0] != 'V' || decH[1] != 'E' || decH[2] != 'R' || decH[3] != 'A') {
            mbedtls_platform_zeroize(decH, sizeof(decH));
            continue; // Header decryption failed for this candidate; try next partition
        }

        const int keyOffsets[] = {VC_KEY_OFFSET_PRIMARY, VC_KEY_OFFSET_SECONDARY};
        unsigned char dKey[VC_KEY_MATERIAL_LEN];

        for (int kOff : keyOffsets) {
            memcpy(dKey, &decH[kOff], VC_KEY_MATERIAL_LEN);
            mbedtls_aes_xts_setkey_dec(&candidate.dec, dKey, 512);

            FsScanResult scan = tryKeyCandidateUsb(volId, part.startSector, candidate.dec);
            if (scan.found) {
                fsFound = true;
                foundDataOffset = scan.dataOffset;
                foundRelTweak = scan.relTweak;
                matchedPartitionStart = part.startSector;
                break;
            }
        }
        mbedtls_platform_zeroize(decH, sizeof(decH));

        if (fsFound) {
            mbedtls_aes_xts_setkey_enc(&candidate.enc, dKey, 512);
            mbedtls_platform_zeroize(dKey, sizeof(dKey));
            break; // Found the active, valid filesystem partition; stop search
        }
        mbedtls_platform_zeroize(dKey, sizeof(dKey));
    }

    if (!fsFound) {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(volumeMutex[volId]);
        if (isDataCtxInitialized[volId]) {
            mbedtls_aes_xts_free(&activeDataCtxDec[volId]);
            mbedtls_aes_xts_free(&activeDataCtxEnc[volId]);
        }
        activeDataCtxDec[volId] = candidate.dec;
        activeDataCtxEnc[volId] = candidate.enc;
        mbedtls_aes_xts_init(&candidate.dec);
        mbedtls_aes_xts_init(&candidate.enc);

        isUsbSource[volId]                = true;
        isDataCtxInitialized[volId]       = true;
        activeFd[volId]                   = -1;
        activeDataOffset[volId]           = foundDataOffset;
        activeIsRelTweak[volId]           = foundRelTweak;
        activePartitionStartSector[volId] = matchedPartitionStart; // Record the matched sector
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

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_unlockAndListNative(
        JNIEnv* env, jobject, jint fd, jstring password, jint pim, jint volId) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    if (!prepareSession(fd, nativePass, pim, volId, true)) {
        env->ReleaseStringUTFChars(password, nativePass);
        return nullptr;
    }

    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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

    std::lock_guard<std::mutex> lock(volumeMutex[volId]);

    // FIX: invalidate any FIL* streams handed out via openStream() before we
    // tear down the fd/crypto context they read through. Without this, a
    // stream left open across a lock() call becomes a dangling handle into
    // freed/zeroized crypto state.
    for (FIL* f : openStreams[volId]) {
        f_close(f);
        delete f;
    }
    openStreams[volId].clear();

    if (activeFd[volId] >= 0) {
        close(activeFd[volId]);
    }
    activeFd[volId]         = -1;
    activeDataOffset[volId] = 0;
    activeIsRelTweak[volId] = false;
    activeFileSize[volId]   = 0;
    isUsbSource[volId] = false;
    activePartitionStartSector[volId] = 0;

    if (isDataCtxInitialized[volId]) {
        mbedtls_aes_xts_free(&activeDataCtxDec[volId]);
        mbedtls_aes_xts_free(&activeDataCtxEnc[volId]);
        isDataCtxInitialized[volId] = false;
    }

    unmountVolume(volId);  // also clears the persistent IO buffer
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jlong sizeBytes, jstring fileSystem) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success = false;

    unsigned char salt[VC_SALT_SIZE]               = {0};
    unsigned char combinedMasterKey[VC_KEY_MATERIAL_LEN] = {0};

    do {
        if (sizeBytes < static_cast<jlong>(300 * 1024)) {
            LOGI("createContainer: sizeBytes too small (%lld)", (long long)sizeBytes);
            break;
        }

        int volId = -1;
        {
            std::lock_guard<std::mutex> allocLock(slotAllocMutex);
            for (int i = 0; i < MAX_VOLUMES; i++) {
                if (!isDataCtxInitialized[i]) { volId = i; break; }
            }
        }
        if (volId == -1) {
            LOGI("createContainer: no free slots available");
            break;
        }

        {
            FILE* urnd = fopen("/dev/urandom", "rb");
            if (!urnd) { LOGI("createContainer: cannot open /dev/urandom"); break; }
            bool ok = (fread(salt,              1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                      (fread(combinedMasterKey, 1, VC_KEY_MATERIAL_LEN, urnd) == VC_KEY_MATERIAL_LEN);
            fclose(urnd);
            if (!ok) { LOGI("createContainer: urandom read failed"); break; }
        }

        const int safePim = clampPim(pim);
        const int iter = (safePim > 0) ? (15000 + safePim * 1000) : 500000;

        unsigned char headerKey[VC_KEY_MATERIAL_LEN] = {0};
        {
            MdContextGuard mdGuard;
            if (mbedtls_md_setup(&mdGuard.ctx,
                    mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1) != 0) {
                LOGI("createContainer: mbedtls_md_setup failed");
                break;
            }
            mbedtls_pkcs5_pbkdf2_hmac(&mdGuard.ctx,
                reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
                salt, VC_SALT_SIZE,
                static_cast<unsigned int>(iter),
                VC_KEY_MATERIAL_LEN, headerKey);
        }

        const uint64_t VOLUME_SIZE = static_cast<uint64_t>(sizeBytes);
        const uint64_t DATA_SIZE   = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));

        body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
        body[4] = 0x00; body[5] = 0x02;
        body[6] = 0x01; body[7] = 0x0b;

        for (int i = 7; i >= 0; --i)
            body[36 + (7 - i)] = (VOLUME_SIZE >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i)
            body[44 + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
        for (int i = 7; i >= 0; --i)
            body[52 + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;

        body[64] = 0x00; body[65] = 0x00; body[66] = 0x02; body[67] = 0x00;

        memcpy(&body[VC_KEY_OFFSET_SECONDARY], combinedMasterKey, VC_KEY_MATERIAL_LEN);

        auto crc32 = [](const unsigned char* data, size_t len) -> uint32_t {
            uint32_t crc = 0xFFFFFFFFu;
            for (size_t i = 0; i < len; ++i) {
                crc ^= data[i];
                for (int b = 0; b < 8; ++b)
                    crc = (crc >> 1) ^ (0xEDB88320u & ~((crc & 1) - 1));
            }
            return crc ^ 0xFFFFFFFFu;
        };

        uint32_t keyCrc = crc32(&body[VC_KEY_OFFSET_SECONDARY], 256);
        body[ 8] = (keyCrc >> 24) & 0xFF;
        body[ 9] = (keyCrc >> 16) & 0xFF;
        body[10] = (keyCrc >>  8) & 0xFF;
        body[11] = (keyCrc      ) & 0xFF;

        uint32_t hdrCrc = crc32(body, 188);
        body[188] = (hdrCrc >> 24) & 0xFF;
        body[189] = (hdrCrc >> 16) & 0xFF;
        body[190] = (hdrCrc >>  8) & 0xFF;
        body[191] = (hdrCrc      ) & 0xFF;

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            XtsContextPair hdrXts;
            mbedtls_aes_xts_setkey_enc(&hdrXts.enc, headerKey, 512);
            const unsigned char zeroTweak[16] = {0};
            mbedtls_aes_crypt_xts(&hdrXts.enc, MBEDTLS_AES_ENCRYPT,
                                  VC_HEADER_BODY_SIZE, zeroTweak, body, encBody);
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
            XtsContextPair dataXts;
            mbedtls_aes_xts_setkey_enc(&dataXts.enc, combinedMasterKey, 512);

            const uint64_t START_SECTOR  = VC_DATA_AREA_OFFSET / 512;
            const uint64_t TOTAL_SECTORS = (VOLUME_SIZE - VC_DATA_AREA_OFFSET) / 512;

            // FIX P14: Use CREATE_FILL_BATCH (4096 sectors = 2 MB) instead of
            // SCAN_BATCH (64 sectors = 32 KB). For a 1 GB container this reduces
            // pwrite() syscalls from 32,768 → 512, cutting creation time noticeably.
            const unsigned char ZERO_SECTOR[512] = {0};
            const size_t batchBufBytes = CREATE_FILL_BATCH * 512;
            std::unique_ptr<unsigned char[]> batch(new unsigned char[batchBufBytes]);
            unsigned char tweak[16];
            bool writeOk = true;

            for (uint64_t s = START_SECTOR; s < TOTAL_SECTORS && writeOk; ) {
                const uint64_t rem   = TOTAL_SECTORS - s;
                const uint64_t count = (rem < CREATE_FILL_BATCH) ? rem : CREATE_FILL_BATCH;

                for (uint64_t i = 0; i < count; ++i) {
                    setTweak(tweak, (s + i));
                    mbedtls_aes_crypt_xts(&dataXts.enc, MBEDTLS_AES_ENCRYPT,
                                          512, tweak, ZERO_SECTOR,
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
            std::lock_guard<std::mutex> vlock(volumeMutex[volId]);

            if (isDataCtxInitialized[volId]) {
                mbedtls_aes_xts_free(&activeDataCtxDec[volId]);
                mbedtls_aes_xts_free(&activeDataCtxEnc[volId]);
            }
            mbedtls_aes_xts_init(&activeDataCtxDec[volId]);
            mbedtls_aes_xts_init(&activeDataCtxEnc[volId]);
            mbedtls_aes_xts_setkey_dec(&activeDataCtxDec[volId], combinedMasterKey, 512);
            mbedtls_aes_xts_setkey_enc(&activeDataCtxEnc[volId], combinedMasterKey, 512);
            isDataCtxInitialized[volId] = true;
            activeFd[volId]             = fd;
            activeDataOffset[volId]     = VC_DATA_AREA_OFFSET;
            activeIsRelTweak[volId]     = false;
            activeFileSize[volId]       = VOLUME_SIZE;

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
            fsMounted[volId]          = false;
            activeFd[volId]           = -1;
            activeDataOffset[volId]   = 0;
            activeIsRelTweak[volId]   = false;
            activeFileSize[volId]     = 0;
            mbedtls_aes_xts_free(&activeDataCtxDec[volId]);
            mbedtls_aes_xts_free(&activeDataCtxEnc[volId]);
            isDataCtxInitialized[volId] = false;

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
        // globalFs[volId] (e.g. this listDirectory racing a writeFileChunk
        // or deleteFile on another thread) can corrupt FAT/directory state.
        // volumeMutex[volId] is the only lock the codebase uses to protect
        // this instance, so serialize FatFs access through it.
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
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
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
        if (ensureMounted(volId)) {
            FIL* f = new FIL();
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            if (f_open(f, fatPath.c_str(), FA_READ) == FR_OK) {
                streamPtr = reinterpret_cast<jlong>(f);
                openStreams[volId].push_back(f);
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
    // Take volumeMutex and confirm the pointer is still a stream we handed
    // out for THIS volume before touching it. lockNative() removes entries
    // from openStreams[volId] when it invalidates them, so this check fails
    // safely once a lock has happened.
    std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
    auto& streams = openStreams[volId];
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
    std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
    auto& streams = openStreams[volId];
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
        JNIEnv* env, jobject, jstring password, jint pim, jint volId, jlong deviceSizeBytes) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const bool ok = prepareUsbSession(nativePass, pim, volId);
    env->ReleaseStringUTFChars(password, nativePass);
    if (!ok) return nullptr;

    {
        std::lock_guard<std::mutex> lock(volumeMutex[volId]);
        activeFileSize[volId] = static_cast<uint64_t>(deviceSizeBytes);
    }

    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumeMutex[volId]);
        if (ensureMounted(volId)) {
            result = buildDirectoryListing(env, volId, nullptr);
        } else {
            LOGI("FATFS Mount failed on USB volume %d", volId);
        }
    }
    return result;
}