// Exercises archive_engine.cpp against a real libarchive (not a fake/stub),
// over in-memory archives this test builds itself with libarchive's own
// write API -- so there's no fixture file to keep in the repo and no
// dependency on a real mounted container. Covers: metadata-only indexing
// (no payload decompression happens during a scan), single-entry
// extraction skipping unrelated entries, AES-256 ZIP passphrase handling
// (right password, wrong password, and no password at all), and a
// non-ZIP format+filter combination (tar+gzip) to confirm the engine
// isn't ZIP-specific.
//
// g++ -std=c++17 archive_engine_test.cpp ../archive_engine.cpp -larchive -o archive_engine_test && ./archive_engine_test
#include "../archive_engine.h"

#include <archive.h>
#include <archive_entry.h>

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace {

void writeEntry(struct archive* a, const std::string& path, const std::string& content) {
    struct archive_entry* entry = archive_entry_new();
    archive_entry_set_pathname(entry, path.c_str());
    archive_entry_set_filetype(entry, AE_IFREG);
    archive_entry_set_perm(entry, 0644);
    archive_entry_set_size(entry, static_cast<int64_t>(content.size()));
    archive_write_header(a, entry);
    archive_write_data(a, content.data(), content.size());
    archive_entry_free(entry);
}

// Builds a ZIP (optionally AES-256 encrypted, if `passphrase` is non-empty)
// containing one directory entry plus the given name->content files.
std::vector<uint8_t> buildZip(const std::vector<std::pair<std::string, std::string>>& files,
                              const std::string& passphrase = "") {
    struct archive* a = archive_write_new();
    archive_write_set_format_zip(a);
    if (!passphrase.empty()) {
        archive_write_set_passphrase(a, passphrase.c_str());
        archive_write_set_options(a, "zip:encryption=aes256");
    }
    std::vector<uint8_t> buffer(1 << 20);
    size_t used = 0;
    archive_write_open_memory(a, buffer.data(), buffer.size(), &used);

    struct archive_entry* dirEntry = archive_entry_new();
    archive_entry_set_pathname(dirEntry, "docs/");
    archive_entry_set_filetype(dirEntry, AE_IFDIR);
    archive_entry_set_perm(dirEntry, 0755);
    archive_write_header(a, dirEntry);
    archive_entry_free(dirEntry);

    for (const auto& file : files) {
        writeEntry(a, file.first, file.second);
    }

    archive_write_close(a);
    archive_write_free(a);
    buffer.resize(used);
    return buffer;
}

std::vector<uint8_t> buildTarGz(const std::vector<std::pair<std::string, std::string>>& files) {
    struct archive* a = archive_write_new();
    archive_write_set_format_pax_restricted(a);
    archive_write_add_filter_gzip(a);
    std::vector<uint8_t> buffer(1 << 20);
    size_t used = 0;
    archive_write_open_memory(a, buffer.data(), buffer.size(), &used);
    for (const auto& file : files) {
        writeEntry(a, file.first, file.second);
    }
    archive_write_close(a);
    archive_write_free(a);
    buffer.resize(used);
    return buffer;
}

// Bytes must outlive the returned source -- same contract real callers
// have with whatever backs their ArchiveStreamSource.
ArchiveStreamSource sourceOver(const std::vector<uint8_t>& bytes) {
    ArchiveStreamSource source;
    source.size = [&bytes]() { return static_cast<uint64_t>(bytes.size()); };
    source.read = [&bytes](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        if (offset >= bytes.size()) return 0;
        const size_t available = std::min(length, bytes.size() - static_cast<size_t>(offset));
        std::memcpy(dest, bytes.data() + offset, available);
        return static_cast<int64_t>(available);
    };
    return source;
}

// Builds a 7-Zip archive through the engine's own archiveCreate() -- the code
// path the app uses -- from name->content files, optionally password protected.
std::vector<uint8_t> buildSevenZipViaEngine(const std::vector<std::pair<std::string, std::string>>& files,
                                            const std::string& passphrase = "") {
    std::vector<uint8_t> out;
    ArchiveSink sink;
    sink.write = [&out](const uint8_t* data, size_t length) -> int64_t {
        out.insert(out.end(), data, data + length);
        return static_cast<int64_t>(length);
    };
    std::vector<size_t> offsets(files.size(), 0);
    std::vector<ArchiveSourceEntry> entries(files.size());
    for (size_t i = 0; i < files.size(); ++i) {
        const std::string& content = files[i].second;
        entries[i].pathInArchive = files[i].first;
        entries[i].uncompressedSize = content.size();
        entries[i].readData = [&content, &offsets, i](uint8_t* dest, size_t length) -> int64_t {
            const size_t n = std::min(length, content.size() - offsets[i]);
            std::memcpy(dest, content.data() + offsets[i], n);
            offsets[i] += n;
            return static_cast<int64_t>(n);
        };
    }
    const auto result = archiveCreate(sink, ArchiveFormat::SevenZip, entries, passphrase);
    assert(result.status == ArchiveOpenStatus::Ok);
    assert(result.entriesArchived == files.size());
    return out;
}

// Tiny 7-Zip archives produced by the real 7-Zip (password: hunter2).
// Files: a.txt = "hello from a" + newline, 20 times; b.txt = "bravo" + newline, 30 times;
// c.txt = "charlie" + newline, 25 times.
// kSevenZipHeaderEncrypted: 7z a -mhe=on a.txt b.txt   (file names are encrypted too)
// kSevenZipAesBcj:          7z a -mf=BCJ -m0=lzma a.txt (3-coder chain: AES + LZMA + BCJ)
// kSevenZipNonSolid:        7z a -ms=off a.txt b.txt c.txt (one AES folder per file)
const unsigned char kSevenZipHeaderEncrypted[] = {
    0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0x5f, 0x53, 0x23, 0xea, 0xb0, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x3d, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x6f, 0x9d, 0x67,
    0xf6, 0xf8, 0xac, 0xfa, 0xd9, 0x17, 0x1e, 0x7f, 0x29, 0xac, 0xbd, 0x85, 0x1c, 0xf7, 0xce, 0x71,
    0x41, 0x91, 0xf4, 0xad, 0xb2, 0x6d, 0xf0, 0x71, 0x93, 0xe2, 0xc9, 0xa4, 0x5c, 0x7b, 0xc2, 0x4f,
    0x6d, 0xf7, 0xad, 0x65, 0x88, 0x98, 0x8e, 0x9d, 0x73, 0x76, 0x83, 0x86, 0x1e, 0x83, 0xa3, 0x9f,
    0x94, 0x4f, 0x05, 0x95, 0x12, 0x4b, 0xe0, 0x18, 0x7c, 0x4c, 0xd5, 0x5d, 0xd2, 0xc5, 0x40, 0xd8,
    0x3a, 0x10, 0x07, 0x61, 0xa3, 0xe3, 0xd4, 0xd8, 0x26, 0xdd, 0xc2, 0xd5, 0x7c, 0x2a, 0xdb, 0x31,
    0xf0, 0x64, 0xf4, 0xdf, 0x6c, 0x69, 0x47, 0xb0, 0xa3, 0x02, 0x38, 0xaa, 0x2c, 0xd1, 0x4f, 0x68,
    0x66, 0x64, 0x48, 0x0f, 0xb4, 0x9a, 0xf2, 0xf2, 0xdc, 0x24, 0xa3, 0x08, 0xa0, 0xe6, 0x98, 0x5d,
    0xab, 0xc9, 0x94, 0xd4, 0x70, 0xdc, 0x46, 0x56, 0x98, 0x22, 0xc2, 0xa8, 0xae, 0x0e, 0x88, 0x8b,
    0x9f, 0x38, 0x4a, 0x05, 0xde, 0x55, 0xde, 0x68, 0xb7, 0x3e, 0xb5, 0x10, 0x56, 0x47, 0xa9, 0x5b,
    0x81, 0x30, 0x7b, 0x33, 0x24, 0x14, 0xbc, 0x67, 0x76, 0xaf, 0xbf, 0xeb, 0xf7, 0x73, 0xd7, 0x04,
    0x73, 0xfc, 0x8a, 0x0e, 0x95, 0x68, 0x8a, 0x4a, 0xf4, 0xad, 0x50, 0x56, 0x7e, 0x4b, 0x41, 0x0b,
    0x17, 0x06, 0x30, 0x01, 0x09, 0x80, 0x80, 0x00, 0x07, 0x0b, 0x01, 0x00, 0x02, 0x24, 0x06, 0xf1,
    0x07, 0x01, 0x12, 0x53, 0x0f, 0xcd, 0xab, 0x63, 0xaa, 0x61, 0x93, 0x83, 0x58, 0xc2, 0xf3, 0x51,
    0x20, 0xc8, 0xc8, 0xd9, 0xb2, 0x23, 0x03, 0x01, 0x01, 0x05, 0x5d, 0x00, 0x10, 0x00, 0x00, 0x01,
    0x00, 0x0c, 0x7b, 0x80, 0x8e, 0x0a, 0x01, 0xd5, 0xff, 0xd1, 0x95, 0x00, 0x00,
};

const unsigned char kSevenZipAesBcj[] = {
    0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0xf5, 0x06, 0x45, 0xa1, 0x20, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x72, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41, 0xbd, 0x4b, 0xd4,
    0x1a, 0x69, 0x58, 0x14, 0xc2, 0x09, 0x5c, 0x87, 0xe5, 0x06, 0x29, 0x94, 0xb3, 0xda, 0x57, 0x8a,
    0x8d, 0x5c, 0x4b, 0x2a, 0x11, 0xbe, 0x4b, 0x1e, 0xee, 0x98, 0x69, 0x2b, 0xed, 0x1c, 0x4e, 0xbf,
    0x01, 0x04, 0x06, 0x00, 0x01, 0x09, 0x20, 0x00, 0x07, 0x0b, 0x01, 0x00, 0x03, 0x24, 0x06, 0xf1,
    0x07, 0x01, 0x12, 0x53, 0x0f, 0x71, 0x25, 0xee, 0x8d, 0x46, 0xe9, 0x67, 0x80, 0xa7, 0x7d, 0xae,
    0xff, 0xe6, 0xe3, 0xbc, 0x26, 0x23, 0x03, 0x01, 0x01, 0x05, 0x5d, 0x00, 0x10, 0x00, 0x00, 0x04,
    0x03, 0x03, 0x01, 0x03, 0x01, 0x00, 0x02, 0x01, 0x0c, 0x15, 0x81, 0x04, 0x81, 0x04, 0x00, 0x08,
    0x0a, 0x01, 0x00, 0xc6, 0xa9, 0x6d, 0x00, 0x00, 0x05, 0x01, 0x19, 0x01, 0x00, 0x11, 0x0d, 0x00,
    0x61, 0x00, 0x2e, 0x00, 0x74, 0x00, 0x78, 0x00, 0x74, 0x00, 0x00, 0x00, 0x14, 0x0a, 0x01, 0x00,
    0xa6, 0xb6, 0xec, 0xd3, 0xe0, 0x58, 0xdd, 0x01, 0x15, 0x06, 0x01, 0x00, 0x20, 0x80, 0xa4, 0x81,
    0x00, 0x00,
};

const unsigned char kSevenZipNonSolid[] = {
    0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0x51, 0x72, 0x71, 0xc1, 0x0c, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xb3, 0xad, 0x32, 0x8a,
    0x47, 0x93, 0x4d, 0xd3, 0xe6, 0x08, 0x5d, 0x9e, 0x61, 0x8c, 0x88, 0x88, 0x0e, 0xb1, 0xd2, 0x73,
    0x78, 0x37, 0x37, 0x9b, 0x38, 0x41, 0x9e, 0xa6, 0xfc, 0x33, 0xd3, 0x64, 0x16, 0x4d, 0xad, 0xd8,
    0x1a, 0x0b, 0xcb, 0x53, 0x56, 0xbd, 0x64, 0x0f, 0xa2, 0x12, 0xf0, 0xc3, 0xfd, 0xb0, 0x49, 0x9d,
    0xca, 0x55, 0xcd, 0x43, 0xd4, 0x73, 0x38, 0x33, 0x11, 0x94, 0xb9, 0x2b, 0xdc, 0x6d, 0x6d, 0x98,
    0xe5, 0x3e, 0xb9, 0x34, 0xc6, 0x6c, 0x1c, 0x72, 0xd1, 0x19, 0xfe, 0xd3, 0x2a, 0xd8, 0x9a, 0x5e,
    0xc6, 0x72, 0x50, 0xb1, 0x0b, 0x87, 0xf8, 0x4b, 0xe6, 0xff, 0x81, 0xb3, 0x6b, 0xbe, 0x39, 0xca,
    0x00, 0x00, 0x81, 0x33, 0x07, 0xae, 0x4f, 0xa0, 0x80, 0x6e, 0x73, 0x31, 0x06, 0xc1, 0x86, 0x5a,
    0x41, 0x07, 0x23, 0x9d, 0xcd, 0x21, 0x79, 0xf1, 0xc5, 0x33, 0x18, 0xc4, 0xda, 0x0a, 0x17, 0xdf,
    0x5e, 0x50, 0x6a, 0xd1, 0x7f, 0x51, 0xd7, 0x53, 0xad, 0x62, 0xc8, 0x9a, 0xf1, 0xf7, 0xc6, 0xa9,
    0xbc, 0x83, 0x28, 0x59, 0x73, 0xd9, 0x6a, 0xc7, 0x39, 0x5e, 0xbf, 0xbe, 0x8d, 0x51, 0xc8, 0x0a,
    0x8d, 0xf6, 0xfb, 0x0d, 0x02, 0xc7, 0xed, 0xa3, 0xf4, 0x4a, 0xae, 0x92, 0xf2, 0xfa, 0xa2, 0x39,
    0x26, 0x53, 0xd5, 0xb6, 0x58, 0xd3, 0x00, 0x9c, 0x0d, 0xd7, 0x3c, 0x72, 0x90, 0x38, 0x85, 0xdb,
    0x1c, 0x27, 0x7a, 0xd5, 0xe3, 0x0f, 0xbe, 0x37, 0x75, 0x29, 0x90, 0x3e, 0xab, 0xca, 0x81, 0xbb,
    0x9d, 0xd8, 0xbf, 0xd0, 0xbc, 0xe5, 0xbc, 0x14, 0x66, 0x0e, 0x39, 0x5e, 0xfd, 0xce, 0x2b, 0xef,
    0x41, 0x15, 0xf7, 0x8b, 0xf7, 0xe5, 0xc2, 0x67, 0x04, 0x3f, 0x9c, 0x05, 0x6b, 0xa5, 0x2f, 0x57,
    0x1c, 0x10, 0x86, 0x2d, 0x7e, 0x7b, 0x2b, 0x27, 0x1c, 0xe7, 0x64, 0x43, 0x20, 0xd3, 0x0a, 0xc8,
    0xf0, 0x8b, 0x4b, 0x04, 0x41, 0x3a, 0xec, 0x14, 0xe3, 0x00, 0x00, 0x00, 0x17, 0x06, 0x60, 0x01,
    0x09, 0x80, 0xac, 0x00, 0x07, 0x0b, 0x01, 0x00, 0x01, 0x23, 0x03, 0x01, 0x01, 0x05, 0x5d, 0x00,
    0x10, 0x00, 0x00, 0x0c, 0x80, 0xe2, 0x0a, 0x01, 0x71, 0x04, 0x6f, 0x08, 0x00, 0x00,
};

std::vector<uint8_t> toVector(const unsigned char* data, size_t length) {
    return std::vector<uint8_t>(data, data + length);
}

std::string extractText(const std::vector<uint8_t>& archive, const std::string& name,
                        const std::string& passphrase, ArchiveOpenStatus* status) {
    const auto scan = archiveScanEntries(sourceOver(archive), passphrase);
    for (const auto& e : scan.entries) {
        if (e.path == name) {
            const auto r = archiveExtractEntry(sourceOver(archive), e.index, passphrase);
            *status = r.status;
            return std::string(r.data.begin(), r.data.end());
        }
    }
    *status = scan.status;
    return {};
}

}  // namespace

