#include "vhd_image.h"

#include <cstring>
#include <memory>
#include <vector>

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_VHD", __VA_ARGS__)

namespace {

// ── On-disk constants ("Virtual Hard Disk Image Format Specification") ──
//
// NOTE: unlike vhdx_image.cpp, every multi-byte field below is BIG-ENDIAN.

static const unsigned char kFooterCookie[8] = { 'c','o','n','e','c','t','i','x' };
static const unsigned char kDynHeaderCookie[8] = { 'c','x','s','p','a','r','s','e' };

constexpr size_t kFooterSize = 512;
constexpr size_t kDynHeaderSize = 1024;

constexpr uint32_t kDiskTypeFixed = 2;
constexpr uint32_t kDiskTypeDynamic = 3;
constexpr uint32_t kDiskTypeDifferencing = 4;

constexpr uint32_t kBatUnallocated = 0xFFFFFFFFu;

uint32_t readU32BE(const unsigned char* p) {
    return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}
uint64_t readU64BE(const unsigned char* p) {
    return (static_cast<uint64_t>(readU32BE(p)) << 32) | static_cast<uint64_t>(readU32BE(p + 4));
}
void writeU32BE(unsigned char* p, uint32_t v) {
    p[0] = static_cast<unsigned char>((v >> 24) & 0xFF);
    p[1] = static_cast<unsigned char>((v >> 16) & 0xFF);
    p[2] = static_cast<unsigned char>((v >> 8) & 0xFF);
    p[3] = static_cast<unsigned char>(v & 0xFF);
}

} // namespace

VhdDiskKind probeVhdDiskKind(int fd, uint64_t fileSize) {
    if (fd < 0 || fileSize < kFooterSize) return VhdDiskKind::kNotVhd;
    unsigned char footer[kFooterSize];
    if (::pread(fd, footer, sizeof(footer), static_cast<off_t>(fileSize - kFooterSize)) !=
        static_cast<ssize_t>(sizeof(footer))) {
        return VhdDiskKind::kNotVhd;
    }
    if (std::memcmp(footer, kFooterCookie, sizeof(kFooterCookie)) != 0) return VhdDiskKind::kNotVhd;

    switch (readU32BE(footer + 60)) {
        case kDiskTypeFixed: return VhdDiskKind::kFixed;
        case kDiskTypeDynamic: return VhdDiskKind::kDynamic;
        case kDiskTypeDifferencing: return VhdDiskKind::kDifferencing;
        default: return VhdDiskKind::kNotVhd; // unrecognized type -- be conservative
    }
}

VhdImage::VhdImage() = default;

VhdImage::~VhdImage() {
    delete[] bat_;
    bat_ = nullptr;
}

