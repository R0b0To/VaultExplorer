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

std::vector<ArchiveSourceEntry> entriesFor(const Files& files, std::vector<size_t>& offsets) {
    offsets.assign(files.size(), 0);
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
    return entries;
}

Built build(ArchiveFormat format, const Files& files, int level,
            const std::string& pass = "", bool encryptNames = false,
            std::function<bool(uint64_t)> progress = nullptr) {
    Built b;
    ArchiveSink sink;
    sink.write = [&b](const uint8_t* d, size_t n) -> int64_t {
        b.bytes.insert(b.bytes.end(), d, d + n);
        return static_cast<int64_t>(n);
    };
    std::vector<size_t> offsets;
    const auto entries = entriesFor(files, offsets);
    b.result = archiveCreate(sink, format, entries, pass, encryptNames, std::move(progress), level);
    return b;
}

// One progress report, with how many archive bytes had reached the sink when it
// was made. That pairing is what tells the reading phase (sink still empty, for
// 7z/ISO) from the finishing phase (buffered output being copied out).
struct ProgressSample {
    uint64_t value;
    size_t sinkBytes;
};

struct ProgressRun {
    ArchiveCreateResult result;
    std::vector<ProgressSample> samples;
    size_t sinkTotal = 0;
};

// `cancelWhen` returning true for a sample makes the callback ask to cancel.
ProgressRun runWithProgress(ArchiveFormat format, const Files& files, int level,
                            const std::string& pass = "",
                            std::function<bool(const ProgressSample&)> cancelWhen = nullptr) {
    ProgressRun run;
    ArchiveSink sink;
    sink.write = [&run](const uint8_t*, size_t n) -> int64_t {
        run.sinkTotal += n;
        return static_cast<int64_t>(n);
    };
    std::vector<size_t> offsets;
    const auto entries = entriesFor(files, offsets);
    run.result = archiveCreate(
        sink, format, entries, pass, false,
        [&](uint64_t value) {
            const ProgressSample sample{value, run.sinkTotal};
            run.samples.push_back(sample);
            return !(cancelWhen && cancelWhen(sample));
        },
        level);
    return run;
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

    // --- Progress ------------------------------------------------------------
    // Range is 0 .. total source bytes. Streaming formats use all of it for
    // reading. 7z and ISO only write output when the archive is closed, so the
    // tail of the range belongs to that finishing phase: otherwise a store would
    // sit at 100% for as long as the copy-out takes (nearly all of its time).
    {
        for (ArchiveFormat f : {ArchiveFormat::Zip, ArchiveFormat::Tar, ArchiveFormat::Cpio}) {
            const auto run = runWithProgress(f, files, 5);
            CHECK(run.result.status == ArchiveOpenStatus::Ok);
            CHECK(run.samples.size() > 4);
            for (size_t i = 1; i < run.samples.size(); ++i) {
                CHECK(run.samples[i].value >= run.samples[i - 1].value);
            }
            CHECK(run.samples.back().value == raw);  // all of the range is reading
            // ...and the sink is already being fed while it reads.
            CHECK(run.samples[run.samples.size() / 2].sinkBytes > 0);
        }
        std::printf("zip/tar/cpio progress: whole range is reading, ends at total: ok\n");

        struct Case {
            const char* label;
            ArchiveFormat format;
            int level;
            const char* pass;
            double readShare;  // part of the range given to reading the sources
            bool storesData;
        };
        const Case cases[] = {
            {"7z level 1", ArchiveFormat::SevenZip, 1, "", 0.9, false},
            {"7z default level", ArchiveFormat::SevenZip, kArchiveDefaultCompressionLevel, "", 0.9, false},
            {"7z store", ArchiveFormat::SevenZip, 0, "", 0.5, true},
            {"7z store + password", ArchiveFormat::SevenZip, 0, "hunter2", 0.5, true},
            {"iso", ArchiveFormat::Iso, kArchiveDefaultCompressionLevel, "", 0.5, true},
        };
        for (const Case& c : cases) {
            const auto run = runWithProgress(c.format, files, c.level, c.pass);
            CHECK(run.result.status == ArchiveOpenStatus::Ok);
            const uint64_t readEnd = static_cast<uint64_t>(static_cast<double>(raw) * c.readShare);

            uint64_t lastReading = 0;
            size_t finishing = 0;
            for (size_t i = 0; i < run.samples.size(); ++i) {
                const auto& sm = run.samples[i];
                CHECK(sm.value <= raw);
                if (i > 0) CHECK(sm.value >= run.samples[i - 1].value);
                if (sm.sinkBytes == 0) {
                    // Reading never claims the share reserved for finishing.
                    CHECK(sm.value <= readEnd);
                    lastReading = sm.value;
                } else {
                    // Finishing starts where reading stopped and stays within range.
                    CHECK(sm.value >= readEnd);
                    ++finishing;
                }
            }
            CHECK(lastReading + 1 >= readEnd);  // reading really does use its whole share
            CHECK(finishing > 0);               // the copy-out is reported, not silent
            if (c.storesData) {
                CHECK(finishing >= 3);
                // The bar must be well short of done when the copy-out begins, and
                // finish close to the total (it's nearly the same amount of data).
                CHECK(lastReading <= raw / 2 + 1);
                CHECK(run.samples.back().value >= raw * 9 / 10);
            }
            std::printf("%-20s progress: reading ends at %5.1f%%, %zu finishing updates, last=%5.1f%%: ok\n",
                        c.label, 100.0 * static_cast<double>(lastReading) / static_cast<double>(raw),
                        finishing, 100.0 * static_cast<double>(run.samples.back().value) / static_cast<double>(raw));
        }

        // Cancelling while the buffered output is copied out is a cancel, not an
        // "unsupported format" failure, and stops the copy.
        const auto full = runWithProgress(ArchiveFormat::SevenZip, files, 0);
        const auto cut = runWithProgress(ArchiveFormat::SevenZip, files, 0, "",
                                         [](const ProgressSample& sm) { return sm.sinkBytes > 0; });
        CHECK(full.result.status == ArchiveOpenStatus::Ok);
        CHECK(cut.result.status == ArchiveOpenStatus::IoError);
        CHECK(cut.result.errorMessage.find("cancelled") != std::string::npos);
        CHECK(cut.sinkTotal < full.sinkTotal / 2);
        std::printf("7z cancel during copy-out: reported as cancelled, %zu of %zu bytes written: ok\n",
                    cut.sinkTotal, full.sinkTotal);
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
