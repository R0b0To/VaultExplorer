// Folder-vault Check & Repair: entry points and the helpers the per-format files share.
#include "fv_check.h"

#include <algorithm>

#include "fv_check_internal.h"
#include "fv_crypto.h"

namespace fv::check {

const char* formatWire(VaultFormat format) {
    switch (format) {
        case VaultFormat::Gocryptfs: return "gocryptfs";
        case VaultFormat::Cryptomator: return "cryptomator";
        case VaultFormat::Cryfs: return "cryfs";
    }
    return "";
}

namespace detail {

std::string reportPath(const std::string& virtualPath) {
    const std::string n = normalizePath(virtualPath);
    return n.empty() ? std::string("/") : "/" + n;
}

std::string vchild(const std::string& dir, const std::string& name) {
    return dir.empty() ? name : dir + "/" + name;
}

const Bytes* exportedField(const KeyExport& k, const char* name) {
    for (const auto& f : k.fields) if (f.first == name) return &f.second;
    return nullptr;
}

const std::string* exportedString(const KeyExport& k, const char* name) {
    for (const auto& s : k.strings) if (s.first == name) return &s.second;
    return nullptr;
}

FileVerdict verifyChunkedFile(Storage& st, const FileFormat& fmt, const std::string& physPath, const std::string& hint) {
    FileVerdict v;
    FdFile f = st.openRead(physPath, hint);
    if (!f.valid()) { v.state = FileState::Io; return v; }

    const size_t hdr = fmt.headerSize();
    Bytes hb(hdr);
    int64_t n = f.readAt(hb.data(), hdr, 0);
    if (n < 0) { v.state = FileState::Io; return v; }
    if (n == 0) { v.state = FileState::Empty; return v; }
    if ((size_t)n < hdr) { v.state = FileState::ShortHeader; return v; }

    std::shared_ptr<FileKey> key;
    try {
        key = fmt.decodeHeader(hb.data(), hdr);
    } catch (const Error& e) {
        v.state = FileState::HeaderAuth;
        v.detail = e.what();
        return v;
    }
    if (!key) { v.state = FileState::HeaderAuth; v.detail = "the header could not be decoded"; return v; }

    const size_t ccs = fmt.ciphertextChunk(), cs = fmt.cleartextChunk();
    const size_t perBatch = std::max<size_t>(1, (size_t(2) << 20) / ccs);   // ~2 MiB per batch; decrypt() fans out across cores
    Bytes in(perBatch * ccs), out(perBatch * cs);
    struct Wipe { Bytes& b; ~Wipe() { secureZero(b.data(), b.size()); } } wipe{out};

    uint64_t chunk = 0;
    int64_t off = (int64_t)hdr;
    for (;;) {
        const int64_t got = f.readAt(in.data(), in.size(), off);
        if (got < 0) { v.state = FileState::Io; return v; }
        if (got == 0) break;
        const size_t bytes = (size_t)got;
        const size_t tail = bytes % ccs;
        // A trailing piece shorter than a chunk's own nonce+tag cannot be a chunk at all.
        if (tail != 0 && tail < fmt.overhead()) {
            v.state = FileState::ChunkAuth;
            v.badChunk = chunk + bytes / ccs;
            v.detail = "the last chunk is shorter than its authentication data";
            return v;
        }
        try {
            fmt.decrypt(*key, chunk, in.data(), bytes, out.data());
        } catch (const Error& e) {
            // Narrow the failure down to the first bad chunk of this batch.
            v.state = FileState::ChunkAuth;
            v.badChunk = chunk;
            v.detail = e.what();
            const size_t chunks = (bytes + ccs - 1) / ccs;
            for (size_t i = 0; i < chunks; i++) {
                const size_t len = std::min(ccs, bytes - i * ccs);
                try {
                    fmt.decrypt(*key, chunk + i, in.data() + i * ccs, len, out.data());
                } catch (const Error& e2) {
                    v.badChunk = chunk + i;
                    v.detail = e2.what();
                    break;
                }
            }
            return v;
        }
        chunk += (bytes + ccs - 1) / ccs;
        off += got;
        if (bytes < in.size()) break;   // readAt only returns less than asked at the end of the file
    }
    return v;
}

std::string truncUtf8(const std::string& s, size_t maxBytes) {
    if (s.size() <= maxBytes) return s;
    size_t cut = maxBytes;
    while (cut > 0 && (static_cast<unsigned char>(s[cut]) & 0xC0) == 0x80) cut--;
    return s.substr(0, cut);
}

std::string newUuid() {
    uint8_t b[16];
    crypto::randomFast(b, 16);
    b[6] = (uint8_t)((b[6] & 0x0F) | 0x40);
    b[8] = (uint8_t)((b[8] & 0x3F) | 0x80);
    const std::string h = toHex(b, 16);
    return h.substr(0, 8) + "-" + h.substr(8, 4) + "-" + h.substr(12, 4) + "-" + h.substr(16, 4) + "-" + h.substr(20);
}

std::string numberedName(const std::string& base, int n) {
    if (n <= 0) return base;
    static const std::string ext = ".bin";
    if (base.size() > ext.size() && base.compare(base.size() - ext.size(), ext.size(), ext) == 0)
        return base.substr(0, base.size() - ext.size()) + "_" + std::to_string(n) + ext;
    return base + "_" + std::to_string(n);
}

}  // namespace detail

CheckResult checkVault(VaultFormat format, Storage& storage, const Credentials& creds, const HostEnv& env, const Hooks& hooks) {
    try {
        switch (format) {
            case VaultFormat::Gocryptfs: return detail::checkGocryptfs(storage, creds, hooks);
            case VaultFormat::Cryptomator: return detail::checkCryptomator(storage, creds, hooks);
            case VaultFormat::Cryfs: return detail::checkCryfs(storage, creds, env, hooks);
        }
    } catch (const std::exception& e) {
        CheckResult r;
        r.outcome = Outcome::InvalidVault;
        r.message = std::string("The check could not finish: ") + e.what();
        return r;
    }
    CheckResult r;
    r.message = "Unsupported folder vault format.";
    return r;
}

RepairResult repairVault(VaultFormat format, Storage& storage, const Credentials& creds, const HostEnv& /*env*/, const Hooks& hooks) {
    try {
        switch (format) {
            case VaultFormat::Gocryptfs: return detail::repairGocryptfs(storage, creds, hooks);
            case VaultFormat::Cryptomator: return detail::repairCryptomator(storage, creds, hooks);
            case VaultFormat::Cryfs: break;
        }
    } catch (const std::exception& e) {
        RepairResult r;
        r.outcome = Outcome::InvalidVault;
        r.message = std::string("The repair could not finish: ") + e.what();
        return r;
    }
    RepairResult r;
    r.outcome = Outcome::InvalidVault;
    r.message = "Automatic repair is currently supported for Cryptomator and gocryptfs vaults.";
    return r;
}

}  // namespace fv::check