bool VhdImage::open(int fd, uint64_t fileSize, bool requestReadWrite) {
    fd_ = fd;
    lastError_ = "";

    const VhdDiskKind kind = probeVhdDiskKind(fd, fileSize);
    if (kind == VhdDiskKind::kNotVhd) {
        lastError_ = "not a VHD file (missing 'conectix' footer signature)";
        return false;
    }
    if (kind == VhdDiskKind::kFixed) {
        lastError_ = "fixed-format VHD -- use the flat-file path instead of VhdImage";
        return false;
    }
    if (kind == VhdDiskKind::kDifferencing) {
        lastError_ = "differencing VHD (has a parent disk) is not supported";
        return false;
    }

    footerOffset_ = fileSize - kFooterSize;
    if (::pread(fd, footerBytes_, sizeof(footerBytes_), static_cast<off_t>(footerOffset_)) !=
        static_cast<ssize_t>(sizeof(footerBytes_))) {
        lastError_ = "failed to read VHD footer";
        return false;
    }

    // We don't verify the footer's 32-bit ones'-complement checksum: a
    // corrupt footer would also almost certainly fail the structural
    // checks below (bad cookie already ruled out above; implausible
    // block size / disk size next), and this app has no other need for a
    // ones'-complement checksum implementation -- same stance vhdx_image.cpp
    // takes on skipping VHDX's CRC-32C.
    virtualDiskSize_ = readU64BE(footerBytes_ + 48);
    const uint64_t dynHeaderOffset = readU64BE(footerBytes_ + 16);

    unsigned char dynHeader[kDynHeaderSize];
    if (::pread(fd, dynHeader, sizeof(dynHeader), static_cast<off_t>(dynHeaderOffset)) !=
        static_cast<ssize_t>(sizeof(dynHeader))) {
        lastError_ = "failed to read VHD dynamic disk header";
        return false;
    }
    if (std::memcmp(dynHeader, kDynHeaderCookie, sizeof(kDynHeaderCookie)) != 0) {
        lastError_ = "VHD dynamic disk header has bad signature";
        return false;
    }

    const uint64_t batOffset = readU64BE(dynHeader + 16);
    const uint32_t maxTableEntries = readU32BE(dynHeader + 28);
    blockSizeBytes_ = readU32BE(dynHeader + 32);

    if (virtualDiskSize_ == 0) {
        lastError_ = "VHD footer has implausible zero-valued virtual disk size";
        return false;
    }
    if (blockSizeBytes_ == 0 || (blockSizeBytes_ & (blockSizeBytes_ - 1)) != 0 ||
        blockSizeBytes_ % 512 != 0) {
        lastError_ = "VHD block size is not a nonzero, sector-aligned power of two";
        return false;
    }

    const uint64_t expectedEntries = (virtualDiskSize_ + blockSizeBytes_ - 1) / blockSizeBytes_;
    if (maxTableEntries < expectedEntries) {
        lastError_ = "VHD BAT has fewer entries than the virtual disk size requires";
        return false;
    }
    batEntryCount_ = maxTableEntries;
    batRegionOffset_ = batOffset;

    // Sector bitmap: 1 bit per 512-byte sector of a block, rounded up to a
    // 512-byte boundary (MS-VHD "Block Bitmap" section). For the default
    // 2MB block size this is exactly 512 bytes (4096 sectors -> 512 bits ->
    // 512 bytes, already sector-aligned).
    const uint32_t sectorsPerBlock = blockSizeBytes_ / 512;
    const uint32_t bitmapBits = (sectorsPerBlock + 7) / 8;
    bitmapSizeBytes_ = ((bitmapBits + 511) / 512) * 512;

    delete[] bat_;
    bat_ = new uint32_t[batEntryCount_];
    {
        std::unique_ptr<unsigned char[]> batBuf(new unsigned char[static_cast<size_t>(batEntryCount_) * 4]);
        if (::pread(fd, batBuf.get(), batEntryCount_ * 4, static_cast<off_t>(batOffset)) !=
            static_cast<ssize_t>(batEntryCount_ * 4)) {
            lastError_ = "failed to read VHD BAT";
            delete[] bat_;
            bat_ = nullptr;
            return false;
        }
        for (uint64_t i = 0; i < batEntryCount_; i++) {
            bat_[i] = readU32BE(batBuf.get() + i * 4);
        }
    }

    readOnly_ = !requestReadWrite;

    LOGI("VhdImage::open: ok, virtualDiskSize=%llu, blockSize=%u, bitmapSize=%u, "
         "batEntries=%llu, readOnly=%d",
         (unsigned long long)virtualDiskSize_, blockSizeBytes_, bitmapSizeBytes_,
         (unsigned long long)batEntryCount_, readOnly_ ? 1 : 0);
    return true;
}

