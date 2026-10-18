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

// The codec behind a compressed archive. Values are shared with the Dart
// ArchiveCompressionMethod enum and the JNI layer, so don't renumber them.
enum class ArchiveCompressionMethod : int32_t {
    Default = 0,  // the format's own default codec
    Deflate = 1,  // ZIP, 7z, TAR.GZ
    Lzma    = 2,  // LZMA1: 7z, TAR.LZMA
    Lzma2   = 3,  // 7z, TAR.XZ
};

/// Whether `format` can write its data with `method`:
///   ZIP      Deflate
///   7z       Deflate, LZMA, LZMA2 (with or without a password)
///   TAR.GZ   Deflate   (the only codec; accepted so a caller can state it)
///   TAR.XZ   LZMA2     (same)
///   TAR.LZMA LZMA      (same)
/// Everything else (TAR.BZ2, TAR.ZST, plain TAR, ISO, CPIO) only accepts
/// Default. Default is accepted by every format.
bool archiveCompressionMethodSupported(ArchiveFormat format, ArchiveCompressionMethod method);

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
    // archiveCreateSplit() only: how many part files were written.
    uint32_t partCount = 0;
    std::string errorMessage;
};

// Keeps the compression library's own default for the chosen format.
constexpr int kArchiveDefaultCompressionLevel = -1;

ArchiveCreateResult archiveCreate(
    const ArchiveSink& sink,
    ArchiveFormat format,
    const std::vector<ArchiveSourceEntry>& entries,
    const std::string& passphrase = "",
    // 7z only: also encrypt the archive header, so file names, sizes and times
    // are hidden as well (7-Zip's "Encrypt file names"). Needs a passphrase;
    // the request fails, rather than being ignored, when it can't be honoured.
    bool encryptFilenames = false,
    // Progress, in units of source bytes: the range is 0 .. (sum of the
    // entries' uncompressedSize), so a caller can divide by that total. Return
    // false to cancel.
    //
    // It deliberately follows the input rather than archive bytes written: the
    // 7z and ISO writers buffer everything in a temporary file and only emit
    // output when the archive is closed, so output bytes stay at 0 for the whole
    // run and then jump. For those two the range is split in two: reading the
    // sources, then copying the buffered output to the sink. A store spends
    // most of its time in the second part (the first is a plain copy), so it
    // gets half of the range; compressing 7z gets a tenth. Streaming formats
    // (ZIP, TAR, CPIO) have no second part and use the whole range for reading.
    std::function<bool(uint64_t progress)> progressCallback = nullptr,
    // 0 = store (no compression), 1 = fastest .. 9 = smallest. Applies to ZIP,
    // 7z and the compressed TAR variants; TAR, ISO and CPIO don't compress, so
    // it is ignored for them. kArchiveDefaultCompressionLevel keeps the
    // library default; any other value outside 0-9 is rejected. (Password-
    // protected 7z stores via Deflate level 0: its encryption can't be
    // combined with the 7z "copy" method. The tar filters have no store mode,
    // so 0 selects each one's fastest setting.)
    int compressionLevel = kArchiveDefaultCompressionLevel,
    // Which codec compresses the data. kDefault keeps the format's own choice
    // (see archiveCompressionMethodSupported for what each format accepts).
    // A method the format can't write is rejected rather than ignored, and so
    // is any explicit method together with level 0 on ZIP/7z (level 0 means
    // "store", which has no codec).
    ArchiveCompressionMethod compressionMethod = ArchiveCompressionMethod::Default
);


// ── Split (multi-part) archives ─────────────────────────────────────────
//
// 7z  -> plain volumes: the finished archive cut into pieces. Name them
//        `<name>.7z.001`, `.002`, ... (what 7-Zip itself writes).
// ZIP -> a real spanned archive (PKWARE APPNOTE 8.5): `<name>.z01`, `.z02`,
//        ... and the final part named `<name>.zip` (what WinRAR, Info-ZIP
//        and MiXplorer write). Every part is a separate "disk": the central
//        directory records which disk each entry starts on, so a ZIP set
//        can NOT simply be concatenated (the reader side below handles it).
//
// The engine never names or opens files. It asks the target for part N (0
// based) and tells it when a part is finished, and whether it was the last
// one (the ZIP set's last part is named differently, so a target that
// writes straight to its final name has to rename it then).

