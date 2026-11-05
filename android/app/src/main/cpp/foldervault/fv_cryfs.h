// CryFS (format 0.10, as written by CryFS 0.10 - 1.0) building blocks:
// config file, block ids, the encrypted block store with its local
// integrity bookkeeping, the blob data tree, directory blobs.
#pragma once

#include <algorithm>
#include <array>
#include <cstring>
#include <atomic>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <unordered_map>

#include "fv_crypto.h"
#include "fv_vault.h"
#include "crypto/cryfs_block_cipher.h"

namespace fv::cryfs {

constexpr const char* kConfigName = "cryfs.config";

struct BlockId {
    std::array<uint8_t, 16> b{};
    static BlockId random();      // creation-time ids (honours user entropy)
    static BlockId randomFast();  // per-block ids, served from a per-thread buffer
    static std::optional<BlockId> fromHex(const std::string& s);
    // Lowercase: used for in-memory keys and the persisted integrity state
    // (kept stable so existing installs keep their recorded versions).
    std::string hex() const { return toHex(b.data(), 16); }
    // Uppercase: what the official CryFS writes in file names and its config.
    std::string hexUpper() const;
    // Physical location of the block file. Uppercase is canonical; vaults
    // written by older builds of this app used lowercase (fine on Android's
    // case-insensitive storage, invisible to CryFS elsewhere), so lowercase
    // is still accepted when reading.
    std::string pathUpper() const { std::string h = hexUpper(); return h.substr(0, 3) + "/" + h.substr(3); }
    std::string pathLower() const { std::string h = hex(); return h.substr(0, 3) + "/" + h.substr(3); }
    bool operator==(const BlockId& o) const { return b == o.b; }
    bool operator!=(const BlockId& o) const { return b != o.b; }
    struct Hash {
        size_t operator()(const BlockId& i) const { size_t h; std::memcpy(&h, i.b.data(), sizeof h); return h; }
    };
};

struct Config {
    std::string cipherName;
    Secret key;
    int blocksizeBytes = 0;
    BlockId rootBlob;
    Bytes filesystemId;
    std::optional<int64_t> exclusiveClientId;
    std::string formatVersion = "0.10", createdWithVersion = "0.10", lastOpenedWithVersion = "0.10";
};

constexpr size_t kCombinedKeySize = 88;   // 32 (outer) + 56 (inner, max)

// Throws Error(InvalidVault / Unsupported / WrongPassword).
Secret deriveCombinedKey(const Bytes& rawConfig, const uint8_t* pw, size_t pwLen);
Config parseWithCombinedKey(const Bytes& rawConfig, const Secret& combinedKey);
Bytes buildConfig(const Config& c, const uint8_t* pw, size_t pwLen);
Config newVaultConfig(const std::string& cipher, int blocksizeBytes);
int cipherKeySize(const std::string& cipherName);       // throws Unsupported
int virtualBlockSize(int physicalBlockSize, const std::string& cipherName);

// Which client wrote which block at which version; persisted outside the
// vault so rollbacks of the vault folder are detected.
class LocalIntegrityState {
public:
    static std::unique_ptr<LocalIntegrityState> open(const std::string& baseDir, const Bytes& filesystemId);
    ~LocalIntegrityState();
    uint64_t myClientId() const { return myClientId_; }
    // [durable]: fsync the reservation before returning (overwrites). New
    // blocks need not: an unrecorded version is simply learned on first read.
    uint64_t nextVersionForOwnWrite(const BlockId& id, bool durable);
    // Returns the already-known higher version if [version] is a rollback.
    std::optional<uint64_t> checkAndRecordRead(uint64_t writerClientId, const BlockId& id, uint64_t version);
    void flush();
private:
    LocalIntegrityState() = default;
    void append(const std::string& key, uint64_t version, bool durable);
    void compact();
    std::string dir_;
    uint64_t myClientId_ = 0;
    std::unordered_map<std::string, uint64_t> known_;
    FILE* log_ = nullptr;
    int pendingLines_ = 0;
    std::mutex mu_;
};

struct IntegrityViolation { BlockId id; uint64_t writer, attempted, known; };

class BlockStore {
public:
    BlockStore(Storage& st, CryfsCipherId cipher, const Secret& key, LocalIntegrityState& integrity);
    std::optional<Bytes> load(const BlockId& id);
    void store(const BlockId& id, const Bytes& payload, bool isNew);
    bool remove(const BlockId& id);
    void clearCache();
    void flushIntegrity() { integrity_.flush(); }
    std::optional<IntegrityViolation> lastViolation() const;
private:
    void cachePut(const BlockId& id, const Bytes& payload);
    bool cacheGet(const BlockId& id, Bytes& out);
    Storage& st_;
    CryfsCipherId cipher_;
    Secret key_;
    LocalIntegrityState& integrity_;
    std::mutex cmu_;
    std::list<BlockId> lru_;
    struct Slot { Bytes data; std::list<BlockId>::iterator it; };
    std::unordered_map<BlockId, Slot, BlockId::Hash> cache_;
    std::mutex smu_;
    std::unordered_map<std::string, bool> shards_;   // shard dirs known to exist
    mutable std::mutex vmu_;
    std::optional<IntegrityViolation> violation_;
    static constexpr size_t kCacheEntries = 1024;
};

// Blob = a tree of fixed-size blocks (leaves carry data, inner nodes child ids).
class DataTree {
public:
    DataTree(BlockStore& bs, int nodeBlockSize) : bs_(bs), nodeBlock_((size_t)nodeBlockSize) {
        maxLeaf_ = nodeBlock_ > kNodeHeader ? nodeBlock_ - kNodeHeader : 1;
        maxChildren_ = std::max<size_t>(maxLeaf_ / 16, 2);
    }
    int64_t size(const BlockId& root);
    Bytes read(const BlockId& root, int64_t offset, int length);
    Bytes readAll(const BlockId& root);
    // Builds a brand-new blob (fresh random ids, nothing references it yet) and
    // returns its root. Lock-free by design: the caller publishes it later.
    BlockId buildBlob(const Bytes& content);
    BlockId buildBlobStream(ByteSource& src);

