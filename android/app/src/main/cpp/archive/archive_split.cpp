#include "archive_engine.h"
#include "archive_engine_internal.h"

#include <archive.h>
#include <archive_entry.h>

#include <algorithm>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <map>
#include <memory>

// Split (multi-part) archives. See the block comment in archive_engine.h for
// the on-disk conventions. Two halves live here:
//   * writing: archiveCreateSplit() -- 7z volumes and a spanned ZIP;
//   * reading: archiveOpenPartsSource() -- one logical source over the parts.
// Both halves share the central-directory record rewriting below, because a
// spanned ZIP differs from a normal one only in "which disk + which offset
// inside that disk" for every entry, plus the end-of-directory records.

namespace {

using Bytes = std::vector<uint8_t>;

constexpr uint32_t kSigCentralDir = 0x02014b50;
constexpr uint32_t kSigEocd = 0x06054b50;
constexpr uint32_t kSigZip64Eocd = 0x06064b50;
constexpr uint32_t kSigZip64Locator = 0x07064b50;
constexpr uint32_t kMax32 = 0xFFFFFFFFu;
constexpr uint32_t kMax16 = 0xFFFFu;
constexpr size_t kCdFixed = 46;
constexpr size_t kEocdFixed = 22;
constexpr size_t kZip64EocdSize = 56;
constexpr size_t kZip64LocatorSize = 20;
constexpr size_t kChunk = 256 * 1024;

inline uint16_t le16(const uint8_t* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }
inline uint32_t le32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
inline uint64_t le64(const uint8_t* p) {
    return static_cast<uint64_t>(le32(p)) | (static_cast<uint64_t>(le32(p + 4)) << 32);
}
inline void put16(uint8_t* p, uint32_t v) {
    p[0] = static_cast<uint8_t>(v);
    p[1] = static_cast<uint8_t>(v >> 8);
}
inline void put32(uint8_t* p, uint32_t v) {
    for (int i = 0; i < 4; ++i) p[i] = static_cast<uint8_t>(v >> (8 * i));
}
inline void put64(uint8_t* p, uint64_t v) {
    for (int i = 0; i < 8; ++i) p[i] = static_cast<uint8_t>(v >> (8 * i));
}
void append16(Bytes& b, uint32_t v) { b.push_back(static_cast<uint8_t>(v)); b.push_back(static_cast<uint8_t>(v >> 8)); }
void append64(Bytes& b, uint64_t v) { for (int i = 0; i < 8; ++i) b.push_back(static_cast<uint8_t>(v >> (8 * i))); }

// ── Central directory record rewriting ──────────────────────────────────

// Reads the entry's start disk and local-header offset (resolving the Zip64
// extra field when the 32/16-bit fields hold their "look in the extra" marker),
// lets `remap` change them, and writes the record back, adding or dropping the
// Zip64 extra as the new values need. Everything else in the record (name,
// timestamps, comment, other extra fields, sizes) is preserved.
using CdRemap = std::function<bool(uint32_t& disk, uint64_t& offset)>;

bool rewriteCdRecord(Bytes& rec, const CdRemap& remap) {
    if (rec.size() < kCdFixed || le32(rec.data()) != kSigCentralDir) return false;
    const size_t nameLen = le16(rec.data() + 28);
    const size_t extraLen = le16(rec.data() + 30);
    const size_t commentLen = le16(rec.data() + 32);
    if (kCdFixed + nameLen + extraLen + commentLen != rec.size()) return false;
    const size_t extraStart = kCdFixed + nameLen;
    const size_t extraEnd = extraStart + extraLen;

    uint64_t uncompressed = le32(rec.data() + 24);
    uint64_t compressed = le32(rec.data() + 20);
    uint64_t offset = le32(rec.data() + 42);
    uint32_t disk = le16(rec.data() + 34);
    const bool wantUncompressed = uncompressed == kMax32;
    const bool wantCompressed = compressed == kMax32;
    const bool wantOffset = offset == kMax32;
    const bool wantDisk = disk == kMax16;

    Bytes keptExtra;
    size_t q = extraStart;
    while (q + 4 <= extraEnd) {
        const uint32_t id = le16(rec.data() + q);
        const size_t len = le16(rec.data() + q + 2);
        if (q + 4 + len > extraEnd) return false;
        if (id == 1) {
            const uint8_t* d = rec.data() + q + 4;
            size_t used = 0;
            auto take64 = [&](uint64_t& v) {
                if (used + 8 > len) return false;
                v = le64(d + used);
                used += 8;
                return true;
            };
            if (wantUncompressed && !take64(uncompressed)) return false;
            if (wantCompressed && !take64(compressed)) return false;
            if (wantOffset && !take64(offset)) return false;
            if (wantDisk) {
                if (used + 4 > len) return false;
                disk = le32(d + used);
                used += 4;
            }
        } else {
            keptExtra.insert(keptExtra.end(), rec.begin() + q, rec.begin() + q + 4 + len);
        }
        q += 4 + len;
    }
    if (q < extraEnd) keptExtra.insert(keptExtra.end(), rec.begin() + q, rec.begin() + extraEnd);

    if (!remap(disk, offset)) return false;
    if (disk >= kMax16) return false;  // would need a Zip64 disk field; not supported

    Bytes zip64;
    const bool putUncompressed = uncompressed >= kMax32;
    const bool putCompressed = compressed >= kMax32;
    const bool putOffset = offset >= kMax32;
    if (putUncompressed) append64(zip64, uncompressed);
    if (putCompressed) append64(zip64, compressed);
    if (putOffset) append64(zip64, offset);

    Bytes extra = keptExtra;
    if (!zip64.empty()) {
        append16(extra, 1);
        append16(extra, static_cast<uint32_t>(zip64.size()));
        extra.insert(extra.end(), zip64.begin(), zip64.end());
    }
    if (extra.size() > 0xFFFF) return false;

    Bytes out(rec.begin(), rec.begin() + extraStart);
    out.insert(out.end(), extra.begin(), extra.end());
    out.insert(out.end(), rec.begin() + extraEnd, rec.end());
    put32(out.data() + 24, putUncompressed ? kMax32 : static_cast<uint32_t>(uncompressed));
    put32(out.data() + 20, putCompressed ? kMax32 : static_cast<uint32_t>(compressed));
    put32(out.data() + 42, putOffset ? kMax32 : static_cast<uint32_t>(offset));
    put16(out.data() + 34, disk);
    put16(out.data() + 30, static_cast<uint32_t>(extra.size()));
    if (!zip64.empty() && le16(out.data() + 6) < 45) put16(out.data() + 6, 45);
    rec.swap(out);
    return true;
}

// Splits a raw central directory into its records.
bool splitCentralDirectory(const Bytes& cd, std::vector<Bytes>* records) {
    size_t pos = 0;
    while (pos + kCdFixed <= cd.size() && le32(cd.data() + pos) == kSigCentralDir) {
        const size_t size = kCdFixed + le16(cd.data() + pos + 28) + le16(cd.data() + pos + 30) +
                            le16(cd.data() + pos + 32);
        if (pos + size > cd.size()) return false;
        records->emplace_back(cd.begin() + pos, cd.begin() + pos + size);
        pos += size;
    }
    return true;
}

// ── Writing ─────────────────────────────────────────────────────────────

// Cuts one sequential byte stream into parts of at most `partSize` bytes.
// A part is opened lazily, on its first byte, so a stream that ends exactly on
// a part boundary never leaves an empty trailing part behind.
class PartWriter {
public:
    PartWriter(const ArchivePartTarget& target, uint64_t partSize)
        : target_(target), partSize_(partSize) {}

