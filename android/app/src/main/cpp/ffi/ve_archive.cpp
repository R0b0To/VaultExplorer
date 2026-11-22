// Desktop C ABI for the archive engine (see "archives" in ve_engine.h).
//
// The engine itself (archive/archive_engine.*, libarchive underneath) is already compiled into the desktop
// library and takes its bytes from an ArchiveStreamSource, so this file only has to say where those bytes come
// from and where extracted ones go:
//
//   source  a file inside an unlocked slot (src_vol >= 0, read through ve_open_stream/ve_read_stream) or a host
//           file (src_vol < 0). Split sets (name.7z.001, name.z01 + name.zip) are found next to the opened file
//           with std::filesystem or ve_list_directory and presented as one archive by archiveOpenPartSet.
//   sink    memory, a host file or directory, or a vault file or directory (dest_vol >= 0).
//
// Everything goes through the public ve_* calls, so block containers and folder vaults (gocryptfs, Cryptomator,
// CryFS) behave the same and nothing plaintext is ever staged on disk for an in-vault archive. (Android's JNI
// bridge cannot do that: its in-vault path is block-volume only, which is why ArchiveHandlers.kt stages folder
// vault archives to cache files.)
#include "ve_engine.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_set>
#include <vector>

#include "../archive/archive_engine.h"
#include "../platform/engine_hooks.h"

namespace fs = std::filesystem;

namespace {

constexpr size_t kVaultReadStep = 1u << 20;   // one ve_read_stream call never asks for more than this
constexpr size_t kVaultWriteStep = 4u << 20;  // ... and one ve_write_file_chunk never carries more (limit: 64 MiB)

// Result flags (bit 0/1 describe the archive, bit 2 the run).
constexpr uint32_t kFlagSolid = 1u << 0;
constexpr uint32_t kFlagSevenZip = 1u << 1;
constexpr uint32_t kFlagCancelled = 1u << 2;

// ── UTF-8 <-> std::filesystem ────────────────────────────────────────────

fs::path toPath(const std::string& utf8) {
    return fs::path(std::u8string(utf8.begin(), utf8.end()));
}

std::string toUtf8(const fs::path& p) {
    const std::u8string s = p.u8string();
    return std::string(s.begin(), s.end());
}

// ── Result record packing (little-endian) ────────────────────────────────

struct Packer {
    std::vector<uint8_t> b;
    void u32(uint32_t v) {
        for (int i = 0; i < 4; ++i) b.push_back(static_cast<uint8_t>(v >> (8 * i)));
    }
    void u64(uint64_t v) {
        for (int i = 0; i < 8; ++i) b.push_back(static_cast<uint8_t>(v >> (8 * i)));
    }
    void str(const std::string& s) {
        u32(static_cast<uint32_t>(s.size()));
        b.insert(b.end(), s.begin(), s.end());
    }
    // status, flags, count, message -- the head of every result record.
    void head(ArchiveOpenStatus status, uint32_t flags, uint32_t count, const std::string& message) {
        u32(static_cast<uint32_t>(status));
        u32(flags);
        u32(count);
        str(message);
    }
};

bool emitBuffer(const uint8_t* data, size_t len, ve_buffer* out) {
    out->data = nullptr;
    out->len = 0;
    if (len == 0) return true;
    auto* mem = static_cast<uint8_t*>(std::malloc(len));
    if (!mem) return false;
    std::memcpy(mem, data, len);
    out->data = mem;
    out->len = len;
    return true;
}

bool emitRecord(const Packer& p, ve_buffer* out) { return emitBuffer(p.b.data(), p.b.size(), out); }

int32_t finishWithRecord(const Packer& p, ve_buffer* out) {
    return emitRecord(p, out) ? VE_OK : VE_ERR_FAILED;
}

// ── Sources ──────────────────────────────────────────────────────────────

// A host file read at absolute offsets. The stream is shared by the source closures, so it closes when the last
// copy of the source (and with it every part of a split set) is gone.
struct HostFile {
    std::mutex mu;
    std::ifstream in;
    uint64_t size = 0;

    bool open(const fs::path& p) {
        std::error_code ec;
        const auto sz = fs::file_size(p, ec);
        if (ec) return false;
        size = static_cast<uint64_t>(sz);
        in.open(p, std::ios::binary);
        return in.is_open();
    }

