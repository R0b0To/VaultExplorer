#include "bitlocker_backend.h"

#include <cstring>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#include <android/log.h>

// Dislocker headers (C API, extern "C" already inside)
extern "C" {
#include <dislocker/dislocker.h>
#include <dislocker/config.h>
#include <dislocker/virtual_io.h>
}

#include "jni_callbacks.h"   // usbReadSectors/usbWriteSectors, reportUnlockProgress
#include "container_format.h"
#include "volume_state.h"
#include "session_prepare.h"
#include "vhdx_image.h"
#include "vhd_image.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_BDE", __VA_ARGS__)

namespace {

// ── Virtual I/O bridge ──────────────────────────────────────────────────
//
// Routes dislocker's sector I/O to this app's existing fd/USB transport
// through dis_virtual_io_t callbacks. For file-backed containers, the
// callbacks use pread/pwrite on the real fd. For USB-backed containers,
// they go through usbReadSectors/usbWriteSectors (JNI round-trips to
// Kotlin's UsbMassStorageDevice).
//
// The callbacks are lseek(2)/read(2)/write(2)-shaped (position tracked
// internally), matching dis_virtual_io_t's contract.

// kVhdx is distinct from kFile: kFile's vioRead/vioWrite do a flat pread/
// pwrite against fileBaseOffset + position, which is only valid when
// "byte N of the file" (past some fixed base offset) really is "byte N of
// the volume" -- true for a raw container or a fixed-format VHD's footer-
// excluded region, but NOT true for VHDX, where every byte of the volume
// is indirected through the BAT (see vhdx_image.h). kVhdx routes through
// VhdxImage::pread/pwrite instead, which do that translation.
//
// kVhd is the same idea for a legacy *dynamic* VHD (see vhd_image.h) --
// distinct from kVhdx only in which translator (VhdImage vs. VhdxImage) it
// routes through; a fixed-format VHD still goes through kFile, same as
// today, since it needs no translation at all.
enum class IoKind { kFile, kUsb, kVhdx, kVhd };

struct IoContext {
    IoKind kind;

    // File-backed (kFile only):
    int fd = -1;
    // Byte offset within the file where the BitLocker volume actually
    // starts -- 0 for a raw single-volume container file, or a partition's
    // start offset when the file is a whole-disk image (e.g. a
    // fixed-format VHD) that dislocker sees as if it were its own file.
    uint64_t fileBaseOffset = 0;

    // USB-backed:
    int volId = -1;
    uint64_t partitionStartSector = 0;
    uint64_t partitionSizeBytes = 0;

    // VHDX-backed (kVhdx only): the BitLocker volume lives inside a
    // partition of the VHDX's *virtual* disk, at partitionStartByte
    // (analogous to fileBaseOffset for the plain-file case, but every
    // read/write of it still has to go through the BAT). Owned by this
    // IoContext -- freed alongside it in bitlockerCloseVolume().
    VhdxImage* vhdx = nullptr;
    uint64_t vhdxPartitionStartByte = 0;

    // Legacy dynamic-VHD-backed (kVhd only): same idea as the VHDX fields
    // above, just routed through VhdImage instead. Owned by this IoContext
    // -- freed alongside it in bitlockerCloseVolume().
    VhdImage* vhd = nullptr;
    uint64_t vhdPartitionStartByte = 0;

