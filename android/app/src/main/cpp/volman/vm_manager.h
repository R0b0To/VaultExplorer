// The slot table of unlocked volumes, and every operation addressed by slot.
//
// Callers address an unlocked volume by its numeric slot (`volId`, 0..max-1)
// and never need to know which family serves it -- the same rule the whole app
// follows (docs/architecture.md §1). This class is that rule in C++:
//
//   * slots: reserve -> attach -> close, with a free-slot search, an opaque
//     per-slot tag (Android: the container URI; desktop: the path) and
//     "slot removed" listeners;
//   * forwarding of every Volume operation, answering NotUnlocked for an
//     empty slot instead of crashing or guessing;
//   * read streams addressed by handle (media playback), native where the
//     volume has them and emulated with positioned reads otherwise;
//   * copyFile(): a copy between any two volumes that moves the bytes through
//     memory only -- decrypted content never reaches a temp file.
//
// Locking: the manager only guards its own tables. Volumes lock internally
// (see vm_volume.h), so no lock is held across a transfer and a long copy never
// stalls listings on the same volume. close() removes the volume from its slot
// first (new calls see NotUnlocked), then lets it drain calls already running.
#pragma once

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "vm_volume.h"

namespace vm {

class VolumeManager {
public:
    static constexpr int kDefaultMaxVolumes = 8;
    // Same chunk size the Kotlin copy path used (VaultCopyInputStream).
    static constexpr size_t kCopyChunkBytes = 2 * 1024 * 1024;

    explicit VolumeManager(int maxVolumes = kDefaultMaxVolumes);
    ~VolumeManager();                       // closes every volume, without notifying listeners
    VolumeManager(const VolumeManager&) = delete;
    VolumeManager& operator=(const VolumeManager&) = delete;

    int maxVolumes() const { return max_; }

    // ---- slots ----------------------------------------------------------
    // Lowest free slot, marked reserved so two concurrent unlocks cannot pick
    // the same one; -1 when all are taken. Give it back with releaseSlot()
    // when the unlock fails, or hand it to attach().
    int reserveSlot();
    void releaseSlot(int volId);            // no-op unless the slot is only reserved
    // Puts `v` into `volId` (free or reserved by the caller). False when the
    // slot is out of range or already occupied.
    bool attach(int volId, std::shared_ptr<Volume> v, std::string tag = {});
    // reserveSlot() + attach(); the slot, or -1 when full.
    int attach(std::shared_ptr<Volume> v, std::string tag = {});

    // True for a slot holding a volume that is still alive() (see Volume::alive).
    bool isUnlocked(int volId) const;
    bool hasAnyVolume() const;
    // Keeps the volume alive for as long as the caller holds it, even if its
    // slot is closed meanwhile. Null for an empty slot; a volume that is no
    // longer alive() is still returned (isUnlocked() tells them apart).
    std::shared_ptr<Volume> get(int volId) const;
    int findByTag(const std::string& tag) const;      // -1 if none
    std::string tagOf(int volId) const;
    std::vector<int> unlockedSlots() const;
    // Frees every slot whose volume is no longer alive() -- a container locked
    // by the session layer, a vault closed by someone holding its handle --
    // closing the volume's streams and notifying listeners as close() does.
    // reserveSlot() and attach() sweep first, so hosts rarely need to call it.
    void reapDead();

    // Removes the volume, ends its streams, waits for calls in flight and
    // closes it. False when the slot held nothing.
    bool close(int volId);
    void closeAll();

    // Called after a volume has been closed (by close(), closeAll() or a sweep), outside the
    // manager's lock. Not called while the manager is being destroyed.
    using RemovedListener = std::function<void(int volId)>;
    int addRemovedListener(RemovedListener l);        // token for removeRemovedListener
    void removeRemovedListener(int token);

    // What a front-end needs to know about a volume before it talks to it, read in one
    // call: which family it is, and the capabilities that decide how it is used. NotUnlocked
    // for an empty slot or a volume that is no longer alive().
    struct Traits {
        Family family = Family::BlockDevice;
        bool readOnly = false;          // current state: a block volume can become read-only after unlock
        bool caseInsensitive = false;
        bool randomWrites = false;      // Volume::supportsRandomWrites
    };
    Status traits(int volId, Traits& out);

