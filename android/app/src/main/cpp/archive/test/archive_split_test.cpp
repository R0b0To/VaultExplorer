// Exercises archiveCreateSplit() and archiveOpenPartsSource() against a real
// libarchive, entirely in memory (no fixtures, no external tools):
//   * 7z volumes and spanned ZIP (.z01 ... .zip) round trips through the
//     engine's own reader, over several part sizes, including a result that
//     fits in one part;
//   * the spanned-ZIP structure itself (spanning marker, disk numbers in the
//     end record, no local header or central directory record cut in two);
//   * abort / cancel / refused-part handling and argument validation;
//   * the reader's central directory rewrite for offsets beyond 4 GiB (Zip64
//     extra fields), using virtual parts so no multi-gigabyte data is needed.
//
// Third-party compatibility (Info-ZIP `zip -s 0`, 7-Zip) was checked by hand
// with real tools; see the notes in archive_engine.h.
//
// g++ -std=c++17 archive_split_test.cpp ../archive_engine.cpp ../archive_split.cpp -larchive -o archive_split_test && ./archive_split_test
#include "../archive_engine.h"

#include <algorithm>
#include <cassert>
#include <clocale>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {

using Bytes = std::vector<uint8_t>;

uint16_t le16(const uint8_t* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }
uint32_t le32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
std::string lowerAscii(std::string s) {
    for (auto& c : s) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return s;
}
uint64_t le64(const uint8_t* p) { return le32(p) | (static_cast<uint64_t>(le32(p + 4)) << 32); }

ArchiveStreamSource sourceOver(const Bytes& data) {
    ArchiveStreamSource s;
    s.size = [&data]() { return static_cast<uint64_t>(data.size()); };
    s.read = [&data](uint64_t off, uint8_t* dest, size_t len) -> int64_t {
        if (off >= data.size()) return 0;
        const size_t n = std::min<size_t>(len, data.size() - off);
        std::memcpy(dest, data.data() + off, n);
        return static_cast<int64_t>(n);
    };
    return s;
}

// Collects every part in memory.
struct MemoryTarget {
    std::vector<Bytes> parts;
    std::vector<bool> closedAsLast;
    int failOpenAt = -1;  // refuse to open this part index
    bool aborted = false;
    int openCalls = 0;

    ArchivePartTarget target() {
        ArchivePartTarget t;
        t.openPart = [this](uint32_t index) {
            ++openCalls;
            if (static_cast<int>(index) == failOpenAt) return false;
            assert(index == parts.size());
            parts.emplace_back();
            closedAsLast.push_back(false);
            return true;
        };
        t.writePart = [this](const uint8_t* d, size_t n) -> int64_t {
            parts.back().insert(parts.back().end(), d, d + n);
            return static_cast<int64_t>(n);
        };
        t.closePart = [this](uint32_t index, bool last) {
            assert(index + 1 == parts.size());
            closedAsLast[index] = last;
            return true;
        };
        t.abort = [this]() { aborted = true; };
        return t;
    }
};

struct TestFile {
    std::string name;
    std::string content;
    bool isDir = false;
};

std::string noise(size_t n, uint32_t seed) {
    std::string s(n, '\0');
    uint32_t x = seed;
    for (auto& c : s) {
        x = x * 1664525u + 1013904223u;
        c = static_cast<char>(x >> 24);
    }
    return s;
}

std::vector<TestFile> sampleFiles() {
    std::vector<TestFile> files;
    files.push_back({"docs/", "", true});
    files.push_back({"docs/readme.txt", std::string(80000, 'a') + "end"});
    files.push_back({"docs/empty.dat", ""});
    files.push_back({"random.bin", noise(300000, 1)});
    files.push_back({"unicode-\xC3\xBCn\xC3\xAF.txt", "hello"});
    for (int i = 0; i < 40; ++i) {
        files.push_back({"many/f" + std::to_string(i) + ".txt", "file number " + std::to_string(i)});
    }
    files.push_back({"tail.bin", noise(120000, 2)});
    return files;
}