    // Tracked current position (lseek-shaped contract).
    int64_t position = 0;
    // Total size for SEEK_END.
    uint64_t totalSize = 0;
};

// ── USB byte-level helpers (mirrors session_prepare.cpp's approach) ─────

bool usbReadBytes(int volId, uint64_t byteOffset, void* outData, size_t len) {
    if (len == 0) return true;
    const uint64_t startSector = byteOffset / 512;
    const uint64_t endSector = (byteOffset + len + 511) / 512;
    const uint32_t sectorCount = static_cast<uint32_t>(endSector - startSector);
    std::vector<unsigned char> buf(static_cast<size_t>(sectorCount) * 512);
    if (!usbReadSectors(volId, startSector, sectorCount, buf.data())) return false;
    const size_t innerOffset = static_cast<size_t>(byteOffset - startSector * 512);
    std::memcpy(outData, buf.data() + innerOffset, len);
    return true;
}

bool usbWriteBytes(int volId, uint64_t byteOffset, const void* inData, size_t len) {
    if (len == 0) return true;
    const uint64_t startSector = byteOffset / 512;
    const uint64_t endSector = (byteOffset + len + 511) / 512;
    const uint32_t sectorCount = static_cast<uint32_t>(endSector - startSector);
    std::vector<unsigned char> buf(static_cast<size_t>(sectorCount) * 512);
    // Read-modify-write for partial sectors.
    if (!usbReadSectors(volId, startSector, sectorCount, buf.data())) return false;
    const size_t innerOffset = static_cast<size_t>(byteOffset - startSector * 512);
    std::memcpy(buf.data() + innerOffset, inData, len);
    return usbWriteSectors(volId, startSector, sectorCount, buf.data());
}

// ── dis_virtual_io_t callback implementations ───────────────────────────

ssize_t vioRead(void* user_data, uint8_t* buffer, size_t size) {
    auto* ctx = static_cast<IoContext*>(user_data);
    if (ctx->kind == IoKind::kFile) {
        const ssize_t n = pread(ctx->fd, buffer, size, static_cast<off_t>(ctx->fileBaseOffset + ctx->position));
        if (n < 0) return -1;
        ctx->position += n;
        return n;
    }
    if (ctx->kind == IoKind::kVhdx) {
        const uint64_t virtualOffset = ctx->vhdxPartitionStartByte + static_cast<uint64_t>(ctx->position);
        if (!ctx->vhdx->pread(virtualOffset, buffer, size)) return -1;
        ctx->position += static_cast<int64_t>(size);
        return static_cast<ssize_t>(size);
    }
    if (ctx->kind == IoKind::kVhd) {
        const uint64_t virtualOffset = ctx->vhdPartitionStartByte + static_cast<uint64_t>(ctx->position);
        if (!ctx->vhd->pread(virtualOffset, buffer, size)) return -1;
        ctx->position += static_cast<int64_t>(size);
        return static_cast<ssize_t>(size);
    }
    // USB path
    const uint64_t absOffset = ctx->partitionStartSector * 512ULL + static_cast<uint64_t>(ctx->position);
    if (!usbReadBytes(ctx->volId, absOffset, buffer, size)) return -1;
    ctx->position += static_cast<int64_t>(size);
    return static_cast<ssize_t>(size);
}

ssize_t vioWrite(void* user_data, const uint8_t* buffer, size_t size) {
    auto* ctx = static_cast<IoContext*>(user_data);
    if (ctx->kind == IoKind::kFile) {
        const ssize_t n = pwrite(ctx->fd, buffer, size, static_cast<off_t>(ctx->fileBaseOffset + ctx->position));
        if (n < 0) return -1;
        ctx->position += n;
        return n;
    }
    if (ctx->kind == IoKind::kVhdx) {
        const uint64_t virtualOffset = ctx->vhdxPartitionStartByte + static_cast<uint64_t>(ctx->position);
        if (!ctx->vhdx->pwrite(virtualOffset, buffer, size)) return -1;
        ctx->position += static_cast<int64_t>(size);
        return static_cast<ssize_t>(size);
    }
    if (ctx->kind == IoKind::kVhd) {
        const uint64_t virtualOffset = ctx->vhdPartitionStartByte + static_cast<uint64_t>(ctx->position);
        if (!ctx->vhd->pwrite(virtualOffset, buffer, size)) return -1;
        ctx->position += static_cast<int64_t>(size);
        return static_cast<ssize_t>(size);
    }
    // USB path
    const uint64_t absOffset = ctx->partitionStartSector * 512ULL + static_cast<uint64_t>(ctx->position);
    if (!usbWriteBytes(ctx->volId, absOffset, buffer, size)) return -1;
    ctx->position += static_cast<int64_t>(size);
    return static_cast<ssize_t>(size);
}

off_t vioSeek(void* user_data, off_t offset, int whence) {
    auto* ctx = static_cast<IoContext*>(user_data);
    int64_t newPos;
    switch (whence) {
        case SEEK_SET: newPos = offset; break;
        case SEEK_CUR: newPos = ctx->position + offset; break;
        case SEEK_END: newPos = static_cast<int64_t>(ctx->totalSize) + offset; break;
        default: return static_cast<off_t>(-1);
    }
    if (newPos < 0) return static_cast<off_t>(-1);
    ctx->position = newPos;
    return static_cast<off_t>(newPos);
}

int vioClose(void* /*user_data*/) {
    // IoContext lifetime is managed by bitlocker_backend.cpp, not dislocker.
    // The close callback is called by dis_destroy() -- we don't free anything
    // here because the IoContext may outlive the dis_context_t slightly
    // (cleaned up in bitlockerCloseVolume).
    return 0;
}

// ── BitLocker FVE signature check ───────────────────────────────────────
//
// Dislocker has no cheap signature-only probe separate from a full
// credentialed unlock (dis_initialize). We hand-roll a FVE metadata
// signature check: the BitLocker volume header contains "-FVE-FS-" at
// byte offset 3, or "MSWIN4.1" (BitLocker To Go) at offset 3.

static const uint8_t kFveSig[] = { '-','F','V','E','-','F','S','-' };
static const uint8_t kBtgSig[] = { 'M','S','W','I','N','4','.','1' };
constexpr size_t kSigOffset = 3;
constexpr size_t kSigLen = 8;
constexpr size_t kProbeReadLen = kSigOffset + kSigLen; // 11 bytes

bool checkFveSignature(const uint8_t* header) {
    return std::memcmp(header + kSigOffset, kFveSig, kSigLen) == 0 ||
           std::memcmp(header + kSigOffset, kBtgSig, kSigLen) == 0;
}

// ── Credential handling ─────────────────────────────────────────────────

// Recognizes the 48-digit BitLocker recovery key regardless of how the
// user typed it (with or without the usual dash-separated groups-of-6),
// and re-renders it into the canonical "123456-123456-...-123456" (8
// groups of 6 digits) shape dislocker expects.
bool tryNormalizeRecoveryKey(const unsigned char* input, size_t inputLen, std::string* out) {
    std::string digitsOnly;
    digitsOnly.reserve(48);
    for (size_t i = 0; i < inputLen; i++) {
        const unsigned char c = input[i];
        if (c >= '0' && c <= '9') {
            digitsOnly.push_back(static_cast<char>(c));
        } else if (c == '-' || c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            continue;
        } else {
            return false;
        }
    }
    if (digitsOnly.size() != 48) return false;

    std::string grouped;
    grouped.reserve(48 + 7);
    for (size_t i = 0; i < 48; i++) {
        if (i > 0 && i % 6 == 0) grouped.push_back('-');
        grouped.push_back(digitsOnly[i]);
    }
    *out = grouped;
    return true;
}

// Tries to unlock a BitLocker volume with a given credential using dislocker.
// On success, *outCtx is a fully initialized dis_context_t ready for
// dislock()/enlock(). On failure, everything is cleaned up.
bool tryDislockerUnlock(IoContext* ioCtx, bool asRecoveryKey,
                        const unsigned char* credential, size_t credentialLen,
                        bool readOnly, dis_context_t* outCtx) {
    dis_context_t ctx = dis_new();
    if (!ctx) {
        LOGI("tryDislockerUnlock: dis_new() failed");
        return false;
    }

    // Set up the virtual I/O backend.
    dis_virtual_io_t vio{};
    vio.read  = vioRead;
    vio.write = vioWrite;
    vio.seek  = vioSeek;
    vio.close = vioClose;
    vio.user_data = ioCtx;
    dis_setopt(ctx, DIS_OPT_SET_VIRTUAL_IO, &vio);

    // Set credential.
    if (asRecoveryKey) {
        int useRp = 1;
        dis_setopt(ctx, DIS_OPT_USE_RECOVERY_PASSWORD, &useRp);
        dis_setopt(ctx, DIS_OPT_SET_RECOVERY_PASSWORD, credential);
    } else {
        int useUp = 1;
        dis_setopt(ctx, DIS_OPT_USE_USER_PASSWORD, &useUp);
        dis_setopt(ctx, DIS_OPT_SET_USER_PASSWORD, credential);
    }

    if (readOnly) {
        int ro = 1;
        dis_setopt(ctx, DIS_OPT_READ_ONLY, &ro);
    }

    // Skip the volume-state check -- Android can't check Windows dirty bits
    // meaningfully, and the user explicitly chose to unlock.
    int skipCheck = 1;
    dis_setopt(ctx, DIS_OPT_DONT_CHECK_VOLUME_STATE, &skipCheck);

    // Initialize (reads metadata, derives FVEK, unlocks).
    const int ret = dis_initialize(ctx);
    if (ret != 0) {
        LOGI("tryDislockerUnlock: dis_initialize() returned %d (asRecovery=%d)", ret, asRecoveryKey ? 1 : 0);
        // Do NOT call dis_destroy(ctx) here, because dis_initialize() cleans it up internally on failure
        return false;
    }

    LOGI("tryDislockerUnlock: success (asRecovery=%d)", asRecoveryKey ? 1 : 0);
    *outCtx = ctx;
    return true;
}

// Auto-detect credential type and try both, same strategy as VeraCrypt's
// cipher/hash cascade auto-try.
bool unlockWithBestCredentialGuess(IoContext* ioCtx,
                                   const unsigned char* password, size_t passwordLen,
                                   int volId, bool readOnly,
                                   dis_context_t* outCtx) {
    std::string recoveryCandidate;
    const bool looksLikeRecoveryKey = tryNormalizeRecoveryKey(password, passwordLen, &recoveryCandidate);
    const int fmt = static_cast<int>(ContainerFormat::kBitLocker);

    if (looksLikeRecoveryKey) {
        reportUnlockProgress(volId, 1, 2, 255, 255, fmt, 0);
        if (tryDislockerUnlock(ioCtx, /*asRecoveryKey=*/true,
                               reinterpret_cast<const unsigned char*>(recoveryCandidate.data()),
                               recoveryCandidate.size(), readOnly, outCtx)) {
            return true;
        }
        if (isUnlockCancelled(volId)) return false;
        reportUnlockProgress(volId, 2, 2, 255, 255, fmt, 0);
        return tryDislockerUnlock(ioCtx, /*asRecoveryKey=*/false, password, passwordLen, readOnly, outCtx);
    }

    reportUnlockProgress(volId, 1, 1, 255, 255, fmt, 0);
    return tryDislockerUnlock(ioCtx, /*asRecoveryKey=*/false, password, passwordLen, readOnly, outCtx);
}

} // namespace

