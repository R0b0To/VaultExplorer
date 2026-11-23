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
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
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

// ── creating archives ────────────────────────────────────────────────────

constexpr int32_t kLastFormat = 9;  // ArchiveFormat::Cpio

ArchiveCompressionMethod toCompressionMethod(int32_t code) {
    switch (code) {
        case 1: return ArchiveCompressionMethod::Deflate;
        case 2: return ArchiveCompressionMethod::Lzma;
        case 3: return ArchiveCompressionMethod::Lzma2;
        default: return ArchiveCompressionMethod::Default;
    }
}

bool hasDirectoryMarker(const std::string& name) { return !name.empty() && name.back() == '/'; }

std::string withoutDirectoryMarker(std::string name) {
    while (!name.empty() && name.back() == '/') name.pop_back();
    return name;
}

// Seconds since the epoch of a host file's modification time, 0 when unknown. Computed from the distance to
// "now" on both clocks, because converting between file_clock and system_clock is not portable across the
// standard libraries this is built with.
int64_t hostMtimeSeconds(const fs::path& p) {
    std::error_code ec;
    const auto ft = fs::last_write_time(p, ec);
    if (ec) return 0;
    const auto sysNow = std::chrono::system_clock::now();
    const auto fileNow = fs::file_time_type::clock::now();
    return std::chrono::duration_cast<std::chrono::seconds>((sysNow + (ft - fileNow)).time_since_epoch()).count();
}

// One file going into the archive, read only while the archive is working on it: a selection of thousands of
// files never holds thousands of open files or vault streams.
struct CreateSource {
    bool vault = false;
    int32_t vol = -1;
    std::string path;  // vault path, or host path (UTF-8)
    uint64_t size = 0;
    uint64_t offset = 0;
    bool opened = false;
    bool finished = false;
    std::unique_ptr<HostFile> host;
    std::unique_ptr<VaultStream> stream;

    int64_t read(uint8_t* dest, size_t length) {
        if (finished) return 0;
        if (!opened) {
            opened = true;
            if (vault) {
                auto v = std::make_unique<VaultStream>();
                if (!v->open(vol, path)) return -1;
                stream = std::move(v);
            } else {
                auto h = std::make_unique<HostFile>();
                if (!h->open(toPath(path))) return -1;
                host = std::move(h);
            }
        }
        const int64_t n = vault ? stream->readAt(offset, dest, length) : host->readAt(offset, dest, length);
        if (n < 0) return -1;
        offset += static_cast<uint64_t>(n);
        if (n == 0 || offset >= size) release();
        return n;
    }

    void release() {
        finished = true;
        stream.reset();
        host.reset();
    }
};

// Turns the caller's (source path, name in the archive, mtime) triples into engine entries. A name ending in '/'
// is a folder entry, and so is any host source that is a directory.
bool buildEntries(int32_t srcVol, const char* const* paths, const char* const* names, const int64_t* modified,
                  int32_t count, std::vector<CreateSource>& sources, std::vector<ArchiveSourceEntry>& entries,
                  uint64_t* totalBytes, std::string* error) {
    sources.resize(static_cast<size_t>(count));
    entries.assign(static_cast<size_t>(count), ArchiveSourceEntry());
    *totalBytes = 0;
    for (int32_t i = 0; i < count; ++i) {
        if (!paths[i] || !names[i]) {
            *error = "A source path or entry name is missing";
            return false;
        }
        const std::string name = names[i];
        CreateSource& src = sources[static_cast<size_t>(i)];
        ArchiveSourceEntry& e = entries[static_cast<size_t>(i)];
        src.vault = srcVol >= 0;
        src.vol = srcVol;
        src.path = paths[i];
        e.modTimeEpochSeconds = modified ? modified[i] : 0;

        bool isDir = hasDirectoryMarker(name);
        if (!isDir && !src.vault) {
            std::error_code ec;
            isDir = fs::is_directory(toPath(src.path), ec);
        }
        if (isDir) {
            e.pathInArchive = withoutDirectoryMarker(name);
            e.isDirectory = true;
            if (!src.vault && e.modTimeEpochSeconds <= 0) e.modTimeEpochSeconds = hostMtimeSeconds(toPath(src.path));
            continue;
        }

        e.pathInArchive = name;
        if (src.vault) {
            const int64_t size = ve_get_file_size(srcVol, src.path.c_str());
            if (size < 0) {
                *error = "Source file not found in the vault: " + src.path;
                return false;
            }
            src.size = static_cast<uint64_t>(size);
        } else {
            std::error_code ec;
            const auto size = fs::file_size(toPath(src.path), ec);
            if (ec) {
                *error = "Source file not found: " + src.path;
                return false;
            }
            src.size = static_cast<uint64_t>(size);
            if (e.modTimeEpochSeconds <= 0) e.modTimeEpochSeconds = hostMtimeSeconds(toPath(src.path));
        }
        e.uncompressedSize = src.size;
        e.readData = [s = &src](uint8_t* dest, size_t length) -> int64_t { return s->read(dest, length); };
        *totalBytes += src.size;
    }
    return true;
}

