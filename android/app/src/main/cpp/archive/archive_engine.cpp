#include "archive_engine.h"
#include "archive_engine_internal.h"

#include <archive.h>
#include <archive_entry.h>

#include <algorithm>
#include <cctype>
#include <ctime>
#include <cstring>

namespace {

constexpr size_t kSequentialChunkSize = 256 * 1024;
constexpr size_t kPostSeekChunkSize = 8 * 1024;

// ── zstd trailing-padding tolerance ─────────────────────────────────────
//
// libarchive pads the final write block with zeros even after a compression
// filter, so older `.tar.zst` files made by archiveCreate() end in up to 10 KiB
// of NULs after the last zstd frame. gzip/xz/lzma readers ignore trailing
// zeros; libarchive's zstd reader instead tries to decode them as another
// frame and fails the whole archive ("Unknown frame descriptor"). This walks
// the frame/block headers (3 bytes per block, payload skipped) to find where
// the real stream ends, and the engine then hands libarchive a source that
// stops there. Anything unexpected returns the original size unchanged.
uint32_t readLe(const uint8_t* b, size_t n) {
    uint32_t v = 0;
    for (size_t i = 0; i < n; ++i) v |= static_cast<uint32_t>(b[i]) << (8 * i);
    return v;
}

// Returns the offset one past the standard zstd frame starting at `start`, or
// 0 if the frame can't be parsed or runs past `total`.
uint64_t zstdFrameEnd(const ArchiveStreamSource& src, uint64_t start, uint64_t total) {
    uint64_t p = start + 4;  // past the magic
    uint8_t descriptor = 0;
    if (p >= total || src.read(p, &descriptor, 1) != 1) return 0;
    ++p;
    const unsigned fcsFlag = descriptor >> 6;
    const bool singleSegment = ((descriptor >> 5) & 1) != 0;
    const bool hasChecksum = ((descriptor >> 2) & 1) != 0;
    static const unsigned kDictIdBytes[4] = {0, 1, 2, 4};
    static const unsigned kFcsBytes[4] = {0, 2, 4, 8};
    p += singleSegment ? 0 : 1;  // Window_Descriptor
    p += kDictIdBytes[descriptor & 3];
    p += kFcsBytes[fcsFlag] + ((fcsFlag == 0 && singleSegment) ? 1 : 0);
    for (;;) {
        uint8_t h[3];
        if (p + 3 > total || src.read(p, h, 3) != 3) return 0;
        const uint32_t header = readLe(h, 3);
        const bool lastBlock = (header & 1) != 0;
        const unsigned blockType = (header >> 1) & 3;  // 0 raw, 1 RLE, 2 compressed
        const uint32_t blockSize = header >> 3;
        if (blockType == 3) return 0;  // reserved
        p += 3 + (blockType == 1 ? 1 : blockSize);
        if (p > total) return 0;
        if (lastBlock) break;
    }
    if (hasChecksum) p += 4;
    return p <= total ? p : 0;
}

// Size of the archive bytes libarchive should see: `total`, or, for a zstd
// stream followed only by zero padding, the end of its last frame.
uint64_t effectiveArchiveSize(const ArchiveStreamSource& src) {
    const uint64_t total = src.size();
    if (total < 16) return total;
    uint8_t magic[4];
    if (src.read(0, magic, 4) != 4 || readLe(magic, 4) != 0xFD2FB528u) return total;
    // Only a stream that ends in a zero byte can carry padding; this keeps the
    // frame walk off every normally-terminated zstd file.
    uint8_t lastByte = 1;
    if (src.read(total - 1, &lastByte, 1) != 1 || lastByte != 0) return total;

    uint64_t off = 0;
    while (off < total) {
        if (total - off < 4) break;
        uint8_t m[4];
        if (src.read(off, m, 4) != 4) return total;
        const uint32_t word = readLe(m, 4);
        if (word == 0xFD2FB528u) {
            const uint64_t end = zstdFrameEnd(src, off, total);
            if (end == 0) return total;
            off = end;
        } else if ((word & 0xFFFFFFF0u) == 0x184D2A50u) {  // skippable frame
            uint8_t sz[4];
            if (total - off < 8 || src.read(off + 4, sz, 4) != 4) return total;
            const uint64_t skip = 8 + static_cast<uint64_t>(readLe(sz, 4));
            if (skip > total - off) return total;
            off += skip;
        } else {
            break;
        }
    }
    if (off >= total) return total;  // frames end exactly at EOF

    // Trim only if everything after the last frame is zero.
    std::vector<uint8_t> chunk(64 * 1024);
    for (uint64_t pos = off; pos < total;) {
        const size_t want = static_cast<size_t>(std::min<uint64_t>(chunk.size(), total - pos));
        if (src.read(pos, chunk.data(), want) != static_cast<int64_t>(want)) return total;
        for (size_t i = 0; i < want; ++i) {
            if (chunk[i] != 0) return total;
        }
        pos += want;
    }
    return off;
}

struct CallbackState {
    const ArchiveStreamSource* source = nullptr;
    uint64_t position = 0;
    uint64_t size = 0;
    bool positionJustJumped = false;
    std::vector<uint8_t> buffer;
    bool ioErrorSeen = false;