// ────────────────────────────────────────────────────────────────────────
// Public API (declared in bitlocker_backend.h)
// ────────────────────────────────────────────────────────────────────────

bool bitlockerDetectFile(int fd, uint64_t byteOffset) {
    if (fd < 0) return false;
    uint8_t header[kProbeReadLen];
    const ssize_t n = pread(fd, header, sizeof(header), static_cast<off_t>(byteOffset));
    if (n < static_cast<ssize_t>(sizeof(header))) return false;
    return checkFveSignature(header);
}

bool bitlockerDetectUsb(int volId, uint64_t partitionStartSector) {
    uint8_t header[kProbeReadLen];
    if (!usbReadBytes(volId, partitionStartSector * 512, header, sizeof(header))) return false;
    return checkFveSignature(header);
}

bool prepareBitLockerSession(int fd, const unsigned char* password, size_t passwordLen,
                             int volId, bool readOnly,
                             uint64_t partitionStartByte, uint64_t partitionSizeBytes) {
    if (volId < 0 || volId >= FF_VOLUMES) { if (fd >= 0) close(fd); return false; }
    if (fd < 0) return false;

    VolumeState& v = volumes[volId];

    uint64_t fileSize = 0;
    struct stat st{};
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    // partitionSizeBytes == 0 means "the whole file is the volume" (the
    // original, pre-VHD-support behavior for a raw single-volume container
    // file) -- use whatever's left of the file past partitionStartByte.
    const uint64_t volumeSizeBytes = partitionSizeBytes != 0
        ? partitionSizeBytes
        : (fileSize > partitionStartByte ? fileSize - partitionStartByte : 0);

    // Create the virtual I/O context for this file fd, anchored at the
    // partition's start offset so dislocker's own 0-based positions map to
    // the right absolute bytes in the file (see vioRead/vioWrite).
    auto* ioCtx = new IoContext();
    ioCtx->kind = IoKind::kFile;
    ioCtx->fd = fd;
    ioCtx->fileBaseOffset = partitionStartByte;
    ioCtx->totalSize = volumeSizeBytes;

    dis_context_t disCtx = nullptr;
    if (!unlockWithBestCredentialGuess(ioCtx, password, passwordLen, volId, readOnly, &disCtx)) {
        delete ioCtx;
        close(fd);
        LOGI("prepareBitLockerSession(vol=%d): unlock failed (wrong password/recovery key)", volId);
        return false;
    }

    // Determine plaintext volume size. dislocker exposes this through
    // the volume header metadata; we can probe by seeking to end.
    // For now, use the partition/file size as an upper bound -- dislock()
    // handles the actual encrypted-region bounds internally.
    const uint64_t plainSize = volumeSizeBytes;

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.fd = fd;
        v.dataOffset = 0;
        v.dataAreaLengthBytes = plainSize;
        v.isHiddenVolume = false;
        v.fileSize = fileSize;
        v.isUsbSource = false;
        v.readOnly = readOnly;
        v.partitionStartSector = partitionStartByte / 512;
        v.matchedCipherId = -1;
        v.matchedHashId = -1;
        v.containerFormat = ContainerFormat::kBitLocker;
        v.dataCtxInitialized = true;
        v.disContext = static_cast<void*>(disCtx);
        v.bitlockerProxyFd = -1; // no separate proxy fd needed for file-backed
        v.bitlockerIoCtx = static_cast<void*>(ioCtx);
    }

    LOGI("prepareBitLockerSession(vol=%d): unlocked, partitionStartByte=%llu, volumeSize=%llu, readOnly=%d",
         volId, (unsigned long long)partitionStartByte, (unsigned long long)volumeSizeBytes, readOnly ? 1 : 0);
    return true;
}

