// Desktop C ABI for native image thumbnails (see "image thumbnails" in ve_engine.h).
//
// The decoding lives in imaging/thumb.* (platform-neutral, no engine headers). This file only says where the
// encoded bytes come from -- a file inside an unlocked slot, a host file, or a block of memory -- and hands the
// finished thumbnail back in a ve_buffer. Vault files are read through the public ve_open_stream / ve_read_stream
// calls, so block containers and folder vaults (gocryptfs, Cryptomator, CryFS) behave the same, in small steps
// (so one thumbnail never holds a volume's lock for long) and without staging anything on disk.
#include "ve_engine.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <new>
#include <string>

#include "../imaging/thumb.h"
#include "../imaging/video_thumb.h"

namespace {

constexpr int64_t kDefaultMaxSourceBytes = 256ll << 20;
constexpr size_t kVaultReadStep = 1u << 20;  // one ve_read_stream call never asks for more than this

// A file inside an unlocked slot. The size is asked once up front, so a read never runs past the end (where the
// block-volume and folder-vault streams do not agree on what "end" returns).
class VaultSource final : public veimg::ByteSource {
public:
    VaultSource(int32_t vol, int64_t handle, int64_t size) : vol_(vol), handle_(handle), size_(size) {}

    int64_t size() override { return size_; }

    int64_t readAt(int64_t offset, uint8_t* dst, size_t len) override {
        if (offset < 0) return -1;
        if (offset >= size_) return 0;
        len = std::min<size_t>(len, static_cast<size_t>(size_ - offset));
        size_t done = 0;
        while (done < len) {
            const int32_t step = static_cast<int32_t>(std::min(len - done, kVaultReadStep));
            const int32_t n = ve_read_stream(vol_, handle_, offset + static_cast<int64_t>(done), dst + done, step);
            if (n < 0) return done ? static_cast<int64_t>(done) : -1;  // the error shows on the next read
            if (n == 0) break;
            done += static_cast<size_t>(n);
        }
        return static_cast<int64_t>(done);
    }

private:
    int32_t vol_;
    int64_t handle_;
    int64_t size_;
};

// A file on the host.
class HostSource final : public veimg::ByteSource {
public:
    explicit HostSource(const std::string& utf8Path)
        : in_(std::filesystem::path(std::u8string(utf8Path.begin(), utf8Path.end())), std::ios::binary) {
        if (in_) {
            in_.seekg(0, std::ios::end);
            const std::streamoff end = in_.tellg();
            size_ = end < 0 ? -1 : static_cast<int64_t>(end);
            in_.seekg(0, std::ios::beg);
        }
    }

    bool ok() const { return static_cast<bool>(in_) && size_ >= 0; }
    int64_t size() override { return size_; }

    int64_t readAt(int64_t offset, uint8_t* dst, size_t len) override {
        if (offset < 0) return -1;
        if (offset >= size_) return 0;
        in_.clear();
        in_.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
        in_.read(reinterpret_cast<char*>(dst), static_cast<std::streamsize>(len));
        const std::streamsize got = in_.gcount();
        if (got <= 0 && in_.bad()) return -1;
        return static_cast<int64_t>(std::max<std::streamsize>(got, 0));
    }

private:
    std::ifstream in_;
    int64_t size_ = -1;
};


// VE_THUMB_TRACE=1 prints one line per thumbnail to stderr; any other non-empty value (except 0) is a file the lines
// are appended to (run the app with it set and read the file). The lines say what happened -- the route, the result
// code, the sizes, the milliseconds, for a video the container and codec -- and never a file name or a path.
const std::string& traceTarget() {
    static const std::string target = [] {
        const char* e = std::getenv("VE_THUMB_TRACE");
        return (e && *e && std::string(e) != "0") ? std::string(e) : std::string();
    }();
    return target;
}

void traceLine(const std::string& line) {
    const std::string& target = traceTarget();
    if (target.empty()) return;
    static std::mutex mu;
    std::lock_guard<std::mutex> lock(mu);
    if (target == "1") {
        std::fprintf(stderr, "%s\n", line.c_str());
    } else {
        std::ofstream f(std::filesystem::path(std::u8string(target.begin(), target.end())), std::ios::app);
        f << line << "\n";
    }
}

long long msSince(std::chrono::steady_clock::time_point t) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t).count();
}

int32_t toCode(veimg::Status st) {
    switch (st) {
        case veimg::Status::kOk: return VE_OK;
        case veimg::Status::kUnsupported: return VE_ERR_UNSUPPORTED;
        case veimg::Status::kTooLarge: return VE_ERR_TOO_LARGE;
        case veimg::Status::kNoMemory: return VE_ERR_NO_MEMORY;
        case veimg::Status::kFailed:
        case veimg::Status::kIoError: return VE_ERR_FAILED;
    }
    return VE_ERR_FAILED;
}

