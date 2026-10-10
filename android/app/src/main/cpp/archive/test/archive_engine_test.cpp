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
        // Without a password the archive must be recognised as protected.
        const auto lockedScan = archiveScanEntries(sourceOver(locked));
        assert(lockedScan.status == ArchiveOpenStatus::PassphraseRequired);

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
