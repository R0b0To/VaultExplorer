#include "vm_block_volume.h"

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <shared_mutex>

#include "filesystems/fs_ops.h"
#include "io/virtual_block_device.h"
#include "session/volume_state.h"

namespace vm {

namespace {

// NOTE: volume_state.h reaches ntfs-3g's <support.h>, which defines function-like min(a,b) and
// max(a,b) macros. Inside this file call them as (std::min)(...) / (std::max)(...): the extra
// parentheses keep the macro from expanding. (The repo's host test stubs have no such macros, so
// a host build cannot catch a bare std::min here -- clang against the real ntfs-3g headers does.)

// Same cap the JNI chunk calls apply (jni/filesystem_bridge.cpp MAX_CHUNK_SIZE).
constexpr size_t kMaxChunk = 64 * 1024 * 1024;

bool validId(int id) { return id >= 0 && id < FF_VOLUMES; }

// The test session_guard.cpp's requireActiveSession() applies, on state the caller has locked.
bool engineActive(const VolumeState& v) {
    return v.dataCtxInitialized && (v.fd >= 0 || v.isUsbSource || v.isCompositeSource);
}

// One locked, mounted view of the volume for the duration of one call. `ok` is false
// when the adapter is closed, the session it was made for is over (the container was
// locked, possibly another one unlocked since) or the filesystem cannot be mounted;
// `writable` follows the volume's read-only flag.
//
// Every check happens *under* the mutex, not before it as in the JNI layer: a lock
// racing with the call can then not slip in between the check and the work, and
// BlockVolume::close() (which takes the mutex once to drain) is ordered against calls.
struct Access {
    std::unique_lock<std::shared_mutex> lock;
    bool ok = false;
    bool writable = false;

    Access(int id, uint64_t epoch, const std::atomic<bool>& closed, bool mount = true) {
        if (!validId(id)) return;
        VolumeState& v = volumes[id];
        lock = std::unique_lock<std::shared_mutex>(v.mutex);
        if (closed.load() || v.sessionEpoch != epoch || !engineActive(v)) return;
        if (mount && !ensureMounted(id)) return;
        ok = true;
        writable = !v.readOnly;
    }
};

}  // namespace

BlockVolume::Snapshot BlockVolume::snapshotOf(int id) {
    Snapshot s;
    if (!validId(id)) return s;
    VolumeState& v = volumes[id];
    std::shared_lock<std::shared_mutex> lk(v.mutex);
    s.readOnly = v.readOnly;
    s.epoch = v.sessionEpoch;
    return s;
}

BlockVolume::BlockVolume(int engineVolId) : BlockVolume(engineVolId, snapshotOf(engineVolId)) {}

BlockVolume::BlockVolume(int engineVolId, Snapshot snapshot)
    : id_(engineVolId), readOnly_(snapshot.readOnly), epoch_(snapshot.epoch) {}

bool BlockVolume::alive() const {
    if (closed_.load() || !validId(id_)) return false;
    VolumeState& v = volumes[id_];
    // Never wait here: a busy volume is certainly in use, and the manager asks
    // while holding decisions about slots.
    std::shared_lock<std::shared_mutex> lk(v.mutex, std::try_to_lock);
    if (!lk.owns_lock()) return true;
    return v.sessionEpoch == epoch_ && engineActive(v);
}

bool BlockVolume::caseInsensitive() const {
    if (!validId(id_)) return false;
    VolumeState& v = volumes[id_];
    std::shared_lock<std::shared_mutex> lk(v.mutex);
    if (v.sessionEpoch != epoch_) return false;
    return v.fsType == VolumeState::FS_FATFS || v.fsType == VolumeState::FS_NTFS;
}

bool BlockVolume::listDirectory(const std::string& path, std::vector<std::string>& wire) {
    Access a(id_, epoch_, closed_);
    if (!a.ok) return false;
    std::vector<std::string> tmp;
    if (!fsListDirectory(id_, path, tmp)) return false;   // an unreadable folder is not an empty one
    wire = std::move(tmp);
    return true;
}

bool BlockVolume::listSymlinks(const std::string& path, std::vector<std::string>& wire) {
    Access a(id_, epoch_, closed_);
    if (!a.ok) return false;
    std::vector<std::string> tmp;
    fsListSymlinks(id_, path, tmp);
    wire = std::move(tmp);
    return true;
}

std::optional<std::string> BlockVolume::readSymlink(const std::string& path) {
    Access a(id_, epoch_, closed_);
    if (!a.ok) return std::nullopt;
    std::string target;
    if (!fsReadSymlink(id_, path, target)) return std::nullopt;
    return target;
}

bool BlockVolume::createSymlink(const std::string& path, const std::string& target) {
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsCreateSymlink(id_, path, target);
}

bool BlockVolume::createDirectory(const std::string& path) {
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsCreateDirectory(id_, path);
}

bool BlockVolume::renameFile(const std::string& from, const std::string& to) {
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsRenameFile(id_, from, to);
}

bool BlockVolume::setLastModifiedTime(const std::string& path, int64_t epochSeconds) {
    if (epochSeconds < 0) return false;
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsSetLastModifiedTime(id_, path, static_cast<uint64_t>(epochSeconds));
}

bool BlockVolume::deleteFile(const std::string& path) {
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsDeleteFile(id_, path);
}

int64_t BlockVolume::getFileSize(const std::string& path) {
    Access a(id_, epoch_, closed_);
    return a.ok ? fsGetFileSize(id_, path) : -1;
}

int64_t BlockVolume::getFolderSize(const std::string& path) {
    Access a(id_, epoch_, closed_);
    if (!a.ok) return -1;   // the JNI layer answers 0 here; "cannot tell" is -1 in the vm contract
    const uint64_t total = fsGetFolderSize(id_, path);
    return total > static_cast<uint64_t>(INT64_MAX) ? INT64_MAX : static_cast<int64_t>(total);
}

bool BlockVolume::readFileChunk(const std::string& path, int64_t offset, size_t length, Bytes& out) {
    out.clear();
    if (offset < 0) return false;
    Access a(id_, epoch_, closed_);
    if (!a.ok) return false;
    if (length == 0) return true;
    length = (std::min)(length, kMaxChunk);   // a shorter read is always legal

    std::vector<uint8_t> buf;
    if (fsReadFileChunk(id_, path, static_cast<uint64_t>(offset), length, buf)) {
        out = std::move(buf);
        return true;
    }
    // fsReadFileChunk reports "zero bytes read" as false. At or past the end of an
    // existing file that is end-of-file, not a failure; anything else is.
    const int64_t size = fsGetFileSize(id_, path);
    return size >= 0 && offset >= size;
}

bool BlockVolume::writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) {
    if (offset < 0 || len > kMaxChunk) return false;
    static const uint8_t kNoData = 0;   // a zero-length write at offset 0 still creates / empties the file
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsWriteFileChunk(id_, path, static_cast<uint64_t>(offset), data ? data : &kNoData, len);
}