int main() {
    // --- Plain ZIP: metadata-only listing, then targeted extraction of
    // one entry out of several. ---
    {
        const auto zipBytes = buildZip({
            {"hello.txt", "hello world"},
            {"nested/data.bin", std::string(5000, 'x')},
        });
        const auto source = sourceOver(zipBytes);

        const auto indexResult = archiveScanEntries(source);
        assert(indexResult.status == ArchiveOpenStatus::Ok);
        assert(indexResult.entries.size() == 3);  // docs/ + hello.txt + nested/data.bin

        bool sawDir = false, sawHello = false, sawNested = false;
        int32_t helloIndex = -1, nestedIndex = -1;
        for (const auto& e : indexResult.entries) {
            if (e.path == "docs/") {
                sawDir = true;
                assert(e.isDirectory);
            } else if (e.path == "hello.txt") {
                sawHello = true;
                helloIndex = e.index;
                assert(e.uncompressedSize == 11);
                assert(!e.isDirectory);
                assert(!e.isEncrypted);
            } else if (e.path == "nested/data.bin") {
                sawNested = true;
                nestedIndex = e.index;
                assert(e.uncompressedSize == 5000);
            }
        }
        assert(sawDir && sawHello && sawNested);

        const auto extractedNested = archiveExtractEntry(source, nestedIndex);
        assert(extractedNested.status == ArchiveOpenStatus::Ok);
        assert(extractedNested.data.size() == 5000);
        assert(extractedNested.data.front() == 'x' && extractedNested.data.back() == 'x');

        const auto extractedHello = archiveExtractEntry(source, helloIndex);
        assert(extractedHello.status == ArchiveOpenStatus::Ok);
        assert(std::string(extractedHello.data.begin(), extractedHello.data.end()) == "hello world");

        std::vector<uint8_t> streamedNested;
        const auto streamedResult = archiveExtractEntryToSink(
            source,
            nestedIndex,
            "",
            [&streamedNested](const uint8_t* data, size_t length) {
                streamedNested.insert(streamedNested.end(), data, data + length);
                return true;
            });
        assert(streamedResult.status == ArchiveOpenStatus::Ok);
        assert(streamedResult.data.empty());
        assert(streamedNested == extractedNested.data);

        printf("zip index+extract: ok\n");
    }

    // --- AES-256 encrypted ZIP: archiveScanEntries probe-decrypts the
    // first non-empty encrypted entry it hits (see the comment above that
    // probe in archive_engine.cpp) specifically so a missing or wrong
    // passphrase is caught at scan time, not silently deferred to
    // extraction -- so, unlike a plain ZIP, listing this one needs the
    // right passphrase too. ---
    {
        const auto zipBytes = buildZip({{"secret.txt", "top secret payload"}},
                                       "correct horse battery staple");
        const auto source = sourceOver(zipBytes);

        const auto noPassScan = archiveScanEntries(source);
        assert(noPassScan.status == ArchiveOpenStatus::PassphraseRequired);

        const auto wrongPassScan = archiveScanEntries(source, "wrong password");
        assert(wrongPassScan.status == ArchiveOpenStatus::WrongPassphrase);

        const auto indexResult = archiveScanEntries(source, "correct horse battery staple");
        assert(indexResult.status == ArchiveOpenStatus::Ok);
        int32_t secretIndex = -1;
        for (const auto& e : indexResult.entries) {
            if (e.path == "secret.txt") {
                secretIndex = e.index;
                assert(e.isEncrypted);
            }
        }
        assert(secretIndex >= 0);

        const auto noPass = archiveExtractEntry(source, secretIndex);
        assert(noPass.status != ArchiveOpenStatus::Ok);

        const auto wrongPass = archiveExtractEntry(source, secretIndex, "wrong password");
        assert(wrongPass.status != ArchiveOpenStatus::Ok);

        const auto rightPass = archiveExtractEntry(source, secretIndex, "correct horse battery staple");
        assert(rightPass.status == ArchiveOpenStatus::Ok);
        assert(std::string(rightPass.data.begin(), rightPass.data.end()) == "top secret payload");

        printf("zip aes256 passphrase handling: ok\n");
    }

    // --- TAR+gzip: different format/filter combination, and confirms
    // that skipping earlier entries doesn't disturb extraction of a
    // later one. ---
    {
        const auto tarGzBytes = buildTarGz({
            {"a.txt", "first"},
            {"b.txt", "second file, a bit longer"},
            {"c.txt", "third"},
        });
        const auto source = sourceOver(tarGzBytes);

        const auto indexResult = archiveScanEntries(source);
        assert(indexResult.status == ArchiveOpenStatus::Ok);
        assert(indexResult.entries.size() == 3);
        assert(!indexResult.isSolid);  // tar+gzip isn't a solid-capable format family

        const auto middle = archiveExtractEntry(source, indexResult.entries[1].index);
        assert(middle.status == ArchiveOpenStatus::Ok);
        assert(std::string(middle.data.begin(), middle.data.end()) == "second file, a bit longer");

        const auto last = archiveExtractEntry(source, indexResult.entries[2].index);
        assert(last.status == ArchiveOpenStatus::Ok);
        assert(std::string(last.data.begin(), last.data.end()) == "third");

        printf("tar.gz index+extract: ok\n");
    }

    // --- 7-Zip creation through the engine: a plain archive must stay
    // plain, and one created with a passphrase must really be encrypted.
    // (Stock libarchive accepts a passphrase for 7-Zip and then silently
    // writes an unprotected archive; libarchive-7zip-encryption.patch fixes
    // that, and this fails if the patch is ever missing.) ---
    {
        const std::vector<std::pair<std::string, std::string>> files = {
            {"docs/a.txt", std::string(70000, 'A')},
            {"b.txt", "short secret"},
        };

        const auto plain = buildSevenZipViaEngine(files);
        const auto plainScan = archiveScanEntries(sourceOver(plain));
        assert(plainScan.status == ArchiveOpenStatus::Ok);
        assert(plainScan.entries.size() == 2);
        for (const auto& e : plainScan.entries) assert(!e.isEncrypted);

        const auto locked = buildSevenZipViaEngine(files, "hunter2");
        // Without a password the 7-Zip entry list is still readable (names are
        // not encrypted) but every entry must be flagged as protected, and
        // reading the data must ask for the password.
        const auto lockedScan = archiveScanEntries(sourceOver(locked));
        assert(lockedScan.status == ArchiveOpenStatus::Ok);
        assert(lockedScan.entries.size() == files.size());
        for (const auto& e : lockedScan.entries) assert(e.isEncrypted);
        const auto noPass = archiveExtractEntry(sourceOver(locked), lockedScan.entries[0].index, "");
        assert(noPass.status == ArchiveOpenStatus::PassphraseRequired);

        const auto wrongPassScan = archiveScanEntries(sourceOver(locked), "wrong password");
        assert(wrongPassScan.status == ArchiveOpenStatus::WrongPassphrase);

        const auto unlockedScan = archiveScanEntries(sourceOver(locked), "hunter2");
        assert(unlockedScan.status == ArchiveOpenStatus::Ok);
        assert(unlockedScan.entries.size() == files.size());
        int32_t firstFileIndex = -1;
        for (const auto& entry : unlockedScan.entries) {
            assert(entry.isEncrypted);
            if (entry.path == "docs/a.txt") firstFileIndex = entry.index;
        }
        assert(firstFileIndex >= 0);

        const auto extracted = archiveExtractEntry(sourceOver(locked), firstFileIndex, "hunter2");
        assert(extracted.status == ArchiveOpenStatus::Ok);
        assert(std::string(extracted.data.begin(), extracted.data.end()) == files[0].second);

        // The archive ends exactly where its start header says: no zero
        // padding after the header (7-Zip warns about trailing data).
        for (const auto* archiveBytes : {&plain, &locked}) {
            const auto& b = *archiveBytes;
            assert(b.size() > 32 && std::memcmp(b.data(), "7z\xBC\xAF\x27\x1C", 6) == 0);
            uint64_t headerOffset = 0, headerSize = 0;
            for (int i = 7; i >= 0; --i) {
                headerOffset = (headerOffset << 8) | b[12 + i];
                headerSize = (headerSize << 8) | b[20 + i];
            }
            assert(32 + headerOffset + headerSize == b.size());
        }
        printf("7z create (plain + password): ok\n");
    }

    // --- Reading password-protected 7-Zip archives made by the real 7-Zip. ---
    {
        const std::string a = "hello from a\n", b = "bravo\n", c = "charlie\n";
        auto repeat = [](const std::string& s, int n) { std::string r; for (int i = 0; i < n; ++i) r += s; return r; };
        ArchiveOpenStatus st = ArchiveOpenStatus::IoError;

        // Encrypted header: nothing is listed without the password, a wrong one
        // is reported as such (not as a damaged archive), the right one works.
        const auto hdr = toVector(kSevenZipHeaderEncrypted, sizeof(kSevenZipHeaderEncrypted));
        assert(archiveScanEntries(sourceOver(hdr)).status == ArchiveOpenStatus::PassphraseRequired);
        assert(archiveScanEntries(sourceOver(hdr), "wrong").status == ArchiveOpenStatus::WrongPassphrase);
        assert(extractText(hdr, "b.txt", "hunter2", &st) == repeat(b, 30) && st == ArchiveOpenStatus::Ok);

        // AES + LZMA + BCJ is a three-coder chain.
        const auto bcj = toVector(kSevenZipAesBcj, sizeof(kSevenZipAesBcj));
        assert(extractText(bcj, "a.txt", "hunter2", &st) == repeat(a, 20) && st == ArchiveOpenStatus::Ok);
        extractText(bcj, "a.txt", "wrong", &st);
        assert(st == ArchiveOpenStatus::WrongPassphrase);

        // One AES folder per file: every folder must get the passphrase, and
        // the (expensive) key derivation is shared between them.
        const auto ns = toVector(kSevenZipNonSolid, sizeof(kSevenZipNonSolid));
        assert(archiveScanEntries(sourceOver(ns), "hunter2").entries.size() == 3);
        assert(extractText(ns, "a.txt", "hunter2", &st) == repeat(a, 20) && st == ArchiveOpenStatus::Ok);
        assert(extractText(ns, "b.txt", "hunter2", &st) == repeat(b, 30) && st == ArchiveOpenStatus::Ok);
        assert(extractText(ns, "c.txt", "hunter2", &st) == repeat(c, 25) && st == ArchiveOpenStatus::Ok);
        extractText(ns, "c.txt", "wrong", &st);
        assert(st == ArchiveOpenStatus::WrongPassphrase);
        printf("7z read (encrypted header, AES+BCJ, non-solid): ok\n");
    }

    // --- Out-of-range index: should fail cleanly, not crash or return
    // another entry's data. ---
    {
        const auto zipBytes = buildZip({{"only.txt", "x"}});
        const auto source = sourceOver(zipBytes);
        const auto result = archiveExtractEntry(source, 999);
        assert(result.status != ArchiveOpenStatus::Ok);
        assert(result.data.empty());
        printf("out-of-range index: ok\n");
    }

    printf("archive_engine_test: all assertions passed\n");
    return 0;
}