    bool write(const uint8_t* data, size_t length) {
        while (length > 0) {
            if (open_ && used_ == partSize_ && !closeCurrent(false)) return false;
            if (!open_) {
                if (!target_.openPart(nextIndex_)) return false;
                curIndex_ = nextIndex_++;
                open_ = true;
                used_ = 0;
            }
            const size_t room = static_cast<size_t>(std::min<uint64_t>(length, partSize_ - used_));
            if (target_.writePart(data, room) != static_cast<int64_t>(room)) return false;
            used_ += room;
            total_ += room;
            data += room;
            length -= room;
        }
        return true;
    }

    // Starts a fresh part now if fewer than `need` bytes are left in this one,
    // so a record written next is never cut in two. No-op on an empty part.
    bool keepTogether(uint64_t need) {
        if (!open_ || used_ == 0 || need > partSize_) return true;
        if (partSize_ - used_ >= need) return true;
        return closeCurrent(false);
    }

    // Where the next byte will land: {part index, offset inside that part}.
    struct Position { uint32_t part; uint64_t offset; };
    Position position() const {
        if (open_ && used_ < partSize_) return {curIndex_, used_};
        return {nextIndex_, 0};
    }

    bool finish() {
        if (open_) return closeCurrent(true);
        return true;
    }

    uint64_t total() const { return total_; }
    uint32_t partCount() const { return nextIndex_; }
    bool anyOpened() const { return nextIndex_ > 0; }

private:
    bool closeCurrent(bool isLast) {
        open_ = false;
        return target_.closePart(curIndex_, isLast);
    }

