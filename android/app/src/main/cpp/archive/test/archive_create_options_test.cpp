// Covers the options archiveCreate() takes beyond format + entries:
//
//  * compressionLevel -- must change what is written (it used to be dropped
//    before it reached libarchive, so every archive came out at the default),
//    must round-trip for every format that compresses, and out-of-range values
//    must be refused rather than ignored.
//  * progressCallback -- counts *source* bytes. The 7z writer buffers all of
//    its output in a temporary file until close, so output bytes cannot drive
//    a progress bar; this pins that down.
//  * cancellation -- observed per source chunk (the only place it can be for
//    7z) and must not stall finishing a large unfinished entry.
//
// Own executable (no dependency on archive_engine_test.cpp) so it runs even
// if another test aborts early. Uses CHECK instead of assert() so it still
// checks under NDEBUG.
//
// g++ -std=c++17 archive_create_options_test.cpp ../archive_engine.cpp -larchive -o archive_create_options_test && ./archive_create_options_test
#include "../archive_engine.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
            std::abort();                                                        \
        }                                                                        \
    } while (0)

namespace {

using Files = std::vector<std::pair<std::string, std::string>>;

// Deterministic, compressible, but not trivially repetitive text.
std::string makeText(size_t bytes, uint32_t seed) {
    std::vector<std::string> vocab;
    uint32_t x = seed;
    auto next = [&x]() { x ^= x << 13; x ^= x >> 17; x ^= x << 5; return x; };
    for (int i = 0; i < 400; ++i) {
        std::string w;
        const int len = 2 + static_cast<int>(next() % 8);
        for (int j = 0; j < len; ++j) w.push_back(static_cast<char>('a' + next() % 26));
        vocab.push_back(w);
    }
    std::string out;
    out.reserve(bytes + 16);
    while (out.size() < bytes) {
        out += vocab[next() % vocab.size()];
        out.push_back(next() % 13 == 0 ? '\n' : ' ');
    }
    out.resize(bytes);
    return out;
}

struct Built {
    ArchiveCreateResult result;
    std::vector<uint8_t> bytes;
};

Built build(ArchiveFormat format, const Files& files, int level,
            const std::string& pass = "", bool encryptNames = false,
            std::function<bool(uint64_t)> progress = nullptr) {
    Built b;
    ArchiveSink sink;
    sink.write = [&b](const uint8_t* d, size_t n) -> int64_t {
        b.bytes.insert(b.bytes.end(), d, d + n);
        return static_cast<int64_t>(n);
    };
    std::vector<size_t> offsets(files.size(), 0);
    std::vector<ArchiveSourceEntry> entries(files.size());
    for (size_t i = 0; i < files.size(); ++i) {
        const std::string& content = files[i].second;
        entries[i].pathInArchive = files[i].first;
        entries[i].uncompressedSize = content.size();
        entries[i].modTimeEpochSeconds = 1700000000;  // fixed, so output is byte-reproducible
        entries[i].readData = [&content, &offsets, i](uint8_t* dest, size_t length) -> int64_t {
            const size_t n = std::min(length, content.size() - offsets[i]);
            std::memcpy(dest, content.data() + offsets[i], n);
            offsets[i] += n;
            return static_cast<int64_t>(n);
        };
    }
    b.result = archiveCreate(sink, format, entries, pass, encryptNames, std::move(progress), level);
    return b;
}

ArchiveStreamSource sourceOver(const std::vector<uint8_t>& bytes) {
    ArchiveStreamSource s;
    s.size = [&bytes]() { return static_cast<uint64_t>(bytes.size()); };
    s.read = [&bytes](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        if (offset >= bytes.size()) return 0;
        const size_t n = std::min(length, bytes.size() - static_cast<size_t>(offset));
        std::memcpy(dest, bytes.data() + offset, n);
        return static_cast<int64_t>(n);
    };
    return s;
}

// Opens `bytes` with the engine's own reader and checks every file's content.
void checkRoundTrip(const std::vector<uint8_t>& bytes, const Files& files, const std::string& pass = "") {
    const auto source = sourceOver(bytes);
    const auto scan = archiveScanEntries(source, pass);
    CHECK(scan.status == ArchiveOpenStatus::Ok);
    for (const auto& f : files) {
        int32_t idx = -1;
        for (const auto& e : scan.entries) {
            if (e.path == f.first) idx = e.index;
        }
        CHECK(idx >= 0);
        const auto got = archiveExtractEntry(source, idx, pass);
        CHECK(got.status == ArchiveOpenStatus::Ok);
        CHECK(std::string(got.data.begin(), got.data.end()) == f.second);
    }
}

size_t totalSize(const Files& files) {
    size_t n = 0;
    for (const auto& f : files) n += f.second.size();
    return n;
}

const char* name(ArchiveFormat f) {
    switch (f) {
        case ArchiveFormat::Zip: return "zip";
        case ArchiveFormat::SevenZip: return "7z";
        case ArchiveFormat::TarGz: return "tar.gz";
        case ArchiveFormat::TarBz2: return "tar.bz2";
        case ArchiveFormat::TarXz: return "tar.xz";
        case ArchiveFormat::TarZstd: return "tar.zst";
        case ArchiveFormat::TarLzma: return "tar.lzma";
        default: return "?";
    }
}

}  // namespace

