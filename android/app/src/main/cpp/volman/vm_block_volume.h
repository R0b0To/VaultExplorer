// Adapter that puts a block-device volume (VeraCrypt, LUKS, BitLocker, VHD/VHDX:
// whatever the engine unlocked into volumes[volId] and mounts as FAT/exFAT, NTFS
// or ext) behind vm::Volume, so it can share a vm::VolumeManager with folder vaults.
//
// It is a thin layer over filesystems/fs_ops.h and follows that header's contract:
// every call takes volumes[volId].mutex exclusively, makes sure the filesystem is
// mounted (ensureMounted), then calls the matching fsXxx(). That is what the JNI
// entry points in jni/filesystem_bridge.cpp do, minus the JNI marshalling, so the
// behaviour on the wire is the same; a Kotlin lock layer on top is not needed.
//
// Unlike vm_foldervault, this file is NOT part of volman_core: it needs the engine
// (session/volume_state.h, fs_ops.h, io/virtual_block_device.h), so it is compiled
// into the target that has the engine -- the Android library today, a desktop engine
// target later. Keeping it out of volman_core keeps that library buildable on its own.
//
// Lifecycle: unlocking and locking a container belongs to the session layer
// (lock policy, flush, key wipe). BlockVolume only *detaches*: close() makes the
// adapter refuse further calls and waits for the ones in flight, but does not lock the
// container. When the session layer locks the container first, alive() turns false
// and VolumeManager treats the slot as NotUnlocked and frees it. The adapter is tied to
// the unlock session it was created for (VolumeState::sessionEpoch): once that session
// ends it stays dead even if another container is later unlocked into the same engine slot.
#pragma once

#include <atomic>
#include <memory>

#include "vm_volume.h"

namespace vm {

class BlockVolume final : public Volume {
public:
    // `engineVolId` indexes the engine's volumes[] table. Using the same number for
    // the manager slot is the convention everywhere in the app, but not required.
    explicit BlockVolume(int engineVolId);
    ~BlockVolume() override = default;

    int engineVolId() const { return id_; }

    Family family() const override { return Family::BlockDevice; }
    bool readOnly() const override { return readOnly_; }
    bool alive() const override;

    bool listDirectory(const std::string& path, std::vector<std::string>& wire) override;
    bool listSymlinks(const std::string& path, std::vector<std::string>& wire) override;
    std::optional<std::string> readSymlink(const std::string& path) override;
    bool createSymlink(const std::string& path, const std::string& target) override;
    bool createDirectory(const std::string& path) override;
    bool renameFile(const std::string& from, const std::string& to) override;
    bool setLastModifiedTime(const std::string& path, int64_t epochSeconds) override;
    bool deleteFile(const std::string& path) override;
    int64_t getFileSize(const std::string& path) override;
    int64_t getFolderSize(const std::string& path) override;

    bool readFileChunk(const std::string& path, int64_t offset, size_t length, Bytes& out) override;
    bool writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) override;
    // finishWrite(): the default (true) -- block filesystems have nothing to commit.
    // importStream(): the default chunk loop; each chunk is its own locked call, so
    // other operations on the volume interleave with a long import.

    bool spaceInfo(SpaceInfo& out) override;
    std::vector<InfoItem> info() override;

    bool hasNativeStreams() const override { return true; }
    std::optional<uint64_t> openStream(const std::string& path) override;
    int64_t readStream(uint64_t handle, uint64_t offset, uint8_t* dst, size_t n) override;
    void closeStream(uint64_t handle) override;

    void close() override;

private:
    // Read together, under the volume's mutex, so the flag and the epoch belong to the same session.
    struct Snapshot {
        bool readOnly = false;
        uint64_t epoch = 0;
    };
    static Snapshot snapshotOf(int engineVolId);
    BlockVolume(int engineVolId, Snapshot snapshot);

    const int id_;
    // Fixed at construction: the read-only flag and the engine's session epoch (VolumeState::sessionEpoch).
    // If the container is locked and another one is unlocked into the same engine slot, the epoch
    // differs and this adapter is dead for good -- it never starts serving the new container.
    const bool readOnly_;
    const uint64_t epoch_;
    std::atomic<bool> closed_{false};
};

std::shared_ptr<BlockVolume> wrapBlockVolume(int engineVolId);

}  // namespace vm
