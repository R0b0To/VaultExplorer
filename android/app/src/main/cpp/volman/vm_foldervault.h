// Adapter that puts a folder vault (cpp/foldervault: gocryptfs, Cryptomator,
// CryFS) behind vm::Volume, so it can sit in a vm::VolumeManager slot next to
// block-device volumes.
//
// The vault already locks internally (one shared_mutex per session, drained by
// close()), so the adapter adds no lock of its own. Anything the core reports
// by exception (fv::Error) becomes a plain failure here, as vm_volume.h
// promises.
#pragma once

#include <memory>

#include "foldervault/fv_vault.h"
#include "vm_volume.h"

namespace vm {

class FolderVaultVolume final : public Volume {
public:
    // Shared, so a host that keeps its own handle to the session (the Android
    // bridge's registry) and the manager can both hold it; whoever closes it
    // first wins and the other sees alive() turn false. A unique_ptr converts implicitly.
    explicit FolderVaultVolume(std::shared_ptr<fv::Vault> vault);
    ~FolderVaultVolume() override;

    // The underlying session, for tooling that works next to an unlocked vault
    // (Check & Repair's exportKeys(), format-specific info). Valid until close().
    fv::Vault& vault() { return *vault_; }

    Family family() const override { return Family::FolderVault; }
    bool readOnly() const override;
    bool alive() const override;

    bool listDirectory(const std::string& path, std::vector<std::string>& wire) override;
    bool listSymlinks(const std::string& path, std::vector<std::string>& wire) override;
    std::optional<std::string> readSymlink(const std::string& path) override;
    bool createSymlink(const std::string& path, const std::string& target) override;
    int hiddenEntryCount(const std::string& path) override;
    bool createDirectory(const std::string& path) override;
    bool renameFile(const std::string& from, const std::string& to) override;
    bool setLastModifiedTime(const std::string& path, int64_t epochSeconds) override;
    bool deleteFile(const std::string& path) override;
    int64_t getFileSize(const std::string& path) override;
    int64_t getFolderSize(const std::string& path) override;

    bool readFileChunk(const std::string& path, int64_t offset, size_t length, Bytes& out) override;
    bool writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) override;
    bool finishWrite(const std::string& path) override;
    bool importStream(const std::string& path, ByteSource& src, Observer* obs) override;

    void beginBatchWrite() override;
    void endBatchWrite() override;
    void beginBatchDelete() override;
    void endBatchDelete() override;
    void invalidateCache(const std::string& path) override;

    bool spaceInfo(SpaceInfo& out) override;
    std::vector<InfoItem> info() override;

    void close() override;

private:
    std::shared_ptr<fv::Vault> vault_;
};

// Convenience for the usual `auto r = fv::openGocryptfs(...); manager.attach(wrapFolderVault(std::move(r.vault)))`.
std::shared_ptr<FolderVaultVolume> wrapFolderVault(std::shared_ptr<fv::Vault> vault);

}  // namespace vm