    explicit CallbackState(const ArchiveStreamSource& src)
        : source(&src), size(effectiveArchiveSize(src)) {
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

la_int64_t skipCallback(struct archive*, void* clientData, la_int64_t request) {
    auto* state = static_cast<CallbackState*>(clientData);
    if (request < 0) return 0;
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

ArchiveOpenStatus classifyFailure(struct archive* a, bool passphraseGiven) {
    const char* err = archive_error_string(a);
    if (containsCaseInsensitive(err, "passphrase") ||
        containsCaseInsensitive(err, "password") ||
        containsCaseInsensitive(err, "encrypt")) {
        return passphraseGiven ? ArchiveOpenStatus::WrongPassphrase
                               : ArchiveOpenStatus::PassphraseRequired;
    }
    if (passphraseGiven &&
        (containsCaseInsensitive(err, "crc") ||
         containsCaseInsensitive(err, "checksum") ||
         containsCaseInsensitive(err, "too small block") ||
         containsCaseInsensitive(err, "header type error") ||
         containsCaseInsensitive(err, "block header size"))) {
        return ArchiveOpenStatus::WrongPassphrase;
    }
    return ArchiveOpenStatus::IoError;
}

std::string archiveErrorAt(struct archive* a, const char* stage, const char* fallback) {
    const char* error = archive_error_string(a);
    return std::string(stage) + ": " + (error ? error : fallback);
}

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
        result.errorMessage = archiveErrorAt(a, "scan/open", "failed to open archive");
        archive_read_free(a);
        return result;
    }

    int32_t nonDirectoryCount = 0;
    bool passphraseVerified = false;
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
            result.errorMessage = archiveErrorAt(a, "scan/header", "failed to read header");
            break;
        }
        ArchiveEntryInfo info = buildEntryInfo(entry, index);
        if (!info.isDirectory) {
            ++nonDirectoryCount;
        }

        // 7-Zip and ZIP formats leave headers (including filenames) unencrypted
        // even when file data is encrypted (ZIP central directory is always
        // unencrypted; 7-Zip headers are unencrypted unless header encryption
        // is selected). Let the browser index those entries without a passphrase;
        // extraction will request and validate the password when data is actually
        // read. If the 7-Zip header itself is encrypted, libarchive requests a
        // passphrase from archive_read_next_header() above, so that case still
        // prompts here.
        // Other formats retain the scan-time probe so their existing
        // password-required behavior is unchanged.
        const int formatFamily = archive_format(a) & ARCHIVE_FORMAT_BASE_MASK;
        const bool deferPassphrase =
            (formatFamily == ARCHIVE_FORMAT_7ZIP || formatFamily == ARCHIVE_FORMAT_ZIP || formatFamily == ARCHIVE_FORMAT_RAR_V5) && passphrase.empty();
        if (!passphraseVerified && info.isEncrypted && !info.isDirectory && info.uncompressedSize > 0) {
            if (deferPassphrase) {
                // Checked when the data is actually read.
            } else if (passphrase.empty()) {
                result.status = ArchiveOpenStatus::PassphraseRequired;
                result.errorMessage = "Archive is password protected";
                break;
            }
            // Probe only when validating a supplied passphrase. A zero-byte
            // entry has nothing to decrypt, so keep scanning for a non-empty
            // encrypted entry that can validate it.
            if (!deferPassphrase &&
                archive_entry_size_is_set(entry) && archive_entry_size(entry) > 0) {
                uint8_t probe[64];
                const la_ssize_t n = archive_read_data(a, probe, sizeof(probe));
                if (n < 0) {
                    result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                                      : classifyFailure(a, /*passphraseGiven=*/true);
                    result.errorMessage = archiveErrorAt(a, "scan/encrypted-entry probe", "incorrect passphrase");
                    break;
                }
                passphraseVerified = true;
            }
        }

        result.entries.push_back(std::move(info));
        archive_read_data_skip(a);
        ++index;
    }