    int64_t readAt(uint64_t offset, uint8_t* dest, size_t length) {
        std::lock_guard<std::mutex> g(mu);
        if (offset >= size || length == 0) return 0;
        in.clear();
        in.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
        if (!in) return -1;
        in.read(reinterpret_cast<char*>(dest), static_cast<std::streamsize>(length));
        if (in.bad()) return -1;
        return static_cast<int64_t>(in.gcount());
    }
};

// A stream inside an unlocked slot. ve_read_stream may return fewer bytes than asked for, so readAt loops until
// the request is filled or the file ends (the engine treats any other short read as an I/O error).
struct VaultStream {
    int32_t vol = -1;
    int64_t handle = 0;
    uint64_t size = 0;
    std::mutex mu;

    bool open(int32_t volume, const std::string& path) {
        vol = volume;
        const int64_t sz = ve_get_file_size(vol, path.c_str());
        if (sz < 0) return false;
        handle = ve_open_stream(vol, path.c_str());
        if (handle == 0) return false;
        size = static_cast<uint64_t>(sz);
        return true;
    }

    int64_t readAt(uint64_t offset, uint8_t* dest, size_t length) {
        std::lock_guard<std::mutex> g(mu);
        // Stops at the file's end (known from the size), not at the first short read: a short read in the
        // middle of a file is legal for a stream and must not look like EOF to the engine.
        size_t done = 0;
        while (done < length && offset + done < size) {
            const size_t want = std::min(length - done, kVaultReadStep);
            const int32_t n = ve_read_stream(vol, handle, static_cast<int64_t>(offset + done), dest + done,
                                             static_cast<int32_t>(want));
            if (n < 0) return -1;
            if (n == 0) break;
            done += static_cast<size_t>(n);
        }
        return static_cast<int64_t>(done);
    }

