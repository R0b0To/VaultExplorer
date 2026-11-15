// MBR / GPT handling for the Expand BitLocker container tool when the container is a disk image (VHD / VHDX): scan the
// partition table and grow the last partition to the end of a virtual disk that has just been enlarged.
//
// Header-only and free of Android/JNI dependencies, working through a [DiskIo] over the virtual disk, so it can be
// tested on the host (containers/test/disk_partition_test.cpp) and cross-checked with sfdisk / sgdisk.
//
// Assumes 512-byte logical sectors, like the rest of the app's partition handling (scanPartitionTable).
//
// GPT write order keeps every intermediate state a valid table:
//   1. backup entries + backup header at the NEW end of the disk (the primary still points at the old backup),
//   2. primary header + entries (one contiguous write), now pointing at the new backup,
//   3. the protective MBR's size,
//   4. the old backup header and entries, now inside the grown partition, are cleared.
#pragma once

#include <cstdint>
#include <cstring>
#include <functional>
#include <vector>

#include "bl_expand.h"   // blexp::crc32 and the little-endian helpers

struct DiskIo {
    std::function<bool(uint64_t offset, unsigned char* out, size_t len)> read;
    std::function<bool(uint64_t offset, const unsigned char* data, size_t len)> write;
    std::function<bool()> sync;   // optional
};

struct DiskPartition {
    uint64_t startLba = 0;
    uint64_t sectors = 0;
    uint8_t mbrType = 0;   // MBR partition type (0 for GPT entries)
};

enum class PtResult {
    kOk,
    kNothingToDo,    // the partition already reaches the end of the disk (resume after an interrupted run)
    kNoTable,        // sector 0 carries no MBR signature
    kUnsupported,    // extended partition, hybrid / damaged GPT, implausible fields
    kNotLast,        // another partition lies behind the one to grow
    kNotFound,       // no partition starts at the given LBA
    kIoError,
};

namespace ptx {

constexpr uint64_t kSector = 512;

inline bool rd(const DiskIo& io, uint64_t lba, unsigned char* out, size_t sectors) {
    return io.read(lba * kSector, out, sectors * kSector);
}
inline bool wr(const DiskIo& io, uint64_t lba, const unsigned char* data, size_t sectors) {
    return io.write(lba * kSector, data, sectors * kSector);
}
inline bool sync(const DiskIo& io) { return !io.sync || io.sync(); }

struct GptHeader {
    unsigned char raw[kSector];
    uint32_t headerSize = 0;
    uint64_t myLba = 0, alternateLba = 0, firstUsable = 0, lastUsable = 0, entriesLba = 0;
    uint32_t numEntries = 0, entrySize = 0, entriesCrc = 0;
};

// Reads and validates a GPT header at [lba] (signature, header CRC, own LBA).
inline bool readGptHeader(const DiskIo& io, uint64_t lba, GptHeader& h) {
    if (!rd(io, lba, h.raw, 1) || std::memcmp(h.raw, "EFI PART", 8) != 0) return false;
    h.headerSize = blexp::rd32(h.raw + 12);
    if (h.headerSize < 92 || h.headerSize > kSector) return false;
    unsigned char tmp[kSector];
    std::memcpy(tmp, h.raw, sizeof(tmp));
    blexp::wr32(tmp + 16, 0);
    if (blexp::crc32(tmp, h.headerSize) != blexp::rd32(h.raw + 16)) return false;
    h.myLba = blexp::rd64(h.raw + 24);
    h.alternateLba = blexp::rd64(h.raw + 32);
    h.firstUsable = blexp::rd64(h.raw + 40);
    h.lastUsable = blexp::rd64(h.raw + 48);
    h.entriesLba = blexp::rd64(h.raw + 72);
    h.numEntries = blexp::rd32(h.raw + 80);
    h.entrySize = blexp::rd32(h.raw + 84);
    h.entriesCrc = blexp::rd32(h.raw + 88);
    if (h.myLba != lba) return false;
    if (h.entrySize < 128 || (h.entrySize & (h.entrySize - 1)) != 0 || h.numEntries == 0 || h.numEntries > 4096)
        return false;
    return uint64_t(h.numEntries) * h.entrySize <= (1u << 20);
}

inline void sealGptHeader(unsigned char* hdrSector, uint32_t headerSize) {
    blexp::wr32(hdrSector + 16, 0);
    blexp::wr32(hdrSector + 16, blexp::crc32(hdrSector, headerSize));
}

inline bool entryUsed(const unsigned char* e) {
    for (int i = 0; i < 16; i++) if (e[i]) return true;
    return false;
}

// CHS for an MBR partition entry; anything past the CHS limit is the conventional "max" triple.
inline void chsFromLba(uint64_t lba, unsigned char out[3]) {
    constexpr uint64_t kHeads = 255, kSpt = 63;
    if (lba >= 1024ull * kHeads * kSpt) { out[0] = 0xFE; out[1] = 0xFF; out[2] = 0xFF; return; }
    const uint64_t cyl = lba / (kHeads * kSpt);
    const uint64_t head = (lba / kSpt) % kHeads;
    const uint64_t sec = lba % kSpt + 1;
    out[0] = static_cast<unsigned char>(head);
    out[1] = static_cast<unsigned char>((sec & 0x3F) | ((cyl >> 2) & 0xC0));
    out[2] = static_cast<unsigned char>(cyl & 0xFF);
}

}  // namespace ptx