    const int formatFamily = archive_format(a) & ARCHIVE_FORMAT_BASE_MASK;
    result.isSevenZip = formatFamily == ARCHIVE_FORMAT_7ZIP;
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
        result.errorMessage = archiveErrorAt(a, "extract/open", "failed to open archive");
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
            result.errorMessage = archiveErrorAt(a, "extract/header", "failed to read header");
            archive_read_free(a);
            return result;
        }
        if (index == targetIndex) {
            found = true;
            break;
        }
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
            ArchiveOpenStatus status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                                        : classifyFailure(a, !passphrase.empty());
            if (status == ArchiveOpenStatus::IoError && archive_entry_is_data_encrypted(entry) > 0) {
                status = passphrase.empty() ? ArchiveOpenStatus::PassphraseRequired
                                            : ArchiveOpenStatus::WrongPassphrase;
            }
            result.status = status;
            result.errorMessage = archiveErrorAt(a, "extract/entry data", "failed to read entry data");
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

ArchiveExtractResult archiveExtractEntryToSink(
    const ArchiveStreamSource& source,
    int32_t targetIndex,
    const std::string& passphrase,
    std::function<bool(const uint8_t* data, size_t length)> writeChunk
) {
    ArchiveExtractResult result;
    if (targetIndex < 0) {
        result.errorMessage = "targetIndex must be >= 0";
        return result;
    }
    if (!writeChunk) {
        result.errorMessage = "writeChunk callback is required";
        return result;
    }

    CallbackState state(source);
    struct archive* a = archive_read_new();
    if (openArchiveWithCallbacks(a, state, passphrase) != ARCHIVE_OK) {
        result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                          : classifyFailure(a, !passphrase.empty());
        result.errorMessage = archiveErrorAt(a, "extract-to-sink/open", "failed to open archive");
        archive_read_free(a);
        return result;
    }

    struct archive_entry* entry = nullptr;
    int32_t index = 0;
    bool found = false;
    for (;;) {
        const int r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF) break;
        if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                              : classifyFailure(a, !passphrase.empty());
            result.errorMessage = archiveErrorAt(a, "extract-to-sink/header", "failed to read header");
            archive_read_free(a);
            return result;
        }
        if (index == targetIndex) {
            found = true;
            break;
        }
        archive_read_data_skip(a);
        ++index;
    }

    if (!found) {
        result.errorMessage = "no entry at index " + std::to_string(targetIndex);
        archive_read_free(a);
        return result;
    }

    std::vector<uint8_t> chunk(kSequentialChunkSize);
    for (;;) {
        const la_ssize_t n = archive_read_data(a, chunk.data(), chunk.size());
        if (n == 0) break;
        if (n < 0) {
            ArchiveOpenStatus status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                                        : classifyFailure(a, !passphrase.empty());
            if (status == ArchiveOpenStatus::IoError && archive_entry_is_data_encrypted(entry) > 0) {
                status = passphrase.empty() ? ArchiveOpenStatus::PassphraseRequired
                                            : ArchiveOpenStatus::WrongPassphrase;
            }
            result.status = status;
            result.errorMessage = archiveErrorAt(a, "extract-to-sink/entry data", "failed to read entry data");
            archive_read_free(a);
            return result;
        }
        if (!writeChunk(chunk.data(), static_cast<size_t>(n))) {
            result.errorMessage = "failed to write extracted entry";
            archive_read_free(a);
            return result;
        }
    }

    result.status = ArchiveOpenStatus::Ok;
    archive_read_free(a);
    return result;
}