    const ArchivePartTarget& target_;
    uint64_t partSize_;
    bool open_ = false;
    uint32_t curIndex_ = 0;
    uint32_t nextIndex_ = 0;
    uint64_t used_ = 0;
    uint64_t total_ = 0;
};

struct ZipWriteContext {
    std::function<int64_t(const uint8_t*, size_t)> out;
    bool ioError = false;
    bool cancelled = false;
};

// After the target fails or the caller cancels, this keeps answering "written"
// and throws the bytes away. Returning an error instead would put libarchive in
// its fatal state, and a ZIP writer torn down mid-entry never releases its
// deflate stream (about 270 KB). Callers poll ioError/cancelled between steps
// and wind the archive down normally.
la_ssize_t zipWriteCallback(struct archive*, void* client, const void* buffer, size_t length) {
    auto* ctx = static_cast<ZipWriteContext*>(client);
    if (ctx->ioError || ctx->cancelled || length == 0) return static_cast<la_ssize_t>(length);
    const int64_t n = ctx->out(static_cast<const uint8_t*>(buffer), length);
    if (n < 0 || static_cast<size_t>(n) != length) {
        ctx->ioError = true;
        return static_cast<la_ssize_t>(length);
    }
    return static_cast<la_ssize_t>(length);
}
int zipOpenCallback(struct archive*, void*) { return ARCHIVE_OK; }
int zipCloseCallback(struct archive*, void*) { return ARCHIVE_OK; }

ArchiveCreateResult failed(ArchiveCreateResult r, ArchiveOpenStatus status, const std::string& msg) {
    r.status = status;
    r.errorMessage = msg;
    return r;
}

ArchiveCreateResult createSplitSevenZip(const ArchivePartTarget& target, uint64_t partSize,
                                        const std::vector<ArchiveSourceEntry>& entries,
                                        const std::string& passphrase, bool encryptFilenames,
                                        std::function<bool(uint64_t)> progress, int compressionLevel,
                                        ArchiveCompressionMethod compressionMethod) {
    PartWriter parts(target, partSize);
    ArchiveSink sink;
    sink.write = [&parts](const uint8_t* data, size_t length) -> int64_t {
        return parts.write(data, length) ? static_cast<int64_t>(length) : -1;
    };
    ArchiveCreateResult res =
        archiveCreate(sink, ArchiveFormat::SevenZip, entries, passphrase, encryptFilenames, std::move(progress),
                      compressionLevel, compressionMethod);
    if (res.status == ArchiveOpenStatus::Ok && !parts.finish()) {
        res.status = ArchiveOpenStatus::IoError;
        res.errorMessage = "failed to finish the last part";
    }
    if (res.status != ArchiveOpenStatus::Ok) {
        if (parts.anyOpened() && target.abort) target.abort();
    }
    res.partCount = parts.partCount();
    return res;
}

ArchiveCreateResult createSplitZip(const ArchivePartTarget& target, uint64_t partSize,
                                   const std::vector<ArchiveSourceEntry>& entries,
                                   const std::string& passphrase,
                                   std::function<bool(uint64_t)> progress, int compressionLevel,
                                   ArchiveCompressionMethod compressionMethod) {
    ArchiveCreateResult res;
    PartWriter parts(target, partSize);

    auto abortAll = [&](ArchiveCreateResult r) {
        if (parts.anyOpened() && target.abort) target.abort();
        r.partCount = parts.partCount();
        return r;
    };

    // Configure (and validate the options) before anything touches the target.
    struct archive* a = archive_write_new();
    if (!a) return failed(res, ArchiveOpenStatus::IoError, "failed to create archive writer");
    std::string configError;
    if (!archiveConfigureWriter(a, ArchiveFormat::Zip, passphrase, false, compressionLevel, compressionMethod,
                                &configError)) {
        archive_write_free(a);
        return failed(res, ArchiveOpenStatus::UnsupportedFormat, configError);
    }
    // No write-side blocking: libarchive must hand every record to the sink as
    // soon as it is produced, so the sink knows exactly where each entry starts
    // (and so no zero padding is appended after the end-of-directory record).
    if (archive_write_set_bytes_per_block(a, 0) != ARCHIVE_OK ||
        archive_write_set_bytes_in_last_block(a, 1) != ARCHIVE_OK) {
        archive_write_free(a);
        return failed(res, ArchiveOpenStatus::UnsupportedFormat, "cannot disable write blocking");
    }

    // Spanning marker: the first four bytes of the first part of a split ZIP.
    static const uint8_t kMarker[4] = {'P', 'K', 7, 8};
    if (!parts.write(kMarker, sizeof(kMarker))) {
        archive_write_free(a);
        return abortAll(failed(res, ArchiveOpenStatus::IoError, "failed to write the first part"));
    }

    // Until the central directory starts, libarchive's output goes straight to
    // the parts. After that it is captured so each record can be rewritten
    // with its disk number before it is written.
    bool capturing = false;
    Bytes tail;
    ZipWriteContext ctx;
    ctx.out = [&](const uint8_t* data, size_t length) -> int64_t {
        if (capturing) {
            tail.insert(tail.end(), data, data + length);
            return static_cast<int64_t>(length);
        }
        return parts.write(data, length) ? static_cast<int64_t>(length) : -1;
    };
    if (archive_write_open(a, &ctx, zipOpenCallback, zipWriteCallback, zipCloseCallback) != ARCHIVE_OK) {
        std::string msg = archive_error_string(a) ? archive_error_string(a) : "failed to open archive writer";
        archive_write_free(a);
        return abortAll(failed(res, ArchiveOpenStatus::IoError, msg));
    }

    struct EntryPlace { uint32_t part; uint64_t offset; };
    std::vector<EntryPlace> places;
    places.reserve(entries.size());

    auto fail = [&](ArchiveOpenStatus status, const std::string& fallback) {
        std::string msg = archive_error_string(a) ? archive_error_string(a) : fallback;
        if (ctx.cancelled) msg = "archive creation cancelled";
        else if (ctx.ioError) msg = "failed to write a part";
        // Let libarchive finish the open entry (its sink now discards), so it
        // frees everything; see zipWriteCallback.
        archive_write_finish_entry(a);
        archive_write_close(a);
        archive_write_free(a);
        return abortAll(failed(res, status, msg));
    };

    Bytes chunk(kChunk);
    uint64_t sourceBytesProcessed = 0;
    for (const auto& entry : entries) {
        // A local header is 30 bytes + the name + a few extra fields. Start a
        // new part rather than cut one in two; 192 covers every extra field
        // libarchive can add (timestamps, Zip64, AES).
        if (!parts.keepTogether(30 + entry.pathInArchive.size() + 192)) {
            return fail(ArchiveOpenStatus::IoError, "failed to start a new part");
        }
        const auto where = parts.position();
        places.push_back({where.part, where.offset});

        struct archive_entry* ae = archive_entry_new();
        archive_entry_set_pathname(ae, entry.pathInArchive.c_str());
        archive_entry_set_filetype(ae, entry.isDirectory ? AE_IFDIR : AE_IFREG);
        archive_entry_set_perm(ae, entry.isDirectory ? 0755 : 0644);
        archive_entry_set_size(ae, static_cast<int64_t>(entry.uncompressedSize));
        archive_entry_set_mtime(ae, entry.modTimeEpochSeconds > 0 ? entry.modTimeEpochSeconds
                                                                   : static_cast<int64_t>(std::time(nullptr)), 0);
        const int hr = archive_write_header(a, ae);
        archive_entry_free(ae);
        if (hr != ARCHIVE_OK || ctx.ioError || ctx.cancelled) {
            return fail(hr != ARCHIVE_OK && !ctx.ioError && !ctx.cancelled ? ArchiveOpenStatus::UnsupportedFormat
                                                                           : ArchiveOpenStatus::IoError,
                        "failed to write entry header");
        }

        if (!entry.isDirectory && entry.readData && entry.uncompressedSize > 0) {
            uint64_t done = 0;
            while (done < entry.uncompressedSize) {
                const size_t want = static_cast<size_t>(std::min<uint64_t>(chunk.size(), entry.uncompressedSize - done));
                const int64_t got = entry.readData(chunk.data(), want);
                if (got < 0) return fail(ArchiveOpenStatus::IoError, "failed to read source file");
                if (got == 0) break;
                const la_ssize_t w = archive_write_data(a, chunk.data(), static_cast<size_t>(got));
                if (w < 0 || ctx.ioError || ctx.cancelled) {
                    return fail(ArchiveOpenStatus::IoError, "failed to write entry payload");
                }
                done += static_cast<uint64_t>(w);
                sourceBytesProcessed += static_cast<uint64_t>(w);
                // Progress is in source bytes, as for archiveCreate().
                if (progress && !progress(sourceBytesProcessed)) {
                    ctx.cancelled = true;
                    return fail(ArchiveOpenStatus::IoError, "archive creation cancelled");
                }
            }
        }
        // Flush the entry's trailing bytes (last compressed block, data
        // descriptor) NOW. libarchive would otherwise emit them while writing
        // the next header, after this loop has already noted where that
        // header starts -- which would put every later entry at a wrong offset.
        if (archive_write_finish_entry(a) != ARCHIVE_OK || ctx.ioError || ctx.cancelled) {
            return fail(ArchiveOpenStatus::IoError, "failed to finish an entry");
        }
        res.entriesArchived++;
    }

    capturing = true;
    const int closeRc = archive_write_close(a);
    archive_write_free(a);
    a = nullptr;
    if (closeRc != ARCHIVE_OK || ctx.ioError || ctx.cancelled) {
        return abortAll(failed(res, ArchiveOpenStatus::IoError,
                               ctx.cancelled ? "archive creation cancelled" : "failed to finalize archive"));
    }

    // ── Rewrite the central directory for a spanned archive ────────────
    Bytes cd;
    {
        // The captured tail is: central directory records, optional Zip64
        // end records, end-of-directory record. Only the records matter; the
        // end records are rebuilt below.
        size_t pos = 0;
        while (pos + kCdFixed <= tail.size() && le32(tail.data() + pos) == kSigCentralDir) {
            pos += kCdFixed + le16(tail.data() + pos + 28) + le16(tail.data() + pos + 30) + le16(tail.data() + pos + 32);
        }
        if (pos > tail.size()) {
            return abortAll(failed(res, ArchiveOpenStatus::IoError, "malformed central directory"));
        }
        cd.assign(tail.begin(), tail.begin() + pos);
    }
    std::vector<Bytes> records;
    if (!splitCentralDirectory(cd, &records) || records.size() != places.size()) {
        return abortAll(failed(res, ArchiveOpenStatus::IoError, "central directory does not match the entries written"));
    }

    uint64_t cdSize = 0;
    uint32_t cdStartPart = 0;
    uint64_t cdStartOffset = 0;
    uint32_t countedPart = 0;
    uint64_t entriesOnPart = 0;
    for (size_t i = 0; i < records.size(); ++i) {
        const EntryPlace place = places[i];
        if (!rewriteCdRecord(records[i], [&](uint32_t& disk, uint64_t& offset) {
                disk = place.part;
                offset = place.offset;
                return true;
            })) {
            return abortAll(failed(res, ArchiveOpenStatus::UnsupportedFormat,
                                   "too many parts for a ZIP central directory"));
        }
        if (!parts.keepTogether(records[i].size())) {
            return abortAll(failed(res, ArchiveOpenStatus::IoError, "failed to start a new part"));
        }
        const auto where = parts.position();
        if (i == 0) {
            cdStartPart = where.part;
            cdStartOffset = where.offset;
            countedPart = where.part;
        }
        if (where.part != countedPart) {
            countedPart = where.part;
            entriesOnPart = 0;
        }
        if (!parts.write(records[i].data(), records[i].size())) {
            return abortAll(failed(res, ArchiveOpenStatus::IoError, "failed to write the central directory"));
        }
        ++entriesOnPart;
        cdSize += records[i].size();
    }

    const uint64_t totalEntries = records.size();
    const bool zip64 = totalEntries >= kMax16 || cdSize >= kMax32 || cdStartPart + 2 >= kMax16 ||
                       parts.position().part + 2 >= kMax16;
    const uint64_t need = kEocdFixed + (zip64 ? kZip64EocdSize + kZip64LocatorSize : 0);
    if (!parts.keepTogether(need)) {
        return abortAll(failed(res, ArchiveOpenStatus::IoError, "failed to start a new part"));
    }
    const auto eocdAt = parts.position();
    if (records.empty()) {
        cdStartPart = eocdAt.part;
        cdStartOffset = eocdAt.offset;
        countedPart = eocdAt.part;
    }
    const uint64_t entriesOnThisDisk = (countedPart == eocdAt.part) ? entriesOnPart : 0;

    Bytes end;
    if (zip64) {
        Bytes z(kZip64EocdSize, 0);
        put32(z.data(), kSigZip64Eocd);
        put64(z.data() + 4, 44);
        put16(z.data() + 12, 45);
        put16(z.data() + 14, 45);
        put32(z.data() + 16, eocdAt.part);
        put32(z.data() + 20, cdStartPart);
        put64(z.data() + 24, entriesOnThisDisk);
        put64(z.data() + 32, totalEntries);
        put64(z.data() + 40, cdSize);
        put64(z.data() + 48, cdStartOffset);
        end.insert(end.end(), z.begin(), z.end());
        Bytes loc(kZip64LocatorSize, 0);
        put32(loc.data(), kSigZip64Locator);
        put32(loc.data() + 4, eocdAt.part);
        put64(loc.data() + 8, eocdAt.offset);
        put32(loc.data() + 16, eocdAt.part + 1);
        end.insert(end.end(), loc.begin(), loc.end());
    }
    Bytes eocd(kEocdFixed, 0);
    put32(eocd.data(), kSigEocd);
    put16(eocd.data() + 4, std::min<uint32_t>(eocdAt.part, kMax16));
    put16(eocd.data() + 6, std::min<uint32_t>(cdStartPart, kMax16));
    put16(eocd.data() + 8, static_cast<uint32_t>(std::min<uint64_t>(entriesOnThisDisk, kMax16)));
    put16(eocd.data() + 10, static_cast<uint32_t>(std::min<uint64_t>(totalEntries, kMax16)));
    put32(eocd.data() + 12, static_cast<uint32_t>(std::min<uint64_t>(cdSize, kMax32)));
    put32(eocd.data() + 16, static_cast<uint32_t>(std::min<uint64_t>(cdStartOffset, kMax32)));
    end.insert(end.end(), eocd.begin(), eocd.end());
    if (!parts.write(end.data(), end.size()) || !parts.finish()) {
        return abortAll(failed(res, ArchiveOpenStatus::IoError, "failed to write the end of the archive"));
    }

    res.status = ArchiveOpenStatus::Ok;
    res.totalBytesWritten = parts.total();
    res.partCount = parts.partCount();
    return res;
}

// ── Reading ─────────────────────────────────────────────────────────────

// The parts laid end to end.
struct ConcatView {
    std::vector<ArchiveStreamSource> parts;
    std::vector<uint64_t> sizes;
    std::vector<uint64_t> bases;
    uint64_t total = 0;

