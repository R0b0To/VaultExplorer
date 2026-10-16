#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <functional>

#include "archive_stream_source.h"

struct ArchiveEntryInfo {
    std::string path;
    uint64_t uncompressedSize = 0;
    uint64_t compressedSize = 0;
    int64_t modTimeEpochSeconds = 0;
    bool isEncrypted = false;
    bool isDirectory = false;
    int32_t index = -1;
};

enum class ArchiveOpenStatus {
    Ok,
    UnsupportedFormat,
    PassphraseRequired,
    WrongPassphrase,
    IoError,
};

struct ArchiveIndexResult {
    ArchiveOpenStatus status = ArchiveOpenStatus::IoError;
    std::vector<ArchiveEntryInfo> entries;
    bool isSolid = false;
    bool isSevenZip = false;
    std::string errorMessage;
};

ArchiveIndexResult archiveScanEntries(const ArchiveStreamSource& source,
                                      const std::string& passphrase = "");

struct ArchiveExtractResult {
    ArchiveOpenStatus status = ArchiveOpenStatus::IoError;
    std::vector<uint8_t> data;
    std::string errorMessage;
};

ArchiveExtractResult archiveExtractEntry(const ArchiveStreamSource& source,
                                         int32_t targetIndex,
                                         const std::string& passphrase = "");

/// Streams one archive entry to [writeChunk] without retaining its payload in
/// memory. The callback receives sequential chunks and must return false to
/// abort the extraction.
ArchiveExtractResult archiveExtractEntryToSink(
    const ArchiveStreamSource& source,
    int32_t targetIndex,
    const std::string& passphrase,
    std::function<bool(const uint8_t* data, size_t length)> writeChunk
);

struct ArchiveBulkExtractResult {
    ArchiveOpenStatus status = ArchiveOpenStatus::IoError;
    int32_t extractedCount = 0;
    std::string errorMessage;
};

ArchiveBulkExtractResult archiveExtractAll(
    const ArchiveStreamSource& source,
    const std::string& passphrase,
    const std::string& subPathPrefix,
    std::function<bool(const std::string& dirPath)> makeDir,
    std::function<bool(const std::string& filePath, uint64_t offset, const uint8_t* data, size_t length)> writeFileChunk,
    std::function<bool(int32_t count, const std::string& currentPath)> progressCallback = nullptr
);

// ── Archive Creation (Compression / Packaging) ──────────────────────────

enum class ArchiveFormat : int32_t {
    Zip = 0,
    SevenZip = 1,
    Tar = 2,
    TarGz = 3,
    TarBz2 = 4,
    TarXz = 5,
    TarZstd = 6,
    TarLzma = 7,
    Iso = 8,
    Cpio = 9,
};

struct ArchiveSourceEntry {
    std::string pathInArchive;
    bool isDirectory = false;
    uint64_t uncompressedSize = 0;
    int64_t modTimeEpochSeconds = 0;
    // Callback to read chunk data for this file entry. Return <= 0 on EOF, -1 on error.
    std::function<int64_t(uint8_t* dest, size_t length)> readData;
};

struct ArchiveSink {
    // Callback to write compressed archive output bytes. Return bytes written or -1 on error.
    std::function<int64_t(const uint8_t* data, size_t length)> write;
};

struct ArchiveCreateResult {
    ArchiveOpenStatus status = ArchiveOpenStatus::IoError;
    uint64_t totalBytesWritten = 0;
    uint32_t entriesArchived = 0;
    std::string errorMessage;
};

ArchiveCreateResult archiveCreate(
    const ArchiveSink& sink,
    ArchiveFormat format,
    const std::vector<ArchiveSourceEntry>& entries,
    const std::string& passphrase = "",
    // 7z only: also encrypt the archive header, so file names, sizes and times
    // are hidden as well (7-Zip's "Encrypt file names"). Needs a passphrase;
    // the request fails, rather than being ignored, when it can't be honoured.
    bool encryptFilenames = false,
    std::function<bool(uint64_t bytesWrittenSoFar)> progressCallback = nullptr
);