bool BlockVolume::createEmptyFile(const std::string& path) {
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsCreateEmptyFile(id_, path);
}

bool BlockVolume::writeFileAt(const std::string& path, int64_t offset, const uint8_t* data, size_t len) {
    if (offset < 0 || len > kMaxChunk || (len > 0 && !data)) return false;
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsWriteFileAt(id_, path, static_cast<uint64_t>(offset), data, len);
}

bool BlockVolume::truncateFile(const std::string& path, int64_t size) {
    if (size < 0) return false;
    Access a(id_, epoch_, closed_);
    return a.ok && a.writable && fsTruncateFile(id_, path, static_cast<uint64_t>(size));
}

bool BlockVolume::spaceInfo(SpaceInfo& out) {
    Access a(id_, epoch_, closed_);
    if (!a.ok) return false;
    uint64_t total = 0, free = 0;
    fsGetSpaceInfo(id_, total, free);
    // A mounted filesystem never has zero capacity: 0 means the query failed. Reporting
    // "unknown" keeps callers from reading 0 free bytes as real and refusing every copy.
    if (total == 0) return false;
    out.total = total > static_cast<uint64_t>(INT64_MAX) ? INT64_MAX : static_cast<int64_t>(total);
    out.free = free > static_cast<uint64_t>(INT64_MAX) ? INT64_MAX : static_cast<int64_t>(free);
    return true;
}

std::vector<InfoItem> BlockVolume::info() {
    // Only what the mounted filesystem knows. The container-level facts (format, cipher,
    // KDF...) live in the session state and are reported by the session layer.
    std::vector<InfoItem> out;
    Access a(id_, epoch_, closed_);
    if (!a.ok) return out;
    const std::string label = fsGetFilesystemLabel(id_);
    if (!label.empty()) out.push_back({InfoItem::Kind::Str, "fileSystem", label});
    return out;
}

std::optional<uint64_t> BlockVolume::openStream(const std::string& path) {
    // Exclusive: fsOpenStream pushes onto the volume's open-stream vector.
    Access a(id_, epoch_, closed_);
    if (!a.ok) return std::nullopt;
    void* h = fsOpenStream(id_, path);
    if (!h) return std::nullopt;
    return static_cast<uint64_t>(reinterpret_cast<uintptr_t>(h));
}

int64_t BlockVolume::readStream(uint64_t handle, uint64_t offset, uint8_t* dst, size_t n) {
    if (handle == 0 || n == 0) return handle == 0 ? -1 : 0;
    // No mount check, as in the JNI layer: a stream can only exist on a mounted volume.
    // Exclusive: the handle is validated against the same vector open/close modify.
    Access a(id_, epoch_, closed_, /*mount=*/false);
    if (!a.ok) return -1;
    n = (std::min)(n, kMaxChunk);
    return fsReadStream(id_, reinterpret_cast<void*>(static_cast<uintptr_t>(handle)), offset, dst, n);
}

void BlockVolume::closeStream(uint64_t handle) {
    if (handle == 0 || !validId(id_)) return;
    // Taken even when the adapter is closed: the manager ends a volume's streams before close().
    VolumeState& v = volumes[id_];
    std::unique_lock<std::shared_mutex> lk(v.mutex);
    if (v.sessionEpoch != epoch_ || !engineActive(v)) return;   // the engine dropped every stream when this session ended
    fsCloseStream(id_, reinterpret_cast<void*>(static_cast<uintptr_t>(handle)));
}

void BlockVolume::close() {
    closed_ = true;
    if (!validId(id_)) return;
    // Drain: calls check closed_ under the mutex, so once this lock has been taken and
    // released none is running and none will start. The container itself stays unlocked.
    std::unique_lock<std::shared_mutex> lk(volumes[id_].mutex);
}

std::shared_ptr<BlockVolume> wrapBlockVolume(int engineVolId) {
    if (!validId(engineVolId)) return nullptr;
    return std::make_shared<BlockVolume>(engineVolId);
}

}  // namespace vm
