// fvcli -- command-line front-end over the foldervault core. Doubles as the
// harness the interop tests drive (real gocryptfs / cryfs on one side, this on
// the other) and as a proof that the core runs with no Android around it.
//
//   fvcli <gocryptfs|cryptomator|cryfs> <vaultdir> <password> <command> [args]
//
// commands: create [opts] | ls P | cat P | get P LOCAL | put P LOCAL |
//           putchunks P LOCAL | mkdir P | mv A B | rm P | size P | du P |
//           passwd NEWPW | migrate7to8 | probe | info | touch P EPOCH |
//           lsl P (symlinks of folder P) | lslt P (same, with mtime) | readlink P | symlink P TARGET | hidden P (entries not shown) |
//           tree [P]   (recursive, one "D|F <TAB> size <TAB> sha256 <TAB> path" line per entry, names
//                       escaped with \\ \n \r \t so any name round-trips; files that cannot be read
//                       get sha256 "ERROR")
// env: FV_LOCALSTATE (cryfs integrity state dir), FV_CIPHER, FV_PLAINNAMES,
//      gocryptfs create: FV_DETERMINISTIC (-deterministic-names), FV_LONGNAMEMAX, FV_SCRYPTN
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>

#include "../fv_crypto.h"
#include "../fv_vault.h"

using namespace fv;

static Bytes slurp(const std::string& p) {
    std::ifstream f(p, std::ios::binary);
    std::stringstream ss; ss << f.rdbuf();
    std::string s = ss.str();
    return Bytes(s.begin(), s.end());
}


static std::string escName(const std::string& s) {
    std::string o;
    for (char c : s) {
        if (c == '\\') o += "\\\\"; else if (c == '\n') o += "\\n"; else if (c == '\r') o += "\\r"; else if (c == '\t') o += "\\t"; else o += c;
    }
    return o;
}

static void walkTree(Vault& v, const std::string& dir) {
    std::vector<DirEntry> es;
    if (!v.listDirectory(dir, es)) { std::printf("E\t0\tERROR\t%s\n", escName(dir).c_str()); return; }
    std::sort(es.begin(), es.end(), [](const DirEntry& a, const DirEntry& b) { return a.name < b.name; });
    for (auto& e : es) {
        std::string path = dir.empty() ? e.name : dir + "/" + e.name;
        if (e.isDir) {
            std::printf("D\t0\t-\t%s\n", escName(path).c_str());
            walkTree(v, path);
            continue;
        }
        Bytes all;
        bool ok = true;
        for (int64_t off = 0;;) {
            auto c = v.readFileChunk(path, off, 1 << 20);
            if (!c) { ok = false; break; }
            if (c->empty()) break;
            all.insert(all.end(), c->begin(), c->end());
            off += (int64_t)c->size();
        }
        std::string h = ok ? toHex(crypto::hash(crypto::Md::Sha256, all.data(), all.size()).data(), 32) : "ERROR";
        std::printf("F\t%lld\t%s\t%s\n", (long long)(ok ? (int64_t)all.size() : e.size), h.c_str(), escName(path).c_str());
    }
}

struct FileSrc : ByteSource {
    std::ifstream f;
    explicit FileSrc(const std::string& p) : f(p, std::ios::binary) {}
    int64_t read(uint8_t* b, size_t n) override { f.read((char*)b, (std::streamsize)n); return (int64_t)f.gcount(); }
};