ArchiveBulkExtractResult archiveExtractAll(
    const ArchiveStreamSource& source,
    const std::string& passphrase,
    const std::string& subPathPrefix,
    std::function<bool(const std::string& dirPath)> makeDir,
    std::function<bool(const std::string& filePath, uint64_t offset, const uint8_t* data, size_t length)> writeFileChunk,
    std::function<bool(int32_t count, const std::string& currentPath)> progressCallback
) {
    ArchiveBulkExtractResult result;
    CallbackState state(source);
    struct archive* a = archive_read_new();
    if (openArchiveWithCallbacks(a, state, passphrase) != ARCHIVE_OK) {
        result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                          : classifyFailure(a, !passphrase.empty());
        result.errorMessage = archiveErrorAt(a, "extract-all/open", "failed to open archive");
        archive_read_free(a);
        return result;
    }

    std::string prefix = subPathPrefix;
    while (!prefix.empty() && (prefix.front() == '/' || prefix.front() == '\\')) prefix.erase(prefix.begin());
    while (!prefix.empty() && (prefix.back() == '/' || prefix.back() == '\\')) prefix.pop_back();

    std::vector<uint8_t> chunk(kSequentialChunkSize);
    struct archive_entry* entry = nullptr;

    for (;;) {
        const int r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF) {
            result.status = ArchiveOpenStatus::Ok;
            break;
        }
        if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                              : classifyFailure(a, !passphrase.empty());
            result.errorMessage = archiveErrorAt(a, "extract-all/header", "failed to read header");
            break;
        }

        const char* utf8Path = archive_entry_pathname_utf8(entry);
        const char* rawPath = archive_entry_pathname(entry);
        std::string entryPath = utf8Path ? utf8Path : (rawPath ? rawPath : "");

        for (char& c : entryPath) {
            if (c == '\\') c = '/';
        }
        while (!entryPath.empty() && entryPath.front() == '/') entryPath.erase(entryPath.begin());
        while (!entryPath.empty() && entryPath.back() == '/') entryPath.pop_back();

        // Zip-slip traversal defense. "." is the archive's own root record
        // (ISO 9660 lists one): it is the destination itself, and handing it
        // to makeDir would ask a vault filesystem to create a folder named ".".
        if (entryPath.empty() || entryPath == "." || entryPath.find("..") != std::string::npos || entryPath.find(':') != std::string::npos) {
            archive_read_data_skip(a);
            continue;
        }

        // Filter by prefix if specified
        if (!prefix.empty()) {
            if (entryPath != prefix && entryPath.rfind(prefix + "/", 0) != 0) {
                archive_read_data_skip(a);
                continue;
            }
        }

        std::string relPath = entryPath;
        if (!prefix.empty() && relPath.rfind(prefix + "/", 0) == 0) {
            relPath = relPath.substr(prefix.length() + 1);
        } else if (relPath == prefix) {
            if (archive_entry_filetype(entry) == AE_IFDIR) {
                archive_read_data_skip(a);
                continue;
            }
        }

        const bool isDir = archive_entry_filetype(entry) == AE_IFDIR;
        if (isDir) {
            if (makeDir && !relPath.empty()) {
                makeDir(relPath);
            }
            archive_read_data_skip(a);
            continue;
        }

        uint64_t fileOffset = 0;
        bool writeSuccess = true;

        if (writeFileChunk) {
            writeFileChunk(relPath, 0, nullptr, 0);
        }

        for (;;) {
            const la_ssize_t n = archive_read_data(a, chunk.data(), chunk.size());
            if (n == 0) break;
            if (n < 0) {
                ArchiveOpenStatus status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                                            : classifyFailure(a, !passphrase.empty());
                if (status == ArchiveOpenStatus::IoError && archive_entry_is_data_encrypted(entry) > 0) {
                    status = passphrase.empty() ? ArchiveOpenStatus::PassphraseRequired
                                                : ArchiveOpenStatus::WrongPassphrase;
                }
                result.status = status;
                result.errorMessage = archiveErrorAt(a, "extract-all/entry data", "failed to read entry data");
                writeSuccess = false;
                break;
            }
            if (writeFileChunk) {
                if (!writeFileChunk(relPath, fileOffset, chunk.data(), static_cast<size_t>(n))) {
                    result.status = ArchiveOpenStatus::IoError;
                    result.errorMessage = "failed to write extracted file";
                    writeSuccess = false;
                    break;
                }
            }
            fileOffset += static_cast<uint64_t>(n);
        }

        if (!writeSuccess) {
            break;
        }

        result.extractedCount++;
        if (progressCallback) {
            if (!progressCallback(result.extractedCount, relPath)) {
                result.status = ArchiveOpenStatus::Ok;
                break;
            }
        }
    }

    archive_read_free(a);
    return result;
}

// ── Write Implementation ───────────────────────────────────────────────

namespace {

// How often (in archive bytes) the finishing phase reports progress. The sink
// is called once per libarchive block, which is far more often than a progress
// bar or a JNI round trip needs.
constexpr uint64_t kFinishProgressStepBytes = 256 * 1024;

struct WriteState {
    const ArchiveSink* sink = nullptr;
    uint64_t totalWritten = 0;
    bool ioErrorSeen = false;
    bool cancelled = false;

