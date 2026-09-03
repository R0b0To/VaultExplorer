#include "archive_engine.h"

#include <archive.h>
#include <archive_entry.h>

#include <algorithm>
#include <cctype>
#include <cstring>

namespace {

// Size of the internal read buffer libarchive's read callback hands back
// a pointer into when it's reading contiguously (e.g. streaming through
// archiveExtractEntry()'s target entry) -- big enough for good decode
// throughput.
constexpr size_t kSequentialChunkSize = 256 * 1024;

// Size used for the *first* read after a seek/skip. This is the fix for
// a real measured problem: if that first post-seek read were the full
// kSequentialChunkSize, it would frequently over-fetch past a whole small
// entry in one shot (entries here are commonly tens to low hundreds of
// KB), and libarchive would then satisfy the *next* header's "skip" out
// of that already-buffered data without ever calling skipCallback --
// which sounds harmless, but it means ArchiveStreamSource::read() (backed
// in production by a real decrypt-and-read from the container) still got
// asked to fetch and decrypt that entry's payload for nothing. Measured
// on a 293 MB / 2000-entry synthetic archive: with a flat 256 KB buffer,
// a metadata-only scan pulled 250 MB through read() (~85% of the file);
// dropping the post-seek read to this size brings that down to roughly
// the size of the headers actually being parsed. Sized around a local
// ZIP header plus a generous filename/extra-field allowance -- small
// enough to not accidentally swallow a whole small entry, comfortably
// larger than any single header actually needs.
constexpr size_t kPostSeekChunkSize = 8 * 1024;

// Everything the three libarchive callbacks below need, bundled so a
// single void* client_data pointer can reach it. Owns the scratch buffer
// libarchive's read callback points into (see archive_read_callback's
// "give me a pointer, not a copy" contract in archive.h).
struct CallbackState {
    const ArchiveStreamSource* source = nullptr;
    uint64_t position = 0;
    uint64_t size = 0;
    // Tracks whether `position` was just moved non-contiguously (by
    // seekCallback/skipCallback) since the last read, so readCallback
    // knows whether to fetch a small "just enough to parse a header"
    // chunk or a large "we're streaming an entry's data" chunk. See
    // kPostSeekChunkSize above.
    bool positionJustJumped = false;
    std::vector<uint8_t> buffer;
    bool ioErrorSeen = false;