std::vector<ArchiveSourceEntry> toEntries(const std::vector<TestFile>& files) {
    std::vector<ArchiveSourceEntry> entries;
    for (const auto& f : files) {
        ArchiveSourceEntry e;
        e.pathInArchive = f.name;
        e.isDirectory = f.isDir;
        e.uncompressedSize = f.content.size();
        e.modTimeEpochSeconds = 1700000000;
        auto offset = std::make_shared<size_t>(0);
        const std::string* content = &f.content;
        e.readData = [content, offset](uint8_t* dest, size_t n) -> int64_t {
            const size_t left = content->size() - *offset;
            const size_t take = std::min(n, left);
            std::memcpy(dest, content->data() + *offset, take);
            *offset += take;
            return static_cast<int64_t>(take);
        };
        entries.push_back(std::move(e));
    }
    return entries;
}

// Opens `parts` through the engine and checks every file comes back intact.
void verifyParts(const std::vector<Bytes>& parts, const std::vector<TestFile>& files) {
    std::vector<ArchiveStreamSource> sources;
    for (const auto& p : parts) sources.push_back(sourceOver(p));
    ArchiveStreamSource joined;
    std::string err;
    const bool opened = archiveOpenPartsSource(sources, &joined, &err);
    if (!opened) std::fprintf(stderr, "open parts failed: %s\n", err.c_str());
    assert(opened);

    const auto scan = archiveScanEntries(joined);
    assert(scan.status == ArchiveOpenStatus::Ok);
    assert(scan.entries.size() == files.size());

    std::map<std::string, const TestFile*> expected;
    for (const auto& f : files) {
        std::string key = f.name;
        if (!key.empty() && key.back() == '/') key.pop_back();
        expected[key] = &f;
    }
    for (const auto& entry : scan.entries) {
        std::string key = entry.path;
        if (!key.empty() && key.back() == '/') key.pop_back();
        auto it = expected.find(key);
        assert(it != expected.end());
        if (entry.isDirectory) continue;
        const auto data = archiveExtractEntry(joined, entry.index);
        assert(data.status == ArchiveOpenStatus::Ok);
        assert(std::string(data.data.begin(), data.data.end()) == it->second->content);
    }
}

void testZipRoundTrip(uint64_t partSize) {
    const auto files = sampleFiles();
    const auto entries = toEntries(files);
    MemoryTarget mem;
    const auto res = archiveCreateSplit(mem.target(), partSize, ArchiveFormat::Zip, entries);
    assert(res.status == ArchiveOpenStatus::Ok);
    assert(res.partCount == mem.parts.size());
    assert(res.entriesArchived == files.size());
    for (size_t i = 0; i < mem.parts.size(); ++i) {
        assert(mem.parts[i].size() <= partSize);
        assert(mem.closedAsLast[i] == (i + 1 == mem.parts.size()));
    }
    // Spanning marker leads the first part.
    assert(mem.parts[0].size() > 4 && std::memcmp(mem.parts[0].data(), "PK\x07\x08", 4) == 0);

    // The final part ends with an end-of-central-directory record that names
    // its own disk number, so readers know how many parts to expect.
    const Bytes& last = mem.parts.back();
    assert(last.size() >= 22);
    const uint8_t* eocd = last.data() + last.size() - 22;
    assert(le32(eocd) == 0x06054b50);
    assert(le16(eocd + 4) == mem.parts.size() - 1);
    assert(le16(eocd + 6) <= le16(eocd + 4));
    assert(le16(eocd + 10) == files.size());

    // No part ends inside a local header: the last 30 bytes of a non-final
    // part must not contain the start of one.
    for (size_t i = 0; i + 1 < mem.parts.size(); ++i) {
        const Bytes& p = mem.parts[i];
        const size_t from = p.size() > 29 ? p.size() - 29 : 0;
        for (size_t k = from; k + 4 <= p.size(); ++k) {
            assert(std::memcmp(p.data() + k, "PK\x03\x04", 4) != 0);
        }
    }

    verifyParts(mem.parts, files);
    std::printf("zip split, part size %llu -> %zu parts: ok\n",
                static_cast<unsigned long long>(partSize), mem.parts.size());
}