int main() {
    std::setvbuf(stdout, nullptr, _IOLBF, 0);
    const Files files = {
        {"notes.txt", makeText(900 * 1024, 7)},
        {"dir/log.txt", makeText(600 * 1024, 99)},
    };
    const size_t raw = totalSize(files);

    // --- The level changes what is written, for 7z and ZIP. ---------------
    for (ArchiveFormat f : {ArchiveFormat::SevenZip, ArchiveFormat::Zip}) {
        const auto store = build(f, files, 0);
        const auto fast = build(f, files, 1);
        const auto best = build(f, files, 9);
        CHECK(store.result.status == ArchiveOpenStatus::Ok);
        CHECK(fast.result.status == ArchiveOpenStatus::Ok);
        CHECK(best.result.status == ArchiveOpenStatus::Ok);
        // Level 0 is real "store": nothing is compressed.
        CHECK(store.bytes.size() >= raw);
        // Any compression level shrinks this text well below store...
        CHECK(fast.bytes.size() < raw * 8 / 10);
        // ...and a higher level is never larger than a lower one.
        CHECK(best.bytes.size() <= fast.bytes.size());
        checkRoundTrip(store.bytes, files);
        checkRoundTrip(fast.bytes, files);
        checkRoundTrip(best.bytes, files);
        std::printf("%-7s size  store=%zu  L1=%zu  L9=%zu  (raw %zu): ok\n", name(f),
                    store.bytes.size(), fast.bytes.size(), best.bytes.size(), raw);
    }

    // --- Every compressing format accepts every UI level and round-trips. --
    for (ArchiveFormat f : {ArchiveFormat::Zip, ArchiveFormat::SevenZip, ArchiveFormat::TarGz,
                            ArchiveFormat::TarBz2, ArchiveFormat::TarXz, ArchiveFormat::TarZstd,
                            ArchiveFormat::TarLzma}) {
        for (int level : {0, 1, 5, 9}) {
            const auto b = build(f, files, level);
            if (b.result.status != ArchiveOpenStatus::Ok) {
                std::fprintf(stderr, "%s level %d failed: %s\n", name(f), level,
                             b.result.errorMessage.c_str());
            }
            CHECK(b.result.status == ArchiveOpenStatus::Ok);
            checkRoundTrip(b.bytes, files);
        }
    }
    std::printf("all formats x levels {0,1,5,9} round-trip: ok\n");

    // The default is unchanged when no level is given.
    {
        const auto dflt = build(ArchiveFormat::SevenZip, files, kArchiveDefaultCompressionLevel);
        const auto explicit6 = build(ArchiveFormat::SevenZip, files, 6);
        CHECK(dflt.result.status == ArchiveOpenStatus::Ok);
        CHECK(dflt.bytes == explicit6.bytes);  // libarchive's default is level 6
        std::printf("default level is libarchive's (6): ok\n");
    }

    // --- Out-of-range levels are refused, not ignored. --------------------
    for (int bad : {-2, 10, 22}) {
        const auto b = build(ArchiveFormat::SevenZip, files, bad);
        CHECK(b.result.status == ArchiveOpenStatus::UnsupportedFormat);
        CHECK(b.bytes.empty());
    }
    std::printf("out-of-range levels rejected: ok\n");

    // --- Passwords combine with every level, including store. -------------
    {
        const std::string pw = "hunter2";
        for (int level : {0, 1, 9}) {
            const auto z = build(ArchiveFormat::Zip, files, level, pw);
            CHECK(z.result.status == ArchiveOpenStatus::Ok);
            checkRoundTrip(z.bytes, files, pw);

            const auto s = build(ArchiveFormat::SevenZip, files, level, pw);
            CHECK(s.result.status == ArchiveOpenStatus::Ok);
            checkRoundTrip(s.bytes, files, pw);

            const auto h = build(ArchiveFormat::SevenZip, files, level, pw, /*encryptNames=*/true);
            CHECK(h.result.status == ArchiveOpenStatus::Ok);
            checkRoundTrip(h.bytes, files, pw);
            // Names really are hidden, even for a stored archive.
            const std::string needle = "notes.txt";
            CHECK(std::search(h.bytes.begin(), h.bytes.end(), needle.begin(), needle.end()) ==
                  h.bytes.end());
        }
        std::printf("encrypted zip / 7z / 7z+header at levels 0,1,9: ok\n");
    }

    // --- Progress counts source bytes, monotonic, ends at the total. ------
    {
        std::vector<uint64_t> seen;
        std::vector<uint8_t> out;
        size_t sinkBytesAtLastProgress = 0;
        ArchiveSink sink;
        sink.write = [&out](const uint8_t* d, size_t n) -> int64_t {
            out.insert(out.end(), d, d + n);
            return static_cast<int64_t>(n);
        };
        std::vector<size_t> offsets(files.size(), 0);
        std::vector<ArchiveSourceEntry> entries(files.size());
        for (size_t i = 0; i < files.size(); ++i) {
            const std::string& content = files[i].second;
            entries[i].pathInArchive = files[i].first;
            entries[i].uncompressedSize = content.size();
            entries[i].modTimeEpochSeconds = 1700000000;
            entries[i].readData = [&content, &offsets, i](uint8_t* dest, size_t length) -> int64_t {
                const size_t n = std::min(length, content.size() - offsets[i]);
                std::memcpy(dest, content.data() + offsets[i], n);
                offsets[i] += n;
                return static_cast<int64_t>(n);
            };
        }
        const auto r = archiveCreate(
            sink, ArchiveFormat::SevenZip, entries, "", false,
            [&](uint64_t processed) {
                seen.push_back(processed);
                sinkBytesAtLastProgress = out.size();
                return true;
            },
            1);
        CHECK(r.status == ArchiveOpenStatus::Ok);
        CHECK(seen.size() > 4);                          // many updates, not one at the end
        CHECK(std::is_sorted(seen.begin(), seen.end())); // monotonic
        CHECK(seen.back() == raw);                       // ends exactly at total source bytes
        // The reason progress must count input: a 7z sink is still empty at the
        // last progress update; all output arrives afterwards, at close.
        CHECK(sinkBytesAtLastProgress == 0);
        CHECK(!out.empty());
        std::printf("7z progress: %zu updates, final=%llu of %zu, sink empty until close: ok\n",
                    seen.size(), static_cast<unsigned long long>(seen.back()), raw);
    }

    // --- Cancel: observed during compression, quick, never "Ok". ----------
    {
        // 1 GiB declared, produced as zeros on demand. Cancelling after the first
        // chunk must not push the other ~1 GiB through the encoder to "finish"
        // the entry.
        const uint64_t huge = 1ull << 30;
        ArchiveSourceEntry e;
        e.pathInArchive = "big.bin";
        e.uncompressedSize = huge;
        uint64_t produced = 0;
        e.readData = [&](uint8_t* dest, size_t length) -> int64_t {
            const size_t n = static_cast<size_t>(std::min<uint64_t>(length, huge - produced));
            std::memset(dest, 0, n);
            produced += n;
            return static_cast<int64_t>(n);
        };
        size_t sinkWrites = 0;
        ArchiveSink sink;
        sink.write = [&](const uint8_t*, size_t n) -> int64_t { ++sinkWrites; return static_cast<int64_t>(n); };

        int calls = 0;
        const auto t0 = std::chrono::steady_clock::now();
        const auto r = archiveCreate(sink, ArchiveFormat::SevenZip, {e}, "", false,
                                     [&](uint64_t) { return ++calls < 2; }, 5);
        const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

        CHECK(r.status != ArchiveOpenStatus::Ok);
        CHECK(calls == 2);                    // stopped polling once it said no
        CHECK(produced < 8ull * 1024 * 1024); // read almost none of the 1 GiB
        CHECK(sinkWrites == 0);               // nothing half-written reaches the destination
        CHECK(secs < 2.0);
        std::printf("7z cancel: stopped after %d callbacks in %.3fs, status!=Ok, no output: ok\n", calls, secs);
    }

    std::printf("archive_create_options_test: all checks passed\n");
    return 0;
}