    explicit CallbackState(const ArchiveStreamSource& src)
        : source(&src), size(src.size()) {
        buffer.resize(kSequentialChunkSize);
    }
};

la_ssize_t readCallback(struct archive*, void* clientData, const void** outBuffer) {
    auto* state = static_cast<CallbackState*>(clientData);
    const uint64_t remaining = state->size > state->position ? state->size - state->position : 0;
    if (remaining == 0) {
        *outBuffer = nullptr;
        return 0;
    }
    const size_t chunkSize = state->positionJustJumped ? kPostSeekChunkSize : kSequentialChunkSize;
    state->positionJustJumped = false;
    const size_t wanted = static_cast<size_t>(std::min<uint64_t>(remaining, chunkSize));
    const int64_t got = state->source->read(state->position, state->buffer.data(), wanted);
    if (got < 0) {
        state->ioErrorSeen = true;
        *outBuffer = nullptr;
        return -1;
    }
    state->position += static_cast<uint64_t>(got);
    *outBuffer = state->buffer.data();
    return static_cast<la_ssize_t>(got);
}

// No physical I/O needed to skip -- we always know the file's total size,
// so skipping is just arithmetic on `position`. This is what lets
// archiveExtractEntry() bypass every entry before the target one without
// reading their (possibly large) payloads.
la_int64_t skipCallback(struct archive*, void* clientData, la_int64_t request) {
    auto* state = static_cast<CallbackState*>(clientData);
    if (request < 0) {
        return 0;
    }
    const uint64_t remaining = state->size > state->position ? state->size - state->position : 0;
    const uint64_t skipped = std::min<uint64_t>(remaining, static_cast<uint64_t>(request));
    state->position += skipped;
    state->positionJustJumped = true;
    return static_cast<la_int64_t>(skipped);
}

la_int64_t seekCallback(struct archive*, void* clientData, la_int64_t offset, int whence) {
    auto* state = static_cast<CallbackState*>(clientData);
    int64_t base;
    switch (whence) {
        case SEEK_SET: base = 0; break;
        case SEEK_CUR: base = static_cast<int64_t>(state->position); break;
        case SEEK_END: base = static_cast<int64_t>(state->size); break;
        default: return ARCHIVE_FATAL;
    }
    const int64_t target = base + offset;
    if (target < 0 || static_cast<uint64_t>(target) > state->size) {
        return ARCHIVE_FATAL;
    }
    state->position = static_cast<uint64_t>(target);
    state->positionJustJumped = true;
    return static_cast<la_int64_t>(state->position);
}

int openCallback(struct archive*, void*) { return ARCHIVE_OK; }
int closeCallback(struct archive*, void*) { return ARCHIVE_OK; }

bool containsCaseInsensitive(const char* haystack, const char* needle) {
    if (!haystack || !needle) return false;
    std::string h(haystack), n(needle);
    std::transform(h.begin(), h.end(), h.begin(), [](unsigned char c) { return std::tolower(c); });
    std::transform(n.begin(), n.end(), n.begin(), [](unsigned char c) { return std::tolower(c); });
    return h.find(n) != std::string::npos;
}

// libarchive doesn't return a distinct error code for "wrong/missing
// passphrase" -- it's ARCHIVE_FATAL/ARCHIVE_FAILED like any other unusable
// entry, distinguishable only by archive_error_string() containing
// wording like "Incorrect passphrase" or "Passphrase required". This is a
// heuristic, not a documented libarchive contract, so it can miss a
// passphrase problem worded differently by some future libarchive
// version -- callers should treat IoError with a plausible-sounding
// message as "might also be a bad passphrase" rather than ruling it out.
ArchiveOpenStatus classifyFailure(struct archive* a, bool passphraseGiven) {
    if (containsCaseInsensitive(archive_error_string(a), "passphrase")) {
        return passphraseGiven ? ArchiveOpenStatus::WrongPassphrase
                                : ArchiveOpenStatus::PassphraseRequired;
    }
    return ArchiveOpenStatus::IoError;
}

// Configures format/filter support, the passphrase (if any), and wires
// the three callbacks above to `state`. Registering the seek callback
// before archive_read_open2() is what makes libarchive prefer the
// seekable ZIP reader (Central Directory first) over the streamable one
// -- see archive_engine.h's design notes.
int openArchiveWithCallbacks(struct archive* a, CallbackState& state, const std::string& passphrase) {
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    if (!passphrase.empty()) {
        archive_read_add_passphrase(a, passphrase.c_str());
    }
    archive_read_set_seek_callback(a, seekCallback);
    return archive_read_open2(a, &state, openCallback, readCallback, skipCallback, closeCallback);
}

ArchiveEntryInfo buildEntryInfo(struct archive_entry* entry, int32_t index) {
    ArchiveEntryInfo info;
    info.index = index;
    const char* utf8Path = archive_entry_pathname_utf8(entry);
    const char* rawPath = archive_entry_pathname(entry);
    info.path = utf8Path ? utf8Path : (rawPath ? rawPath : "");
    if (archive_entry_size_is_set(entry)) {
        info.uncompressedSize = static_cast<uint64_t>(archive_entry_size(entry));
    }
    info.modTimeEpochSeconds = static_cast<int64_t>(archive_entry_mtime(entry));
    info.isDirectory = archive_entry_filetype(entry) == AE_IFDIR;
    info.isEncrypted = archive_entry_is_data_encrypted(entry) > 0;
    // compressedSize deliberately left at 0: no libarchive accessor
    // reports it consistently across formats (ZIP's central directory
    // has the concept, a bare .tar.gz stream doesn't), so a value here
    // would be misleading for exactly the formats where it'd matter most.
    return info;
}

}  // namespace

