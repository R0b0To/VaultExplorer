#include "archive_engine.h"

#include <archive.h>
#include <archive_entry.h>

#include <algorithm>
#include <cctype>
#include <cstring>

namespace {

constexpr size_t kSequentialChunkSize = 256 * 1024;
constexpr size_t kPostSeekChunkSize = 8 * 1024;

struct CallbackState {
    const ArchiveStreamSource* source = nullptr;
    uint64_t position = 0;
    uint64_t size = 0;
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
    if (containsCaseInsensitive(archive_error_string(a), "passphrase")) {
        return passphraseGiven ? ArchiveOpenStatus::WrongPassphrase
                                : ArchiveOpenStatus::PassphraseRequired;
    }
    return ArchiveOpenStatus::IoError;
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
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to open archive";
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
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to read header";
            break;
        }
        ArchiveEntryInfo info = buildEntryInfo(entry, index);
        if (!info.isDirectory) {
            ++nonDirectoryCount;
        }

        // Header metadata (name/size/the encrypted flag) is readable on ZIP
        // and several other formats without the passphrase, since only the
        // entry *payload* is encrypted. archive_read_data_skip() below just
        // advances past that payload using the size from the header (or via
        // the central directory when seekable) -- it never decrypts anything,
        // so a missing or wrong passphrase would otherwise go undetected here
        // and this scan would report Ok regardless. Probe-decrypt a few bytes
        // of the first encrypted file entry we hit so we can actually tell.
        if (!passphraseVerified && info.isEncrypted && !info.isDirectory) {
            if (passphrase.empty()) {
                result.status = ArchiveOpenStatus::PassphraseRequired;
                result.errorMessage = "Archive is password protected";
                break;
            }
            // A zero-byte entry has nothing to decrypt, so a probe read can't
            // tell us anything -- keep scanning for a non-empty encrypted
            // entry to actually validate the passphrase against.
            if (archive_entry_size_is_set(entry) && archive_entry_size(entry) > 0) {
                uint8_t probe[64];
                const la_ssize_t n = archive_read_data(a, probe, sizeof(probe));
                if (n < 0) {
                    result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                                      : classifyFailure(a, /*passphraseGiven=*/true);
                    result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "incorrect passphrase";
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
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to open archive";
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
            result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to read header";
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

        // Zip-slip traversal defense
        if (entryPath.empty() || entryPath.find("..") != std::string::npos || entryPath.find(':') != std::string::npos) {
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
                result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError
                                                  : classifyFailure(a, !passphrase.empty());
                result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to read entry data";
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

struct WriteState {
    const ArchiveSink* sink = nullptr;
    uint64_t totalWritten = 0;
    bool ioErrorSeen = false;
    bool cancelled = false;
    std::function<bool(uint64_t)> progressCb;
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
    if (state->progressCb) {
        if (!state->progressCb(state->totalWritten)) {
            state->cancelled = true;
            return -1;
        }
    }
    return static_cast<la_ssize_t>(n);
}

int openSinkCallback(struct archive*, void*) { return ARCHIVE_OK; }
int closeSinkCallback(struct archive*, void*) { return ARCHIVE_OK; }

int configureFormatAndFilters(struct archive* a, ArchiveFormat format, const std::string& passphrase) {
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
            if (!passphrase.empty()) {
                archive_write_set_passphrase(a, passphrase.c_str());
            }
            break;
        case ArchiveFormat::Tar:
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        case ArchiveFormat::TarGz:
            if (archive_write_add_filter_gzip(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        case ArchiveFormat::TarBz2:
            if (archive_write_add_filter_bzip2(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        case ArchiveFormat::TarXz:
            if (archive_write_add_filter_xz(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        case ArchiveFormat::TarZstd:
            if (archive_write_add_filter_zstd(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            break;
        case ArchiveFormat::TarLzma:
            if (archive_write_add_filter_lzma(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
            if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) return ARCHIVE_FATAL;
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

}  // namespace

ArchiveCreateResult archiveCreate(
    const ArchiveSink& sink,
    ArchiveFormat format,
    const std::vector<ArchiveSourceEntry>& entries,
    const std::string& passphrase,
    std::function<bool(uint64_t bytesWrittenSoFar)> progressCallback
) {
    ArchiveCreateResult result;
    WriteState state;
    state.sink = &sink;
    state.progressCb = std::move(progressCallback);

    struct archive* a = archive_write_new();
    if (!a) {
        result.status = ArchiveOpenStatus::IoError;
        result.errorMessage = "failed to create archive writer";
        return result;
    }

    if (configureFormatAndFilters(a, format, passphrase) != ARCHIVE_OK) {
        result.status = ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "unsupported format or filter";
        archive_write_free(a);
        return result;
    }

    if (archive_write_open(a, &state, openSinkCallback, writeSinkCallback, closeSinkCallback) != ARCHIVE_OK) {
        result.status = state.ioErrorSeen ? ArchiveOpenStatus::IoError : ArchiveOpenStatus::UnsupportedFormat;
        result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to open archive write sink";
        archive_write_free(a);
        return result;
    }

    std::vector<uint8_t> chunkBuf(kSequentialChunkSize);
    for (const auto& entry : entries) {
        if (state.cancelled) break;

        struct archive_entry* ae = archive_entry_new();
        archive_entry_set_pathname(ae, entry.pathInArchive.c_str());
        archive_entry_set_filetype(ae, entry.isDirectory ? AE_IFDIR : AE_IFREG);
        archive_entry_set_perm(ae, entry.isDirectory ? 0755 : 0644);
        archive_entry_set_size(ae, static_cast<int64_t>(entry.uncompressedSize));
        if (entry.modTimeEpochSeconds > 0) {
            archive_entry_set_mtime(ae, entry.modTimeEpochSeconds, 0);
        }

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
            }
            if (state.ioErrorSeen) {
                result.status = ArchiveOpenStatus::IoError;
                result.errorMessage = archive_error_string(a) ? archive_error_string(a) : "failed to write entry payload";
                archive_write_close(a);
                archive_write_free(a);
                return result;
            }
        }
        result.entriesArchived++;
    }

    if (archive_write_close(a) != ARCHIVE_OK) {
        if (result.status == ArchiveOpenStatus::Ok || result.errorMessage.empty()) {
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