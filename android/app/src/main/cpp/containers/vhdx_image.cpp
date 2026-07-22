#include "vhdx_image.h"

#include <cstring>
#include <memory>
#include <vector>

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_VHDX", __VA_ARGS__)

namespace {

// ── On-disk constants (MS-VHDX / "VHDX Format Specification v1.00") ────

constexpr uint64_t kOneMiB = 1024ULL * 1024ULL;

constexpr uint64_t kHeader1Offset = 64 * 1024ULL;
constexpr uint64_t kHeader2Offset = 128 * 1024ULL;
constexpr uint64_t kRegionTable1Offset = 192 * 1024ULL;
constexpr uint64_t kRegionTable2Offset = 256 * 1024ULL;
constexpr size_t kHeaderStructSize = 4096;
constexpr size_t kRegionTableStructSize = 64 * 1024;

static const unsigned char kVhdxFileSig[8] = { 'v','h','d','x','f','i','l','e' };
static const unsigned char kHeadSig[4] = { 'h','e','a','d' };
static const unsigned char kRegiSig[4] = { 'r','e','g','i' };
static const unsigned char kMetadataSig[8] = { 'm','e','t','a','d','a','t','a' };

// Region table entry GUIDs (little-endian byte layout, as stored on disk --
// i.e. this is memcmp-ready against the 16 raw bytes, not a
// human-readable/hyphenated GUID string).
// BAT:      2DC27766-F623-4200-9D64-115E9BFD4A08
// Metadata: 8B7CA206-4790-4B9A-B8FE-575F050F886E
static const unsigned char kRegionGuidBat[16] = {
    0x66,0x77,0xc2,0x2d, 0x23,0xf6, 0x00,0x42,
    0x9d,0x64, 0x11,0x5e,0x9b,0xfd,0x4a,0x08
};
static const unsigned char kRegionGuidMetadata[16] = {
    0x06,0xa2,0x7c,0x8b, 0x90,0x47, 0x9a,0x4b,
    0xb8,0xfe, 0x57,0x5f,0x05,0x0f,0x88,0x6e
};

// Metadata item GUIDs we care about (again, raw on-disk byte layout).
// File Parameters:      CAA16737-FA36-4D43-B3B6-33F0AA44E76B
// Virtual Disk Size:    2FA54224-CD1B-4876-B211-5DBED83BF4B8
// Logical Sector Size:  8141BF1D-A96F-4709-BA47-F233A8FAAB5F
static const unsigned char kMetaGuidFileParams[16] = {
    0x37,0x67,0xa1,0xca, 0x36,0xfa, 0x43,0x4d,
    0xb3,0xb6, 0x33,0xf0,0xaa,0x44,0xe7,0x6b
};
static const unsigned char kMetaGuidVirtualDiskSize[16] = {
    0x24,0x42,0xa5,0x2f, 0x1b,0xcd, 0x76,0x48,
    0xb2,0x11, 0x5d,0xbe,0xd8,0x3b,0xf4,0xb8
};
static const unsigned char kMetaGuidLogicalSectorSize[16] = {
    0x1d,0xbf,0x41,0x81, 0x6f,0xa9, 0x09,0x47,
    0xba,0x47, 0xf2,0x33,0xa8,0xfa,0xab,0x5f
};

// BAT entry: upper 44 bits (bits 63:20) = file offset in 1MB units,
// bits 19:6 reserved, bits 5:3 reserved (differencing only), bits 2:0 = state.
// (We only need the state (bits 2:0) and the FileOffsetMB (bits 63:20) --
// the differencing-only bits in between are irrelevant since we reject
// differencing images before ever reading a payload BAT entry's bits.)
constexpr uint64_t kBatStateMask = 0x7ULL;
constexpr uint64_t kBatFileOffsetMask = 0xFFFFFFFFFFF00000ULL;

constexpr uint64_t kPayloadBlockNotPresent = 0;
constexpr uint64_t kPayloadBlockUndefined = 1;
constexpr uint64_t kPayloadBlockZero = 2;
constexpr uint64_t kPayloadBlockUnmapped = 3;
constexpr uint64_t kPayloadBlockFullyPresent = 6;
constexpr uint64_t kPayloadBlockPartiallyPresent = 7;

uint32_t readU32LE(const unsigned char* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
uint64_t readU64LE(const unsigned char* p) {
    uint64_t lo = readU32LE(p);
    uint64_t hi = readU32LE(p + 4);
    return lo | (hi << 32);
}

bool isAllZeroGuid(const unsigned char* g) {
    for (int i = 0; i < 16; i++) if (g[i] != 0) return false;
    return true;
}

struct RegionTableEntry {
    unsigned char guid[16];
    uint64_t fileOffset;
    uint32_t length;
    bool required;
};

struct MetadataTableEntry {
    unsigned char itemId[16];
    uint32_t offsetWithinRegion;
    uint32_t length;
    bool isVirtualDisk; // vs. file metadata -- irrelevant to us, kept for completeness
};

} // namespace

VhdxImage::VhdxImage() = default;

VhdxImage::~VhdxImage() {
    delete[] bat_;
    bat_ = nullptr;
}

bool VhdxImage::detect(int fd) {
    if (fd < 0) return false;
    unsigned char sig[8];
    if (::pread(fd, sig, sizeof(sig), 0) != static_cast<ssize_t>(sizeof(sig))) return false;
    return std::memcmp(sig, kVhdxFileSig, sizeof(kVhdxFileSig)) == 0;
}

bool isVhdxContainer(int fd) {
    return VhdxImage::detect(fd);
}

bool VhdxImage::open(int fd, bool requestReadWrite) {
    fd_ = fd;
    lastError_ = "";

    if (!detect(fd)) {
        lastError_ = "not a VHDX file (missing 'vhdxfile' signature)";
        return false;
    }

    // ── Header: find whichever of the two copies is valid, prefer the
    // higher SequenceNumber if both are (matches spec guidance -- the
    // "current" header is the structurally valid one with the highest
    // sequence number). We don't verify the CRC-32C checksum: a corrupt
    // header would also almost certainly fail the structural checks below
    // (bad Version, implausible LogLength/Offset), and CRC-32C isn't
    // otherwise needed by this app (unlike dislocker/NTFS-3G, we have
    // nothing else that already carries a CRC-32C implementation).
    struct ParsedHeader {
        bool valid = false;
        uint64_t sequenceNumber = 0;
        bool hasLog = false; // LogGuid != 0 -- pending replay
    };
    auto parseHeaderAt = [&](uint64_t offset) -> ParsedHeader {
        ParsedHeader h;
        unsigned char buf[kHeaderStructSize];
        if (::pread(fd, buf, sizeof(buf), static_cast<off_t>(offset)) != static_cast<ssize_t>(sizeof(buf))) {
            return h;
        }
        if (std::memcmp(buf, kHeadSig, 4) != 0) return h;
        const uint16_t version = static_cast<uint16_t>(buf[0x42] | (buf[0x43] << 8));
        if (version != 1) return h;
        h.valid = true;
        h.sequenceNumber = readU64LE(buf + 8);
        const unsigned char* logGuid = buf + 0x30;
        h.hasLog = !isAllZeroGuid(logGuid);
        return h;
    };

    ParsedHeader h1 = parseHeaderAt(kHeader1Offset);
    ParsedHeader h2 = parseHeaderAt(kHeader2Offset);
    if (!h1.valid && !h2.valid) {
        lastError_ = "no valid VHDX header (both copies corrupt or unsupported version)";
        return false;
    }
    const ParsedHeader& active = (h1.valid && (!h2.valid || h1.sequenceNumber >= h2.sequenceNumber)) ? h1 : h2;

    const bool pendingLogReplay = active.hasLog;

    // ── Region table: same current-copy selection as the header. ──
    struct ParsedRegionTable {
        bool valid = false;
        std::vector<RegionTableEntry> entries;
    };
    auto parseRegionTableAt = [&](uint64_t offset) -> ParsedRegionTable {
        ParsedRegionTable rt;
        std::unique_ptr<unsigned char[]> buf(new unsigned char[kRegionTableStructSize]);
        if (::pread(fd, buf.get(), kRegionTableStructSize, static_cast<off_t>(offset)) !=
            static_cast<ssize_t>(kRegionTableStructSize)) {
            return rt;
        }
        if (std::memcmp(buf.get(), kRegiSig, 4) != 0) return rt;
        const uint32_t entryCount = readU32LE(buf.get() + 8);
        // Header (16 bytes) + entryCount * 32-byte entries must fit within
        // the 64KB structure; spec caps entryCount at 2047.
        if (entryCount > 2047) return rt;
        for (uint32_t i = 0; i < entryCount; i++) {
            const unsigned char* e = buf.get() + 16 + static_cast<size_t>(i) * 32;
            RegionTableEntry entry{};
            std::memcpy(entry.guid, e, 16);
            entry.fileOffset = readU64LE(e + 16);
            entry.length = readU32LE(e + 24);
            entry.required = (readU32LE(e + 28) & 0x1) != 0;
            rt.entries.push_back(entry);
        }
        rt.valid = true;
        return rt;
    };

    ParsedRegionTable rt1 = parseRegionTableAt(kRegionTable1Offset);
    ParsedRegionTable rt2 = parseRegionTableAt(kRegionTable2Offset);
    const ParsedRegionTable& regionTable = rt1.valid ? rt1 : rt2;
    if (!regionTable.valid) {
        lastError_ = "no valid VHDX region table";
        return false;
    }

    const RegionTableEntry* batRegion = nullptr;
    const RegionTableEntry* metadataRegion = nullptr;
    for (const auto& e : regionTable.entries) {
        if (std::memcmp(e.guid, kRegionGuidBat, 16) == 0) batRegion = &e;
        else if (std::memcmp(e.guid, kRegionGuidMetadata, 16) == 0) metadataRegion = &e;
        else if (e.required) {
            // An unrecognized region we don't understand but which the file
            // says is mandatory to open it correctly -- per spec, we must
            // refuse rather than guess.
            lastError_ = "VHDX file requires an unrecognized region";
            return false;
        }
    }
    if (!batRegion || !metadataRegion) {
        lastError_ = "VHDX file missing required BAT or metadata region";
        return false;
    }

    // ── Metadata region: pull File Parameters, Virtual Disk Size, Logical
    // Sector Size. (Physical Sector Size / Page83Data aren't needed for
    // read/write translation.) ──
    std::unique_ptr<unsigned char[]> metaBuf(new unsigned char[metadataRegion->length]);
    if (::pread(fd, metaBuf.get(), metadataRegion->length,
                static_cast<off_t>(metadataRegion->fileOffset)) != static_cast<ssize_t>(metadataRegion->length)) {
        lastError_ = "failed to read VHDX metadata region";
        return false;
    }
    if (std::memcmp(metaBuf.get(), kMetadataSig, 8) != 0) {
        lastError_ = "VHDX metadata region has bad signature";
        return false;
    }
    const uint16_t metaEntryCount = static_cast<uint16_t>(metaBuf[10] | (metaBuf[11] << 8));

    const unsigned char* fileParamsBytes = nullptr;
    const unsigned char* virtualDiskSizeBytes = nullptr;
    const unsigned char* logicalSectorSizeBytes = nullptr;

    for (uint16_t i = 0; i < metaEntryCount; i++) {
        const unsigned char* e = metaBuf.get() + 32 + static_cast<size_t>(i) * 32;
        const unsigned char* itemId = e;
        const uint32_t offsetWithinRegion = readU32LE(e + 16);
        const uint32_t length = readU32LE(e + 20);
        if (static_cast<uint64_t>(offsetWithinRegion) + length > metadataRegion->length) continue;
        const unsigned char* valuePtr = metaBuf.get() + offsetWithinRegion;

        if (std::memcmp(itemId, kMetaGuidFileParams, 16) == 0 && length >= 8) {
            fileParamsBytes = valuePtr;
        } else if (std::memcmp(itemId, kMetaGuidVirtualDiskSize, 16) == 0 && length >= 8) {
            virtualDiskSizeBytes = valuePtr;
        } else if (std::memcmp(itemId, kMetaGuidLogicalSectorSize, 16) == 0 && length >= 4) {
            logicalSectorSizeBytes = valuePtr;
        }
    }

    if (!fileParamsBytes || !virtualDiskSizeBytes || !logicalSectorSizeBytes) {
        lastError_ = "VHDX metadata missing a required item (File Parameters / Virtual Disk Size / Logical Sector Size)";
        return false;
    }

    blockSizeBytes_ = readU32LE(fileParamsBytes);
    const uint32_t fileParamsFlags = readU32LE(fileParamsBytes + 4);
    const bool hasParent = (fileParamsFlags & 0x2) != 0; // bit 1 = has_parent
    virtualDiskSize_ = readU64LE(virtualDiskSizeBytes);
    logicalSectorSize_ = readU32LE(logicalSectorSizeBytes);

    if (hasParent) {
        lastError_ = "differencing VHDX (has a parent disk) is not supported";
        return false;
    }
    if (blockSizeBytes_ == 0 || logicalSectorSize_ == 0 || virtualDiskSize_ == 0) {
        lastError_ = "VHDX metadata has implausible zero-valued size fields";
        return false;
    }
    // Sanity bounds per spec: block size is a power of two in [1MB, 256MB];
    // logical sector size is 512 or 4096.
    if (blockSizeBytes_ < kOneMiB || blockSizeBytes_ > 256 * kOneMiB ||
        (blockSizeBytes_ & (blockSizeBytes_ - 1)) != 0) {
        lastError_ = "VHDX block size out of spec range";
        return false;
    }
    if (logicalSectorSize_ != 512 && logicalSectorSize_ != 4096) {
        lastError_ = "VHDX logical sector size not 512 or 4096";
        return false;
    }

    isDynamic_ = true; // fixed vs. dynamic doesn't change BAT-based addressing;
                        // "fixed" VHDX still goes through the BAT, it's just
                        // that every payload block happens to already be
                        // FULLY_PRESENT. We don't need to distinguish the two
                        // for read/write purposes.

    // Chunk ratio: number of payload-block BAT entries between each
    // interleaved sector-bitmap BAT entry. For a non-differencing (fixed/
    // dynamic) image the sector-bitmap entries still exist in the BAT
    // layout (reserved, unused) -- see MS-VHDX 2.5 -- so we still need this
    // to compute the correct BAT index for a given payload block.
    //   chunkRatio = (2^23 * LogicalSectorSize) / BlockSize
    chunkRatio_ = (static_cast<uint64_t>(1) << 23) * logicalSectorSize_ / blockSizeBytes_;
    if (chunkRatio_ == 0) chunkRatio_ = 1;

    const uint64_t payloadBlockCount = (virtualDiskSize_ + blockSizeBytes_ - 1) / blockSizeBytes_;
    // Total BAT entries for fixed/dynamic (non-differencing):
    //   ((payloadBlockCount - 1) / chunkRatio) + payloadBlockCount
    // (one extra sector-bitmap entry per completed chunk, interleaved after
    // every chunkRatio_ payload entries.)
    const uint64_t sectorBitmapEntries = payloadBlockCount == 0 ? 0 : (payloadBlockCount - 1) / chunkRatio_;
    batEntryCount_ = payloadBlockCount + sectorBitmapEntries;

    if (batRegion->length < batEntryCount_ * 8) {
        lastError_ = "VHDX BAT region too small for computed entry count";
        return false;
    }
    batRegionOffset_ = batRegion->fileOffset;

    delete[] bat_;
    bat_ = new uint64_t[batEntryCount_];
    {
        std::unique_ptr<unsigned char[]> batBuf(new unsigned char[batEntryCount_ * 8]);
        if (::pread(fd, batBuf.get(), batEntryCount_ * 8, static_cast<off_t>(batRegion->fileOffset)) !=
            static_cast<ssize_t>(batEntryCount_ * 8)) {
            lastError_ = "failed to read VHDX BAT region";
            delete[] bat_;
            bat_ = nullptr;
            return false;
        }
        for (uint64_t i = 0; i < batEntryCount_; i++) {
            bat_[i] = readU64LE(batBuf.get() + i * 8);
        }
    }

    readOnly_ = true;
    if (requestReadWrite) {
        if (pendingLogReplay) {
            lastError_ = "pending log replay -- opening read-only for safety";
            LOGI("VhdxImage::open: %s", lastError_);
        } else {
            readOnly_ = false;
        }
    }

    LOGI("VhdxImage::open: ok, virtualDiskSize=%llu, blockSize=%u, logicalSectorSize=%u, "
         "batEntries=%llu, chunkRatio=%llu, readOnly=%d",
         (unsigned long long)virtualDiskSize_, blockSizeBytes_, logicalSectorSize_,
         (unsigned long long)batEntryCount_, (unsigned long long)chunkRatio_, readOnly_ ? 1 : 0);
    return true;
}

uint64_t VhdxImage::payloadBatIndex(uint64_t blockIndex) const {
    // Every completed chunk of chunkRatio_ payload blocks is followed by one
    // sector-bitmap entry in the flat BAT array, so the payload entry for
    // blockIndex sits (blockIndex / chunkRatio_) sector-bitmap-entries past
    // its naive position.
    return blockIndex + (blockIndex / chunkRatio_);
}

bool VhdxImage::resolveBlock(uint64_t blockIndex, bool allocateIfMissing,
                             uint64_t* outFileOffset, bool* outPresent) {
    *outFileOffset = 0;
    *outPresent = false;
    const uint64_t idx = payloadBatIndex(blockIndex);
    if (idx >= batEntryCount_) return false;

    const uint64_t entry = bat_[idx];
    const uint64_t state = entry & kBatStateMask;

    if (state == kPayloadBlockFullyPresent) {
        // kBatFileOffsetMask already isolates the top 44 bits in place (bit
        // 20 upward), so masking alone yields a byte offset that's an exact
        // multiple of 1MB -- no separate "* 1MB" scaling step is needed.
        *outFileOffset = entry & kBatFileOffsetMask;
        *outPresent = true;
        return true;
    }

    // kPayloadBlockPartiallyPresent only occurs in differencing images,
    // which open() already rejected -- treat defensively as "not present"
    // if ever seen (e.g. a malformed file) rather than misreading it as
    // fully present.
    if (state == kPayloadBlockNotPresent || state == kPayloadBlockUndefined ||
        state == kPayloadBlockZero || state == kPayloadBlockUnmapped ||
        state == kPayloadBlockPartiallyPresent) {
        if (!allocateIfMissing) {
            *outPresent = false;
            return true; // not an error -- caller should treat as all-zero
        }
        if (readOnly_) return false;

        // Allocate: append a new, zero-filled block to the end of the file,
        // 1MB-aligned (per spec, every BAT-referenced offset must be a
        // multiple of 1MB), and point this BAT entry at it.
        struct stat st{};
        if (fstat(fd_, &st) != 0) return false;
        uint64_t newOffset = static_cast<uint64_t>(st.st_size);
        if (newOffset % kOneMiB != 0) {
            newOffset += kOneMiB - (newOffset % kOneMiB);
        }
        // Zero-fill the new block region so unwritten sub-ranges of it read
        // back as zero (matches PAYLOAD_BLOCK_ZERO/NOT_PRESENT semantics
        // for the parts of this block that this particular write doesn't
        // touch).
        {
            std::vector<unsigned char> zeros(blockSizeBytes_, 0);
            if (::pwrite(fd_, zeros.data(), zeros.size(), static_cast<off_t>(newOffset)) !=
                static_cast<ssize_t>(zeros.size())) {
                return false;
            }
        }
        bat_[idx] = (newOffset & kBatFileOffsetMask) | kPayloadBlockFullyPresent;
        // Persist the updated BAT entry immediately so a crash between now
        // and volume close doesn't leave the in-memory BAT (which now
        // thinks the block is allocated) out of sync with what's on disk.
        // We don't batch/defer BAT writes -- correctness over the small
        // extra I/O here, matching how bitlockerWrite() also doesn't defer
        // dislocker's own metadata writes.
        {
            unsigned char entryBytes[8];
            const uint64_t v = bat_[idx];
            for (int b = 0; b < 8; b++) entryBytes[b] = static_cast<unsigned char>((v >> (8 * b)) & 0xFF);
            // Need the BAT's own on-file location -- recompute via the
            // region table entry we resolved in open(). We don't keep that
            // pointer around post-open, so instead we rely on the BAT
            // region being contiguous and stash its file offset here via
            // a member the first time open() succeeds. See batRegionOffset_.
            if (::pwrite(fd_, entryBytes, 8, static_cast<off_t>(batRegionOffset_ + idx * 8)) != 8) {
                return false;
            }
        }

        *outFileOffset = newOffset;
        *outPresent = true;
        return true;
    }

    // Any other/unknown state: be conservative and fail rather than guess.
    return false;
}

bool VhdxImage::pread(uint64_t virtualOffset, unsigned char* outBuf, size_t len) {
    if (len == 0) return true;
    if (virtualOffset + len > virtualDiskSize_) return false;

    size_t done = 0;
    while (done < len) {
        const uint64_t curVOffset = virtualOffset + done;
        const uint64_t blockIndex = curVOffset / blockSizeBytes_;
        const uint64_t inBlockOffset = curVOffset % blockSizeBytes_;
        const size_t chunk = static_cast<size_t>(
            std::min<uint64_t>(len - done, blockSizeBytes_ - inBlockOffset));

        uint64_t fileOffset = 0;
        bool present = false;
        if (!resolveBlock(blockIndex, /*allocateIfMissing=*/false, &fileOffset, &present)) {
            return false;
        }
        if (!present) {
            std::memset(outBuf + done, 0, chunk);
        } else {
            const ssize_t n = ::pread(fd_, outBuf + done, chunk,
                                       static_cast<off_t>(fileOffset + inBlockOffset));
            if (n != static_cast<ssize_t>(chunk)) return false;
        }
        done += chunk;
    }
    return true;
}

bool VhdxImage::pwrite(uint64_t virtualOffset, const unsigned char* inBuf, size_t len) {
    if (len == 0) return true;
    if (readOnly_) return false;
    if (virtualOffset + len > virtualDiskSize_) return false;

    size_t done = 0;
    while (done < len) {
        const uint64_t curVOffset = virtualOffset + done;
        const uint64_t blockIndex = curVOffset / blockSizeBytes_;
        const uint64_t inBlockOffset = curVOffset % blockSizeBytes_;
        const size_t chunk = static_cast<size_t>(
            std::min<uint64_t>(len - done, blockSizeBytes_ - inBlockOffset));

        uint64_t fileOffset = 0;
        bool present = false;
        if (!resolveBlock(blockIndex, /*allocateIfMissing=*/true, &fileOffset, &present) || !present) {
            return false;
        }
        const ssize_t n = ::pwrite(fd_, inBuf + done, chunk,
                                    static_cast<off_t>(fileOffset + inBlockOffset));
        if (n != static_cast<ssize_t>(chunk)) return false;
        done += chunk;
    }
    return true;
}