ArchiveIndexResult archiveScanEntries(const ArchiveStreamSource& source, const std::string& passphrase) {
    ArchiveIndexResult result;
    CallbackState state(source);

    struct archive* a = archive_read_new();
    if (openArchiveWithCallbacks(a, state, passphrase) != ARCHIVE_OK) {
        result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                          : classifyFailure(a, !passphrase.empty());
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to open archive";
        archive_read_free(a);
        return result;
    }

    // Coarse "can this format even be solid" signal -- RAR (both legacy
    // and RAR5) and 7-Zip group files into shared-compression blocks;
    // none of the other formats libarchive supports do. This is NOT
    // "this archive IS solid": libarchive doesn't expose a portable way
    // to ask that per-archive, so a RAR/7z file with every entry in its
    // own block still reports isSolid=true here once it has more than
    // one file. Milestone 5's UI should treat this as "extraction from
    // this archive may need to decode more than just the requested
    // entry", not as a precise per-file guarantee.
    //
    // archive_format() only reports a meaningful value once format
    // bidding has actually run, which happens lazily on the first
    // archive_read_next_header() call rather than at open2() time --
    // so this is read after the loop below, not before it.
    int32_t nonDirectoryCount = 0;

    struct archive_entry* entry = nullptr;
    int32_t index = 0;
    for (;;) {
        const int r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF) {
            result.status = ArchiveOpenStatus::Ok;
            break;
        }
        if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                              : classifyFailure(a, !passphrase.empty());
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to read header";
            break;
        }
        ArchiveEntryInfo info = buildEntryInfo(entry, index);
        if (!info.isDirectory) {
            ++nonDirectoryCount;
        }
        result.entries.push_back(std::move(info));
        archive_read_data_skip(a);
        ++index;
    }

    const int formatFamily = archive_format(a) & ARCHIVE_FORMAT_BASE_MASK;
    const bool formatCanBeSolid =
        formatFamily == ARCHIVE_FORMAT_RAR ||
        formatFamily == ARCHIVE_FORMAT_RAR_V5 ||
        formatFamily == ARCHIVE_FORMAT_7ZIP;
    result.isSolid = formatCanBeSolid && nonDirectoryCount > 1;
    archive_read_free(a);
    return result;
}

ArchiveExtractResult archiveExtractEntry(const ArchiveStreamSource& source, int32_t targetIndex,
                                         const std::string& passphrase) {
    ArchiveExtractResult result;
    if (targetIndex < 0) {
        result.errorMessage = "targetIndex must be >= 0";
        return result;
    }

    CallbackState state(source);
    struct archive* a = archive_read_new();
    if (openArchiveWithCallbacks(a, state, passphrase) != ARCHIVE_OK) {
        result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                          : classifyFailure(a, !passphrase.empty());
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to open archive";
        archive_read_free(a);
        return result;
    }

    struct archive_entry* entry = nullptr;
    int32_t index = 0;
    bool found = false;
    for (;;) {
        const int r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF) {
            break;
        }
        if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                              : classifyFailure(a, !passphrase.empty());
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to read header";
            archive_read_free(a);
            return result;
        }
        if (index == targetIndex) {
            found = true;
            break;
        }
        // Skip this entry's payload without decompressing it. For a ZIP
        // opened with a seek callback this is a real seek; for a solid
        // RAR/7z block libarchive still has to walk the compressed
        // stream internally, but it does so once here rather than once
        // per byte the caller might otherwise have requested.
        archive_read_data_skip(a);
        ++index;
    }

    if (!found) {
        result.status = ArchiveOpenStatus::IoError;
        result.errorMessage = "no entry at index " + std::to_string(targetIndex);
        archive_read_free(a);
        return result;
    }

    if (archive_entry_size_is_set(entry)) {
        result.data.reserve(static_cast<size_t>(archive_entry_size(entry)));
    }

    std::vector<uint8_t> chunk(kSequentialChunkSize);
    for (;;) {
        const la_ssize_t n = archive_read_data(a, chunk.data(), chunk.size());
        if (n == 0) {
            break;
        }
        if (n < 0) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                              : classifyFailure(a, !passphrase.empty());
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to read entry data";
            result.data.clear();
            archive_read_free(a);
            return result;
        }
        result.data.insert(result.data.end(), chunk.begin(), chunk.begin() + n);
    }

    result.status = ArchiveOpenStatus::Ok;
    archive_read_free(a);
    return result;
}