// Lists the partitions of the disk in the order the unlock path tries them (MBR entries in table order, GPT entries in
// array order). [isGpt] tells which kind of table was found. Returns kNoTable when sector 0 has no MBR signature.
inline PtResult ptScan(const DiskIo& io, std::vector<DiskPartition>& out, bool& isGpt) {
    using namespace ptx;
    out.clear();
    isGpt = false;
    unsigned char s0[kSector];
    if (!rd(io, 0, s0, 1)) return PtResult::kIoError;
    if (s0[510] != 0x55 || s0[511] != 0xAA) return PtResult::kNoTable;
    for (int i = 0; i < 4; i++) {
        const unsigned char* e = s0 + 446 + i * 16;
        if (e[4] == 0xEE) { isGpt = true; break; }
    }
    if (!isGpt) {
        for (int i = 0; i < 4; i++) {
            const unsigned char* e = s0 + 446 + i * 16;
            const uint32_t start = blexp::rd32(e + 8), count = blexp::rd32(e + 12);
            if (start > 0 && count > 0) out.push_back({start, count, e[4]});
        }
        return PtResult::kOk;
    }
    GptHeader h;
    if (!readGptHeader(io, 1, h)) return PtResult::kUnsupported;
    std::vector<unsigned char> entries(size_t(h.numEntries) * h.entrySize);
    const size_t sectors = (entries.size() + kSector - 1) / kSector;
    std::vector<unsigned char> buf(sectors * kSector);
    if (!rd(io, h.entriesLba, buf.data(), sectors)) return PtResult::kIoError;
    std::memcpy(entries.data(), buf.data(), entries.size());
    if (blexp::crc32(entries.data(), entries.size()) != h.entriesCrc) return PtResult::kUnsupported;
    for (uint32_t i = 0; i < h.numEntries; i++) {
        const unsigned char* e = entries.data() + size_t(i) * h.entrySize;
        if (!entryUsed(e)) continue;
        const uint64_t start = blexp::rd64(e + 32), end = blexp::rd64(e + 40);
        if (start > 0 && end >= start) out.push_back({start, end - start + 1, 0});
    }
    return PtResult::kOk;
}

