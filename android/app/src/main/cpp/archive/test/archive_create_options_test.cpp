// Covers the options archiveCreate() takes beyond format + entries:
//
//  * compressionLevel -- must change what is written (it used to be dropped
//    before it reached libarchive, so every archive came out at the default),
//    must round-trip for every format that compresses, and out-of-range values
//    must be refused rather than ignored.
//  * compressionMethod -- LZMA2 / LZMA / Deflate where the format can write
//    them (7z; ZIP and the TARs only their own), refused everywhere else, and
//    checked on the bytes rather than on archiveCreate's say-so.
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
            std::function<bool(uint64_t)> progress = nullptr,
            ArchiveCompressionMethod method = ArchiveCompressionMethod::Default) {
    Built b;
    ArchiveSink sink;
    sink.write = [&b](const uint8_t* d, size_t n) -> int64_t {
        b.bytes.insert(b.bytes.end(), d, d + n);
        return static_cast<int64_t>(n);
    };
    std::vector<size_t> offsets;
    const auto entries = entriesFor(files, offsets);
    b.result = archiveCreate(sink, format, entries, pass, encryptNames, std::move(progress), level, method);
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

const char* methodName(ArchiveCompressionMethod m) {
    switch (m) {
        case ArchiveCompressionMethod::Default: return "default";
        case ArchiveCompressionMethod::Deflate: return "deflate";
        case ArchiveCompressionMethod::Lzma: return "lzma";
        case ArchiveCompressionMethod::Lzma2: return "lzma2";
    }
    return "?";
}

// Which codec a finished archive really used, read off its bytes.
//  * 7z: the first packed stream starts right after the 32-byte signature
//    header. A raw LZMA stream always begins with a 0x00 range-coder byte; an
//    LZMA2 stream begins with a chunk control byte whose top three bits are set
//    (0xE0: dictionary reset + new properties) for compressible input. Anything
//    else here is Deflate. Only meaningful for an unencrypted archive.
//  * ZIP: the first local header holds the method at offset 8 (8 = deflate).
//  * TAR.GZ / .XZ / .LZMA: the filter's own magic.
ArchiveCompressionMethod detectMethod(ArchiveFormat f, const std::vector<uint8_t>& b) {
    switch (f) {
        case ArchiveFormat::SevenZip: {
            CHECK(b.size() > 33);
            const uint8_t first = b[32];
            if (first == 0x00) return ArchiveCompressionMethod::Lzma;
            if ((first & 0xE0) == 0xE0) return ArchiveCompressionMethod::Lzma2;
            return ArchiveCompressionMethod::Deflate;
        }
        case ArchiveFormat::Zip:
            CHECK(b.size() > 10 && b[0] == 'P' && b[1] == 'K');
            return (b[8] | (b[9] << 8)) == 8 ? ArchiveCompressionMethod::Deflate
                                             : ArchiveCompressionMethod::Default;
        case ArchiveFormat::TarGz:
            CHECK(b.size() > 2 && b[0] == 0x1f && b[1] == 0x8b);
            return ArchiveCompressionMethod::Deflate;
        case ArchiveFormat::TarXz:
            CHECK(b.size() > 6 && b[0] == 0xfd && b[1] == '7' && b[2] == 'z' && b[3] == 'X' && b[4] == 'Z');
            return ArchiveCompressionMethod::Lzma2;
        case ArchiveFormat::TarLzma:
            CHECK(b.size() > 5 && b[0] == 0x5d && !(b[1] == '7' && b[2] == 'z'));
            return ArchiveCompressionMethod::Lzma;
        default:
            return ArchiveCompressionMethod::Default;
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

    // --- Compression method ------------------------------------------------
    {
        using M = ArchiveCompressionMethod;
        const std::vector<ArchiveFormat> allFormats = {
            ArchiveFormat::Zip, ArchiveFormat::SevenZip, ArchiveFormat::Tar, ArchiveFormat::TarGz,
            ArchiveFormat::TarBz2, ArchiveFormat::TarXz, ArchiveFormat::TarZstd, ArchiveFormat::TarLzma,
            ArchiveFormat::Iso, ArchiveFormat::Cpio};
        const std::vector<M> allMethods = {M::Default, M::Deflate, M::Lzma, M::Lzma2};

        // The support matrix, spelled out.
        auto expected = [](ArchiveFormat f, M m) {
            if (m == M::Default) return true;
            switch (f) {
                case ArchiveFormat::Zip: return m == M::Deflate;
                case ArchiveFormat::SevenZip: return m != M::Default;
                case ArchiveFormat::TarGz: return m == M::Deflate;
                case ArchiveFormat::TarXz: return m == M::Lzma2;
                case ArchiveFormat::TarLzma: return m == M::Lzma;
                default: return false;
            }
        };
        for (ArchiveFormat f : allFormats) {
            for (M m : allMethods) CHECK(archiveCompressionMethodSupported(f, m) == expected(f, m));
        }
        std::printf("method support matrix: ok\n");

        // archiveCreate agrees with the matrix: supported combinations write an
        // archive that reads back, unsupported ones are refused with nothing written.
        for (ArchiveFormat f : allFormats) {
            for (M m : allMethods) {
                const auto b = build(f, files, kArchiveDefaultCompressionLevel, "", false, nullptr, m);
                if (expected(f, m)) {
                    if (b.result.status != ArchiveOpenStatus::Ok) {
                        std::fprintf(stderr, "%s + %s failed: %s\n", name(f), methodName(m),
                                     b.result.errorMessage.c_str());
                    }
                    CHECK(b.result.status == ArchiveOpenStatus::Ok);
                    if (f != ArchiveFormat::Iso && f != ArchiveFormat::Cpio && f != ArchiveFormat::Tar) {
                        checkRoundTrip(b.bytes, files);
                    }
                } else {
                    CHECK(b.result.status == ArchiveOpenStatus::UnsupportedFormat);
                    CHECK(b.bytes.empty());
                }
            }
        }
        std::printf("every format x method follows the matrix (written, or refused with no output): ok\n");

        // The method that was asked for is the one on disk.
        for (M m : {M::Deflate, M::Lzma, M::Lzma2}) {
            const auto b = build(ArchiveFormat::SevenZip, files, kArchiveDefaultCompressionLevel, "",
                                 false, nullptr, m);
            CHECK(b.result.status == ArchiveOpenStatus::Ok);
            CHECK(detectMethod(ArchiveFormat::SevenZip, b.bytes) == m);
            checkRoundTrip(b.bytes, files);
        }
        for (auto [f, m] : {std::pair{ArchiveFormat::Zip, M::Deflate}, std::pair{ArchiveFormat::TarGz, M::Deflate},
                            std::pair{ArchiveFormat::TarXz, M::Lzma2}, std::pair{ArchiveFormat::TarLzma, M::Lzma}}) {
            const auto b = build(f, files, kArchiveDefaultCompressionLevel, "", false, nullptr, m);
            CHECK(b.result.status == ArchiveOpenStatus::Ok);
            CHECK(detectMethod(f, b.bytes) == m);
        }
        std::printf("the chosen method is what ends up in the archive: ok\n");

        // 7z with no method keeps libarchive's own default, which is LZMA (not
        // LZMA2): byte-identical to asking for LZMA, and different from LZMA2.
        {
            const auto dflt = build(ArchiveFormat::SevenZip, files, kArchiveDefaultCompressionLevel);
            const auto lzma = build(ArchiveFormat::SevenZip, files, kArchiveDefaultCompressionLevel, "", false, nullptr, M::Lzma);
            const auto lzma2 = build(ArchiveFormat::SevenZip, files, kArchiveDefaultCompressionLevel, "", false, nullptr, M::Lzma2);
            const auto deflate = build(ArchiveFormat::SevenZip, files, kArchiveDefaultCompressionLevel, "", false, nullptr, M::Deflate);
            CHECK(dflt.bytes == lzma.bytes);
            CHECK(dflt.bytes != lzma2.bytes);
            // On compressible text both LZMA flavours beat Deflate.
            CHECK(lzma.bytes.size() < deflate.bytes.size());
            CHECK(lzma2.bytes.size() < deflate.bytes.size());
            std::printf("7z sizes  deflate=%zu  lzma=%zu  lzma2=%zu (default == lzma): ok\n",
                        deflate.bytes.size(), lzma.bytes.size(), lzma2.bytes.size());
        }

        // Methods combine with levels, passwords and (7z) encrypted file names.
        {
            const std::string pw = "hunter2";
            for (M m : {M::Deflate, M::Lzma, M::Lzma2}) {
                for (int level : {1, 5, 9}) {
                    const auto b = build(ArchiveFormat::SevenZip, files, level, "", false, nullptr, m);
                    CHECK(b.result.status == ArchiveOpenStatus::Ok);
                    CHECK(detectMethod(ArchiveFormat::SevenZip, b.bytes) == m);
                    checkRoundTrip(b.bytes, files);
                }
                const auto enc = build(ArchiveFormat::SevenZip, files, 5, pw, false, nullptr, m);
                CHECK(enc.result.status == ArchiveOpenStatus::Ok);
                checkRoundTrip(enc.bytes, files, pw);
                const auto hidden = build(ArchiveFormat::SevenZip, files, 5, pw, true, nullptr, m);
                CHECK(hidden.result.status == ArchiveOpenStatus::Ok);
                checkRoundTrip(hidden.bytes, files, pw);
                const std::string needle = "log.txt";
                CHECK(std::search(hidden.bytes.begin(), hidden.bytes.end(), needle.begin(), needle.end()) ==
                      hidden.bytes.end());
            }
            const auto zipPw = build(ArchiveFormat::Zip, files, 5, pw, false, nullptr, M::Deflate);
            CHECK(zipPw.result.status == ArchiveOpenStatus::Ok);
            checkRoundTrip(zipPw.bytes, files, pw);
            std::printf("methods x levels x password x hidden names: ok\n");
        }

        // Level 0 is "store", which has no codec: naming one is an error on ZIP and
        // 7z rather than a silent override. The TARs still accept their own.
        for (ArchiveFormat f : {ArchiveFormat::Zip, ArchiveFormat::SevenZip}) {
            for (M m : {M::Deflate, M::Lzma, M::Lzma2}) {
                if (!expected(f, m)) continue;
                const auto b = build(f, files, 0, "", false, nullptr, m);
                CHECK(b.result.status == ArchiveOpenStatus::UnsupportedFormat);
                CHECK(b.bytes.empty());
            }
        }
        const auto xzStore = build(ArchiveFormat::TarXz, files, 0, "", false, nullptr, M::Lzma2);
        CHECK(xzStore.result.status == ArchiveOpenStatus::Ok);
        std::printf("method + store: refused on zip/7z, fine where the method is the filter: ok\n");
    }

    std::printf("archive_create_options_test: all checks passed\n");
    return 0;
}
