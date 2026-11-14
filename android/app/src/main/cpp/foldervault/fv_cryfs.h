// CryFS (format 0.10, as written by CryFS 0.10 - 1.0) building blocks:
// config file, block ids, the encrypted block store with its local
// integrity bookkeeping, the blob data tree, directory blobs.
#pragma once

#include <algorithm>
#include <array>
#include <cstring>
#include <functional>
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

// Password-free structural check of the outer cryfs.config envelope (header string, KDF parameter block).
// Throws Error(InvalidVault) with a human-readable reason.
void checkConfigEnvelope(const Bytes& rawConfig);

// Throws Error(InvalidVault / Unsupported / WrongPassword).
Secret deriveCombinedKey(const Bytes& rawConfig, const uint8_t* pw, size_t pwLen);
Config parseWithCombinedKey(const Bytes& rawConfig, const Secret& combinedKey);
// scrypt cost recorded in (and read back from) cryfs.config. Any values are
// readable by official CryFS; only the cost of guessing the password differs.
struct KdfParams { uint32_t N = 1u << 17, r = 8, p = 2; };
KdfParams defaultKdfParams();
KdfParams readKdfParams(const Bytes& rawConfig);   // throws InvalidVault on a malformed file
// [kdf] == nullptr uses defaultKdfParams().
Bytes buildConfig(const Config& c, const uint8_t* pw, size_t pwLen, const KdfParams* kdf = nullptr);
// Re-encrypts [c] keeping the KDF parameters/salt of [oldRaw] and the
// already-derived [combinedKey] -- no password needed. Used to persist a
// config change (e.g. disabling single-client mode) the way official CryFS does.
Bytes rebuildConfigKeepingKey(const Bytes& oldRaw, const Secret& combinedKey, const Config& c);
// Numeric dotted-version comparison ("0.10" == "0.10.0" > "0.9"). Throws
// InvalidVault if either side is not a dotted number.
int compareFormatVersion(const std::string& a, const std::string& b);
constexpr const char* kSupportedFormatVersion = "0.10";
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
    // Same rules as upstream CryFS: returns the already-known version if [version] is older than what
    // [writerClientId] was seen to write, or -- when a *different* client was the last known writer of the
    // block -- not newer than it (an old copy came back).
    std::optional<uint64_t> checkAndRecordRead(uint64_t writerClientId, const BlockId& id, uint64_t version);
    // Records that this client deleted the block, so a restored copy of it is flagged as a rollback.
    void markDeleted(const BlockId& id);
    // Small per-vault markers kept next to the integrity data (e.g. "block names normalised").
    bool flag(const char* name) const;
    void setFlag(const char* name);
    void flush();
private:
    LocalIntegrityState() = default;
    void append(const std::string& key, uint64_t version, bool durable);
    void ingest(const std::string& key, uint64_t value);
    void compact();
    std::string dir_;
    uint64_t myClientId_ = 0;
    std::unordered_map<std::string, uint64_t> known_;
    // Last known writer per block ("L:<hex>" in the persisted files); 0 = the block was deleted. Absent = unknown
    // (state written by older builds), in which case the second rollback rule is not applied.
    std::unordered_map<BlockId, uint32_t, BlockId::Hash> last_;
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
    void setReadOnly(bool ro) { readOnly_ = ro; }
    // Renames block files/shard folders written in lowercase by older builds of this app to the canonical
    // uppercase spelling official CryFS expects. Idempotent; [complete] tells whether nothing was left to do.
    // This is only ever needed for vaults an older build of this app wrote, so it first looks at the top-level
    // folder names only (cheap) and does nothing for vaults that have no lowercase shard folder -- walking every
    // block of a large vault on slow storage would otherwise stall the unlock for minutes. When there is work, it
    // stops after [budgetSeconds] (<= 0: no limit) with *complete == false; the caller passes [forceFull] on the
    // next open so an interrupted pass is resumed even though the folder names alone no longer show the need.
    size_t normalizeBlockNames(bool* complete, double budgetSeconds = 0, bool forceFull = false);
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
    std::atomic<bool> readOnly_{false};
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
    // Loads every block of the blob rooted at [root] (decrypting and authenticating each) and reports, per block
    // id, whether it could be loaded. The children of a block that cannot be loaded are unknown and not visited.
    // [visit] runs right after each load, so BlockStore::lastViolation() still describes that block.
    void walkBlocks(const BlockId& root, const std::function<void(const BlockId&, bool loaded)>& visit);
    void patchFirstLeafBytes(const BlockId& root, size_t offset, const uint8_t* bytes, size_t n);
    size_t maxLeafPayload() const { return maxLeaf_; }
    // Upstream CryFS refuses to load inner nodes deeper than this, so a bigger blob could never be read back by it.
    static constexpr int kMaxTreeDepth = 10;
    // Most leaves a blob may have (maxChildren^kMaxTreeDepth, saturating).
    uint64_t maxLeafCount() const;
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
    int64_t atime = 0, mtime = 0, ctime = 0;          // seconds since the epoch (upstream stores u64)
    uint32_t atimeNs = 0, mtimeNs = 0, ctimeNs = 0;   // nanoseconds, preserved across rewrites
};

constexpr size_t kFsHeaderSize = 2 + 1 + 16;
Bytes dirSerialize(std::vector<DirRecord> entries);
std::vector<DirRecord> dirParse(const Bytes& payload);
Bytes fsWrap(EntryType t, const BlockId& parent, const Bytes& payload);

}  // namespace fv::cryfs