// Grows the partition starting at [startLba] so that it reaches the end of a disk of [newDiskBytes]. It must be the last
// partition. *newSectors receives the partition's new length in sectors (also for kNothingToDo).
inline PtResult ptGrowPartition(const DiskIo& io, uint64_t newDiskBytes, uint64_t startLba, uint64_t* newSectors) {
    using namespace ptx;
    unsigned char s0[kSector];
    if (!rd(io, 0, s0, 1)) return PtResult::kIoError;
    if (s0[510] != 0x55 || s0[511] != 0xAA) return PtResult::kNoTable;
    const uint64_t totalSectors = newDiskBytes / kSector;
    if (totalSectors < 64) return PtResult::kUnsupported;

    bool isGpt = false;
    for (int i = 0; i < 4; i++) if (s0[446 + i * 16 + 4] == 0xEE) isGpt = true;

    if (!isGpt) {
        int target = -1;
        for (int i = 0; i < 4; i++) {
            const unsigned char* e = s0 + 446 + i * 16;
            const uint32_t start = blexp::rd32(e + 8), count = blexp::rd32(e + 12);
            if (count == 0) continue;
            if (start == startLba) target = i;
        }
        if (target < 0) return PtResult::kNotFound;
        unsigned char* te = s0 + 446 + target * 16;
        const uint8_t type = te[4];
        if (type == 0x05 || type == 0x0F || type == 0x85) return PtResult::kUnsupported;
        for (int i = 0; i < 4; i++) {
            if (i == target) continue;
            const unsigned char* e = s0 + 446 + i * 16;
            if (blexp::rd32(e + 12) != 0 && blexp::rd32(e + 8) > startLba) return PtResult::kNotLast;
        }
        const uint64_t oldCount = blexp::rd32(te + 12);
        uint64_t newCount = totalSectors > startLba ? totalSectors - startLba : 0;
        if (startLba + newCount > 0x100000000ull) newCount = 0x100000000ull - startLba;   // 32-bit LBA limit (2 TiB)
        if (newCount > 0xFFFFFFFFull) newCount = 0xFFFFFFFFull;
        if (newSectors) *newSectors = newCount > oldCount ? newCount : oldCount;
        if (newCount <= oldCount) return PtResult::kNothingToDo;
        blexp::wr32(te + 12, static_cast<uint32_t>(newCount));
        chsFromLba(startLba + newCount - 1, te + 5);
        if (!wr(io, 0, s0, 1) || !sync(io)) return PtResult::kIoError;
        return PtResult::kOk;
    }

    // GPT.
    GptHeader h;
    if (!readGptHeader(io, 1, h)) return PtResult::kUnsupported;
    const size_t entryBytes = size_t(h.numEntries) * h.entrySize;
    const size_t entrySectors = (entryBytes + kSector - 1) / kSector;
    std::vector<unsigned char> buf(entrySectors * kSector, 0);
    if (!rd(io, h.entriesLba, buf.data(), entrySectors)) return PtResult::kIoError;
    if (blexp::crc32(buf.data(), entryBytes) != h.entriesCrc) return PtResult::kUnsupported;

    const uint64_t newLastLba = totalSectors - 1;
    if (h.alternateLba > newLastLba) return PtResult::kUnsupported;
    if (newLastLba < h.entriesLba + entrySectors + entrySectors + 8) return PtResult::kUnsupported;
    const uint64_t backupEntriesLba = newLastLba - entrySectors;
    const uint64_t newLastUsable = backupEntriesLba - 1;

    int target = -1;
    for (uint32_t i = 0; i < h.numEntries; i++) {
        const unsigned char* e = buf.data() + size_t(i) * h.entrySize;
        if (!entryUsed(e)) continue;
        if (blexp::rd64(e + 32) == startLba) target = int(i);
    }
    if (target < 0) return PtResult::kNotFound;
    unsigned char* te = buf.data() + size_t(target) * h.entrySize;
    for (uint32_t i = 0; i < h.numEntries; i++) {
        if (int(i) == target) continue;
        const unsigned char* e = buf.data() + size_t(i) * h.entrySize;
        if (entryUsed(e) && blexp::rd64(e + 32) > startLba) return PtResult::kNotLast;
    }
    const uint64_t oldEnd = blexp::rd64(te + 40);
    if (newSectors) *newSectors = (newLastUsable > oldEnd ? newLastUsable : oldEnd) - startLba + 1;
    if (h.alternateLba == newLastLba && oldEnd >= newLastUsable) return PtResult::kNothingToDo;
    if (newLastUsable <= oldEnd) return PtResult::kNothingToDo;

    const uint64_t oldAlternate = h.alternateLba;
    blexp::wr64(te + 40, newLastUsable);
    const uint32_t newEntriesCrc = blexp::crc32(buf.data(), entryBytes);

    // 1. Backup entries + backup header at the new end.
    unsigned char backupHdr[kSector];
    std::memcpy(backupHdr, h.raw, sizeof(backupHdr));
    blexp::wr64(backupHdr + 24, newLastLba);
    blexp::wr64(backupHdr + 32, 1);
    blexp::wr64(backupHdr + 48, newLastUsable);
    blexp::wr64(backupHdr + 72, backupEntriesLba);
    blexp::wr32(backupHdr + 88, newEntriesCrc);
    sealGptHeader(backupHdr, h.headerSize);
    if (!wr(io, backupEntriesLba, buf.data(), entrySectors) || !wr(io, newLastLba, backupHdr, 1) || !sync(io))
        return PtResult::kIoError;

    // 2. Primary header + entries: one contiguous write when the entries follow the header, as they normally do.
    unsigned char primaryHdr[kSector];
    std::memcpy(primaryHdr, h.raw, sizeof(primaryHdr));
    blexp::wr64(primaryHdr + 32, newLastLba);
    blexp::wr64(primaryHdr + 48, newLastUsable);
    blexp::wr32(primaryHdr + 88, newEntriesCrc);
    sealGptHeader(primaryHdr, h.headerSize);
    if (h.entriesLba == 2) {
        std::vector<unsigned char> both((1 + entrySectors) * kSector);
        std::memcpy(both.data(), primaryHdr, kSector);
        std::memcpy(both.data() + kSector, buf.data(), entrySectors * kSector);
        if (!wr(io, 1, both.data(), 1 + entrySectors)) return PtResult::kIoError;
    } else if (!wr(io, h.entriesLba, buf.data(), entrySectors) || !wr(io, 1, primaryHdr, 1)) {
        return PtResult::kIoError;
    }
    if (!sync(io)) return PtResult::kIoError;

    // 3. Protective MBR: its 0xEE entry covers the whole disk (capped at 32 bits).
    for (int i = 0; i < 4; i++) {
        unsigned char* e = s0 + 446 + i * 16;
        if (e[4] != 0xEE) continue;
        const uint64_t cover = totalSectors - 1 > 0xFFFFFFFFull ? 0xFFFFFFFFull : totalSectors - 1;
        blexp::wr32(e + 12, static_cast<uint32_t>(cover));
        chsFromLba(cover, e + 5);
        break;
    }
    if (!wr(io, 0, s0, 1) || !sync(io)) return PtResult::kIoError;

    // 4. The old backup now sits inside the partition: clear it, but only if it really is a GPT backup of this disk.
    if (oldAlternate != newLastLba && oldAlternate > h.lastUsable) {
        GptHeader old;
        if (readGptHeader(io, oldAlternate, old) && old.alternateLba == 1 && old.entriesLba > h.lastUsable &&
            old.entriesLba + entrySectors <= oldAlternate) {
            const std::vector<unsigned char> zeros((entrySectors + 1) * kSector, 0);
            wr(io, old.entriesLba, zeros.data(), entrySectors);   // best effort: the table is already consistent
            wr(io, oldAlternate, zeros.data(), 1);
            sync(io);
        }
    }
    return PtResult::kOk;
}