    explicit ConcatView(std::vector<ArchiveStreamSource> p) : parts(std::move(p)) {
        for (const auto& part : parts) {
            const uint64_t s = part.size();
            sizes.push_back(s);
            bases.push_back(total);
            total += s;
        }
    }

    int64_t read(uint64_t offset, uint8_t* dest, size_t length) const {
        if (offset >= total) return 0;
        length = static_cast<size_t>(std::min<uint64_t>(length, total - offset));
        size_t done = 0;
        size_t i = static_cast<size_t>(std::upper_bound(bases.begin(), bases.end(), offset) - bases.begin());
        i = i == 0 ? 0 : i - 1;
        while (done < length) {
            while (i < parts.size() && offset >= bases[i] + sizes[i]) ++i;
            if (i >= parts.size()) break;
            const uint64_t inPart = offset - bases[i];
            const size_t want = static_cast<size_t>(std::min<uint64_t>(length - done, sizes[i] - inPart));
            const int64_t got = parts[i].read(inPart, dest + done, want);
            if (got < 0) return got;
            if (static_cast<size_t>(got) != want) return -1;
            done += want;
            offset += want;
        }
        return static_cast<int64_t>(done);
    }
};

struct EndRecords {
    bool found = false;
    uint64_t thisDisk = 0;
    uint64_t cdDisk = 0;
    uint64_t totalEntries = 0;
    uint64_t cdSize = 0;
    uint64_t cdOffset = 0;
};

// Looks for a ZIP end-of-central-directory record at the very end of `last`.
EndRecords readEndRecords(const std::vector<ArchiveStreamSource>& parts) {
    EndRecords e;
    const ArchiveStreamSource& last = parts.back();
    const uint64_t size = last.size();
    if (size < kEocdFixed) return e;
    const size_t window = static_cast<size_t>(std::min<uint64_t>(size, kEocdFixed + 0xFFFF));
    Bytes buf(window);
    if (last.read(size - window, buf.data(), window) != static_cast<int64_t>(window)) return e;

    for (size_t i = window - kEocdFixed + 1; i-- > 0;) {
        if (le32(buf.data() + i) != kSigEocd) continue;
        if (i + kEocdFixed + le16(buf.data() + i + 20) != window) continue;
        e.found = true;
        e.thisDisk = le16(buf.data() + i + 4);
        e.cdDisk = le16(buf.data() + i + 6);
        e.totalEntries = le16(buf.data() + i + 10);
        e.cdSize = le32(buf.data() + i + 12);
        e.cdOffset = le32(buf.data() + i + 16);
        if (i >= kZip64LocatorSize && le32(buf.data() + i - kZip64LocatorSize) == kSigZip64Locator) {
            const uint8_t* loc = buf.data() + i - kZip64LocatorSize;
            const uint64_t z64Disk = le32(loc + 4);
            const uint64_t z64Offset = le64(loc + 8);
            if (z64Disk < parts.size()) {
                uint8_t z[kZip64EocdSize];
                if (parts[z64Disk].read(z64Offset, z, sizeof(z)) == static_cast<int64_t>(sizeof(z)) &&
                    le32(z) == kSigZip64Eocd) {
                    e.thisDisk = le32(z + 16);
                    e.cdDisk = le32(z + 20);
                    e.totalEntries = le64(z + 32);
                    e.cdSize = le64(z + 40);
                    e.cdOffset = le64(z + 48);
                }
            }
        }
        return e;
    }
    return e;
}

struct SpanView {
    ConcatView concat;
    uint64_t cdAbsolute = 0;
    Bytes tail;  // rewritten central directory + end records
    explicit SpanView(std::vector<ArchiveStreamSource> p) : concat(std::move(p)) {}
};

}  // namespace