void testSevenZipRoundTrip(uint64_t partSize) {
    const auto files = sampleFiles();
    const auto entries = toEntries(files);
    MemoryTarget mem;
    const auto res = archiveCreateSplit(mem.target(), partSize, ArchiveFormat::SevenZip, entries);
    assert(res.status == ArchiveOpenStatus::Ok);
    assert(res.partCount == mem.parts.size());
    for (size_t i = 0; i < mem.parts.size(); ++i) {
        assert(mem.parts[i].size() <= partSize);
        if (i + 1 < mem.parts.size()) assert(mem.parts[i].size() == partSize);  // plain volumes: full parts
        assert(mem.closedAsLast[i] == (i + 1 == mem.parts.size()));
    }
    assert(std::memcmp(mem.parts[0].data(), "7z\xBC\xAF\x27\x1C", 6) == 0);
    verifyParts(mem.parts, files);
    std::printf("7z volumes, part size %llu -> %zu parts: ok\n",
                static_cast<unsigned long long>(partSize), mem.parts.size());
}

void testFailureHandling() {
    const auto files = sampleFiles();
    // Entry readers are single-use, so every attempt gets fresh ones.
    auto entriesFor = [&files]() { return toEntries(files); };

    {  // A part the target refuses to create -> failure, target told to clean up.
        MemoryTarget mem;
        mem.failOpenAt = 1;
        const auto res = archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor());
        assert(res.status != ArchiveOpenStatus::Ok);
        assert(mem.aborted);
    }
    {
        MemoryTarget mem;
        mem.failOpenAt = 1;
        const auto res = archiveCreateSplit(mem.target(), 100000, ArchiveFormat::SevenZip, entriesFor());
        assert(res.status != ArchiveOpenStatus::Ok);
        assert(mem.aborted);
    }
    {  // Cancelling from the progress callback.
        MemoryTarget mem;
        uint64_t calls = 0;
        const auto res = archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor(), "", false,
                                            [&calls](uint64_t) { return ++calls < 5; });
        assert(res.status != ArchiveOpenStatus::Ok);
        assert(mem.aborted);
    }
    {  // Validation happens before the target is touched.
        MemoryTarget mem;
        assert(archiveCreateSplit(mem.target(), 100, ArchiveFormat::Zip, entriesFor()).status ==
               ArchiveOpenStatus::UnsupportedFormat);
        assert(archiveCreateSplit(mem.target(), kArchiveMaxPartSize + 1, ArchiveFormat::Zip, entriesFor()).status ==
               ArchiveOpenStatus::UnsupportedFormat);
        assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::TarGz, entriesFor()).status ==
               ArchiveOpenStatus::UnsupportedFormat);
        assert(mem.openCalls == 0 && !mem.aborted);
    }
    std::printf("refused part / cancel / invalid arguments: ok\n");
}

void testMissingParts() {
    const auto files = sampleFiles();
    const auto entries = toEntries(files);
    MemoryTarget mem;
    assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entries).status == ArchiveOpenStatus::Ok);
    assert(mem.parts.size() > 3);

    // First and last part only: the end record says it is disk N, so the
    // reader must refuse instead of producing garbage offsets.
    std::vector<ArchiveStreamSource> partial{sourceOver(mem.parts.front()), sourceOver(mem.parts.back())};
    ArchiveStreamSource out;
    std::string err;
    assert(!archiveOpenPartsSource(partial, &out, &err));
    assert(!err.empty());
    std::printf("missing parts are reported: ok (%s)\n", err.c_str());
}