// The archive's own spooling folder: 7z and ISO are assembled in a temporary file located through $TMPDIR (TEMP
// and TMP on Windows). The caller picks a private folder; it is process-wide state, so it is set under a lock.
void setSpoolFolder(const char* dir) {
    if (!dir || !*dir) return;
    static std::mutex mu;
    std::lock_guard<std::mutex> g(mu);
#ifdef _WIN32
    _putenv_s("TMP", dir);
    _putenv_s("TEMP", dir);
#else
    setenv("TMPDIR", dir, 1);
#endif
}

// Names of the parts of one split archive: 7z NAME.7z.001, NAME.7z.002, ...; ZIP NAME.z01, NAME.z02, ... and
// the last part NAME.zip (it is written as NAME.z<n> and renamed when the archive is complete).
struct SplitNaming {
    bool zip = false;
    std::string base;  // 7z: the archive path; zip: the path without ".zip"

    static SplitNaming forArchive(const std::string& archivePath, bool zip) {
        SplitNaming n;
        n.zip = zip;
        n.base = archivePath;
        if (zip && archivePath.size() >= 4) {
            std::string tail = archivePath.substr(archivePath.size() - 4);
            for (auto& c : tail) c = static_cast<char>(c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c);
            if (tail == ".zip") n.base = archivePath.substr(0, archivePath.size() - 4);
        }
        return n;
    }
    std::string working(uint32_t index) const {
        char suffix[24];
        std::snprintf(suffix, sizeof suffix, zip ? ".z%02u" : ".%03u", index + 1);
        return base + suffix;
    }
    std::string finalName(uint32_t index, bool isLast) const { return (zip && isLast) ? base + ".zip" : working(index); }
};

// Parts written as host files next to each other. A part never replaces an existing file.
class HostPartFiles {
public:
    explicit HostPartFiles(SplitNaming naming) : naming_(std::move(naming)) {}

    bool open(uint32_t index) {
        current_ = toPath(naming_.working(index));
        std::error_code ec;
        if (fs::exists(current_, ec)) return false;
        if (current_.has_parent_path()) fs::create_directories(current_.parent_path(), ec);
        out_.open(current_, std::ios::binary);
        if (!out_.is_open()) return false;
        created_.push_back(current_);
        return true;
    }
    int64_t write(const uint8_t* data, size_t len) {
        out_.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(len));
        return out_ ? static_cast<int64_t>(len) : -1;
    }
    bool close(uint32_t index, bool isLast) {
        out_.close();
        if (out_.fail()) return false;
        const fs::path finalPath = toPath(naming_.finalName(index, isLast));
        if (finalPath == current_) return true;
        std::error_code ec;
        if (fs::exists(finalPath, ec)) return false;  // never replace a file
        fs::rename(current_, finalPath, ec);
        if (ec) return false;
        created_.back() = finalPath;
        return true;
    }
    void abort() {
        if (out_.is_open()) out_.close();
        std::error_code ec;
        for (const auto& p : created_) fs::remove(p, ec);
        created_.clear();
    }
    uint32_t count() const { return static_cast<uint32_t>(created_.size()); }

private:
    SplitNaming naming_;
    fs::path current_;
    std::ofstream out_;
    std::vector<fs::path> created_;
};

// Parts written into an unlocked vault, finished (folder vaults) and renamed like the host ones.
class VaultPartFiles {
public:
    VaultPartFiles(int32_t vol, SplitNaming naming) : vol_(vol), naming_(std::move(naming)), writer_(vol) {}

    bool open(uint32_t index) {
        current_ = naming_.working(index);
        if (ve_get_file_size(vol_, current_.c_str()) >= 0) return false;  // never replace a file
        if (created_.empty()) writer_.makeParents(current_);
        offset_ = 0;
        if (!writer_.begin(current_)) {
            writer_.discard();
            return false;
        }
        created_.push_back(current_);
        return true;
    }
    int64_t write(const uint8_t* data, size_t len) {
        if (!writer_.write(offset_, data, len)) return -1;
        offset_ += len;
        return static_cast<int64_t>(len);
    }
    bool close(uint32_t index, bool isLast) {
        if (!writer_.finish()) return false;
        const std::string finalPath = naming_.finalName(index, isLast);
        if (finalPath == current_) return true;
        if (ve_get_file_size(vol_, finalPath.c_str()) >= 0) return false;
        if (ve_rename_file(vol_, current_.c_str(), finalPath.c_str()) != VE_OK) return false;
        created_.back() = finalPath;
        return true;
    }
    void abort() {
        writer_.finish();
        for (const auto& p : created_) ve_delete_file(vol_, p.c_str());
        created_.clear();
    }
    uint32_t count() const { return static_cast<uint32_t>(created_.size()); }

private:
    int32_t vol_;
    SplitNaming naming_;
    VaultFileWriter writer_;
    std::string current_;
    uint64_t offset_ = 0;
    std::vector<std::string> created_;
};

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