bool VhdImage::resolveBlock(uint64_t blockIndex, bool allocateIfMissing,
                            uint64_t* outDataFileOffset, bool* outPresent) {
    *outDataFileOffset = 0;
    *outPresent = false;
    if (blockIndex >= batEntryCount_) return false;

    const uint32_t entry = bat_[blockIndex];
    if (entry != kBatUnallocated) {
        const uint64_t bitmapOffset = static_cast<uint64_t>(entry) * 512ULL;
        *outDataFileOffset = bitmapOffset + bitmapSizeBytes_;
        *outPresent = true;
        return true;
    }

    if (!allocateIfMissing) {
        *outPresent = false;
        return true; // not an error -- caller treats as all-zero
    }
    if (readOnly_) return false;

    // Allocate: append a new block (fully-1 sector bitmap + zero-filled
    // data) at the current footer's location, then re-write the footer --
    // byte-for-byte unmodified -- immediately after it. This mirrors how
    // real dynamic-VHD writers grow the file: the footer is always the
    // last 512 bytes, so growing means "insert before the footer, then
    // move the footer forward".
    const uint64_t newBitmapOffset = footerOffset_;
    if (newBitmapOffset % 512 != 0) return false; // should be unreachable; be conservative
    if (newBitmapOffset / 512 >= kBatUnallocated) return false; // would overflow the 32-bit BAT entry

    // All sectors of a freshly allocated block are marked "present" --
    // this matches real-world dynamic-VHD writers (see vhd_image.h's class
    // doc comment) and means our own subsequent reads see real zero-filled
    // data rather than following the spec's alternate "0 bit == treat as
    // zero" path for a block we know is genuinely all-zero anyway.
    {
        std::vector<unsigned char> bitmap(bitmapSizeBytes_, 0xFF);
        if (::pwrite(fd_, bitmap.data(), bitmap.size(), static_cast<off_t>(newBitmapOffset)) !=
            static_cast<ssize_t>(bitmap.size())) {
            return false;
        }
    }
    const uint64_t newDataOffset = newBitmapOffset + bitmapSizeBytes_;
    {
        std::vector<unsigned char> zeros(blockSizeBytes_, 0);
        if (::pwrite(fd_, zeros.data(), zeros.size(), static_cast<off_t>(newDataOffset)) !=
            static_cast<ssize_t>(zeros.size())) {
            return false;
        }
    }
    const uint64_t newFooterOffset = newDataOffset + blockSizeBytes_;
    if (::pwrite(fd_, footerBytes_, sizeof(footerBytes_), static_cast<off_t>(newFooterOffset)) !=
        static_cast<ssize_t>(sizeof(footerBytes_))) {
        return false;
    }
    footerOffset_ = newFooterOffset;

    // Persist the updated BAT entry immediately, same crash-safety
    // reasoning as VhdxImage::resolveBlock(): correctness over the small
    // extra I/O, rather than batching/deferring BAT writes.
    const uint32_t newEntry = static_cast<uint32_t>(newBitmapOffset / 512);
    bat_[blockIndex] = newEntry;
    {
        unsigned char entryBytes[4];
        writeU32BE(entryBytes, newEntry);
        if (::pwrite(fd_, entryBytes, 4, static_cast<off_t>(batRegionOffset_ + blockIndex * 4)) != 4) {
            return false;
        }
    }

    *outDataFileOffset = newDataOffset;
    *outPresent = true;
    return true;
}