ArchiveCreateResult archiveCreateSplit(const ArchivePartTarget& target, uint64_t partSize,
                                       ArchiveFormat format,
                                       const std::vector<ArchiveSourceEntry>& entries,
                                       const std::string& passphrase, bool encryptFilenames,
                                       std::function<bool(uint64_t)> progressCallback, int compressionLevel,
                                       ArchiveCompressionMethod compressionMethod) {
    ArchiveCreateResult res;
    if (!target.openPart || !target.writePart || !target.closePart) {
        return failed(res, ArchiveOpenStatus::IoError, "incomplete part target");
    }
    if (partSize < kArchiveMinPartSize || partSize > kArchiveMaxPartSize) {
        return failed(res, ArchiveOpenStatus::UnsupportedFormat, "part size out of range");
    }
    if (format == ArchiveFormat::SevenZip) {
        return createSplitSevenZip(target, partSize, entries, passphrase, encryptFilenames,
                                   std::move(progressCallback), compressionLevel, compressionMethod);
    }
    if (format == ArchiveFormat::Zip) {
        if (encryptFilenames) {
            return failed(res, ArchiveOpenStatus::UnsupportedFormat,
                          "filename encryption is only supported for 7z archives");
        }
        return createSplitZip(target, partSize, entries, passphrase, std::move(progressCallback),
                              compressionLevel, compressionMethod);
    }
    return failed(res, ArchiveOpenStatus::UnsupportedFormat, "only ZIP and 7z archives can be split");
}