bool prepareBitLockerSessionVhdx(int fd, const unsigned char* password, size_t passwordLen,
                                 int volId, bool readOnly,
                                 uint64_t partitionStartByte, uint64_t partitionSizeBytes) {
    if (volId < 0 || volId >= FF_VOLUMES) { if (fd >= 0) close(fd); return false; }
    if (fd < 0) return false;

    VolumeState& v = volumes[volId];

    auto* vhdx = new VhdxImage();
    if (!vhdx->open(fd, /*requestReadWrite=*/!readOnly)) {
        LOGI("prepareBitLockerSessionVhdx(vol=%d): VhdxImage::open failed: %s", volId, vhdx->lastError());
        delete vhdx;
        close(fd);
        return false;
    }
    // open() can silently force read-only (pending log replay) even when
    // the caller asked for read-write -- honor whatever it actually granted
    // rather than what was requested, same as dislocker's own DIS_OPT_READ_ONLY
    // reflects the caller's ask but the volume's own state can still block writes.
    const bool actualReadOnly = readOnly || vhdx->isReadOnly();

    uint64_t fileSize = 0;
    struct stat st{};
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    const uint64_t volumeSizeBytes = partitionSizeBytes != 0
        ? partitionSizeBytes
        : (vhdx->virtualDiskSize() > partitionStartByte ? vhdx->virtualDiskSize() - partitionStartByte : 0);

    auto* ioCtx = new IoContext();
    ioCtx->kind = IoKind::kVhdx;
    ioCtx->fd = fd; // kept only so bitlockerCloseVolume-adjacent bookkeeping
                     // has it available if ever needed; vioRead/vioWrite for
                     // kVhdx go through ioCtx->vhdx, not ioCtx->fd directly.
    ioCtx->vhdx = vhdx;
    ioCtx->vhdxPartitionStartByte = partitionStartByte;
    ioCtx->totalSize = volumeSizeBytes;

    dis_context_t disCtx = nullptr;
    if (!unlockWithBestCredentialGuess(ioCtx, password, passwordLen, volId, actualReadOnly, &disCtx)) {
        delete ioCtx->vhdx;
        delete ioCtx;
        close(fd);
        LOGI("prepareBitLockerSessionVhdx(vol=%d): unlock failed (wrong password/recovery key)", volId);
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.fd = fd;
        v.dataOffset = 0;
        v.dataAreaLengthBytes = volumeSizeBytes;
        v.isHiddenVolume = false;
        v.fileSize = fileSize;
        v.isUsbSource = false;
        v.readOnly = actualReadOnly;
        v.partitionStartSector = partitionStartByte / 512;
        v.matchedCipherId = -1;
        v.matchedHashId = -1;
        v.containerFormat = ContainerFormat::kBitLocker;
        v.dataCtxInitialized = true;
        v.disContext = static_cast<void*>(disCtx);
        v.bitlockerProxyFd = -1;
        v.bitlockerIoCtx = static_cast<void*>(ioCtx);
    }

    LOGI("prepareBitLockerSessionVhdx(vol=%d): unlocked, partitionStartByte=%llu, volumeSize=%llu, readOnly=%d",
         volId, (unsigned long long)partitionStartByte, (unsigned long long)volumeSizeBytes, actualReadOnly ? 1 : 0);
    return true;
}

