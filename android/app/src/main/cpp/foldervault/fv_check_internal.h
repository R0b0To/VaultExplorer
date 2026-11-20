// Shared plumbing of the per-format Check & Repair implementations (fv_check_*.cpp). Not part of the public API:
// hosts use fv_check.h.
#pragma once

#include <string>
#include <vector>

#include "fv_check.h"
#include "fv_engine.h"

namespace fv::check::detail {

// UTF-8 punctuation used in user-visible messages (kept as escapes so the sources stay encoding-neutral).
inline const char* kDash = "\xE2\x80\x94";
inline const char* kEllipsis = "\xE2\x80\xA6";

// What one check or repair run collects.
struct Ctx {
    Ctx(Storage& storage, const Hooks& h) : st(storage), hooks(h) {}
    Storage& st;
    const Hooks& hooks;
    std::vector<Issue> issues;

    void log(const std::string& m) const { if (hooks.log) hooks.log(m); }
    void add(Severity s, const std::string& path, std::string msg) { issues.push_back(Issue{s, path, std::move(msg)}); }
};

// Report paths: '/'-separated, leading '/', root = "/". [virtualPath] is a cleartext path with or without a
// leading slash ("" = the root).
std::string reportPath(const std::string& virtualPath);
// Cleartext path arithmetic on paths that have no leading slash.
std::string vchild(const std::string& dir, const std::string& name);

// ---- KeyExport access (live sessions hand their keys over through Vault::exportKeys) -----------------------------
const Bytes* exportedField(const KeyExport& k, const char* name);
const std::string* exportedString(const KeyExport& k, const char* name);
// Wipes the key bytes of a KeyExport when it goes out of scope.
struct ExportWipe {
    explicit ExportWipe(KeyExport& k) : k_(k) {}
    ~ExportWipe() { for (auto& f : k_.fields) secureZero(f.second.data(), f.second.size()); }
    KeyExport& k_;
};

// ---- chunked-file verification (gocryptfs and Cryptomator share the <header><chunk><chunk>... layout) -----------
enum class FileState {
    Ok,
    Empty,        // zero bytes
    ShortHeader,  // fewer bytes than a header
    HeaderAuth,   // the header does not verify
    ChunkAuth,    // a chunk does not authenticate
    Io,           // could not be read
};
struct FileVerdict {
    FileState state = FileState::Ok;
    uint64_t badChunk = 0;   // ChunkAuth
    std::string detail;      // HeaderAuth / ChunkAuth: the engine's explanation
};
// Streams [physPath], authenticating the header and every chunk. [hint] is the cleartext path (shown by hosts
// that label lazy downloads). Reads sequentially, so non-seekable descriptors work.
FileVerdict verifyChunkedFile(Storage& st, const FileFormat& fmt, const std::string& physPath, const std::string& hint);

// ---- small helpers -----------------------------------------------------------------------------------------------
// At most [maxBytes] bytes of [s], cut on a UTF-8 character boundary.
std::string truncUtf8(const std::string& s, size_t maxBytes);
// RFC 4122 version-4 UUID text (Cryptomator directory ids).
std::string newUuid();
// Inserts "_<n>" before a trailing ".bin" (or appends it) -- used to find a free name in /LOST+FOUND.
std::string numberedName(const std::string& base, int n);

// ---- per-format entry points -------------------------------------------------------------------------------------
CheckResult checkGocryptfs(Storage& st, const Credentials& cr, const Hooks& hooks);
RepairResult repairGocryptfs(Storage& st, const Credentials& cr, const Hooks& hooks);
CheckResult checkCryptomator(Storage& st, const Credentials& cr, const Hooks& hooks);
RepairResult repairCryptomator(Storage& st, const Credentials& cr, const Hooks& hooks);
CheckResult checkCryfs(Storage& st, const Credentials& cr, const HostEnv& env, const Hooks& hooks);

}  // namespace fv::check::detail