bool archiveOpenPartsSource(const std::vector<ArchiveStreamSource>& parts, ArchiveStreamSource* out,
                            std::string* errorMessage) {
    auto fail = [&](const std::string& msg) {
        if (errorMessage) *errorMessage = msg;
        return false;
    };
    if (!out || parts.empty()) return fail("no parts");
    if (parts.size() == 1) {
        *out = parts[0];
        return true;
    }

    // A ZIP set records on which disk (= part) its central directory sits;
    // plain volumes (7z, or a ZIP merely cut into pieces) leave that at 0.
    const EndRecords end = readEndRecords(parts);
    const bool spanned = end.found && end.thisDisk != 0;
    if (spanned && end.thisDisk + 1 != parts.size()) {
        return fail("the archive spans " + std::to_string(end.thisDisk + 1) + " parts but " +
                    std::to_string(parts.size()) + " were found");
    }

    auto view = std::make_shared<SpanView>(parts);
    if (!spanned) {
        auto shared = std::make_shared<ConcatView>(view->concat);
        out->size = [shared]() { return shared->total; };
        out->read = [shared](uint64_t off, uint8_t* dest, size_t len) { return shared->read(off, dest, len); };
        return true;
    }

    const ConcatView& cat = view->concat;
    if (end.cdDisk >= parts.size() || end.cdOffset > cat.sizes[end.cdDisk]) return fail("invalid central directory position");
    const uint64_t cdAbs = cat.bases[end.cdDisk] + end.cdOffset;
    if (end.cdSize > cat.total || cdAbs + end.cdSize > cat.total) return fail("invalid central directory size");

    Bytes cd(static_cast<size_t>(end.cdSize));
    if (!cd.empty() && cat.read(cdAbs, cd.data(), cd.size()) != static_cast<int64_t>(cd.size())) {
        return fail("failed to read the central directory");
    }
    std::vector<Bytes> records;
    if (!splitCentralDirectory(cd, &records)) return fail("malformed central directory");

    Bytes tail;
    for (auto& rec : records) {
        if (!rewriteCdRecord(rec, [&](uint32_t& disk, uint64_t& offset) {
                if (disk >= parts.size() || offset > cat.sizes[disk]) return false;
                offset += cat.bases[disk];
                disk = 0;
                return true;
            })) {
            return fail("central directory points outside the available parts");
        }
        tail.insert(tail.end(), rec.begin(), rec.end());
    }

    const uint64_t newCdSize = tail.size();
    const uint64_t entryCount = records.size();
    if (entryCount >= kMax16 || newCdSize >= kMax32 || cdAbs >= kMax32) {
        Bytes z(kZip64EocdSize, 0);
        put32(z.data(), kSigZip64Eocd);
        put64(z.data() + 4, 44);
        put16(z.data() + 12, 45);
        put16(z.data() + 14, 45);
        put64(z.data() + 24, entryCount);
        put64(z.data() + 32, entryCount);
        put64(z.data() + 40, newCdSize);
        put64(z.data() + 48, cdAbs);
        tail.insert(tail.end(), z.begin(), z.end());
        Bytes loc(kZip64LocatorSize, 0);
        put32(loc.data(), kSigZip64Locator);
        put64(loc.data() + 8, cdAbs + newCdSize);
        put32(loc.data() + 16, 1);
        tail.insert(tail.end(), loc.begin(), loc.end());
    }
    Bytes eocd(kEocdFixed, 0);
    put32(eocd.data(), kSigEocd);
    put16(eocd.data() + 8, static_cast<uint32_t>(std::min<uint64_t>(entryCount, kMax16)));
    put16(eocd.data() + 10, static_cast<uint32_t>(std::min<uint64_t>(entryCount, kMax16)));
    put32(eocd.data() + 12, static_cast<uint32_t>(std::min<uint64_t>(newCdSize, kMax32)));
    put32(eocd.data() + 16, static_cast<uint32_t>(std::min<uint64_t>(cdAbs, kMax32)));
    tail.insert(tail.end(), eocd.begin(), eocd.end());

    view->cdAbsolute = cdAbs;
    view->tail = std::move(tail);
    out->size = [view]() { return view->cdAbsolute + view->tail.size(); };
    out->read = [view](uint64_t off, uint8_t* dest, size_t len) -> int64_t {
        const uint64_t total = view->cdAbsolute + view->tail.size();
        if (off >= total) return 0;
        len = static_cast<size_t>(std::min<uint64_t>(len, total - off));
        size_t done = 0;
        if (off < view->cdAbsolute) {
            const size_t n = static_cast<size_t>(std::min<uint64_t>(len, view->cdAbsolute - off));
            const int64_t got = view->concat.read(off, dest, n);
            if (got < 0) return got;
            if (static_cast<size_t>(got) != n) return -1;
            done = n;
            off += n;
        }
        if (done < len) {
            std::memcpy(dest + done, view->tail.data() + (off - view->cdAbsolute), len - done);
        }
        return static_cast<int64_t>(len);
    };
    return true;
}