void clearOut(ve_buffer* out, int32_t* info) {
    out->data = nullptr;
    out->len = 0;
    if (info) std::memset(info, 0, sizeof(int32_t) * VE_IMAGE_INFO_COUNT);
}

// Runs the thumbnailer on `src` and fills `out` / `info`.
int32_t run(veimg::ByteSource& src, int32_t targetSize, int32_t quality, int32_t preserveAlpha, int64_t maxSourceBytes,
            ve_buffer* out, int32_t* info) {
    veimg::Options opt;
    opt.targetSize = std::clamp(targetSize, 1, 16384);
    opt.quality = std::clamp(quality, 1, 100);
    opt.preserveAlpha = preserveAlpha != 0;
    opt.maxSourceBytes = static_cast<uint64_t>(maxSourceBytes > 0 ? maxSourceBytes : kDefaultMaxSourceBytes);

    veimg::Thumbnail t;
    const auto started = std::chrono::steady_clock::now();
    const int32_t rc = toCode(veimg::makeThumbnail(src, opt, t));
    if (rc != VE_OK) {
        traceLine("[ve-thumb] image rc=" + std::to_string(rc) + " " + std::to_string(msSince(started)) + "ms");
        return rc;
    }
    auto* mem = static_cast<uint8_t*>(std::malloc(t.bytes.size()));
    if (!mem) return VE_ERR_NO_MEMORY;
    std::memcpy(mem, t.bytes.data(), t.bytes.size());
    out->data = mem;
    out->len = t.bytes.size();
    if (info) {
        info[0] = t.isPng ? 1 : 0;
        info[1] = t.sourceWidth;
        info[2] = t.sourceHeight;
        info[3] = t.width;
        info[4] = t.height;
        info[5] = t.hasAlpha ? 1 : 0;
        info[6] = t.isBlank ? 1 : 0;
    }
    traceLine("[ve-thumb] image ok " + std::to_string(msSince(started)) + "ms " + std::to_string(t.sourceWidth) + "x" +
              std::to_string(t.sourceHeight) + "->" + std::to_string(t.width) + "x" + std::to_string(t.height) +
              (t.isPng ? " png " : " jpeg ") + std::to_string(t.bytes.size()) + "B");
    return VE_OK;
}

// Runs the video thumbnailer on `src` and fills `out` / `info`.
int32_t runVideo(veimg::ByteSource& src, int32_t targetSize, int32_t quality, int32_t strategy, double framePosition,
                 int64_t explicitTimeUs, int32_t timeoutMs, ve_buffer* out, int32_t* info) {
    veimg::VideoOptions opt;
    opt.targetSize = std::clamp(targetSize, 1, 16384);
    opt.quality = std::clamp(quality, 1, 100);
    opt.strategy = strategy == 0   ? veimg::VideoStrategy::kFirstFrame
                   : strategy == 1 ? veimg::VideoStrategy::kFrameAtPercentage
                                   : veimg::VideoStrategy::kHybrid;
    opt.framePosition = framePosition;
    opt.explicitTimeUs = explicitTimeUs;
    opt.timeoutMs = timeoutMs > 0 ? timeoutMs : 20000;

    veimg::VideoThumbnail v;
    const auto started = std::chrono::steady_clock::now();
    const int32_t rc = toCode(veimg::makeVideoThumbnail(src, opt, v));
    if (rc != VE_OK) {
        traceLine("[ve-thumb] video rc=" + std::to_string(rc) + " " + std::to_string(msSince(started)) + "ms | " + v.diag);
        return rc;
    }
    const veimg::Thumbnail& t = v.thumb;
    auto* mem = static_cast<uint8_t*>(std::malloc(t.bytes.size()));
    if (!mem) return VE_ERR_NO_MEMORY;
    std::memcpy(mem, t.bytes.data(), t.bytes.size());
    out->data = mem;
    out->len = t.bytes.size();
    if (info) {
        info[0] = t.isPng ? 1 : 0;
        info[1] = t.sourceWidth;
        info[2] = t.sourceHeight;
        info[3] = t.width;
        info[4] = t.height;
        info[5] = t.hasAlpha ? 1 : 0;
        info[6] = t.isBlank ? 1 : 0;
        info[7] = static_cast<int32_t>(std::min<int64_t>(v.durationUs / 1000, INT32_MAX));
    }
    traceLine("[ve-thumb] video ok " + std::to_string(msSince(started)) + "ms " + std::to_string(t.sourceWidth) + "x" +
              std::to_string(t.sourceHeight) + "->" + std::to_string(t.width) + "x" + std::to_string(t.height) +
              (t.isBlank ? " BLANK " : " ") + std::to_string(t.bytes.size()) + "B | " + v.diag);
    return VE_OK;
}

}  // namespace