int main(int argc, char** argv) {
    if (argc < 5) { std::fprintf(stderr, "usage: fvcli fmt dir pw cmd [args]\n"); return 2; }
    std::string fmt = argv[1], dir = argv[2], pw = argv[3], cmd = argv[4];
    auto st = std::make_shared<PosixStorage>(dir);
    const uint8_t* p = (const uint8_t*)pw.data();
    HostEnv env;
    if (const char* ls = std::getenv("FV_LOCALSTATE")) env.cryfsLocalStateDir = ls;
    if (const char* td = std::getenv("TMPDIR")) env.tempDir = td;

    if (cmd == "create") {
        PlainResult r;
        const char* c = std::getenv("FV_CIPHER");
        std::string cipher = c ? c : "";
        if (fmt == "gocryptfs") {
            GocryptfsCreateOptions o;
            if (cipher == "xchacha") o.cipher = GocryptfsCipher::XChaCha20Poly1305;
            else if (cipher == "aessiv") o.cipher = GocryptfsCipher::AesSiv;
            o.plaintextNames = std::getenv("FV_PLAINNAMES") != nullptr;
            o.deterministicNames = std::getenv("FV_DETERMINISTIC") != nullptr;
            if (const char* l = std::getenv("FV_LONGNAMEMAX")) o.longNameMax = std::atoi(l);
            if (const char* n = std::getenv("FV_SCRYPTN")) o.scryptLogN = std::atoi(n);
            r = createGocryptfs(*st, p, pw.size(), o);
        } else if (fmt == "cryptomator") {
            r = createCryptomator(*st, p, pw.size());
        } else {
            CryfsCreateOptions o;
            if (!cipher.empty()) o.cipher = cipher;
            if (const char* bsz = std::getenv("FV_BLOCKSIZE")) o.blocksizeBytes = std::atoi(bsz);
            r = createCryfs(*st, p, pw.size(), o, env);
        }
        if (r.status != OpenStatus::Ok) { std::fprintf(stderr, "create failed: %s\n", r.message.c_str()); return 1; }
        std::puts("created");
        return 0;
    }
    if (cmd == "passwd") {
        if (argc < 6) return 2;
        std::string np = argv[5];
        PlainResult r;
        if (fmt == "gocryptfs") r = changeGocryptfsPassword(*st, p, pw.size(), (const uint8_t*)np.data(), np.size());
        else if (fmt == "cryptomator") r = changeCryptomatorPassword(*st, p, pw.size(), (const uint8_t*)np.data(), np.size());
        else r = changeCryfsPassword(*st, p, pw.size(), (const uint8_t*)np.data(), np.size());
        if (r.status != OpenStatus::Ok) { std::fprintf(stderr, "passwd failed (%d): %s\n", (int)r.status, r.message.c_str()); return 1; }
        std::puts("password changed");
        return 0;
    }

    if (cmd == "probe") {   // password-free format check of a Cryptomator folder; prints 0 / 7 / 8 / -8 / 6
        if (fmt != "cryptomator") { std::fprintf(stderr, "only cryptomator\n"); return 2; }
        std::printf("%d\n", probeCryptomatorFormat(*st));
        return 0;
    }
    if (cmd == "migrate7to8") {
        if (fmt != "cryptomator") { std::fprintf(stderr, "only cryptomator\n"); return 2; }
        PlainResult r = migrateCryptomator7To8(*st, p, pw.size());
        if (r.status != OpenStatus::Ok) { std::fprintf(stderr, "migrate failed (%d): %s\n", (int)r.status, r.message.c_str()); return r.status == OpenStatus::WrongPassword ? 3 : 1; }
        std::puts("migrated");
        return 0;
    }

    OpenResult r;
    if (fmt == "gocryptfs") r = openGocryptfs(st, p, pw.size(), false, env);
    else if (fmt == "cryptomator") r = openCryptomator(st, p, pw.size(), false, env);
    else r = openCryfs(st, p, pw.size(), false, env);
    if (r.status != OpenStatus::Ok) {
        std::fprintf(stderr, "open failed (%s): %s\n", r.status == OpenStatus::WrongPassword ? "wrong password" : "invalid", r.message.c_str());
        return r.status == OpenStatus::WrongPassword ? 3 : 1;
    }
    Vault& v = *r.vault;
    auto arg = [&](int i) -> std::string { return i < argc ? argv[i] : std::string(); };

    if (cmd == "ls") {
        std::vector<DirEntry> es;
        if (!v.listDirectory(arg(5), es)) { std::fprintf(stderr, "ls failed\n"); return 1; }
        std::sort(es.begin(), es.end(), [](const DirEntry& a, const DirEntry& b) { return a.name < b.name; });
        for (auto& e : es) std::printf("%c %lld %s\n", e.isDir ? 'D' : 'F', (long long)e.size, e.name.c_str());
    } else if (cmd == "cat" || cmd == "get") {
        std::string out = cmd == "get" ? arg(6) : "";
        FILE* f = out.empty() ? stdout : std::fopen(out.c_str(), "wb");
        int64_t off = 0;
        for (;;) {
            auto c = v.readFileChunk(arg(5), off, 1 << 20);
            if (!c) { std::fprintf(stderr, "read failed\n"); return 1; }
            if (c->empty()) break;
            std::fwrite(c->data(), 1, c->size(), f);
            off += (int64_t)c->size();
        }
        if (f != stdout) std::fclose(f);
    } else if (cmd == "put") {
        FileSrc src(arg(6));
        if (!v.importStream(arg(5), src, nullptr)) { std::fprintf(stderr, "put failed\n"); return 1; }
    } else if (cmd == "putchunks") {
        Bytes data = slurp(arg(6));
        size_t off = 0;
        const size_t step = 7000;   // deliberately not chunk aligned
        while (off < data.size()) {
            size_t n = std::min(step, data.size() - off);
            if (!v.writeFileChunk(arg(5), (int64_t)off, data.data() + off, n)) { std::fprintf(stderr, "writeFileChunk failed\n"); return 1; }
            off += n;
        }
        if (data.empty() && !v.writeFileChunk(arg(5), 0, nullptr, 0)) return 1;
        if (!v.finishWrite(arg(5))) { std::fprintf(stderr, "finishWrite failed\n"); return 1; }
    } else if (cmd == "putfile") {
        if (!v.writeBackFile(arg(5), arg(6), nullptr)) { std::fprintf(stderr, "writeBackFile failed\n"); return 1; }
    } else if (cmd == "extract") {
        if (!v.extractFile(arg(5), arg(6), nullptr)) { std::fprintf(stderr, "extract failed\n"); return 1; }
    } else if (cmd == "mkdir") {
        if (!v.createDirectory(arg(5))) { std::fprintf(stderr, "mkdir failed\n"); return 1; }
    } else if (cmd == "mv") {
        if (!v.renameFile(arg(5), arg(6))) { std::fprintf(stderr, "mv failed\n"); return 1; }
    } else if (cmd == "rm") {
        if (!v.deleteFile(arg(5))) { std::fprintf(stderr, "rm failed\n"); return 1; }
    } else if (cmd == "tree") {
        walkTree(v, normalizePath(arg(5)));
    } else if (cmd == "size") {
        std::printf("%lld\n", (long long)v.getFileSize(arg(5)));
    } else if (cmd == "du") {
        std::printf("%lld\n", (long long)v.getFolderSize(arg(5)));
    } else if (cmd == "touch") {
        if (!v.setLastModifiedTime(arg(5), std::atoll(arg(6).c_str()))) return 1;
    } else if (cmd == "lsl") {
        std::vector<DirEntry> es;
        if (!v.listSymlinks(arg(5), es)) { std::fprintf(stderr, "lsl failed\n"); return 1; }
        std::sort(es.begin(), es.end(), [](const DirEntry& a, const DirEntry& b) { return a.name < b.name; });
        for (auto& e : es) std::printf("L %lld %s\n", (long long)e.size, e.name.c_str());
    } else if (cmd == "lslt") {   // like lsl, plus the mtime in whole seconds: "L <size> <mtime> <name>"
        std::vector<DirEntry> es;
        if (!v.listSymlinks(arg(5), es)) { std::fprintf(stderr, "lslt failed\n"); return 1; }
        std::sort(es.begin(), es.end(), [](const DirEntry& a, const DirEntry& b) { return a.name < b.name; });
        for (auto& e : es) std::printf("L %lld %lld %s\n", (long long)e.size, (long long)(e.mtimeMs / 1000), e.name.c_str());
    } else if (cmd == "readlink") {
        auto t = v.readSymlink(arg(5));
        if (!t) { std::fprintf(stderr, "readlink failed\n"); return 1; }
        std::printf("%s\n", t->c_str());
    } else if (cmd == "symlink") {
        if (!v.createSymlink(arg(5), arg(6))) { std::fprintf(stderr, "symlink failed\n"); return 1; }
    } else if (cmd == "hidden") {
        std::printf("%d\n", v.hiddenEntryCount(arg(5)));
    } else if (cmd == "info") {
        for (auto& i : v.info()) std::printf("%s=%s\n", i.key.c_str(), i.value.c_str());
    } else { std::fprintf(stderr, "unknown command\n"); return 2; }
    v.close();
    return 0;
}