    // ---- namespace ------------------------------------------------------
    Status listDirectory(int volId, const std::string& path, std::vector<std::string>& wire);
    Status listSymlinks(int volId, const std::string& path, std::vector<std::string>& wire);
    Status readSymlink(int volId, const std::string& path, std::string& target);   // Failed: not a readable link
    Status createSymlink(int volId, const std::string& path, const std::string& target);
    Status hiddenEntryCount(int volId, const std::string& path, int& count);
    Status createDirectory(int volId, const std::string& path);
    Status renameFile(int volId, const std::string& from, const std::string& to);
    Status setLastModifiedTime(int volId, const std::string& path, int64_t epochSeconds);
    Status deleteFile(int volId, const std::string& path);
    Status getFileSize(int volId, const std::string& path, int64_t& size);          // Failed: size is -1
    Status getFolderSize(int volId, const std::string& path, int64_t& size);

    // ---- content --------------------------------------------------------
    Status readFileChunk(int volId, const std::string& path, int64_t offset, size_t length, Bytes& out);
    Status writeFileChunk(int volId, const std::string& path, int64_t offset, const uint8_t* data, size_t len);
    Status finishWrite(int volId, const std::string& path);
    Status importStream(int volId, const std::string& path, ByteSource& src, Observer* obs = nullptr);
    Status createEmptyFile(int volId, const std::string& path);
    // Failed when the volume has no random-access writer (see Volume::supportsRandomWrites).
    Status writeFileAt(int volId, const std::string& path, int64_t offset, const uint8_t* data, size_t len);
    Status truncateFile(int volId, const std::string& path, int64_t size);

    Status beginBatchWrite(int volId);
    Status endBatchWrite(int volId);
    Status beginBatchDelete(int volId);
    Status endBatchDelete(int volId);
    Status invalidateCache(int volId, const std::string& path = {});
    Status spaceInfo(int volId, SpaceInfo& out);
    Status info(int volId, std::vector<InfoItem>& out);

    // ---- read streams ---------------------------------------------------
    // Handles are unique across volumes and never reused; a handle only works
    // with the volId it was opened on, and dies when that volume closes.
    Status openStream(int volId, const std::string& path, uint64_t& handle);
    // Bytes read, 0 at end of file, -1 for an unknown handle, a handle of
    // another volume, a closed volume or a read error.
    int64_t readStream(int volId, uint64_t handle, uint64_t offset, uint8_t* dst, size_t n);
    void closeStream(int volId, uint64_t handle);

    // ---- copy between volumes ------------------------------------------
    // Copies one file from `srcVol` to `dstVol` (the same volume is fine),
    // replacing the destination. Source chunks are read, handed straight to the
    // destination and wiped; no plaintext is staged on disk, for any pair of
    // families.
    //
    // A copy that does not deliver every source byte is not a copy: the
    // destination is told the stream failed, and whatever was created under
    // `dstPath` is deleted again (callers clear the destination beforehand, so
    // this only removes what this attempt made). Status::Cancelled when
    // `obs->cancelled()` stopped it. Copying a file onto itself fails without
    // touching it. Empty files are copied like any other.
    Status copyFile(int srcVol, const std::string& srcPath, int dstVol, const std::string& dstPath,
                    Observer* obs = nullptr, size_t chunkBytes = kCopyChunkBytes);

private:
    struct Slot {
        std::shared_ptr<Volume> vol;
        std::string tag;
        bool reserved = false;
    };
    struct Stream {
        int volId = -1;
        std::shared_ptr<Volume> vol;
        std::string path;
        std::optional<uint64_t> inner;   // the volume's own handle, if it has one
    };

    bool inRange(int volId) const { return volId >= 0 && volId < max_; }
    // The volume of an occupied slot that is still alive(); null otherwise.
    std::shared_ptr<Volume> getLive(int volId) const;
    // Empties `volId` if it still holds `expected` (any volume when null) and finishes the close.
    bool detach(int volId, const std::shared_ptr<Volume>& expected);
    void finishClose(int volId, std::shared_ptr<Volume> v);
    template <class F>
    Status with(int volId, F&& f);

    const int max_;
    mutable std::mutex mu_;              // slots_ and listeners_
    std::vector<Slot> slots_;
    std::unordered_map<int, RemovedListener> listeners_;
    int nextListener_ = 1;

    std::mutex streamMu_;
    std::unordered_map<uint64_t, Stream> streams_;
    std::atomic<uint64_t> nextStream_{1};
};

}  // namespace vm