// ── create ───────────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_archive_create(int32_t src_vol, const char* const* src_paths,
                                            const char* const* entry_names, const int64_t* modified_secs,
                                            int32_t count, int32_t dest_vol, const char* dest_path, int32_t format,
                                            const char* passphrase, int32_t encrypt_filenames,
                                            int32_t compression_level, int32_t compression_method,
                                            uint64_t split_size, const char* temp_dir, int32_t op_id,
                                            ve_buffer* out) {
    if (!src_paths || !entry_names || count < 1 || !dest_path || !*dest_path || !out) return VE_ERR_INVALID_ARG;
    if (format < 0 || format > kLastFormat) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    try {
        Packer p;
        std::vector<CreateSource> sources;
        std::vector<ArchiveSourceEntry> entries;
        uint64_t totalBytes = 0;
        std::string error;
        if (!buildEntries(src_vol, src_paths, entry_names, modified_secs, count, sources, entries, &totalBytes,
                          &error)) {
            p.head(ArchiveOpenStatus::IoError, 0, 0, error);
            return finishWithRecord(p, out);
        }

        setSpoolFolder(temp_dir);
        bool cancelled = false;
        auto progress = [&](uint64_t processed) -> bool {
            if (op_id > 0) {
                reportSplitJoinProgress(op_id, processed, totalBytes);
                if (isSplitJoinCancelled(op_id) || isCopyCancelled(op_id)) {
                    cancelled = true;
                    return false;
                }
            }
            return true;
        };

        const std::string pass = passphraseOf(passphrase);
        const bool toVault = dest_vol >= 0;
        const std::string destPath = toVault ? trimSlashes(dest_path) : std::string(dest_path);
        ArchiveCreateResult res;
        uint32_t written = 0;

        if (split_size > 0) {
            const SplitNaming naming = SplitNaming::forArchive(destPath, format == 0 /* Zip */);
            HostPartFiles hostParts(naming);
            VaultPartFiles vaultParts(dest_vol, naming);
            ArchivePartTarget target;
            if (toVault) {
                target.openPart = [&](uint32_t i) { return vaultParts.open(i); };
                target.writePart = [&](const uint8_t* d, size_t n) { return vaultParts.write(d, n); };
                target.closePart = [&](uint32_t i, bool last) { return vaultParts.close(i, last); };
                target.abort = [&]() { vaultParts.abort(); };
            } else {
                target.openPart = [&](uint32_t i) { return hostParts.open(i); };
                target.writePart = [&](const uint8_t* d, size_t n) { return hostParts.write(d, n); };
                target.closePart = [&](uint32_t i, bool last) { return hostParts.close(i, last); };
                target.abort = [&]() { hostParts.abort(); };
            }
            res = archiveCreateSplit(target, split_size, static_cast<ArchiveFormat>(format), entries, pass,
                                     encrypt_filenames != 0, progress, compression_level,
                                     toCompressionMethod(compression_method));
            written = res.partCount;
        } else {
            HostFileWriter host;
            VaultFileWriter vault(dest_vol);
            bool began = false;
            if (toVault) {
                vault.makeParents(destPath);
                began = vault.begin(destPath);
            } else {
                began = host.begin(toPath(destPath));
            }
            if (!began) {
                if (toVault) vault.discard(); else host.discard();
                p.head(ArchiveOpenStatus::IoError, 0, 0, "Could not create the destination file");
                return finishWithRecord(p, out);
            }
            uint64_t offset = 0;
            ArchiveSink sink;
            sink.write = [&](const uint8_t* d, size_t n) -> int64_t {
                const bool ok = toVault ? vault.write(offset, d, n) : host.write(d, n);
                if (!ok) return -1;
                offset += n;
                return static_cast<int64_t>(n);
            };
            res = archiveCreate(sink, static_cast<ArchiveFormat>(format), entries, pass, encrypt_filenames != 0,
                                progress, compression_level, toCompressionMethod(compression_method));
            bool committed = res.status == ArchiveOpenStatus::Ok;
            if (committed) committed = toVault ? vault.finish() : host.close();
            if (!committed) {
                if (toVault) vault.discard(); else host.discard();  // a failed or cancelled archive leaves nothing
                if (res.status == ArchiveOpenStatus::Ok) {
                    res.status = ArchiveOpenStatus::IoError;
                    res.errorMessage = "Could not write the archive";
                }
            }
            written = committed ? 1 : 0;
        }

        // Whatever the archive stopped reading before the end (failure, cancel) is released with `sources`.
        p.head(res.status, cancelled ? kFlagCancelled : 0u, written, res.errorMessage);
        return finishWithRecord(p, out);
    } catch (const std::bad_alloc&) {
        return VE_ERR_FAILED;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}