// ── Offsets beyond 4 GiB, with virtual parts ─────────────────────────────

Bytes cdRecord(const std::string& name, uint32_t uncompressed32, uint32_t compressed32, uint32_t offset32,
               uint16_t disk16, const Bytes& zip64Extra) {
    Bytes r(46, 0);
    auto p16 = [&](size_t at, uint32_t v) { r[at] = static_cast<uint8_t>(v); r[at + 1] = static_cast<uint8_t>(v >> 8); };
    auto p32 = [&](size_t at, uint32_t v) { for (int i = 0; i < 4; ++i) r[at + i] = static_cast<uint8_t>(v >> (8 * i)); };
    p32(0, 0x02014b50);
    p16(4, 45);
    p16(6, 45);
    p32(20, compressed32);
    p32(24, uncompressed32);
    p16(28, static_cast<uint32_t>(name.size()));
    p16(30, static_cast<uint32_t>(zip64Extra.size()));
    p16(34, disk16);
    p32(42, offset32);
    r.insert(r.end(), name.begin(), name.end());
    r.insert(r.end(), zip64Extra.begin(), zip64Extra.end());
    return r;
}

Bytes zip64Extra(const std::vector<uint64_t>& values) {
    Bytes e{1, 0, static_cast<uint8_t>(values.size() * 8), 0};
    for (uint64_t v : values) for (int i = 0; i < 8; ++i) e.push_back(static_cast<uint8_t>(v >> (8 * i)));
    return e;
}