// ── Part set discovery ──────────────────────────────────────────────────

namespace {

std::string lowerAscii(std::string s) {
    for (auto& c : s) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return s;
}
bool allDigits(const std::string& s) {
    if (s.empty()) return false;
    for (char c : s) if (c < '0' || c > '9') return false;
    return true;
}
bool endsWith(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

struct PartName {
    enum Kind { None, Numbered, SpannedPart, ZipFile } kind = None;
    std::string stem;  // Numbered: "x.7z" / "x.zip"; SpannedPart/ZipFile: "x"
};

PartName classify(const std::string& fileName) {
    PartName pn;
    const std::string lower = lowerAscii(fileName);
    const size_t dot = lower.rfind('.');
    if (dot == std::string::npos || dot == 0) return pn;
    const std::string ext = lower.substr(dot + 1);
    const std::string head = fileName.substr(0, dot);
    const std::string headLower = lower.substr(0, dot);
    if (allDigits(ext) && ext.size() >= 3 && (endsWith(headLower, ".7z") || endsWith(headLower, ".zip"))) {
        pn.kind = PartName::Numbered;
        pn.stem = head;
    } else if (ext.size() >= 3 && ext[0] == 'z' && allDigits(ext.substr(1))) {
        pn.kind = PartName::SpannedPart;
        pn.stem = head;
    } else if (ext == "zip") {
        pn.kind = PartName::ZipFile;
        pn.stem = head;
    }
    return pn;
}

}  // namespace

bool archiveIsSplitPartName(const std::string& fileName) {
    const PartName pn = classify(fileName);
    return pn.kind == PartName::Numbered || pn.kind == PartName::SpannedPart;
}

ArchivePartSetStatus archiveOpenPartSet(const std::string& fileName, const ArchivePartSetEnv& env,
                                        ArchiveStreamSource* out, std::string* error) {
    const PartName pn = classify(fileName);
    if (pn.kind == PartName::None || !env.listSiblings || !env.openSibling) return ArchivePartSetStatus::NotASet;

    // case-insensitive name -> real name
    std::map<std::string, std::string> byLower;
    for (const auto& n : env.listSiblings()) byLower.emplace(lowerAscii(n), n);
    auto find = [&](const std::string& wanted) -> const std::string* {
        auto it = byLower.find(lowerAscii(wanted));
        return it == byLower.end() ? nullptr : &it->second;
    };
    auto missing = [&](const std::string& what) {
        if (error) *error = "missing part: " + what;
        return ArchivePartSetStatus::Missing;
    };
    auto openAll = [&](const std::vector<std::string>& names) {
        std::vector<ArchiveStreamSource> parts(names.size());
        for (size_t i = 0; i < names.size(); ++i) {
            if (!env.openSibling(names[i], &parts[i])) {
                if (error) *error = "cannot open part: " + names[i];
                return ArchivePartSetStatus::Missing;
            }
        }
        std::string err;
        if (!archiveOpenPartsSource(parts, out, &err)) {
            if (error) *error = err;
            return ArchivePartSetStatus::Missing;
        }
        return ArchivePartSetStatus::Opened;
    };

    if (pn.kind == PartName::Numbered) {
        const size_t width = fileName.size() - fileName.rfind('.') - 1;
        std::vector<std::string> names;
        for (size_t i = 1;; ++i) {
            char num[32];
            std::snprintf(num, sizeof(num), "%0*zu", static_cast<int>(width), i);
            const std::string* real = find(pn.stem + "." + num);
            if (!real) break;
            names.push_back(*real);
        }
        if (names.empty()) return missing(pn.stem + ".001");
        // Parts beyond the first gap would be silently ignored; say so instead.
        const size_t opened = names.size();
        const std::string ownDigits = fileName.substr(fileName.rfind('.') + 1);
        if (std::strtoull(ownDigits.c_str(), nullptr, 10) > opened) {
            char num[32];
            std::snprintf(num, sizeof(num), "%0*zu", static_cast<int>(width), opened + 1);
            return missing(pn.stem + "." + num);
        }
        return openAll(names);
    }

    // Spanned ZIP: the last disk is the `.zip` file; it says how many there are.
    const std::string* last = find(pn.stem + ".zip");
    if (!last) {
        return pn.kind == PartName::ZipFile ? ArchivePartSetStatus::NotASet : missing(pn.stem + ".zip");
    }
    ArchiveStreamSource lastSource;
    if (!env.openSibling(*last, &lastSource)) return ArchivePartSetStatus::NotASet;
    const uint32_t disks = archiveZipDiskCount(lastSource);
    if (disks <= 1) return pn.kind == PartName::ZipFile ? ArchivePartSetStatus::NotASet : missing(pn.stem + ".zip");

    std::vector<std::string> names;
    for (uint32_t i = 1; i < disks; ++i) {
        char num[32];
        std::snprintf(num, sizeof(num), ".z%02u", i);
        const std::string* real = find(pn.stem + num);
        if (!real) return missing(pn.stem + num);
        names.push_back(*real);
    }
    names.push_back(*last);
    return openAll(names);
}

uint32_t archiveZipDiskCount(const ArchiveStreamSource& lastPart) {
    const EndRecords e = readEndRecords({lastPart});
    if (!e.found) return 0;
    return static_cast<uint32_t>(std::min<uint64_t>(e.thisDisk + 1, 0xFFFFFFFFull));
}