bool prepareBitLockerSessionVhd(int fd, const unsigned char* password, size_t passwordLen,
                                int volId, bool readOnly,
                                uint64_t partitionStartByte, uint64_t partitionSizeBytes) {
    if (volId < 0 || volId >= FF_VOLUMES) { if (fd >= 0) close(fd); return false; }
    if (fd < 0) return false;

    VolumeState& v = volumes[volId];

    uint64_t fileSize = 0;
    struct stat st{};
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    auto* vhd = new VhdImage();
    if (!vhd->open(fd, fileSize, /*requestReadWrite=*/!readOnly)) {
        LOGI("prepareBitLockerSessionVhd(vol=%d): VhdImage::open failed: %s", volId, vhd->lastError());
        delete vhd;
        close(fd);
        return false;
    }
    // Unlike VhdxImage, VhdImage has no "pending log replay" concept that
    // can silently force read-only -- whatever the caller asked for is
    // exactly what they get.

    const uint64_t volumeSizeBytes = partitionSizeBytes != 0
        ? partitionSizeBytes
        : (vhd->virtualDiskSize() > partitionStartByte ? vhd->virtualDiskSize() - partitionStartByte : 0);

    auto* ioCtx = new IoContext();
    ioCtx->kind = IoKind::kVhd;
    ioCtx->fd = fd; // kept only so bitlockerCloseVolume-adjacent bookkeeping
                     // has it available if ever needed; vioRead/vioWrite for
                     // kVhd go through ioCtx->vhd, not ioCtx->fd directly.
    ioCtx->vhd = vhd;
    ioCtx->vhdPartitionStartByte = partitionStartByte;
    ioCtx->totalSize = volumeSizeBytes;

    dis_context_t disCtx = nullptr;
    if (!unlockWithBestCredentialGuess(ioCtx, password, passwordLen, volId, readOnly, &disCtx)) {
        delete ioCtx->vhd;
        delete ioCtx;
        close(fd);
        LOGI("prepareBitLockerSessionVhd(vol=%d): unlock failed (wrong password/recovery key)", volId);
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.fd = fd;
        v.dataOffset = 0;
        v.dataAreaLengthBytes = volumeSizeBytes;
        v.isHiddenVolume = false;
        v.fileSize = fileSize;
        v.isUsbSource = false;
        v.readOnly = readOnly;
        v.partitionStartSector = partitionStartByte / 512;
        v.matchedCipherId = -1;
        v.matchedHashId = -1;
        v.containerFormat = ContainerFormat::kBitLocker;
        v.dataCtxInitialized = true;
        v.disContext = static_cast<void*>(disCtx);
        v.bitlockerProxyFd = -1;
        v.bitlockerIoCtx = static_cast<void*>(ioCtx);
    }

    LOGI("prepareBitLockerSessionVhd(vol=%d): unlocked, partitionStartByte=%llu, volumeSize=%llu, readOnly=%d",
         volId, (unsigned long long)partitionStartByte, (unsigned long long)volumeSizeBytes, readOnly ? 1 : 0);
    return true;
}

