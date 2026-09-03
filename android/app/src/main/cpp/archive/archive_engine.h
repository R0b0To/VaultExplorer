#pragma once

// Native archive engine (Milestone 2 of the libarchive migration spec):
// metadata-only indexing and on-demand single-entry extraction for ZIP,
// RAR4/RAR5, 7-Zip, TAR, and their compression filters (gzip/bzip2/xz/
// zstd), built on top of libarchive.
//
// Deliberately independent of JNI, Dart FFI, and the app's session/volId
// concepts -- see archive_stream_source.h. Everything here works off
// caller-supplied byte ranges, so it's exercised directly against real
// libarchive in archive/test/archive_engine_test.cpp without touching the
// JVM or a mounted container.
//
// Design notes tying this back to the migration spec's principles:
//
//  - VFS indexing (principle 1): archiveScanEntries() calls
//    archive_read_data_skip() after every header instead of
//    archive_read_data(), so payload bytes are never decompressed during
//    a scan. Because ArchiveStreamSource supplies a seek callback,
//    libarchive's format "bidding" prefers the seekable ZIP reader, which
//    reads the Central Directory once instead of walking local headers
//    one at a time -- this is what makes opening a large ZIP fast, not
//    anything this file does explicitly.
//  - Lazy extraction (principle 2): archiveExtractEntry() re-walks
//    headers from the start, skipping every entry before the target and
//    decompressing only the one requested. For ZIP this skip is a seek
//    (cheap); for solid RAR/7z it still has to decode from the start of
//    whatever solid block contains the target (see isSolid on
//    ArchiveIndexResult and Milestone 5's solid-archive handling) --
//    libarchive does that internally, this file doesn't special-case it.
//  - Zero-disk streaming (principle 3): entirely a property of what the
//    caller passes as ArchiveStreamSource -- this file never touches the
//    filesystem itself.
//  - Thread-safety / isolate execution (principle 4): every function here
//    is a plain synchronous call with no shared mutable state, so calling
//    it from a background thread (Kotlin executor, Dart isolate, whatever
//    the eventual bridge picks) is the caller's responsibility and this
//    file adds no obstacle to it.

#include <cstdint>
#include <string>
#include <vector>

#include "archive_stream_source.h"

// One entry's metadata, as read from the archive's header -- never from
// its (still-compressed, still-unread) data payload.
struct ArchiveEntryInfo {
    // Full path within the archive, forward-slash separated, exactly as
    // libarchive reports it (archive_entry_pathname_utf8() if the entry
    // has valid UTF-8 pathname data, else archive_entry_pathname()).
    std::string path;
    uint64_t uncompressedSize = 0;
    // Best-effort only: libarchive doesn't expose a per-entry compressed
    // size for every format (it's a concept ZIP's central directory has
    // but a plain .tar.gz stream doesn't), so this is 0 whenever the
    // format doesn't supply one rather than an estimate.
    uint64_t compressedSize = 0;
    int64_t modTimeEpochSeconds = 0;
    bool isEncrypted = false;
    bool isDirectory = false;
    // This entry's position in the archive's header order (0-based). The
    // only stable "address" libarchive gives us for coming back to this
    // entry later via archiveExtractEntry -- not a byte offset, since
    // that's not meaningful across all formats/filters.
    int32_t index = -1;
};

enum class ArchiveOpenStatus {
    Ok,
    UnsupportedFormat,
    // Headers themselves are encrypted (seen with RAR/7z's "encrypt
    // filenames" option) and couldn't be listed without a passphrase.
    PassphraseRequired,
    WrongPassphrase,
    IoError,
};

struct ArchiveIndexResult {
    ArchiveOpenStatus status = ArchiveOpenStatus::IoError;
    std::vector<ArchiveEntryInfo> entries;
    // Coarse, best-effort signal for Milestone 5's solid-archive UX --
    // true when the archive's format family is one that supports solid
    // (shared-compression-block) storage (RAR, RAR5, 7-Zip) AND it has
    // more than one file. libarchive doesn't expose a portable way to
    // ask "is this *specific* archive solid", so this can be true for a
    // RAR/7z file where every entry actually got its own block -- treat
    // it as "extraction here may need to decode more than the requested
    // entry", not as a precise per-archive guarantee.
    bool isSolid = false;
    std::string errorMessage;
};

// Scans every header in the archive `source` exposes, without
// decompressing any entry's payload. `passphrase` is only needed here for
// formats that encrypt their own header/filename data (RAR5, some 7z
// archives); it is NOT required just to list a ZIP whose file *contents*
// are AES-encrypted -- those show up with isEncrypted=true on the
// relevant entries and only need a passphrase at extraction time.
ArchiveIndexResult archiveScanEntries(const ArchiveStreamSource& source,
                                      const std::string& passphrase = "");

struct ArchiveExtractResult {
    ArchiveOpenStatus status = ArchiveOpenStatus::IoError;
    std::vector<uint8_t> data;
    std::string errorMessage;
};

// Re-opens `source` and decompresses exactly one entry -- the one an
// earlier archiveScanEntries() call reported at `targetIndex` -- into
// memory. Every entry before it is skipped via archive_read_data_skip()
// (a seek, not a decode, when the format/callback combination allows it);
// nothing after the target entry is ever read at all, since libarchive
// stops as soon as archive_read_data() for the target entry is
// exhausted.
ArchiveExtractResult archiveExtractEntry(const ArchiveStreamSource& source,
                                         int32_t targetIndex,
                                         const std::string& passphrase = "");
