// CryFS check (there is no CryFS repair). Without credentials it validates the config envelope and counts the block
// files; with a password or an unlocked vault it walks the whole directory tree from the root blob, loading
// (decrypting and authenticating) every block of every blob, and reports what is missing, damaged, rolled back or
// left over.
#include <cstdio>
#include <cctype>
#include <cstdlib>
#include <optional>
#include <filesystem>
#include <memory>
#include <unordered_set>

#include "fv_check_internal.h"
#include "fv_cryfs.h"
#include "fv_util.h"

namespace fv::check::detail {
namespace {

using namespace fv::cryfs;

bool isHex(char ch) { return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'); }
bool allHex(const std::string& s) { for (char ch : s) if (!isHex(ch)) return false; return !s.empty(); }

// The block files on disk, by (lower-case) id. Shard folders are 3 hex characters, block files the remaining 29.
std::unordered_set<std::string> listBlocks(Storage& st) {
    std::unordered_set<std::string> ids;
    std::vector<DirEntry> shards;
    if (!st.list("", shards)) return ids;
    for (const DirEntry& s : shards) {
        if (!s.isDir || s.name.size() != 3 || !allHex(s.name)) continue;
        std::vector<DirEntry> blocks;
        if (!st.list(s.name, blocks)) continue;
        for (const DirEntry& b : blocks) {
            if (b.isDir || b.name.size() != 29 || !allHex(b.name)) continue;
            std::string id = s.name + b.name;
            for (char& ch : id) ch = (char)std::tolower((unsigned char)ch);
            ids.insert(std::move(id));
        }
    }
    return ids;
}

// A scratch directory for a LocalIntegrityState, removed again on destruction. A check that runs next to a live
// session must not open a second writer on the session's own state, so it records into a throw-away one.
struct ScratchDir {
    std::string path;
    explicit ScratchDir(const std::string& base) {
        namespace fs = std::filesystem;
        std::error_code ec;
        fs::path root = base.empty() ? fs::temp_directory_path(ec) : fs::path(base);
        uint8_t r[6];
        crypto::randomFast(r, sizeof r);
        fs::path p = root / ("fv_check_" + toHex(r, sizeof r));
        if (fs::create_directories(p, ec)) path = p.string();
    }
    ~ScratchDir() {
        if (path.empty()) return;
        std::error_code ec;
        std::filesystem::remove_all(path, ec);
    }
};

}  // namespace

CheckResult checkCryfs(Storage& st, const Credentials& cr, const HostEnv& env, const Hooks& hooks) {
    Ctx c(st, hooks);
    CheckResult res;
    res.report.format = VaultFormat::Cryfs;

    Bytes rawConfig;
    if (!st.readWhole(kConfigName, rawConfig)) { res.message = "No cryfs.config found."; return res; }
    try {
        checkConfigEnvelope(rawConfig);
    } catch (const Error& e) {
        res.message = e.what();
        if (res.message.empty()) res.message = "Malformed cryfs.config";
        return res;
    }

    c.log(std::string("Counting block files") + kEllipsis);
    const std::unordered_set<std::string> onDisk = listBlocks(st);
    res.report.filesScanned = (int)onDisk.size();

    // Credentials -> config (cipher, key, block size, root blob).
    Config cfg;
    if (cr.session) {
        KeyExport ke = cr.session->exportKeys();
        ExportWipe wipe(ke);
        const Bytes* key = exportedField(ke, "key");
        const Bytes* fsId = exportedField(ke, "filesystemId");
        const std::string* cipher = exportedString(ke, "blockCipherName");
        const std::string* blockSize = exportedString(ke, "blocksizeBytes");
        const std::string* root = exportedString(ke, "rootBlobId");
        std::optional<BlockId> rootId = root ? BlockId::fromHex(*root) : std::nullopt;
        if (ke.format != VaultFormat::Cryfs || !key || !fsId || !cipher || !blockSize || !rootId) {
            res.message = "The unlocked vault is not a CryFS vault.";
            return res;
        }
        cfg.cipherName = *cipher;
        cfg.key = Secret(*key);
        cfg.filesystemId = *fsId;
        cfg.blocksizeBytes = std::atoi(blockSize->c_str());
        cfg.rootBlob = *rootId;
    } else if (cr.password) {
        c.log(std::string("Deriving the key from the password") + kEllipsis);
        try {
            Secret combined = deriveCombinedKey(rawConfig, cr.password, cr.passwordLen);
            cfg = parseWithCombinedKey(rawConfig, combined);
        } catch (const Error& e) {
            res.outcome = e.code() == Err::WrongPassword ? Outcome::WrongPassword : Outcome::InvalidVault;
            res.message = e.what();
            return res;
        }
    } else {
        c.log(std::string("No password given ") + kDash + " checking structure only.");
        res.outcome = Outcome::Ok;
        res.report.deepScan = false;
        res.report.issues = std::move(c.issues);
        return res;
    }

    const CryfsCipherId cipherId = cryfsCipherIdFromName(cfg.cipherName.c_str());
    if (cipherId == CryfsCipherId::kUnknown) {
        res.message = "Vault uses cipher \"" + cfg.cipherName + "\", which this app does not support.";
        return res;
    }

    // Integrity bookkeeping: the device's own state when nothing else holds it; a throw-away one next to a session.
    std::unique_ptr<ScratchDir> scratch;
    std::unique_ptr<LocalIntegrityState> integrity;
    try {
        std::string base = env.cryfsLocalStateDir;
        if (cr.session || base.empty()) {
            scratch = std::make_unique<ScratchDir>(env.tempDir);
            if (scratch->path.empty()) { res.message = "Could not create a scratch folder for the integrity state."; return res; }
            base = scratch->path;
        }
        integrity = LocalIntegrityState::open(base, cfg.filesystemId);
    } catch (const Error& e) {
        res.message = std::string("Could not open the CryFS integrity state: ") + e.what();
        return res;
    }

    BlockStore bs(st, cipherId, cfg.key, *integrity);
    DataTree dt(bs, virtualBlockSize(cfg.blocksizeBytes, cfg.cipherName));

    c.log(std::string("Walking the directory tree and authenticating every block") + kEllipsis);
    std::unordered_set<std::string> reachable;
    std::unordered_set<std::string> seenBlobs;
    struct Todo { BlockId blob; std::string path; };
    std::vector<Todo> todo{{cfg.rootBlob, ""}};
    int blobs = 0;

    while (!todo.empty()) {
        Todo t = std::move(todo.back());
        todo.pop_back();
        if (!seenBlobs.insert(t.blob.hex()).second) continue;
        blobs++;
        const std::string rp = reportPath(t.path);

        bool treeOk = true;
        dt.walkBlocks(t.blob, [&](const BlockId& id, bool loaded) {
            reachable.insert(id.hex());
            if (loaded) return;
            treeOk = false;
            auto v = bs.lastViolation();
            DirEntry de;
            const bool present = st.stat(id.pathUpper(), de) || st.stat(id.pathLower(), de);
            if (v) {
                c.add(Severity::Critical, rp, "Block " + id.hex() + " looks rolled back: client " + std::to_string(v->writer) +
                      " wrote version " + std::to_string(v->attempted) + ", this device already recorded " + std::to_string(v->known) +
                      " (restored from a backup, or tampered with).");
            } else if (!present) {
                c.add(Severity::Critical, rp, "Block " + id.hex() + " is missing.");
            } else {
                c.add(Severity::Critical, rp, "Block " + id.hex() + " is damaged (it does not authenticate or has an invalid structure).");
            }
        });
        if (!treeOk) continue;

        // Only directories have children to follow; for a file the blocks above are all there is to check.
        Bytes head;
        try { head = dt.read(t.blob, 0, (int)kFsHeaderSize); } catch (const Error&) { head.clear(); }
        if (head.size() < kFsHeaderSize) { c.add(Severity::Critical, rp, "Blob is too short to contain a valid header."); continue; }
        if (readU16LE(head.data()) != 1) { c.add(Severity::Warning, rp, "Blob has an unknown format version " + std::to_string(readU16LE(head.data())) + "."); continue; }
        if (head[2] != (uint8_t)EntryType::Dir) continue;

        Bytes whole;
        try { whole = dt.readAll(t.blob); } catch (const Error&) { whole.clear(); }
        if (whole.size() < kFsHeaderSize) { c.add(Severity::Critical, rp, "Directory blob could not be read."); continue; }
        std::vector<DirRecord> entries;
        try {
            entries = dirParse(Bytes(whole.begin() + (long)kFsHeaderSize, whole.end()));
        } catch (const Error& e) {
            c.add(Severity::Critical, rp, std::string("Directory listing is damaged: ") + e.what());
            continue;
        }
        for (DirRecord& d : entries) todo.push_back({d.blob, vchild(t.path, d.name)});
    }

    // Blocks that exist but no blob reaches: what an interrupted write or an interrupted delete leaves behind.
    // Harmless (CryFS never reads them), so only an Info line, with a count.
    int unreferenced = 0;
    for (const std::string& id : onDisk) if (!reachable.count(id)) unreferenced++;
    if (unreferenced > 0)
        c.add(Severity::Info, "/", std::to_string(unreferenced) + " block file(s) are not part of any file or folder (leftovers of interrupted writes; harmless).");

    c.log("Scan complete: " + std::to_string(blobs) + " file/folder blob(s) walked, " + std::to_string(c.issues.size()) + " issue(s) found.");
    res.outcome = Outcome::Ok;
    res.report.deepScan = true;
    res.report.issues = std::move(c.issues);
    return res;
}

}  // namespace fv::check::detail