bool prepareUsbBitLockerSession(uint64_t partitionStartSector, uint64_t partitionSizeBytes,
                                const unsigned char* password, size_t passwordLen,
                                int volId, bool readOnly) {
    if (volId < 0 || volId >= FF_VOLUMES) return false;
    VolumeState& v = volumes[volId];

    // Create the virtual I/O context for USB sector transport.
    auto* ioCtx = new IoContext();
    ioCtx->kind = IoKind::kUsb;
    ioCtx->volId = volId;
    ioCtx->partitionStartSector = partitionStartSector;
    ioCtx->partitionSizeBytes = partitionSizeBytes;
    ioCtx->totalSize = partitionSizeBytes;

    dis_context_t disCtx = nullptr;
    if (!unlockWithBestCredentialGuess(ioCtx, password, passwordLen, volId, readOnly, &disCtx)) {
        delete ioCtx;
        LOGI("prepareUsbBitLockerSession(vol=%d): unlock failed", volId);
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.isUsbSource = true;
        v.fd = -1;
        v.dataOffset = 0;
        v.dataAreaLengthBytes = partitionSizeBytes;
        v.isHiddenVolume = false;
        v.readOnly = readOnly;
        v.partitionStartSector = partitionStartSector;
        v.matchedCipherId = -1;
        v.matchedHashId = -1;
        v.containerFormat = ContainerFormat::kBitLocker;
        v.dataCtxInitialized = true;
        v.disContext = static_cast<void*>(disCtx);
        v.bitlockerProxyFd = -1;
        v.bitlockerIoCtx = static_cast<void*>(ioCtx);
    }

    LOGI("prepareUsbBitLockerSession(vol=%d): unlocked, partSize=%llu, readOnly=%d",
         volId, (unsigned long long)partitionSizeBytes, readOnly ? 1 : 0);
    return true;
}