void testZip64OffsetRewrite() {
    constexpr uint64_t kBig = 5000000000ull;  // virtual size of disk 0

    // Record A: plain 32-bit fields, entry starts on disk 1 at offset 100.
    // Record B: 64-bit uncompressed size in a Zip64 extra, and its offset
    // (200, disk 1) stored there too because the 32-bit field holds the marker.
    Bytes cd = cdRecord("a.bin", 10, 10, 100, 1, {});
    const Bytes recB = cdRecord("b.bin", 0xFFFFFFFFu, 20, 0xFFFFFFFFu, 1, zip64Extra({6000000000ull, 200}));
    cd.insert(cd.end(), recB.begin(), recB.end());

    // Disk 1: 256 bytes standing in for entry data, then the central directory.
    constexpr uint32_t kCdStart = 256;
    Bytes part1(kCdStart, 0);
    part1.insert(part1.end(), cd.begin(), cd.end());
    Bytes eocd(22, 0);
    const uint32_t cdSize = static_cast<uint32_t>(cd.size());
    const uint8_t sig[4] = {'P', 'K', 5, 6};
    std::memcpy(eocd.data(), sig, 4);
    eocd[4] = 1;   // this disk
    eocd[6] = 1;   // central directory starts on this disk
    eocd[8] = 2;   // entries on this disk
    eocd[10] = 2;  // total entries
    for (int i = 0; i < 4; ++i) eocd[12 + i] = static_cast<uint8_t>(cdSize >> (8 * i));
    for (int i = 0; i < 4; ++i) eocd[16 + i] = static_cast<uint8_t>(kCdStart >> (8 * i));
    part1.insert(part1.end(), eocd.begin(), eocd.end());

    ArchiveStreamSource virtualDisk0;
    virtualDisk0.size = []() { return kBig; };
    virtualDisk0.read = [](uint64_t off, uint8_t* d, size_t n) -> int64_t {
        if (off >= kBig) return 0;
        n = static_cast<size_t>(std::min<uint64_t>(n, kBig - off));
        std::memset(d, 0, n);
        return static_cast<int64_t>(n);
    };

    ArchiveStreamSource joined;
    std::string err;
    const bool opened = archiveOpenPartsSource({virtualDisk0, sourceOver(part1)}, &joined, &err);
    if (!opened) std::fprintf(stderr, "open parts failed: %s\n", err.c_str());
    assert(opened);

    const uint64_t cdAbs = kBig + kCdStart;  // disk 1 starts right after the virtual disk 0
    Bytes tail(static_cast<size_t>(joined.size() - cdAbs));
    assert(joined.read(cdAbs, tail.data(), tail.size()) == static_cast<int64_t>(tail.size()));

    // Record A is now one disk with a Zip64 offset (5e9 + 100 > 4 GiB).
    assert(le32(tail.data()) == 0x02014b50);
    assert(le16(tail.data() + 34) == 0);                 // single "disk" now
    assert(le32(tail.data() + 42) == 0xFFFFFFFFu);       // offset moved to the extra
    const size_t aNameLen = le16(tail.data() + 28);
    const size_t aExtraLen = le16(tail.data() + 30);
    assert(aNameLen == 5 && aExtraLen == 12);
    const uint8_t* aExtra = tail.data() + 46 + aNameLen;
    assert(le16(aExtra) == 1 && le16(aExtra + 2) == 8);
    assert(le64(aExtra + 4) == kBig + 100);
    assert(le32(tail.data() + 24) == 10 && le32(tail.data() + 20) == 10);  // sizes untouched

    // Record B keeps its 64-bit size and gets the translated offset after it.
    const uint8_t* b = tail.data() + 46 + aNameLen + aExtraLen;
    assert(le32(b) == 0x02014b50);
    assert(le32(b + 24) == 0xFFFFFFFFu && le32(b + 20) == 20 && le32(b + 42) == 0xFFFFFFFFu);
    assert(le16(b + 34) == 0);
    const size_t bNameLen = le16(b + 28);
    const uint8_t* bExtra = b + 46 + bNameLen;
    assert(le16(bExtra) == 1 && le16(bExtra + 2) == 16);
    assert(le64(bExtra + 4) == 6000000000ull);
    assert(le64(bExtra + 12) == kBig + 200);

    // Offsets are past 4 GiB, so the synthesized end records are Zip64 ones.
    const size_t cdBytes = 46 + aNameLen + aExtraLen + 46 + bNameLen + 20;
    const uint8_t* z64 = tail.data() + cdBytes;
    assert(le32(z64) == 0x06064b50);
    assert(le64(z64 + 32) == 2);               // total entries
    assert(le64(z64 + 48) == cdAbs);           // central directory offset
    assert(le32(z64 + 56) == 0x07064b50);      // locator
    assert(le32(z64 + 76) == 0x06054b50);      // classic end record last
    std::printf("offsets beyond 4 GiB are rewritten into Zip64 fields: ok\n");
}


// ── Finding the parts next to an opened file ─────────────────────────────

struct FakeFolder {
    std::map<std::string, Bytes> files;
    ArchivePartSetEnv env() {
        ArchivePartSetEnv e;
        e.listSiblings = [this]() {
            std::vector<std::string> names;
            for (const auto& kv : files) names.push_back(kv.first);
            return names;
        };
        e.openSibling = [this](const std::string& name, ArchiveStreamSource* out) {
            auto it = files.find(name);
            if (it == files.end()) return false;
            *out = sourceOver(it->second);
            return true;
        };
        return e;
    }
};

size_t countEntries(const ArchiveStreamSource& src) {
    const auto scan = archiveScanEntries(src);
    assert(scan.status == ArchiveOpenStatus::Ok);
    return scan.entries.size();
}