    ~VaultStream() {
        if (handle != 0) ve_close_stream(vol, handle);
    }
};

bool openHostSource(const fs::path& p, ArchiveStreamSource* out) {
    auto file = std::make_shared<HostFile>();
    if (!file->open(p)) return false;
    out->size = [file]() { return file->size; };
    out->read = [file](uint64_t off, uint8_t* dest, size_t n) { return file->readAt(off, dest, n); };
    return true;
}

bool openVaultSource(int32_t vol, const std::string& path, ArchiveStreamSource* out) {
    auto stream = std::make_shared<VaultStream>();
    if (!stream->open(vol, path)) return false;
    out->size = [stream]() { return stream->size; };
    out->read = [stream](uint64_t off, uint8_t* dest, size_t n) { return stream->readAt(off, dest, n); };
    return true;
}

// Names of the files in a vault directory, from ve_list_directory's "F|size|mtime|name" lines.
std::vector<std::string> listVaultFiles(int32_t vol, const std::string& dir) {
    std::vector<std::string> names;
    ve_buffer buf{nullptr, 0};
    if (ve_list_directory(vol, dir.c_str(), &buf) != VE_OK || !buf.data) {
        ve_buffer_free(&buf);
        return names;
    }
    auto rd32 = [&](size_t at) {
        uint32_t v = 0;
        for (int i = 0; i < 4; ++i) v |= static_cast<uint32_t>(buf.data[at + i]) << (8 * i);
        return v;
    };
    if (buf.len >= 4) {
        const uint32_t count = rd32(0);
        size_t pos = 4;
        for (uint32_t i = 0; i < count && pos + 4 <= buf.len; ++i) {
            const uint32_t len = rd32(pos);
            pos += 4;
            if (pos + len > buf.len) break;
            const std::string line(reinterpret_cast<const char*>(buf.data + pos), len);
            pos += len;
            if (line.size() < 2 || line[0] != 'F') continue;
            size_t bar = 0;
            int seen = 0;
            while (seen < 3 && (bar = line.find('|', bar)) != std::string::npos) {
                ++bar;
                ++seen;
            }
            if (seen == 3) names.push_back(line.substr(bar));
        }
    }
    ve_buffer_free(&buf);
    return names;
}

struct OpenedSource {
    bool ok = false;
    ArchiveStreamSource source;
    std::string error;
};

// The archive the caller named -- the whole set when that file is one part of a split archive.
OpenedSource openArchiveSource(int32_t vol, const std::string& path) {
    OpenedSource r;
    ArchiveStreamSource single;
    ArchivePartSetEnv env;
    std::string name;

    if (vol < 0) {
        const fs::path file = toPath(path);
        const fs::path dir = file.parent_path();
        name = toUtf8(file.filename());
        if (!openHostSource(file, &single)) {
            r.error = "Failed to open the archive file";
            return r;
        }
        env.listSiblings = [dir]() {
            std::vector<std::string> names;
            std::error_code ec;
            for (fs::directory_iterator it(dir.empty() ? fs::path(".") : dir, ec), end; !ec && it != end;
                 it.increment(ec)) {
                std::error_code typeEc;
                if (!it->is_directory(typeEc)) names.push_back(toUtf8(it->path().filename()));
            }
            return names;
        };
        env.openSibling = [dir](const std::string& sibling, ArchiveStreamSource* out) {
            return openHostSource(dir / toPath(sibling), out);
        };
    } else {
        const size_t slash = path.rfind('/');
        const std::string dir = slash == std::string::npos ? std::string() : path.substr(0, slash);
        name = slash == std::string::npos ? path : path.substr(slash + 1);
        if (!openVaultSource(vol, path, &single)) {
            r.error = "Failed to open archive stream in vault";
            return r;
        }
        env.listSiblings = [vol, dir]() { return listVaultFiles(vol, dir); };
        env.openSibling = [vol, dir](const std::string& sibling, ArchiveStreamSource* out) {
            return openVaultSource(vol, dir.empty() ? sibling : dir + "/" + sibling, out);
        };
    }

    ArchiveStreamSource joined;
    std::string partError;
    switch (archiveOpenPartSet(name, env, &joined, &partError)) {
        case ArchivePartSetStatus::Opened:
            r.source = joined;
            r.ok = true;
            break;
        case ArchivePartSetStatus::Missing:
            r.error = partError;  // a split archive with a part missing: report it, do not scan one piece
            break;
        case ArchivePartSetStatus::NotASet:
            r.source = single;
            r.ok = true;
            break;
    }
    return r;
}

// ── Sinks ────────────────────────────────────────────────────────────────

// Writes one host file at a time. The destination is created (and truncated) by begin(); discard() removes it.
class HostFileWriter {
public:
    bool begin(const fs::path& p) {
        close();
        path_ = p;
        std::error_code ec;
        if (p.has_parent_path()) fs::create_directories(p.parent_path(), ec);
        if (ec) return false;
        out_.open(p, std::ios::binary | std::ios::trunc);
        return out_.is_open();
    }
    bool write(const uint8_t* data, size_t len) {
        if (len == 0) return out_.is_open();
        out_.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(len));
        return static_cast<bool>(out_);
    }
    bool close() {
        if (!out_.is_open()) return true;
        out_.close();
        return !out_.fail();
    }
    void discard() {
        close();
        std::error_code ec;
        if (!path_.empty()) fs::remove(path_, ec);
    }

private:
    fs::path path_;
    std::ofstream out_;
};

// Writes one vault file at a time, in order from offset 0. A folder vault only makes the file valid at
// ve_fv_finish_write; for a block container that call answers NOT_UNLOCKED, which means "nothing to finish".
class VaultFileWriter {
public:
    explicit VaultFileWriter(int32_t vol) : vol_(vol) {}

    bool begin(const std::string& path) {
        finish();
        path_ = path;
        open_ = true;
        return ve_write_file_chunk(vol_, path.c_str(), 0, nullptr, 0) == VE_OK;
    }
    bool write(uint64_t offset, const uint8_t* data, size_t len) {
        while (len > 0) {
            const size_t step = std::min(len, kVaultWriteStep);
            if (ve_write_file_chunk(vol_, path_.c_str(), static_cast<int64_t>(offset), data, step) != VE_OK) return false;
            offset += step;
            data += step;
            len -= step;
        }
        return true;
    }
    bool finish() {
        if (!open_) return true;
        open_ = false;
        const int32_t rc = ve_fv_finish_write(vol_, path_.c_str());
        return rc == VE_OK || rc == VE_ERR_NOT_UNLOCKED;
    }
    bool inFlight() const { return open_; }
    // Drops a file that was not completed.
    void discard() {
        finish();
        if (!path_.empty()) ve_delete_file(vol_, path_.c_str());
    }
    void makeParents(const std::string& path) {
        size_t pos = 0;
        while ((pos = path.find('/', pos)) != std::string::npos) {
            if (pos > 0) {
                const std::string dir = path.substr(0, pos);
                if (dirs_.insert(dir).second) ve_create_directory(vol_, dir.c_str());
            }
            ++pos;
        }
    }
    void makeDirectory(const std::string& path) {
        makeParents(path + "/");
    }

private:
    int32_t vol_;
    std::string path_;
    bool open_ = false;
    std::unordered_set<std::string> dirs_;
};