bool bitlockerRead(int volumeId, uint64_t logicalOffset, unsigned char* outBuf, size_t byteCount) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    if (byteCount == 0) return true;
    VolumeState& v = volumes[volumeId];
    if (!v.disContext) return false;

    std::lock_guard<std::mutex> lock(v.ioBufMutex);
    auto* ctx = static_cast<dis_context_t>(v.disContext);
    const int ret = dislock(ctx, outBuf, static_cast<off_t>(logicalOffset), byteCount);
    return ret == static_cast<int>(byteCount);
}

bool bitlockerWrite(int volumeId, uint64_t logicalOffset, const unsigned char* inBuf, size_t byteCount) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    if (byteCount == 0) return true;
    VolumeState& v = volumes[volumeId];
    if (!v.disContext) return false;
    if (v.readOnly) return false;

    std::lock_guard<std::mutex> lock(v.ioBufMutex);
    auto* ctx = static_cast<dis_context_t>(v.disContext);
    // enlock() takes a non-const buffer because it encrypts in-place before
    // writing. We must copy to honour our const-correct API.
    std::vector<uint8_t> tmp(inBuf, inBuf + byteCount);
    const int ret = enlock(ctx, tmp.data(), static_cast<off_t>(logicalOffset), byteCount);
    return ret == static_cast<int>(byteCount);
}

void bitlockerCloseVolume(VolumeState& v) {
    if (v.disContext) {
        auto* ctx = static_cast<dis_context_t>(v.disContext);
        dis_destroy(ctx);
        v.disContext = nullptr;
    }
    // dis_destroy() calls vioClose (which deliberately doesn't free
    // anything -- see its doc comment) before returning, so it's safe to
    // free the IoContext ourselves right after. For a kVhdx/kVhd session
    // this also frees the VhdxImage/VhdImage it owns (BAT array and all),
    // since nothing else holds a reference to it.
    if (v.bitlockerIoCtx) {
        auto* ctx = static_cast<IoContext*>(v.bitlockerIoCtx);
        delete ctx->vhdx; // no-op if null (non-VHDX sessions)
        delete ctx->vhd;  // no-op if null (non-VHD sessions)
        delete ctx;
        v.bitlockerIoCtx = nullptr;
    }
    // For USB sessions, if we had a proxy fd, close it.
    if (v.bitlockerProxyFd >= 0) {
        close(v.bitlockerProxyFd);
        v.bitlockerProxyFd = -1;
    }
}