    // Finishing phase. 7z and ISO keep their whole output in a temporary file
    // and only copy it to the sink when the archive is closed, so after the last
    // source byte there is still real work (and for a store, most of it). While
    // `finalizing`, each sink write is mapped onto the tail of the progress range
    // so the bar keeps moving instead of sitting at 100%.
    bool finalizing = false;
    const std::function<bool(uint64_t)>* progress = nullptr;
    uint64_t finishBase = 0;      // progress already reported when finishing began
    uint64_t finishSpan = 0;      // share of the range reserved for finishing
    uint64_t finishExpected = 1;  // output size the span is spread over
    uint64_t lastFinishReport = 0;
};

la_ssize_t writeSinkCallback(struct archive*, void* clientData, const void* buffer, size_t length) {
    auto* state = static_cast<WriteState*>(clientData);
    if (state->cancelled || state->ioErrorSeen) return -1;
    if (length == 0) return 0;

    int64_t n = state->sink->write(static_cast<const uint8_t*>(buffer), length);
    if (n < 0 || static_cast<size_t>(n) != length) {
        state->ioErrorSeen = true;
        return -1;
    }

    state->totalWritten += static_cast<uint64_t>(n);

    if (state->finalizing && state->progress && state->finishSpan > 0 &&
        state->totalWritten - state->lastFinishReport >= kFinishProgressStepBytes) {
        state->lastFinishReport = state->totalWritten;
        const double fraction = std::min(
            1.0, static_cast<double>(state->totalWritten) / static_cast<double>(state->finishExpected));
        const uint64_t done = state->finishBase + static_cast<uint64_t>(fraction * static_cast<double>(state->finishSpan));
        if (!(*state->progress)(done)) {
            state->cancelled = true;
            return -1;
        }
    }
    return static_cast<la_ssize_t>(n);
}

int openSinkCallback(struct archive*, void*) { return ARCHIVE_OK; }
int closeSinkCallback(struct archive*, void*) { return ARCHIVE_OK; }

int configureFormatAndFilters(struct archive* a, ArchiveFormat format, const std::string& passphrase,
                               bool encryptFilenames) {
    switch (format) {
        case ArchiveFormat::Zip:
            if (archive_write_set_format_zip(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (!passphrase.empty()) {
                if (archive_write_set_passphrase(a, passphrase.c_str()) != ARCHIVE_OK) return ARCHIVE_FATAL;
                archive_write_set_options(a, "zip:encryption=aes256");
            }
            break;
        case ArchiveFormat::SevenZip:
            if (archive_write_set_format_7zip(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            // The archive ends at the 7z header; without this libarchive pads the
            // last 10 KiB block with zeros, which 7-Zip reports as trailing data.
            archive_write_set_bytes_in_last_block(a, 1);
            if (!passphrase.empty()) {
                // Stock libarchive accepts a passphrase here but never encrypts a
                // 7-Zip archive. libarchive-7zip-encryption.patch (applied from
                // archive_deps.cmake) adds 7zAES (AES-256, SHA-256 key derivation),
                // and archive_engine_test.cpp fails if it is ever missing.
                if (archive_write_set_passphrase(a, passphrase.c_str()) != ARCHIVE_OK) return ARCHIVE_FATAL;
                // Also encrypt the 7z header (file names, sizes, times). The
                // option comes from the same patch; an unpatched libarchive
                // rejects it here instead of writing readable names.
                if (encryptFilenames &&
                    archive_write_set_options(a, "7zip:header-encryption=1") != ARCHIVE_OK) {
                    return ARCHIVE_FATAL;
                }
            }
            break;
        case ArchiveFormat::Tar:
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        // Compressed tars: libarchive would otherwise pad the *compressed*
        // output to a 10 KiB multiple with zeros. That padding means nothing
        // after a compression filter, and `zstd -d` and libarchive's own zstd
        // reader reject it, so write the final block unpadded (same call as
        // the 7z case above). Plain Tar keeps the conventional padding.
        case ArchiveFormat::TarGz:
            if (archive_write_add_filter_gzip(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            archive_write_set_bytes_in_last_block(a, 1);
            break;
        case ArchiveFormat::TarBz2:
            if (archive_write_add_filter_bzip2(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            archive_write_set_bytes_in_last_block(a, 1);
            break;
        case ArchiveFormat::TarXz:
            if (archive_write_add_filter_xz(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            archive_write_set_bytes_in_last_block(a, 1);
            break;
        case ArchiveFormat::TarZstd:
            if (archive_write_add_filter_zstd(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            archive_write_set_bytes_in_last_block(a, 1);
            break;
        case ArchiveFormat::TarLzma:
            if (archive_write_add_filter_lzma(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            archive_write_set_bytes_in_last_block(a, 1);
            break;
        case ArchiveFormat::Iso:
            if (archive_write_set_format_iso9660(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        case ArchiveFormat::Cpio:
            if (archive_write_set_format_cpio(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        default:
            return ARCHIVE_FATAL;
    }
    return ARCHIVE_OK;
}

// Maps the UI level (0 = store, 1 = fastest .. 9 = smallest) onto the options
// libarchive reads for each format. Must run after the format and filters are
// set up. A non-OK return means libarchive rejected the option; that is
// reported rather than ignored, so a level request never silently does nothing.
//
// Level 0 is "store" only where the container supports it. A bare level of 0
// on 7z would still run LZMA at its fastest preset, so 7z/ZIP switch codec.
// TAR filters have no store mode, so 0 means that filter's fastest setting.
int applyCompressionLevel(struct archive* a, ArchiveFormat format, int level, bool encrypted) {
    if (level == kArchiveDefaultCompressionLevel) return ARCHIVE_OK;
    const std::string lvl = std::to_string(level);
    switch (format) {
        case ArchiveFormat::Zip:
            // zip:compression-level=0 selects "store"; 1-9 selects deflate.
            return archive_write_set_options(a, ("zip:compression-level=" + lvl).c_str());
        case ArchiveFormat::SevenZip:
            if (level == 0) {
                if (!encrypted) return archive_write_set_options(a, "7zip:compression=store");
                // libarchive's 7z "copy" method gives every file its own folder,
                // while libarchive-7zip-encryption.patch encrypts one folder and
                // refuses copy outright. Deflate at level 0 writes stored blocks
                // (no compression, negligible CPU) and is allowed with encryption.
                return archive_write_set_options(
                    a, "7zip:compression=deflate,7zip:compression-level=0");
            }
            return archive_write_set_options(a, ("7zip:compression-level=" + lvl).c_str());
        case ArchiveFormat::TarGz:    // 0-9
        case ArchiveFormat::TarBz2:   // 1-9 (libarchive raises 0 to 1)
        case ArchiveFormat::TarXz:    // 0-9
        case ArchiveFormat::TarLzma:  // 0-9
            return archive_write_set_filter_option(a, nullptr, "compression-level", lvl.c_str());
        case ArchiveFormat::TarZstd:  // 1-22; 0 would mean zstd's default (3), not "fastest"
            return archive_write_set_filter_option(
                a, nullptr, "compression-level", std::to_string(std::max(1, level)).c_str());
        case ArchiveFormat::Tar:
        case ArchiveFormat::Iso:
        case ArchiveFormat::Cpio:
        default:
            return ARCHIVE_OK;  // nothing to compress
    }
}

// Selects the codec on top of what configureFormatAndFilters set up. Only ZIP
// and 7z have a choice to make; for the compressed TARs the codec is the
// filter itself, and archiveCompressionMethodSupported has already checked that
// the caller asked for that same one. Runs before applyCompressionLevel.
int applyCompressionMethod(struct archive* a, ArchiveFormat format, ArchiveCompressionMethod method) {
    if (method == ArchiveCompressionMethod::Default) return ARCHIVE_OK;
    switch (format) {
        case ArchiveFormat::Zip:
            // Deflate is the only method here; naming it just makes the
            // writer's default explicit.
            return archive_write_set_options(a, "zip:compression=deflate");
        case ArchiveFormat::SevenZip:
            switch (method) {
                case ArchiveCompressionMethod::Deflate:
                    return archive_write_set_options(a, "7zip:compression=deflate");
                case ArchiveCompressionMethod::Lzma:
                    return archive_write_set_options(a, "7zip:compression=lzma1");
                case ArchiveCompressionMethod::Lzma2:
                    return archive_write_set_options(a, "7zip:compression=lzma2");
                default:
                    return ARCHIVE_FATAL;
            }
        default:
            return ARCHIVE_OK;  // the filter already is the method
    }
}

}  // namespace

bool archiveCompressionMethodSupported(ArchiveFormat format, ArchiveCompressionMethod method) {
    if (method == ArchiveCompressionMethod::Default) return true;
    switch (format) {
        case ArchiveFormat::Zip:
            return method == ArchiveCompressionMethod::Deflate;
        case ArchiveFormat::SevenZip:
            return method == ArchiveCompressionMethod::Deflate ||
                   method == ArchiveCompressionMethod::Lzma ||
                   method == ArchiveCompressionMethod::Lzma2;
        case ArchiveFormat::TarGz:
            return method == ArchiveCompressionMethod::Deflate;
        case ArchiveFormat::TarXz:
            return method == ArchiveCompressionMethod::Lzma2;
        case ArchiveFormat::TarLzma:
            return method == ArchiveCompressionMethod::Lzma;
        default:
            return false;
    }
}

ArchiveCreateResult archiveCreate(
    const ArchiveSink& sink,
    ArchiveFormat format,
    const std::vector<ArchiveSourceEntry>& entries,
    const std::string& passphrase,
    bool encryptFilenames,
    std::function<bool(uint64_t progress)> progressCallback,
    int compressionLevel,
    ArchiveCompressionMethod compressionMethod
) {
    ArchiveCreateResult result;
    if (compressionLevel != kArchiveDefaultCompressionLevel &&
        (compressionLevel < 0 || compressionLevel > 9)) {
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = "compression level must be between 0 and 9";
        return result;
    }
    if (!archiveCompressionMethodSupported(format, compressionMethod)) {
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = "this archive format can't use the requested compression method";
        return result;
    }
    if (compressionMethod != ArchiveCompressionMethod::Default && compressionLevel == 0 &&
        (format == ArchiveFormat::Zip || format == ArchiveFormat::SevenZip)) {
        // Level 0 stores the data, so there is no codec to pick.
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = "a compression method can't be combined with store (level 0)";
        return result;
    }
    if (encryptFilenames && (format != ArchiveFormat::SevenZip || passphrase.empty())) {
        // Never fall back to an archive whose names are readable when the
        // caller asked for them to be hidden.
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = format != ArchiveFormat::SevenZip
            ? "filename encryption is only supported for 7z archives"
            : "filename encryption needs a passphrase";
        return result;
    }
    WriteState state;
    state.sink = &sink;

    struct archive* a = archive_write_new();
    if (!a) {
        result.status = ArchiveOpenStatus::IoError;
        result.errorMessage = "failed to create archive writer";
        return result;
    }

    if (configureFormatAndFilters(a, format, passphrase, encryptFilenames) != ARCHIVE_OK) {
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "unsupported format or filter";
        archive_write_free(a);
        return result;
    }

    if (applyCompressionMethod(a, format, compressionMethod) != ARCHIVE_OK) {
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "compression method rejected";
        archive_write_free(a);
        return result;
    }

    if (applyCompressionLevel(a, format, compressionLevel, !passphrase.empty()) != ARCHIVE_OK) {
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "compression level rejected";
        archive_write_free(a);
        return result;
    }

    if (archive_write_open(a, &state, openSinkCallback, writeSinkCallback, closeSinkCallback) != ARCHIVE_OK) {
        result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError : ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to open archive write sink";
        archive_write_free(a);
        return result;
    }

    // The progress range is the real source size, so byte counts, speed and ETA
    // derived from it stay meaningful. For writers that only produce output at
    // close, the tail of the range is reserved for that finishing phase: half of
    // it when the data is merely stored (reading and copying out are the same
    // amount of work), a tenth when compression dominates.
    uint64_t sourceTotal = 0;
    for (const auto& entry : entries) {
        if (!entry.isDirectory) sourceTotal += entry.uncompressedSize;
    }
    double finishShare = 0.0;
    if (format == ArchiveFormat::SevenZip || format == ArchiveFormat::Iso) {
        const bool storesData = format == ArchiveFormat::Iso || compressionLevel == 0;
        finishShare = storesData ? 0.5 : 0.1;
    }
    const auto scaleReading = [finishShare](uint64_t bytes) {
        return static_cast<uint64_t>(static_cast<double>(bytes) * (1.0 - finishShare));
    };

    std::vector<uint8_t> chunkBuf(kSequentialChunkSize);
    uint64_t sourceBytesProcessed = 0;
    for (const auto& entry : entries) {
        if (state.cancelled) break;

        struct archive_entry* ae = archive_entry_new();
        archive_entry_set_pathname(ae, entry.pathInArchive.c_str());
        archive_entry_set_filetype(ae, entry.isDirectory ? AE_IFDIR : AE_IFREG);
        archive_entry_set_perm(ae, entry.isDirectory ? 0755 : 0644);
        archive_entry_set_size(ae, static_cast<int64_t>(entry.uncompressedSize));
        const int64_t mtime = entry.modTimeEpochSeconds > 0
            ? entry.modTimeEpochSeconds
            : static_cast<int64_t>(std::time(nullptr));
        archive_entry_set_mtime(ae, mtime, 0);

        if (archive_write_header(a, ae) != ARCHIVE_OK) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError : ArchiveOpenStatus::UnsupportedFormat;
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to write entry header";
            archive_entry_free(ae);
            archive_write_close(a);
            archive_write_free(a);
            return result;
        }
        archive_entry_free(ae);

        if (!entry.isDirectory && entry.readData && entry.uncompressedSize > 0) {
            uint64_t bytesProcessed = 0;
            while (bytesProcessed < entry.uncompressedSize) {
                if (state.cancelled) break;
                const size_t toRead = static_cast<size_t>(
                    std::min<uint64_t>(chunkBuf.size(), entry.uncompressedSize - bytesProcessed));
                int64_t got = entry.readData(chunkBuf.data(), toRead);
                if (got < 0) {
                    state.ioErrorSeen = true;
                    break;
                }
                if (got == 0) break; // EOF

                la_ssize_t written = archive_write_data(a, chunkBuf.data(), static_cast<size_t>(got));
                if (written < 0) {
                    state.ioErrorSeen = true;
                    break;
                }
                bytesProcessed += static_cast<uint64_t>(written);
                sourceBytesProcessed += static_cast<uint64_t>(written);

                // Polled per source chunk (not per sink write): for 7z the sink
                // stays silent until close, so this is the only place progress
                // and cancellation can be observed during compression.
                if (progressCallback && !progressCallback(scaleReading(sourceBytesProcessed))) {
                    state.cancelled = true;
                    break;
                }
            }
            if (state.ioErrorSeen) {
                result.status = ArchiveOpenStatus::IoError;
                result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to write entry payload";
                archive_write_close(a);
                archive_write_free(a);
                return result;
            }
        }
        if (state.cancelled) break;
        result.entriesArchived++;
    }

    if (state.cancelled) {
        // Don't close: finishing an unfinished entry makes the 7z writer push the
        // rest of its declared size through the encoder as zeros, which can take
        // a long time after an early cancel of a large file. Marking the writer
        // failed makes archive_write_free skip that and just release resources.
        archive_write_fail(a);
        archive_write_free(a);
        result.status = ArchiveOpenStatus::IoError;
        result.errorMessage = "archive creation cancelled";
        return result;
    }

    if (progressCallback && finishShare > 0.0 && sourceTotal > 0) {
        state.progress = &progressCallback;
        state.finishBase = scaleReading(sourceTotal);
        state.finishSpan = sourceTotal - state.finishBase;
        state.finishExpected = sourceTotal;
        state.finalizing = true;
    }

    if (archive_write_close(a) != ARCHIVE_OK) {
        if (state.cancelled) {
            // Cancelled while the buffered output was being copied out.
            result.status = ArchiveOpenStatus::IoError;
            result.errorMessage = "archive creation cancelled";
        } else if (result.status == ArchiveOpenStatus::Ok || result.errorMessage.empty()) {
            result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError : ArchiveOpenStatus::UnsupportedFormat;
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to finalize archive";
        }
    } else {
        result.status = ArchiveOpenStatus::Ok;
    }

    result.totalBytesWritten = state.totalWritten;
    archive_write_free(a);
    return result;
}

// Same checks and the same configuration steps as the start of archiveCreate().
// Kept next to it (and to the helpers it uses) so the two can't drift apart.
bool archiveConfigureWriter(struct archive* a, ArchiveFormat format, const std::string& passphrase,
                            bool encryptFilenames, int compressionLevel,
                            ArchiveCompressionMethod compressionMethod, std::string* error) {
    auto fail = [error](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    if (compressionLevel != kArchiveDefaultCompressionLevel && (compressionLevel < 0 || compressionLevel > 9)) {
        return fail("compression level must be between 0 and 9");
    }
    if (!archiveCompressionMethodSupported(format, compressionMethod)) {
        return fail("this archive format can't use the requested compression method");
    }
    if (compressionMethod != ArchiveCompressionMethod::Default && compressionLevel == 0 &&
        (format == ArchiveFormat::Zip || format == ArchiveFormat::SevenZip)) {
        return fail("a compression method can't be combined with store (level 0)");
    }
    if (encryptFilenames && (format != ArchiveFormat::SevenZip || passphrase.empty())) {
        return fail(format != ArchiveFormat::SevenZip ? "filename encryption is only supported for 7z archives"
                                                      : "filename encryption needs a passphrase");
    }
    const auto libraryError = [a](const char* fallback) {
        return std::string(archive_error_string(a) ? archive_error_string(a) : fallback);
    };
    if (configureFormatAndFilters(a, format, passphrase, encryptFilenames) != ARCHIVE_OK) {
        return fail(libraryError("unsupported format or filter"));
    }
    if (applyCompressionMethod(a, format, compressionMethod) != ARCHIVE_OK) {
        return fail(libraryError("compression method rejected"));
    }
    if (applyCompressionLevel(a, format, compressionLevel, !passphrase.empty()) != ARCHIVE_OK) {
        return fail(libraryError("compression level rejected"));
    }
    return true;
}