std::string joinVaultPath(const std::string& dir, const std::string& rel) {
    return dir.empty() ? rel : dir + "/" + rel;
}

std::string trimSlashes(std::string s) {
    while (!s.empty() && s.front() == '/') s.erase(s.begin());
    while (!s.empty() && s.back() == '/') s.pop_back();
    return s;
}

std::string passphraseOf(const char* p) { return p ? std::string(p) : std::string(); }

}  // namespace

// ── scan ─────────────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_archive_scan(int32_t src_vol, const char* src_path, const char* passphrase,
                                          ve_buffer* out) {
    if (!src_path || !out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    try {
        const OpenedSource src = openArchiveSource(src_vol, src_path);
        Packer p;
        if (!src.ok) {
            p.head(ArchiveOpenStatus::IoError, 0, 0, src.error);
            return finishWithRecord(p, out);
        }
        const ArchiveIndexResult res = archiveScanEntries(src.source, passphraseOf(passphrase));
        const uint32_t flags = (res.isSolid ? kFlagSolid : 0u) | (res.isSevenZip ? kFlagSevenZip : 0u);
        p.head(res.status, flags, static_cast<uint32_t>(res.entries.size()), res.errorMessage);
        for (const ArchiveEntryInfo& e : res.entries) {
            p.str(e.path);
            p.u64(e.uncompressedSize);
            p.u64(e.compressedSize);
            p.u64(static_cast<uint64_t>(e.modTimeEpochSeconds));
            p.u32((e.isEncrypted ? 1u : 0u) | (e.isDirectory ? 2u : 0u));
            p.u32(static_cast<uint32_t>(e.index));
        }
        return finishWithRecord(p, out);
    } catch (const std::bad_alloc&) {
        return VE_ERR_FAILED;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

// ── extract one entry ────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_archive_extract_entry(int32_t src_vol, const char* src_path, int32_t target_index,
                                                   const char* passphrase, int32_t dest_vol, const char* dest_path,
                                                   ve_buffer* data_out, ve_buffer* result_out) {
    if (!src_path || !result_out || target_index < 0) return VE_ERR_INVALID_ARG;
    if (!dest_path && !data_out) return VE_ERR_INVALID_ARG;
    result_out->data = nullptr;
    result_out->len = 0;
    if (data_out) {
        data_out->data = nullptr;
        data_out->len = 0;
    }
    try {
        const OpenedSource src = openArchiveSource(src_vol, src_path);
        Packer p;
        if (!src.ok) {
            p.head(ArchiveOpenStatus::IoError, 0, 0, src.error);
            return finishWithRecord(p, result_out);
        }
        const std::string pass = passphraseOf(passphrase);

        if (!dest_path) {
            ArchiveExtractResult res = archiveExtractEntry(src.source, target_index, pass);
            p.head(res.status, 0, 0, res.errorMessage);
            if (res.status == ArchiveOpenStatus::Ok && !emitBuffer(res.data.data(), res.data.size(), data_out)) {
                return VE_ERR_FAILED;
            }
            return finishWithRecord(p, result_out);
        }

        // Streamed into a host file or a vault file; a failed or cancelled run leaves nothing behind.
        HostFileWriter host;
        VaultFileWriter vault(dest_vol);
        const bool toVault = dest_vol >= 0;
        bool began = false;
        if (toVault) {
            began = vault.begin(trimSlashes(dest_path));
        } else {
            began = host.begin(toPath(dest_path));
        }
        if (!began) {
            if (toVault) vault.discard(); else host.discard();
            p.head(ArchiveOpenStatus::IoError, 0, 0, "Could not create the destination file");
            return finishWithRecord(p, result_out);
        }
        uint64_t offset = 0;
        ArchiveExtractResult res = archiveExtractEntryToSink(
            src.source, target_index, pass, [&](const uint8_t* data, size_t length) {
                const bool ok = toVault ? vault.write(offset, data, length) : host.write(data, length);
                offset += length;
                return ok;
            });
        bool committed = res.status == ArchiveOpenStatus::Ok;
        if (committed) committed = toVault ? vault.finish() : host.close();
        if (!committed) {
            if (toVault) vault.discard(); else host.discard();
            if (res.status == ArchiveOpenStatus::Ok) {
                res.status = ArchiveOpenStatus::IoError;
                res.errorMessage = "Could not write the destination file";
            }
        }
        p.head(res.status, 0, 0, res.errorMessage);
        return finishWithRecord(p, result_out);
    } catch (const std::bad_alloc&) {
        return VE_ERR_FAILED;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

// ── extract everything ───────────────────────────────────────────────────

extern "C" VE_API int32_t ve_archive_extract_all(int32_t src_vol, const char* src_path, const char* passphrase,
                                                 const char* sub_path, int32_t dest_vol, const char* dest_dir,
                                                 int32_t op_id, ve_buffer* out) {
    if (!src_path || !dest_dir || !out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    try {
        const OpenedSource src = openArchiveSource(src_vol, src_path);
        Packer p;
        if (!src.ok) {
            p.head(ArchiveOpenStatus::IoError, 0, 0, src.error);
            return finishWithRecord(p, out);
        }

        const bool toVault = dest_vol >= 0;
        const std::string vaultDir = toVault ? trimSlashes(dest_dir) : std::string();
        const fs::path hostDir = toVault ? fs::path() : toPath(dest_dir);
        HostFileWriter host;
        VaultFileWriter vault(dest_vol);
        std::string currentRel;
        bool cancelled = false;

        if (!toVault) {
            std::error_code ec;
            fs::create_directories(hostDir, ec);
            if (ec) {
                p.head(ArchiveOpenStatus::IoError, 0, 0, "Could not create the destination folder");
                return finishWithRecord(p, out);
            }
        }

        auto makeDir = [&](const std::string& rel) -> bool {
            if (toVault) {
                vault.makeDirectory(joinVaultPath(vaultDir, rel));
                return true;
            }
            std::error_code ec;
            fs::create_directories(hostDir / toPath(rel), ec);
            return !ec;
        };

        // The engine opens every file with (path, 0, 0 bytes), then sends its data in order.
        auto writeChunk = [&](const std::string& rel, uint64_t offset, const uint8_t* data, size_t length) -> bool {
            if (offset == 0 && length == 0) {
                currentRel = rel;
                if (toVault) {
                    const std::string full = joinVaultPath(vaultDir, rel);
                    vault.makeParents(full);
                    return vault.begin(full);
                }
                return host.begin(hostDir / toPath(rel));
            }
            if (rel != currentRel) return false;
            return toVault ? vault.write(offset, data, length) : host.write(data, length);
        };

        // Called after each completed file: that is where a file becomes valid, and where a cancel takes effect.
        auto progress = [&](int32_t count, const std::string&) -> bool {
            const bool finished = toVault ? vault.finish() : host.close();
            if (!finished) return false;
            currentRel.clear();
            if (op_id > 0) {
                reportSplitJoinProgress(op_id, static_cast<uint64_t>(count), 0);
                if (isSplitJoinCancelled(op_id) || isCopyCancelled(op_id)) {
                    cancelled = true;
                    return false;
                }
            }
            return true;
        };

        ArchiveBulkExtractResult res = archiveExtractAll(src.source, passphraseOf(passphrase),
                                                         passphraseOf(sub_path), makeDir, writeChunk, progress);

        // A file still open here was cut short (error, or the progress hook failed to finish it).
        if (!currentRel.empty()) {
            if (toVault) vault.discard(); else host.discard();
            if (res.status == ArchiveOpenStatus::Ok && !cancelled) {
                res.status = ArchiveOpenStatus::IoError;
                res.errorMessage = "Could not write an extracted file";
            }
        }
        p.head(res.status, cancelled ? kFlagCancelled : 0u, static_cast<uint32_t>(std::max(res.extractedCount, 0)),
               res.errorMessage);
        return finishWithRecord(p, out);
    } catch (const std::bad_alloc&) {
        return VE_ERR_FAILED;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}
