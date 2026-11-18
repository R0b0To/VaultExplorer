#include "vm_foldervault.h"

#include <algorithm>
#include <limits>

#include "filesystems/dir_entry_wire.h"

namespace vm {

namespace {

// Same shape the JNI bridge used (wireEntry in foldervault_bridge.cpp), built
// with the shared encoder so the format lives in one place on the C++ side.
std::string toWire(const fv::DirEntry& e) {
    const uint64_t size = e.size > 0 ? static_cast<uint64_t>(e.size) : 0;
    const uint64_t mtime = e.mtimeMs > 0 ? static_cast<uint64_t>(e.mtimeMs / 1000) : 0;
    return e.isSymlink ? encodeSymlinkEntryWire(e.name, size, mtime, e.isDir)
                       : encodeDirEntryWire(e.name, e.isDir, size, mtime);
}

// fv::Vault reports failures by throwing fv::Error (and the odd std::exception);
// vm::Volume never throws.
template <class F>
bool guard(F&& f) noexcept {
    try {
        return f();
    } catch (...) {
        return false;
    }
}

template <class T, class F>
T guardValue(T failure, F&& f) noexcept {
    try {
        return f();
    } catch (...) {
        return failure;
    }
}

struct SourceBridge final : fv::ByteSource {
    // Qualified: inside a class derived from fv::ByteSource a bare `ByteSource` names the base.
    explicit SourceBridge(vm::ByteSource& s) : src(s) {}
    int64_t read(uint8_t* buf, size_t n) override { return src.read(buf, n); }
    vm::ByteSource& src;
};

struct ProgressBridge final : fv::Progress {
    explicit ProgressBridge(vm::Observer* o) : obs(o) {}
    void onWriteBack(uint64_t bytes) override {
        if (obs) obs->onBytes(bytes);
    }
    bool cancelled() override { return obs && obs->cancelled(); }
    vm::Observer* obs;
};

}  // namespace

FolderVaultVolume::FolderVaultVolume(std::shared_ptr<fv::Vault> vault) : vault_(std::move(vault)) {}

FolderVaultVolume::~FolderVaultVolume() {
    // Only closes a session nobody else holds: when the bridge's registry still
    // owns it, it decides when the vault closes, not the manager dropping a view of it.
    if (vault_ && vault_.use_count() == 1) guard([&] { vault_->close(); return true; });
}

bool FolderVaultVolume::readOnly() const { return vault_->readOnly(); }

bool FolderVaultVolume::alive() const { return !vault_->closed(); }

bool FolderVaultVolume::listDirectory(const std::string& path, std::vector<std::string>& wire) {
    return guard([&] {
        std::vector<fv::DirEntry> entries;
        if (!vault_->listDirectory(path, entries)) return false;
        wire.clear();
        wire.reserve(entries.size());
        for (const auto& e : entries) wire.push_back(toWire(e));
        return true;
    });
}

bool FolderVaultVolume::listSymlinks(const std::string& path, std::vector<std::string>& wire) {
    return guard([&] {
        std::vector<fv::DirEntry> entries;
        if (!vault_->listSymlinks(path, entries)) return false;
        wire.clear();
        wire.reserve(entries.size());
        for (const auto& e : entries) wire.push_back(toWire(e));
        return true;
    });
}

std::optional<std::string> FolderVaultVolume::readSymlink(const std::string& path) {
    return guardValue<std::optional<std::string>>(std::nullopt, [&] { return vault_->readSymlink(path); });
}

bool FolderVaultVolume::createSymlink(const std::string& path, const std::string& target) {
    return guard([&] { return vault_->createSymlink(path, target); });
}

int FolderVaultVolume::hiddenEntryCount(const std::string& path) {
    return guardValue<int>(-1, [&] { return vault_->hiddenEntryCount(path); });
}

bool FolderVaultVolume::createDirectory(const std::string& path) {
    return guard([&] { return vault_->createDirectory(path); });
}

bool FolderVaultVolume::renameFile(const std::string& from, const std::string& to) {
    return guard([&] { return vault_->renameFile(from, to); });
}

bool FolderVaultVolume::setLastModifiedTime(const std::string& path, int64_t epochSeconds) {
    return guard([&] { return vault_->setLastModifiedTime(path, epochSeconds); });
}

bool FolderVaultVolume::deleteFile(const std::string& path) {
    return guard([&] { return vault_->deleteFile(path); });
}

int64_t FolderVaultVolume::getFileSize(const std::string& path) {
    return guardValue<int64_t>(-1, [&] { return vault_->getFileSize(path); });
}

int64_t FolderVaultVolume::getFolderSize(const std::string& path) {
    return guardValue<int64_t>(-1, [&] { return vault_->getFolderSize(path); });
}

bool FolderVaultVolume::readFileChunk(const std::string& path, int64_t offset, size_t length, Bytes& out) {
    return guard([&] {
        const int want = static_cast<int>(std::min<size_t>(length, std::numeric_limits<int>::max()));
        auto chunk = vault_->readFileChunk(path, offset, want);
        if (!chunk) {
            out.clear();
            return false;
        }
        out = std::move(*chunk);
        return true;
    });
}

bool FolderVaultVolume::writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) {
    return guard([&] { return vault_->writeFileChunk(path, offset, data, len); });
}

bool FolderVaultVolume::finishWrite(const std::string& path) {
    return guard([&] { return vault_->finishWrite(path); });
}

bool FolderVaultVolume::importStream(const std::string& path, ByteSource& src, Observer* obs) {
    return guard([&] {
        SourceBridge in(src);
        ProgressBridge progress(obs);
        return vault_->importStream(path, in, obs ? &progress : nullptr);
    });
}

void FolderVaultVolume::beginBatchWrite() { guard([&] { vault_->beginBatchWrite(); return true; }); }
void FolderVaultVolume::endBatchWrite() { guard([&] { vault_->endBatchWrite(); return true; }); }
void FolderVaultVolume::beginBatchDelete() { guard([&] { vault_->beginBatchDelete(); return true; }); }
void FolderVaultVolume::endBatchDelete() { guard([&] { vault_->endBatchDelete(); return true; }); }
void FolderVaultVolume::invalidateCache(const std::string& path) {
    guard([&] { vault_->invalidateCache(path); return true; });
}

bool FolderVaultVolume::spaceInfo(SpaceInfo& out) {
    return guard([&] {
        int64_t total = -1, free = -1;
        if (!vault_->spaceInfo(total, free)) return false;
        out.total = total;
        out.free = free;
        return true;
    });
}

std::vector<InfoItem> FolderVaultVolume::info() {
    std::vector<InfoItem> out;
    guard([&] {
        for (auto& i : vault_->info()) {
            InfoItem item;
            item.kind = i.kind == fv::InfoItem::Kind::Int    ? InfoItem::Kind::Int
                        : i.kind == fv::InfoItem::Kind::Bool ? InfoItem::Kind::Bool
                                                             : InfoItem::Kind::Str;
            item.key = std::move(i.key);
            item.value = std::move(i.value);
            out.push_back(std::move(item));
        }
        return true;
    });
    return out;
}

void FolderVaultVolume::close() { guard([&] { vault_->close(); return true; }); }

std::shared_ptr<FolderVaultVolume> wrapFolderVault(std::shared_ptr<fv::Vault> vault) {
    if (!vault) return nullptr;
    return std::make_shared<FolderVaultVolume>(std::move(vault));
}

}  // namespace vm