void testPartSetDiscovery() {
    const auto files = sampleFiles();
    // Entry readers are single-use, so every archive gets fresh ones.
    auto entriesFor = [&files]() { return toEntries(files); };

    // Spanned ZIP: x.z01 ... x.zip (names as the app writes them, then upper-cased).
    for (bool upper : {false, true}) {
        MemoryTarget mem;
        assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor()).status == ArchiveOpenStatus::Ok);
        const size_t n = mem.parts.size();
        assert(n > 3);
        auto name = [&](size_t i) {
            char b[32];
            if (i + 1 == n) std::snprintf(b, sizeof(b), "%s", upper ? "X.ZIP" : "x.zip");
            else std::snprintf(b, sizeof(b), upper ? "X.Z%02zu" : "x.z%02zu", i + 1);
            return std::string(b);
        };
        FakeFolder folder;
        for (size_t i = 0; i < n; ++i) folder.files[name(i)] = mem.parts[i];
        folder.files["unrelated.txt"] = Bytes{1, 2, 3};

        // Opening any part, including the last, finds the whole set.
        for (size_t i : {size_t(0), size_t(1), n - 1}) {
            ArchiveStreamSource joined;
            std::string err;
            assert(archiveOpenPartSet(name(i), folder.env(), &joined, &err) == ArchivePartSetStatus::Opened);
            assert(countEntries(joined) == files.size());
        }

        // A middle part gone: say which one.
        FakeFolder broken = folder;
        broken.files.erase(name(1));
        ArchiveStreamSource out;
        std::string err;
        assert(archiveOpenPartSet(name(0), broken.env(), &out, &err) == ArchivePartSetStatus::Missing);
        assert(lowerAscii(err) == lowerAscii("missing part: " + name(1)) || err.find(name(1).substr(0, 1)) != std::string::npos);
        assert(err.find("missing part") == 0);

        // Only the last part present.
        FakeFolder lone;
        lone.files[name(n - 1)] = mem.parts.back();
        assert(archiveOpenPartSet(name(n - 1), lone.env(), &out, &err) == ArchivePartSetStatus::Missing);
        assert(err.find("missing part") == 0);

        // Only the first part present.
        FakeFolder first;
        first.files[name(0)] = mem.parts.front();
        assert(archiveOpenPartSet(name(0), first.env(), &out, &err) == ArchivePartSetStatus::Missing);
    }

    {  // An ordinary one-file ZIP is not a set, even with a stray ".z01" beside it.
        MemoryTarget mem;
        assert(archiveCreateSplit(mem.target(), 50ull * 1024 * 1024, ArchiveFormat::Zip, entriesFor()).status ==
               ArchiveOpenStatus::Ok);
        assert(mem.parts.size() == 1);
        FakeFolder folder;
        folder.files["solo.zip"] = mem.parts[0];
        folder.files["solo.z01"] = Bytes{9, 9, 9};
        ArchiveStreamSource out;
        std::string err;
        assert(archiveOpenPartSet("solo.zip", folder.env(), &out, &err) == ArchivePartSetStatus::NotASet);
    }

    {  // 7z volumes: any part opens the set; a gap is reported.
        MemoryTarget mem;
        assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::SevenZip, entriesFor()).status == ArchiveOpenStatus::Ok);
        const size_t n = mem.parts.size();
        assert(n > 2);
        FakeFolder folder;
        for (size_t i = 0; i < n; ++i) {
            char b[32];
            std::snprintf(b, sizeof(b), "bundle.7z.%03zu", i + 1);
            folder.files[b] = mem.parts[i];
        }
        ArchiveStreamSource joined;
        std::string err;
        assert(archiveOpenPartSet("bundle.7z.002", folder.env(), &joined, &err) == ArchivePartSetStatus::Opened);
        assert(countEntries(joined) == files.size());

        FakeFolder gap = folder;
        gap.files.erase("bundle.7z.002");
        assert(archiveOpenPartSet("bundle.7z.003", gap.env(), &joined, &err) == ArchivePartSetStatus::Missing);
        assert(err == "missing part: bundle.7z.002");
    }

    {  // Names that are not archive parts are left alone.
        FakeFolder folder;
        ArchiveStreamSource out;
        std::string err;
        assert(archiveOpenPartSet("movie.mkv.001", folder.env(), &out, &err) == ArchivePartSetStatus::NotASet);
        assert(archiveOpenPartSet("notes.txt", folder.env(), &out, &err) == ArchivePartSetStatus::NotASet);
        assert(!archiveIsSplitPartName("movie.mkv.001"));
        assert(archiveIsSplitPartName("a.7z.001") && archiveIsSplitPartName("a.ZIP.012") && archiveIsSplitPartName("a.z01"));
        assert(!archiveIsSplitPartName("a.zip"));
    }
    std::printf("part set discovery (zip .z01 set, 7z volumes, missing parts, look-alikes): ok\n");
}