constexpr uint64_t kArchiveMinPartSize = 64 * 1024;
// Offsets inside a part are stored as 32-bit values; one value is reserved.
constexpr uint64_t kArchiveMaxPartSize = 0xFFFFFFFEull;

struct ArchivePartTarget {
    // Creates/opens part `index`. Must fail (return false) rather than
    // replace an existing file.
    std::function<bool(uint32_t index)> openPart;
    // Appends to the part opened last. Returns bytes written or -1.
    std::function<int64_t(const uint8_t* data, size_t length)> writePart;
    // Finishes part `index`. `isLast` is true exactly once, for the final part.
    std::function<bool(uint32_t index, bool isLast)> closePart;
    // Optional. Called when creation fails or is cancelled after any part was
    // opened, so the target can delete what was written.
    std::function<void()> abort;
};

// Only ArchiveFormat::Zip and ArchiveFormat::SevenZip can be split; any other
// format (or a partSize outside [kArchiveMinPartSize, kArchiveMaxPartSize])
// returns UnsupportedFormat without touching the target.
//
// Everything else means what it does for archiveCreate(): the same options are
// validated the same way, and `progressCallback` is in source bytes (0 .. sum of
// the entries' sizes; return false to cancel), including the extra "finishing"
// share a 7z gets for copying its buffered output to the parts.
ArchiveCreateResult archiveCreateSplit(
    const ArchivePartTarget& target,
    uint64_t partSize,
    ArchiveFormat format,
    const std::vector<ArchiveSourceEntry>& entries,
    const std::string& passphrase = "",
    bool encryptFilenames = false,
    std::function<bool(uint64_t progress)> progressCallback = nullptr,
    int compressionLevel = kArchiveDefaultCompressionLevel,
    ArchiveCompressionMethod compressionMethod = ArchiveCompressionMethod::Default
);

// Presents the ordered parts of a split archive (`.001, .002...` or
// `.z01, .z02, ..., .zip`) as ONE seekable archive for archiveScanEntries /
// archiveExtract*. Plain volumes are concatenated; a spanned ZIP additionally
// gets its central directory rewritten in memory (disk + offset -> absolute
// offset), the same thing `zip -s 0` does on disk. Parts must be given in
// order, the ZIP set's final `.zip` part last. A single part is returned as is.
bool archiveOpenPartsSource(const std::vector<ArchiveStreamSource>& parts,
                            ArchiveStreamSource* out,
                            std::string* errorMessage = nullptr);

// ── Finding the parts of a split archive ────────────────────────────────
//
// Given the file the user opened (any part of a set), works out which sibling
// files belong to it and opens them as one archive via archiveOpenPartsSource.
// Recognized names (case-insensitive):
//   name.7z.001, .002, ...   name.zip.001, .002, ...   plain volumes
//   name.z01, .z02, ... + name.zip                      spanned ZIP
// A lone `name.zip` is only treated as a set when its end record says it is
// the last of several disks.
//
// The caller supplies the two filesystem operations, so the same logic serves
// device folders and vaults (and is testable in memory).
struct ArchivePartSetEnv {
    // File names (no directories) next to the opened file, itself included.
    std::function<std::vector<std::string>()> listSiblings;
    // Opens the sibling with exactly this name for reading.
    std::function<bool(const std::string& name, ArchiveStreamSource* out)> openSibling;
};

// Number of disks (parts) a ZIP's end record claims it belongs to; 0 when `lastPart`
// does not end with a ZIP end record. 1 for any ordinary ZIP.
uint32_t archiveZipDiskCount(const ArchiveStreamSource& lastPart);

enum class ArchivePartSetStatus {
    NotASet,  // an ordinary single-file archive: open it as is
    Opened,   // `out` presents all parts as one archive
    Missing,  // looks like a set but a part is absent; `error` names it
};

ArchivePartSetStatus archiveOpenPartSet(const std::string& fileName,
                                        const ArchivePartSetEnv& env,
                                        ArchiveStreamSource* out,
                                        std::string* error);

// True when `fileName` is named like a part of a split archive (see above),
// i.e. archiveOpenPartSet() might treat it as one.
bool archiveIsSplitPartName(const std::string& fileName);