// Opens `path` in slot `vol_id` and calls fn(source) on it. The stream is closed afterwards.
template <class Fn>
int32_t withVaultSource(int32_t vol_id, const char* path, int64_t maxSourceBytes, Fn&& fn) {
    const int64_t size = ve_get_file_size(vol_id, path);
    if (size < -1) return static_cast<int32_t>(-size);  // a session error (not unlocked, invalid argument, ...)
    if (size <= 0) return VE_ERR_FAILED;                // missing, a folder, or empty
    if (maxSourceBytes > 0 && size > maxSourceBytes) return VE_ERR_TOO_LARGE;
    const int64_t handle = ve_open_stream(vol_id, path);
    if (handle == 0) return VE_ERR_FAILED;
    struct Closer {
        int32_t vol;
        int64_t handle;
        ~Closer() { ve_close_stream(vol, handle); }
    } closer{vol_id, handle};
    VaultSource src(vol_id, handle, size);
    return fn(src);
}

extern "C" VE_API int32_t ve_image_thumbnail(int32_t vol_id, const char* path, int32_t target_size, int32_t quality,
                                             int32_t preserve_alpha, int64_t max_source_bytes, ve_buffer* out,
                                             int32_t* info) {
    if (!out) return VE_ERR_INVALID_ARG;
    clearOut(out, info);
    if (!path) return VE_ERR_INVALID_ARG;
    try {
        return withVaultSource(vol_id, path, max_source_bytes, [&](veimg::ByteSource& src) {
            return run(src, target_size, quality, preserve_alpha, max_source_bytes, out, info);
        });
    } catch (const std::bad_alloc&) {
        return VE_ERR_NO_MEMORY;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_image_thumbnail_file(const char* host_path_utf8, int32_t target_size, int32_t quality,
                                                  int32_t preserve_alpha, int64_t max_source_bytes, ve_buffer* out,
                                                  int32_t* info) {
    if (!out) return VE_ERR_INVALID_ARG;
    clearOut(out, info);
    if (!host_path_utf8) return VE_ERR_INVALID_ARG;
    try {
        HostSource src{std::string(host_path_utf8)};
        if (!src.ok() || src.size() <= 0) return VE_ERR_FAILED;
        return run(src, target_size, quality, preserve_alpha, max_source_bytes, out, info);
    } catch (const std::bad_alloc&) {
        return VE_ERR_NO_MEMORY;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_image_thumbnail_mem(const uint8_t* data, size_t len, int32_t target_size, int32_t quality,
                                                 int32_t preserve_alpha, ve_buffer* out, int32_t* info) {
    if (!out) return VE_ERR_INVALID_ARG;
    clearOut(out, info);
    if (!data || len == 0) return VE_ERR_INVALID_ARG;
    try {
        veimg::MemorySource src(data, len);
        return run(src, target_size, quality, preserve_alpha, 0, out, info);
    } catch (const std::bad_alloc&) {
        return VE_ERR_NO_MEMORY;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_video_thumbnail(int32_t vol_id, const char* path, int32_t target_size, int32_t quality,
                                             int32_t strategy, double frame_position, int64_t explicit_time_us,
                                             int32_t timeout_ms, ve_buffer* out, int32_t* info) {
    if (!out) return VE_ERR_INVALID_ARG;
    clearOut(out, info);
    if (!path) return VE_ERR_INVALID_ARG;
    if (!veimg::videoThumbnailsAvailable()) {
        traceLine("[ve-thumb] video rc=" + std::to_string(VE_ERR_UNSUPPORTED) + " | this engine was built without FFmpeg");
        return VE_ERR_UNSUPPORTED;
    }
    try {
        // No size cap: a video is read as far as its header and one keyframe need, however large the file is.
        return withVaultSource(vol_id, path, 0, [&](veimg::ByteSource& src) {
            return runVideo(src, target_size, quality, strategy, frame_position, explicit_time_us, timeout_ms, out, info);
        });
    } catch (const std::bad_alloc&) {
        return VE_ERR_NO_MEMORY;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_video_thumbnail_file(const char* host_path_utf8, int32_t target_size, int32_t quality,
                                                  int32_t strategy, double frame_position, int64_t explicit_time_us,
                                                  int32_t timeout_ms, ve_buffer* out, int32_t* info) {
    if (!out) return VE_ERR_INVALID_ARG;
    clearOut(out, info);
    if (!host_path_utf8) return VE_ERR_INVALID_ARG;
    if (!veimg::videoThumbnailsAvailable()) {
        traceLine("[ve-thumb] video rc=" + std::to_string(VE_ERR_UNSUPPORTED) + " | this engine was built without FFmpeg");
        return VE_ERR_UNSUPPORTED;
    }
    try {
        HostSource src{std::string(host_path_utf8)};
        if (!src.ok() || src.size() <= 0) return VE_ERR_FAILED;
        return runVideo(src, target_size, quality, strategy, frame_position, explicit_time_us, timeout_ms, out, info);
    } catch (const std::bad_alloc&) {
        return VE_ERR_NO_MEMORY;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_video_thumbnails_available(void) { return veimg::videoThumbnailsAvailable() ? 1 : 0; }