// Compression level / method are validated and applied like archiveCreate().
void testCompressionOptions() {
    const auto files = sampleFiles();
    auto entriesFor = [&files]() { return toEntries(files); };

    // Store (0) and best (9): both round-trip; stored data is the larger set.
    uint64_t sizes[2] = {0, 0};
    int idx = 0;
    for (int level : {0, 9}) {
        MemoryTarget mem;
        const auto res = archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor(), "", false, nullptr,
                                            level);
        assert(res.status == ArchiveOpenStatus::Ok);
        verifyParts(mem.parts, files);
        sizes[idx++] = res.totalBytesWritten;
    }
    assert(sizes[0] > sizes[1]);

    {  // 7z with an explicit codec and level.
        MemoryTarget mem;
        const auto res = archiveCreateSplit(mem.target(), 100000, ArchiveFormat::SevenZip, entriesFor(), "", false,
                                            nullptr, 5, ArchiveCompressionMethod::Deflate);
        assert(res.status == ArchiveOpenStatus::Ok);
        verifyParts(mem.parts, files);
    }

    // Rejected before the target is touched, exactly as archiveCreate() rejects them.
    MemoryTarget mem;
    assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor(), "", false, nullptr, 12).status ==
           ArchiveOpenStatus::UnsupportedFormat);
    assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor(), "", false, nullptr,
                              kArchiveDefaultCompressionLevel, ArchiveCompressionMethod::Lzma).status ==
           ArchiveOpenStatus::UnsupportedFormat);
    assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor(), "", false, nullptr, 0,
                              ArchiveCompressionMethod::Deflate).status == ArchiveOpenStatus::UnsupportedFormat);
    assert(archiveCreateSplit(mem.target(), 100000, ArchiveFormat::Zip, entriesFor(), "pw", true).status ==
           ArchiveOpenStatus::UnsupportedFormat);
    assert(mem.openCalls == 0 && !mem.aborted);

    // Progress is in source bytes: it ends at the total of the entries' sizes.
    uint64_t sourceTotal = 0;
    for (const auto& f : files) sourceTotal += f.content.size();
    for (ArchiveFormat format : {ArchiveFormat::Zip, ArchiveFormat::SevenZip}) {
        MemoryTarget m2;
        uint64_t last = 0;
        const auto res = archiveCreateSplit(m2.target(), 100000, format, entriesFor(), "", false,
                                            [&last](uint64_t p) { last = p; return true; });
        assert(res.status == ArchiveOpenStatus::Ok);
        assert(last <= sourceTotal && last * 10 >= sourceTotal * 9);
    }
    std::printf("compression level/method and source-byte progress: ok\n");
}

}  // namespace

int main() {
    // libarchive's 7z writer converts names via the C locale; Android's libc is
    // UTF-8 already, a host libc needs to be told.
    std::setlocale(LC_ALL, "C.UTF-8");
    for (uint64_t partSize : {65536ull, 100000ull, 250000ull}) testZipRoundTrip(partSize);
    testZipRoundTrip(50ull * 1024 * 1024);  // fits in a single part
    for (uint64_t partSize : {65536ull, 200000ull}) testSevenZipRoundTrip(partSize);
    testSevenZipRoundTrip(50ull * 1024 * 1024);
    testFailureHandling();
    testCompressionOptions();
    testMissingParts();
    testZip64OffsetRewrite();
    testPartSetDiscovery();
    std::printf("archive_split_test: all assertions passed\n");
    return 0;
}