    // Re-points an existing blob root at a freshly built tree: the scratch
    // root's content replaces [existing]'s, the scratch root block is removed.
    // Returns the old root's children for deleteSubtrees(). Needs exclusive
    // access to the tree (the session holds its write lock around this).
    struct Replaced { std::vector<BlockId> oldChildren; int childDepth = 0; };
    Replaced replaceRoot(const BlockId& existing, const BlockId& scratch);
    void deleteSubtrees(const std::vector<BlockId>& kids, int depth);

    void deleteBlob(const BlockId& root);
    void patchFirstLeafBytes(const BlockId& root, size_t offset, const uint8_t* bytes, size_t n);
    size_t maxLeafPayload() const { return maxLeaf_; }
private:
    static constexpr size_t kNodeHeader = 8;
    struct Node { int depth = 0; Bytes leaf; std::vector<BlockId> children; };
    std::optional<Node> loadNode(const BlockId& id);
    int64_t capacity(int depth) const;
    int64_t nodeSize(const Node& n);
    void planRead(const Node& n, int64_t offset, int64_t length, std::vector<std::tuple<BlockId, int64_t, int64_t>>& plan);
    BlockId writeLeaf(const uint8_t* p, size_t n);
    BlockId writeInner(int depth, const std::vector<BlockId>& kids, size_t from, size_t to);
    BlockId buildUp(std::vector<BlockId> level);
    void deleteSubtree(const BlockId& id, int depth);
    BlockStore& bs_;
    size_t nodeBlock_, maxLeaf_, maxChildren_;
};

enum class EntryType : uint8_t { Dir = 0, File = 1, Symlink = 2 };

struct DirRecord {
    EntryType type = EntryType::File;
    std::string name;
    BlockId blob;
    uint32_t mode = 0, uid = 0, gid = 0;
    int64_t atime = 0, mtime = 0, ctime = 0;
};

constexpr size_t kFsHeaderSize = 2 + 1 + 16;
Bytes dirSerialize(std::vector<DirRecord> entries);
std::vector<DirRecord> dirParse(const Bytes& payload);
Bytes fsWrap(EntryType t, const BlockId& parent, const Bytes& payload);

}  // namespace fv::cryfs