bool VhdImage::pread(uint64_t virtualOffset, unsigned char* outBuf, size_t len) {
    if (len == 0) return true;
    if (virtualOffset + len > virtualDiskSize_) return false;

    size_t done = 0;
    while (done < len) {
        const uint64_t curVOffset = virtualOffset + done;
        const uint64_t blockIndex = curVOffset / blockSizeBytes_;
        const uint64_t inBlockOffset = curVOffset % blockSizeBytes_;
        const size_t blockChunk = static_cast<size_t>(
            std::min<uint64_t>(len - done, blockSizeBytes_ - inBlockOffset));

        uint64_t dataFileOffset = 0;
        bool present = false;
        if (!resolveBlock(blockIndex, /*allocateIfMissing=*/false, &dataFileOffset, &present)) {
            return false;
        }

        if (!present) {
            std::memset(outBuf + done, 0, blockChunk);
            done += blockChunk;
            continue;
        }

        // Load this block's sector bitmap once (rather than once per
        // 512-byte sector below) and keep the rest of this block's I/O to
        // in-memory bit checks.
        std::vector<unsigned char> bitmapBuf(bitmapSizeBytes_);
        if (::pread(fd_, bitmapBuf.data(), bitmapSizeBytes_,
                    static_cast<off_t>(dataFileOffset - bitmapSizeBytes_)) !=
            static_cast<ssize_t>(bitmapSizeBytes_)) {
            return false;
        }

        size_t subDone = 0;
        while (subDone < blockChunk) {
            const uint64_t curInBlock = inBlockOffset + subDone;
            const uint64_t sectorInBlock = curInBlock / 512;
            const uint64_t sectorInnerOffset = curInBlock % 512;
            const size_t sectorChunk = static_cast<size_t>(
                std::min<uint64_t>(blockChunk - subDone, 512 - sectorInnerOffset));

            const bool sectorPresent =
                (bitmapBuf[sectorInBlock / 8] & (0x80 >> (sectorInBlock % 8))) != 0;

            if (!sectorPresent) {
                std::memset(outBuf + done + subDone, 0, sectorChunk);
            } else {
                const uint64_t fileOffset = dataFileOffset + sectorInBlock * 512 + sectorInnerOffset;
                const ssize_t n = ::pread(fd_, outBuf + done + subDone, sectorChunk,
                                           static_cast<off_t>(fileOffset));
                if (n != static_cast<ssize_t>(sectorChunk)) return false;
            }
            subDone += sectorChunk;
        }
        done += blockChunk;
    }
    return true;
}

bool VhdImage::pwrite(uint64_t virtualOffset, const unsigned char* inBuf, size_t len) {
    if (len == 0) return true;
    if (readOnly_) return false;
    if (virtualOffset + len > virtualDiskSize_) return false;

    size_t done = 0;
    while (done < len) {
        const uint64_t curVOffset = virtualOffset + done;
        const uint64_t blockIndex = curVOffset / blockSizeBytes_;
        const uint64_t inBlockOffset = curVOffset % blockSizeBytes_;
        const size_t blockChunk = static_cast<size_t>(
            std::min<uint64_t>(len - done, blockSizeBytes_ - inBlockOffset));

        uint64_t dataFileOffset = 0;
        bool present = false;
        if (!resolveBlock(blockIndex, /*allocateIfMissing=*/true, &dataFileOffset, &present) || !present) {
            return false;
        }
        const uint64_t bitmapOffset = dataFileOffset - bitmapSizeBytes_;

        // Read-modify-write the sector bitmap: mark every sector this
        // write touches as present. Needed even though a freshly allocated
        // block already starts fully-1 (see resolveBlock()), because this
        // same block may have come from an existing BAT entry -- possibly
        // written by another tool -- with some sectors still marked 0.
        std::vector<unsigned char> bitmapBuf(bitmapSizeBytes_);
        if (::pread(fd_, bitmapBuf.data(), bitmapSizeBytes_, static_cast<off_t>(bitmapOffset)) !=
            static_cast<ssize_t>(bitmapSizeBytes_)) {
            return false;
        }
        const uint64_t firstSector = inBlockOffset / 512;
        const uint64_t lastSector = (inBlockOffset + blockChunk - 1) / 512;
        bool bitmapDirty = false;
        for (uint64_t s = firstSector; s <= lastSector; s++) {
            const unsigned char mask = static_cast<unsigned char>(0x80 >> (s % 8));
            if (!(bitmapBuf[s / 8] & mask)) {
                bitmapBuf[s / 8] |= mask;
                bitmapDirty = true;
            }
        }
        if (bitmapDirty) {
            if (::pwrite(fd_, bitmapBuf.data(), bitmapSizeBytes_, static_cast<off_t>(bitmapOffset)) !=
                static_cast<ssize_t>(bitmapSizeBytes_)) {
                return false;
            }
        }

        const ssize_t n = ::pwrite(fd_, inBuf + done, blockChunk,
                                    static_cast<off_t>(dataFileOffset + inBlockOffset));
        if (n != static_cast<ssize_t>(blockChunk)) return false;
        done += blockChunk;
    }
    return true;
}
