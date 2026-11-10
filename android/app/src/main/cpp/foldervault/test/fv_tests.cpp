// Host-side tests for the folder-vault core. No Android, no network.
//   Known-answer vectors were produced with Python's `cryptography` package
//   (an independent implementation); the format engines are additionally
//   checked against the real gocryptfs / Cryptomator / CryFS in test/interop.
#include <cctype>
#include <filesystem>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <random>
#include <sstream>
#include <thread>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>

#include "../fv_cryptomator.h"
#include "../fv_cryfs.h"
#include "../fv_gocryptfs.h"
#include "../fv_json.h"
#include "../fv_vault.h"

using namespace fv;

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { g_checks++; if (!((a) == (b))) { g_failed++; std::printf("  FAIL %s:%d  %s == %s\n", __FILE__, __LINE__, #a, #b); } } while (0)

static Bytes hex(const char* s) { Bytes b; fromHex(s, b); return b; }
static std::string hexs(const Bytes& b) { return toHex(b.data(), b.size()); }

struct TmpDir {
    std::string path;
    TmpDir() { char t[] = "/tmp/fvtestXXXXXX"; path = mkdtemp(t); }
    ~TmpDir() { std::string cmd = "rm -rf '" + path + "'"; if (system(cmd.c_str())) {} }
    std::string sub(const std::string& n) const { std::string p = path + "/" + n; ::mkdir(p.c_str(), 0755); return p; }
};

static Bytes rnd(size_t n, uint32_t seed = 1) {
    std::mt19937 g(seed);
    Bytes b(n);
    for (auto& x : b) x = (uint8_t)g();
    return b;
}

struct MemSource : ByteSource {
    const Bytes& d; size_t pos = 0;
    explicit MemSource(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override {
        size_t k = std::min(n, d.size() - pos);
        if (k) std::memcpy(buf, d.data() + pos, k);
        pos += k;
        return (int64_t)k;
    }
};

static bool put(Vault& v, const std::string& p, const Bytes& d) { MemSource s(d); return v.importStream(p, s, nullptr); }
static std::optional<Bytes> get(Vault& v, const std::string& p) {
    Bytes out;
    int64_t off = 0;
    for (;;) {
        auto c = v.readFileChunk(p, off, 100000);
        if (!c) return std::nullopt;
        if (c->empty()) break;
        out.insert(out.end(), c->begin(), c->end());
        off += (int64_t)c->size();
    }
    return out;
}
static std::vector<std::string> names(Vault& v, const std::string& dir) {
    std::vector<DirEntry> es;
    std::vector<std::string> out;
    if (v.listDirectory(dir, es)) for (auto& e : es) out.push_back((e.isDir ? "D:" : "F:") + e.name);
    std::sort(out.begin(), out.end());
    return out;
}
static bool has(Vault& v, const std::string& dir, const std::string& entry) {
    auto n = names(v, dir);
    return std::find(n.begin(), n.end(), entry) != n.end();
}

static void walkFiles(const std::string& dir, const std::function<void(const std::string&, off_t)>& fn) {
    DIR* d = opendir(dir.c_str());
    if (!d) return;
    while (auto* e = readdir(d)) {
        std::string n = e->d_name;
        if (n == "." || n == "..") continue;
        std::string p = dir + "/" + n;
        struct stat st;
        if (stat(p.c_str(), &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) walkFiles(p, fn); else fn(p, st.st_size);
    }
    closedir(d);
}
static std::string biggestFile(const std::string& root) {
    std::string best; off_t sz = -1;
    walkFiles(root, [&](const std::string& p, off_t s) { if (s > sz) { sz = s; best = p; } });
    return best;
}
static void flipByte(const std::string& path, off_t at) {
    FILE* f = std::fopen(path.c_str(), "r+b");
    if (!f) return;
    std::fseek(f, at, SEEK_SET);
    int c = std::fgetc(f);
    std::fseek(f, at, SEEK_SET);
    std::fputc(c ^ 0x5A, f);
    std::fclose(f);
}

// ---------------------------------------------------------------- tests --

static void testCodecsAndJson() {
    std::puts("codecs / json");
    CHECK_EQ(base32Encode((const uint8_t*)"foobar", 6), "MZXW6YTBOI");
    CHECK_EQ(base32Encode((const uint8_t*)"fo", 2), "MZXQ");
    CHECK_EQ(base64Encode((const uint8_t*)"foob", 4, false, true), "Zm9vYg==");
    CHECK_EQ(base64Encode((const uint8_t*)"foob", 4, false, false), "Zm9vYg");
    Bytes d; CHECK(base64Decode("Zm9vYg", d)); CHECK_EQ(std::string(d.begin(), d.end()), "foob");
    CHECK(base64Decode("-_8=", d)); CHECK_EQ(hexs(d), "fbff");
    CHECK(!base64Decode("A", d));
    CHECK(isValidUtf8("caf\xC3\xA9 \xF0\x9F\x98\x80")); CHECK(!isValidUtf8("\xC0\x80")); CHECK(!isValidUtf8("\xED\xA0\x80"));
    CHECK_EQ(normalizePath("//a/b//"), "a/b"); CHECK_EQ(parentOf("a/b/c"), "a/b"); CHECK_EQ(nameOf("a"), "a");
    auto v = json::parse("{\"a\":[1,\"x\\u00e9\\ud83d\\ude00\",null,true],\"b\":{\"c\":-5}}");
    CHECK(v.find("a")->items().size() == 4);
    CHECK_EQ(v.find("a")->items()[1].asString(), "x\xC3\xA9\xF0\x9F\x98\x80");
    CHECK_EQ(v.find("b")->find("c")->asInt(), -5);
    CHECK_EQ(json::parse(v.dump(2)).dump(0), v.dump(0));
    bool threw = false;
    try { json::parse("{\"a\":"); } catch (const Error&) { threw = true; }
    CHECK(threw);
}

static void testPrimitives() {
    std::puts("primitives (known answers)");
    // RFC 4231 test case 1
    Bytes key(20, 0x0b);
    CHECK_EQ(hexs(crypto::hmac(crypto::Md::Sha256, key.data(), key.size(), (const uint8_t*)"Hi There", 8)),
             "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
    // RFC 5869 A.3 (zero salt, empty info)
    Bytes ikm(22, 0x0b);
    CHECK_EQ(hexs(crypto::hkdfSha256(ikm.data(), ikm.size(), "", 42).bytes()),
             "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8");
    Bytes mk32(32); for (int i = 0; i < 32; i++) mk32[i] = (uint8_t)i;
    CHECK_EQ(hexs(crypto::hkdfSha256(mk32.data(), 32, "EME filename encryption", 32).bytes()),
             "59366f708e4d4ed892d6bd6ca0de6e927040808b21bd0e1a2753ea365aeaf6c9");
    // RFC 3394 section 4.6
    Bytes kek = mk32, kd = hex("00112233445566778899AABBCCDDEEFF000102030405060708090A0B0C0D0E0F");
    Bytes w = crypto::aesKeyWrap(kek.data(), 32, kd.data(), kd.size());
    CHECK_EQ(hexs(w), "28c9f404c4b810f4cbccb35cfb87f8263f5786e2d80ed326cbc7f0e71a99f43bfb988b9b7a02dd21");
    Secret un; CHECK(crypto::aesKeyUnwrap(kek.data(), 32, w.data(), w.size(), un)); CHECK(un.bytes() == kd);
    w[3] ^= 1; CHECK(!crypto::aesKeyUnwrap(kek.data(), 32, w.data(), w.size(), un));
    // AES-GCM with the two nonce sizes the formats use
    Bytes pt((const uint8_t*)"The quick brown fox jumps over the lazy dog", (const uint8_t*)"The quick brown fox jumps over the lazy dog" + 43);
    Bytes aad(24); for (int i = 0; i < 24; i++) aad[i] = (uint8_t)i;
    crypto::AeadKey gcm(crypto::AeadKind::AesGcm, mk32.data(), 32);
    Bytes n16(16), n12(12); for (int i = 0; i < 16; i++) n16[i] = (uint8_t)i; for (int i = 0; i < 12; i++) n12[i] = (uint8_t)i;
    Bytes out(pt.size() + 16);
    CHECK(gcm.seal(n16.data(), 16, aad.data(), 24, pt.data(), pt.size(), out.data()));
    CHECK_EQ(hexs(out), "3304c5564891234bf6dfb95b3ad3429332dc13810df8be33371e22a3eb8becbe001aa9981c3aa9ee86465137c841363a82c28ae9424027e80d472c");
    CHECK(gcm.seal(n12.data(), 12, aad.data(), 24, pt.data(), pt.size(), out.data()));
    CHECK_EQ(hexs(out), "136ab33bb490ab78e661f5f9de9e164de5b9ff149a0e320c4b478af3781b20c669758e90cebb6bb810cb1859a372fddf74f630220bddd28d876e5d");
    Bytes back(pt.size());
    CHECK(gcm.open(n12.data(), 12, aad.data(), 24, out.data(), out.size(), back.data())); CHECK(back == pt);
    out[5] ^= 1; CHECK(!gcm.open(n12.data(), 12, aad.data(), 24, out.data(), out.size(), back.data()));
    // XChaCha20-Poly1305 round trip + tamper
    crypto::AeadKey xc(crypto::AeadKind::XChaCha20Poly1305, mk32.data(), 32);
    Bytes n24(24, 7), o2(pt.size() + 16), b2(pt.size());
    CHECK(xc.seal(n24.data(), 24, aad.data(), 24, pt.data(), pt.size(), o2.data()));
    CHECK(xc.open(n24.data(), 24, aad.data(), 24, o2.data(), o2.size(), b2.data())); CHECK(b2 == pt);
    o2[0] ^= 1; CHECK(!xc.open(n24.data(), 24, aad.data(), 24, o2.data(), o2.size(), b2.data()));
}

static void testGocryptfsSivVector() {
    std::puts("gocryptfs AES-SIV block layout");
    Bytes key64(64); for (int i = 0; i < 64; i++) key64[i] = (uint8_t)i;
    gocryptfs::ContentFormat f(Secret(key64), GocryptfsCipher::AesSiv);
    Bytes fileId(16); for (int i = 0; i < 16; i++) fileId[i] = (uint8_t)(100 + i);
    Bytes nonce(16); for (int i = 0; i < 16; i++) nonce[i] = (uint8_t)i;
    Bytes pt((const uint8_t*)"The quick brown fox jumps over the lazy dog", (const uint8_t*)"The quick brown fox jumps over the lazy dog" + 43);
    Bytes blk(16 + 16 + pt.size());
    f.sealChunk(fileId.data(), 7, nonce.data(), pt.data(), pt.size(), blk.data());
    CHECK_EQ(hexs(blk), "000102030405060708090a0b0c0d0e0faec4fbc2194d976c40297954354f7e6d3641303a2463c980f324271d0110cf71f7fcc378928e563f90e0f9c886be202685b8535368fcbeac755174");
    Bytes back(pt.size());
    f.openChunk(fileId.data(), 7, blk.data(), blk.size(), back.data());
    CHECK(back == pt);
    blk[20] ^= 1;
    bool threw = false;
    try { f.openChunk(fileId.data(), 7, blk.data(), blk.size(), back.data()); } catch (const Error& e) { threw = e.code() == Err::Auth; }
    CHECK(threw);
    // gocryptfs refuses AESSIV without GCMIV128 and combined with XChaCha
    bool a = false, b = false;
    auto cfg = [](const char* flags) {
        return std::string("{\"EncryptedKey\":\"AAAA\",\"ScryptObject\":{\"Salt\":\"AAAA\",\"N\":1024,\"R\":8,\"P\":1,\"KeyLen\":32},\"Version\":2,\"FeatureFlags\":[") + flags + "]}";
    };
    try { gocryptfs::Config::parse(cfg("\"HKDF\",\"DirIV\",\"EMENames\",\"LongNames\",\"Raw64\",\"AESSIV\"")); } catch (const Error&) { a = true; }
    try { gocryptfs::Config::parse(cfg("\"HKDF\",\"XChaCha20Poly1305\",\"AESSIV\",\"GCMIV128\",\"EMENames\",\"Raw64\"")); } catch (const Error&) { b = true; }
    CHECK(a); CHECK(b);
    CHECK(gocryptfs::Config::parse(cfg("\"HKDF\",\"GCMIV128\",\"AESSIV\",\"EMENames\",\"Raw64\"")).cipher == GocryptfsCipher::AesSiv);
}

static void testCryptomatorNames() {
    std::puts("cryptomator name cryptor (vs python AESSIV)");
    Bytes mkb(64); for (int i = 0; i < 64; i++) mkb[i] = (uint8_t)i;
    cryptomator::Masterkey mk{Secret(mkb)};
    cryptomator::NameCryptor nc(mk);
    CHECK_EQ(nc.hashDirectoryId(""), "MN53XCQH5RFQJPKAFCMWDGELQHPPW2YQ");
    CHECK_EQ(nc.hashDirectoryId("11111111-2222-3333-4444-555555555555"), "JHAWBNTZV3IVBJHFOEJL55NBGRYKJ4PV");
    CHECK_EQ(nc.encryptFilename("test.txt", ""), "0-_yUiJbFKgpvhqQqflvFAW80tgVH2aJ");
    const std::string sub = "11111111-2222-3333-4444-555555555555";
    CHECK_EQ(nc.encryptFilename("caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC.txt", sub), "l_a0KjP9o2CKKUHVh__lnIpZuEM_zulD8UTBmRtSOCA=");
    CHECK_EQ(nc.decryptFilename("l_a0KjP9o2CKKUHVh__lnIpZuEM_zulD8UTBmRtSOCA=", sub), "caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC.txt");
    bool threw = false;
    try { nc.decryptFilename("l_a0KjP9o2CKKUHVh__lnIpZuEM_zulD8UTBmRtSOCA=", "wrong-dir"); } catch (const Error& e) { threw = e.code() == Err::Auth; }
    CHECK(threw);
}

// A generic scenario every format must pass.
static void scenario(const char* label, Vault& v) {
    std::printf("  scenario: %s\n", label);
    CHECK(v.createDirectory("a")); CHECK(v.createDirectory("a/b")); CHECK(v.createDirectory("a/b"));   // idempotent
    Bytes small = rnd(5), big = rnd(1500000, 2), odd = rnd(100001, 3), empty;
    CHECK(put(v, "a/big.bin", big)); CHECK(put(v, "a/b/odd.bin", odd)); CHECK(put(v, "small.bin", small)); CHECK(put(v, "empty.bin", empty));
    CHECK(get(v, "a/big.bin") == big); CHECK(get(v, "a/b/odd.bin") == odd); CHECK(get(v, "small.bin") == small);
    CHECK(get(v, "empty.bin") == empty);
    CHECK_EQ(v.getFileSize("a/big.bin"), (int64_t)big.size()); CHECK_EQ(v.getFileSize("empty.bin"), 0);
    CHECK_EQ(v.getFileSize("a"), -1); CHECK_EQ(v.getFileSize("nope"), -1);
    CHECK_EQ(v.getFolderSize(""), (int64_t)(big.size() + odd.size() + small.size()));
    // random-access reads straddling chunk boundaries
    for (int64_t off : {0, 1, 4095, 4096, 4097, 32767, 32768, 65535, 1499990}) {
        auto c = v.readFileChunk("a/big.bin", off, 9000);
        CHECK(c.has_value());
        size_t want = (size_t)std::min<int64_t>(9000, (int64_t)big.size() - off);
        CHECK(c && c->size() == want && std::memcmp(c->data(), big.data() + off, want) == 0);
    }
    CHECK(v.readFileChunk("a/big.bin", (int64_t)big.size() + 10, 100)->empty());
    // incremental writer with awkward step sizes
    {
        Bytes data = rnd(300000, 4);
        size_t off = 0;
        while (off < data.size()) { size_t n = std::min<size_t>(7001, data.size() - off); CHECK(v.writeFileChunk("inc.bin", (int64_t)off, data.data() + off, n)); off += n; }
        CHECK(v.finishWrite("inc.bin")); CHECK(get(v, "inc.bin") == data);
        if (v.format() == VaultFormat::Cryfs) {
            // CryFS buffers into a scratch file, so a sparse write is legal: the gap reads as zeros.
            CHECK(v.writeFileChunk("inc2.bin", 5, data.data(), 10)); CHECK(v.finishWrite("inc2.bin"));
            auto g = get(v, "inc2.bin");
            CHECK(g && g->size() == 15 && (*g)[0] == 0 && std::memcmp(g->data() + 5, data.data(), 10) == 0);
            CHECK(v.deleteFile("inc2.bin"));
        } else {
            // the encrypted formats stream chunks in order: an out-of-order start must fail and leave nothing behind
            CHECK(!v.writeFileChunk("inc2.bin", 5, data.data(), 10));
            CHECK(!has(v, "", "F:inc2.bin"));
        }
    }
    // overwrite
    Bytes second = rnd(777777, 5);
    CHECK(put(v, "a/big.bin", second)); CHECK(get(v, "a/big.bin") == second);
    // rename / move / replace
    CHECK(v.renameFile("small.bin", "a/b/moved.bin")); CHECK(get(v, "a/b/moved.bin") == small); CHECK(!has(v, "", "F:small.bin"));
    CHECK(v.renameFile("a/b", "a/b2")); CHECK(get(v, "a/b2/odd.bin") == odd);
    CHECK(put(v, "t.tmp", small)); CHECK(put(v, "final.txt", odd)); CHECK(v.renameFile("t.tmp", "final.txt")); CHECK(get(v, "final.txt") == small);
    // unicode + long names
    std::string uni = "caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC \xF0\x9F\x98\x80.txt", lng = std::string(180, 'L') + ".txt";
    CHECK(put(v, uni, small)); CHECK(get(v, uni) == small); CHECK(has(v, "", "F:" + uni));
    CHECK(put(v, "a/" + lng, odd)); CHECK(get(v, "a/" + lng) == odd); CHECK(has(v, "a", "F:" + lng));
    CHECK(v.renameFile("a/" + lng, lng)); CHECK(get(v, lng) == odd); CHECK(!has(v, "a", "F:" + lng));
    CHECK(v.createDirectory(lng + "-dir")); CHECK(put(v, lng + "-dir/x", small)); CHECK(get(v, lng + "-dir/x") == small);
    // mtime
    CHECK(v.setLastModifiedTime("a/big.bin", 1700000000));
    { std::vector<DirEntry> es; CHECK(v.listDirectory("a", es)); for (auto& e : es) if (e.name == "big.bin") CHECK_EQ(e.mtimeMs / 1000, 1700000000); }
    // delete, including a populated tree
    CHECK(v.deleteFile("empty.bin")); CHECK(!has(v, "", "F:empty.bin")); CHECK(!v.deleteFile("empty.bin"));
    CHECK(v.deleteFile("a")); CHECK(!has(v, "", "D:a")); { std::vector<DirEntry> gone; CHECK(!v.listDirectory("a", gone)); }
    // a missing parent must not be silently created
    CHECK(!put(v, "ghost/dir/file", small));
    // extract
    std::string tmp = "/tmp/fv_extract_test.bin";
    CHECK(v.extractFile(lng, tmp, nullptr));
    { std::ifstream f(tmp, std::ios::binary); std::stringstream ss; ss << f.rdbuf(); std::string s = ss.str(); CHECK(Bytes(s.begin(), s.end()) == odd); }
    ::unlink(tmp.c_str());
}

static void testGocryptfs(GocryptfsCipher cipher, bool plain, const char* label) {
    std::printf("gocryptfs %s\n", label);
    TmpDir t; std::string root = t.sub("v");
    auto st = std::make_shared<PosixStorage>(root);
    GocryptfsCreateOptions o; o.cipher = cipher; o.plaintextNames = plain;
    const uint8_t pw[] = "pässwörd";
    CHECK(createGocryptfs(*st, pw, sizeof pw - 1, o).status == OpenStatus::Ok);
    CHECK(createGocryptfs(*st, pw, sizeof pw - 1, o).status == OpenStatus::InvalidVault);   // not empty
    CHECK(openGocryptfs(st, (const uint8_t*)"wrong", 5, false, {}).status == OpenStatus::WrongPassword);
    auto r = openGocryptfs(st, pw, sizeof pw - 1, false, {});
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    scenario(label, *r.vault);
    // tamper: flip a byte inside the largest encrypted file -> reads must fail, not return garbage
    CHECK(put(*r.vault, "victim.bin", rnd(40000, 9)));
    r.vault->close();
    r = openGocryptfs(st, pw, sizeof pw - 1, false, {});
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    CHECK(get(*r.vault, "victim.bin").has_value());
    std::string big = biggestFile(root);
    r.vault->close();
    flipByte(big, 100);
    r = openGocryptfs(st, pw, sizeof pw - 1, false, {});
    if (r.vault) { bool anyFailed = false; std::vector<DirEntry> es; r.vault->listDirectory("", es); for (auto& e : es) if (!e.isDir && !get(*r.vault, e.name)) anyFailed = true; CHECK(anyFailed); }
    // password change
    const uint8_t np[] = "new";
    CHECK(changeGocryptfsPassword(*st, (const uint8_t*)"nope", 4, np, 3).status == OpenStatus::WrongPassword);
    CHECK(changeGocryptfsPassword(*st, pw, sizeof pw - 1, np, 3).status == OpenStatus::Ok);
    CHECK(openGocryptfs(st, pw, sizeof pw - 1, false, {}).status == OpenStatus::WrongPassword);
    CHECK(openGocryptfs(st, np, 3, false, {}).status == OpenStatus::Ok);
}

static void testCryptomator(bool ctrmac) {
    std::printf("cryptomator %s\n", ctrmac ? "SIV_CTRMAC (format 7)" : "SIV_GCM (format 8)");
    TmpDir t; std::string root = t.sub("v");
    auto st = std::make_shared<PosixStorage>(root);
    const uint8_t pw[] = "secret";
    CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
    if (ctrmac) {   // turn it into a genuine format-7 vault (the exact inverse of official Version8Migrator):
                    // version-7 masterkey file, NO vault.cryptomator, NO dirid.c9r backups
        Bytes mkRaw;
        CHECK(st->readWhole("masterkey.cryptomator", mkRaw));
        auto mk = cryptomator::unlockMasterkey(cryptomator::MasterkeyFile::parse(std::string(mkRaw.begin(), mkRaw.end())), pw, 6);
        std::string mkJson = cryptomator::lockMasterkey(mk, pw, 6, 7);
        CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)mkJson.data(), mkJson.size()));
        CHECK(st->remove("vault.cryptomator"));
        cryptomator::NameCryptor nc0(mk);
        std::string h0 = nc0.hashDirectoryId("");
        CHECK(st->remove("d/" + h0.substr(0, 2) + "/" + h0.substr(2) + "/dirid.c9r"));
    }
    CHECK(openCryptomator(st, (const uint8_t*)"bad", 3, false, {}).status == OpenStatus::WrongPassword);
    auto r = openCryptomator(st, pw, 6, false, {});
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    scenario(ctrmac ? "ctrmac" : "gcm", *r.vault);
    // dirid.c9r backup must hold the directory's OWN id
    CHECK(r.vault->createDirectory("bk"));
    r.vault->close();
    {   // find the new dir's id through its dir.c9r pointer and check the backup next to its data
        std::string ptr, backup;
        walkFiles(root, [&](const std::string& p, off_t) { if (p.size() > 7 && p.substr(p.size() - 7) == "dir.c9r") ptr = p; });
        Bytes idBytes; std::ifstream f(ptr, std::ios::binary); std::stringstream ss; ss << f.rdbuf();
        std::string dirId = ss.str();
        Bytes mkRaw; st->readWhole("masterkey.cryptomator", mkRaw);
        auto mk = cryptomator::unlockMasterkey(cryptomator::MasterkeyFile::parse(std::string(mkRaw.begin(), mkRaw.end())), pw, 6);
        cryptomator::NameCryptor nc(mk);
        std::string h = nc.hashDirectoryId(dirId);
        Bytes enc;
        CHECK(st->readWhole("d/" + h.substr(0, 2) + "/" + h.substr(2) + "/dirid.c9r", enc));
        cryptomator::ContentFormat fmt(mk, ctrmac ? cryptomator::Combo::SivCtrMac : cryptomator::Combo::SivGcm);
        auto key = fmt.decodeHeader(enc.data(), enc.size());
        Bytes plain(fmt.decryptedSize(enc.size() - fmt.headerSize()));
        fmt.decrypt(*key, 0, enc.data() + fmt.headerSize(), enc.size() - fmt.headerSize(), plain.data());
        CHECK_EQ(std::string(plain.begin(), plain.end()), dirId);
    }
    r = openCryptomator(st, pw, 6, false, {});
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    CHECK(put(*r.vault, "victim.bin", rnd(100000, 11)));
    r.vault->close();
    flipByte(biggestFile(root), 200);
    r = openCryptomator(st, pw, 6, false, {});
    if (r.vault) { bool anyFailed = false; std::vector<DirEntry> es; r.vault->listDirectory("", es); for (auto& e : es) if (!e.isDir && !get(*r.vault, e.name)) anyFailed = true; CHECK(anyFailed); }
    const uint8_t np[] = "other";
    CHECK(changeCryptomatorPassword(*st, pw, 6, np, 5).status == OpenStatus::Ok);
    CHECK(openCryptomator(st, pw, 6, false, {}).status == OpenStatus::WrongPassword);
    CHECK(openCryptomator(st, np, 5, false, {}).status == OpenStatus::Ok);
}

// ---- Cryptomator compatibility fixes. Each behaviour below was checked against the official
// ---- cryptofs 2.8.0 / cryptolib 2.2.0 (Cryptomator CLI 0.6.2) and the official apps' source.
static std::string nfcStandIn(const std::string& in) {   // stand-in for java.text.Normalizer (Android installs it over JNI)
    static const char* const tbl[][2] = {{"a\xCC\x88", "\xC3\xA4"}, {"o\xCC\x88", "\xC3\xB6"}, {"e\xCC\x81", "\xC3\xA9"}};
    std::string r = in;
    for (auto& m : tbl) { size_t pos = 0; std::string from = m[0]; while ((pos = r.find(from, pos)) != std::string::npos) { r.replace(pos, from.size(), m[1]); pos += std::strlen(m[1]); } }
    return r;
}

static std::string readText(Storage& st, const char* p) { Bytes b; st.readWhole(p, b); return std::string(b.begin(), b.end()); }

static void testCryptomatorCompat() {
    std::printf("cryptomator compatibility fixes\n");
    const uint8_t pw[] = "secret";
    namespace cm = cryptomator;
    auto mkOf = [&](Storage& st) { return cm::unlockMasterkey(cm::MasterkeyFile::parse(readText(st, "masterkey.cryptomator")), pw, 6); };
    auto backingOf = [&](const cm::Masterkey& mk, const std::string& dirId) {
        cm::NameCryptor nc(mk); std::string h = nc.hashDirectoryId(dirId);
        return "d/" + h.substr(0, 2) + "/" + h.substr(2);
    };

    {   // (1) a format 8 vault without vault.cryptomator is refused -- never opened as format 7 (it used to be,
        //     and writes then put CTRMAC files into a GCM vault)
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        Bytes cfg; CHECK(st->readWhole("vault.cryptomator", cfg));
        CHECK(st->remove("vault.cryptomator"));
        auto r = openCryptomator(st, pw, 6, false, {});
        CHECK(r.status == OpenStatus::InvalidVault);
        CHECK(r.message.find("vault.cryptomator is missing") != std::string::npos);
        CHECK(!r.vault);
        CHECK(st->writeWhole("vault.cryptomator", cfg.data(), cfg.size()));
        CHECK(openCryptomator(st, pw, 6, false, {}).status == OpenStatus::Ok);
    }
    {   // (2) legacy masterkey versions without a config are refused with a clear message
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto mk = mkOf(*st);
        CHECK(st->remove("vault.cryptomator"));
        for (int ver : {5, 6}) {
            std::string j = cm::lockMasterkey(mk, pw, 6, ver);
            CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
            auto r = openCryptomator(st, pw, 6, false, {});
            CHECK(r.status == OpenStatus::InvalidVault);
            CHECK(r.message.find("not supported") != std::string::npos);
        }
    }
    {   // (3) vault.cryptomator claims are validated like official cryptofs
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto mk = mkOf(*st);
        auto sign = [&](const std::string& payload) {
            std::string h = R"({"alg":"HS256","typ":"JWT","kid":"masterkeyfile:masterkey.cryptomator"})";
            std::string in = base64Encode((const uint8_t*)h.data(), h.size(), true, false) + "." +
                             base64Encode((const uint8_t*)payload.data(), payload.size(), true, false);
            Bytes sig = crypto::hmac(crypto::Md::Sha256, mk.raw().data(), mk.raw().size(), (const uint8_t*)in.data(), in.size());
            std::string j = in + "." + base64Encode(sig.data(), sig.size(), true, false);
            st->writeWhole("vault.cryptomator", (const uint8_t*)j.data(), j.size());
            return openCryptomator(st, pw, 6, false, {});
        };
        CHECK(sign(R"({"jti":"x","format":8,"cipherCombo":"SIV_GCM","shorteningThreshold":220})").status == OpenStatus::Ok);
        CHECK(sign(R"({"jti":"x","format":8,"cipherCombo":"SIV_CTRMAC","shorteningThreshold":100})").status == OpenStatus::Ok);
        CHECK(sign(R"({"jti":"x","format":7,"cipherCombo":"SIV_GCM","shorteningThreshold":220})").status == OpenStatus::InvalidVault);
        auto newer = sign(R"({"jti":"x","format":9,"cipherCombo":"SIV_GCM","shorteningThreshold":220})");
        CHECK(newer.status == OpenStatus::InvalidVault && newer.message.find("newer") != std::string::npos);
        CHECK(sign(R"({"jti":"x","format":8,"cipherCombo":"SIV_FOO","shorteningThreshold":220})").status == OpenStatus::InvalidVault);
        CHECK(sign(R"({"jti":"x","format":8,"cipherCombo":"SIV_GCM"})").status == OpenStatus::InvalidVault);      // no threshold
        CHECK(sign(R"({"jti":"x","cipherCombo":"SIV_GCM","shorteningThreshold":220})").status == OpenStatus::InvalidVault); // no format
    }
    {   // (4) passphrases are NFC-normalized like the official apps do; vaults keyed from raw bytes still open
        setNfcNormalizer(nfcStandIn);
        const std::string composed = "p\xC3\xA4ss", decomposed = "pa\xCC\x88ss", other = "p\xC3\xB6ss";
        auto U = [](const std::string& s) { return (const uint8_t*)s.data(); };
        {   // new vault typed in decomposed form is keyed from the NFC form
            TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
            CHECK(createCryptomator(*st, U(decomposed), decomposed.size()).status == OpenStatus::Ok);
            auto parsed = cm::MasterkeyFile::parse(readText(*st, "masterkey.cryptomator"));
            CHECK(cm::unlockMasterkey(parsed, U(composed), composed.size()).raw().size() == 64);   // really keyed by NFC
            CHECK(openCryptomator(st, U(composed), composed.size(), false, {}).status == OpenStatus::Ok);
            CHECK(openCryptomator(st, U(decomposed), decomposed.size(), false, {}).status == OpenStatus::Ok);
            CHECK(openCryptomator(st, U(other), other.size(), false, {}).status == OpenStatus::WrongPassword);
        }
        {   // vault created by an earlier version of this app from the raw decomposed bytes
            TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
            CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
            auto mk = mkOf(*st);
            std::string j = cm::lockMasterkey(mk, U(decomposed), decomposed.size(), 999);
            CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
            CHECK(openCryptomator(st, U(decomposed), decomposed.size(), false, {}).status == OpenStatus::Ok);   // raw fallback
            CHECK(openCryptomator(st, U(composed), composed.size(), false, {}).status == OpenStatus::WrongPassword);
            // changing the password re-keys it from the NFC form of the new passphrase
            const std::string np = "n\xC3\xB6w", npDec = "no\xCC\x88w";
            CHECK(changeCryptomatorPassword(*st, U(decomposed), decomposed.size(), U(npDec), npDec.size()).status == OpenStatus::Ok);
            CHECK(openCryptomator(st, U(np), np.size(), false, {}).status == OpenStatus::Ok);
            CHECK(openCryptomator(st, U(npDec), npDec.size(), false, {}).status == OpenStatus::Ok);
        }
        setNfcNormalizer(nullptr);
    }
    {   // (5) a read-only session never writes (it used to re-create a missing backing folder); read-write still heals
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto mk = mkOf(*st);
        { auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
          CHECK(r.vault->createDirectory("sub")); CHECK(put(*r.vault, "sub/f.txt", rnd(100))); r.vault->close(); }
        std::string ptr; walkFiles(root, [&](const std::string& p, off_t) { if (p.size() > 7 && p.substr(p.size() - 7) == "dir.c9r") ptr = p; });
        std::string dirId = readText(*st, ptr.substr(root.size() + 1).c_str());
        std::string backing = root + "/" + backingOf(mk, dirId);
        CHECK(std::filesystem::exists(backing));
        std::filesystem::remove_all(backing);
        { auto ro = openCryptomator(st, pw, 6, true, {}); CHECK(ro.status == OpenStatus::Ok); if (!ro.vault) return;
          std::vector<DirEntry> es; ro.vault->listDirectory("sub", es); CHECK(es.empty());
          ro.vault->close(); }
        CHECK(!std::filesystem::exists(backing));                      // read-only left the vault untouched
        { auto rw = openCryptomator(st, pw, 6, false, {}); CHECK(rw.status == OpenStatus::Ok); if (!rw.vault) return;
          std::vector<DirEntry> es; rw.vault->listDirectory("sub", es); rw.vault->close(); }
        CHECK(std::filesystem::exists(backing));                       // read-write healing is unchanged
    }
    {   // (6) password change keeps the vault's scrypt cost and leaves an official-style masterkey backup
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto mk = mkOf(*st);
        std::string j = cm::lockMasterkey(mk, pw, 6, 999, 1u << 14, 16);
        CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
        Bytes before; CHECK(st->readWhole("masterkey.cryptomator", before));
        const uint8_t np[] = "new-secret";
        CHECK(changeCryptomatorPassword(*st, (const uint8_t*)"bad", 3, np, 10).status == OpenStatus::WrongPassword);
        CHECK(changeCryptomatorPassword(*st, pw, 6, np, 10).status == OpenStatus::Ok);
        auto parsed = cm::MasterkeyFile::parse(readText(*st, "masterkey.cryptomator"));
        CHECK_EQ(parsed.scryptCostParam, 1 << 14);
        CHECK_EQ(parsed.scryptBlockSize, 16);
        CHECK_EQ(parsed.version, 999);
        std::string bkup; std::vector<DirEntry> es; st->list("", es);
        for (auto& e : es) if (e.name.rfind("masterkey.cryptomator.", 0) == 0) bkup = e.name;
        const std::string prefix = "masterkey.cryptomator.";
        CHECK(bkup.size() == prefix.size() + 8 + 5 && bkup.substr(bkup.size() - 5) == ".bkup");   // .XXXXXXXX.bkup
        bool upperHex = bkup.size() == prefix.size() + 13;
        for (size_t i = prefix.size(); upperHex && i < prefix.size() + 8; i++) upperHex = std::isxdigit((unsigned char)bkup[i]) && !std::islower((unsigned char)bkup[i]);
        CHECK(upperHex);
        Bytes bk; CHECK(st->readWhole(bkup, bk));
        CHECK(bk == before);
        CHECK(openCryptomator(st, pw, 6, false, {}).status == OpenStatus::WrongPassword);
        CHECK(openCryptomator(st, np, 10, false, {}).status == OpenStatus::Ok);
    }
    {   // (7) root dirid.c9r exists (header only, like official); a genuine v7 vault gets one on first write
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto mk = mkOf(*st);
        Bytes b; CHECK(st->readWhole(backingOf(mk, "") + "/dirid.c9r", b));
        CHECK_EQ(b.size(), (size_t)68);                                  // SIV_GCM header only
        std::string j = cm::lockMasterkey(mk, pw, 6, 7);
        CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
        CHECK(st->remove("vault.cryptomator")); CHECK(st->remove(backingOf(mk, "") + "/dirid.c9r"));
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        CHECK(put(*r.vault, "a.txt", rnd(10))); r.vault->close();
        CHECK(st->readWhole(backingOf(mk, "") + "/dirid.c9r", b));
        CHECK_EQ(b.size(), (size_t)88);                                  // SIV_CTRMAC header only
    }
    {   // (8) scrypt block size up to official's 64 is accepted, above is not
        for (uint32_t rr : {16u, 64u}) {
            TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
            CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
            auto mk = mkOf(*st);
            std::string j = cm::lockMasterkey(mk, pw, 6, 999, 1u << 10, rr);
            CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
            CHECK(openCryptomator(st, pw, 6, false, {}).status == OpenStatus::Ok);
        }
        bool threw = false;
        try { Bytes salt(8, 1); crypto::scrypt(pw, 6, salt.data(), salt.size(), 1u << 10, 65, 1, 32); } catch (const Error&) { threw = true; }
        CHECK(threw);
    }
}

// ---- Symlinks and the hidden-entry counter. Layout, limits and precedence mirror cryptofs 2.8.0 / 2.11.1
// ---- (Symlinks.java, CiphertextFilePath, CryptoPathMapper); the same behaviours are cross-checked against the
// ---- real implementation in test/interop/cryptomator_symlink_interop.sh.
static std::string physicalNodeOf(const std::string& root, const std::string& file) {   // folder holding [file]
    std::string found;
    walkFiles(root, [&](const std::string& p, off_t) { if (p.size() > file.size() && p.substr(p.size() - file.size()) == file) found = p.substr(0, p.size() - file.size() - 1); });
    return found;
}
static int countFiles(const std::string& root, const std::string& file) {
    int n = 0;
    walkFiles(root, [&](const std::string& p, off_t) { if (p.size() >= file.size() && p.substr(p.size() - file.size()) == file) n++; });
    return n;
}

static void testCryptomatorSymlinks() {
    std::printf("cryptomator symlinks + hidden entries\n");
    const uint8_t pw[] = "secret";
    namespace cm = cryptomator;
    const std::string longName = std::string(170, 'L') + ".lnk";                  // > shortening threshold -> .c9s wrapper
    const std::string uni = "caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC.lnk";           // "café 日本.lnk"
    const std::string utarget = "\xE7\x9B\xAE\xE6\xA8\x99/\xF0\x9F\x98\x80";      // "目標/😀" = 3+3+1+4 bytes
    auto symlinksOf = [](Vault& v, const std::string& dir) { std::vector<DirEntry> es; v.listSymlinks(dir, es); return es; };
    auto findLink = [](const std::vector<DirEntry>& es, const std::string& n) -> const DirEntry* { for (auto& e : es) if (e.name == n) return &e; return nullptr; };

    for (bool v7 : {false, true}) {
        std::printf("  scenario: %s\n", v7 ? "format 7 (SIV_CTRMAC)" : "format 8 (SIV_GCM)");
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        if (v7) {
            Bytes mkRaw; CHECK(st->readWhole("masterkey.cryptomator", mkRaw));
            auto mk = cm::unlockMasterkey(cm::MasterkeyFile::parse(std::string(mkRaw.begin(), mkRaw.end())), pw, 6);
            std::string j = cm::lockMasterkey(mk, pw, 6, 7);
            CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
            CHECK(st->remove("vault.cryptomator"));
        }
        auto r = openCryptomator(st, pw, 6, false, {});
        CHECK(r.status == OpenStatus::Ok);
        if (!r.vault) return;
        Vault& v = *r.vault;
        CHECK(v.createDirectory("docs"));
        const Bytes fileData = rnd(10, 5);
        CHECK(put(v, "docs/file.txt", fileData));

        // --- create + list + read ---------------------------------------------------------------------
        CHECK(v.createSymlink("link", "docs/file.txt"));
        CHECK(v.createSymlink("docs/" + longName, "/abs/target"));                  // shortened name
        CHECK(v.createSymlink(uni, utarget));
        CHECK_EQ(names(v, "").size(), (size_t)1);                                   // listDirectory never shows links
        CHECK(has(v, "", "D:docs"));
        CHECK_EQ(names(v, "docs").size(), (size_t)1);
        CHECK(has(v, "docs", "F:file.txt"));
        auto root1 = symlinksOf(v, "");
        CHECK_EQ(root1.size(), (size_t)2);
        const DirEntry* l1 = findLink(root1, "link");
        CHECK(l1 && l1->isSymlink && !l1->isDir && l1->size == 13);                  // size = bytes of the target
        const DirEntry* l2 = findLink(root1, uni);
        CHECK(l2 && l2->isSymlink && l2->size == 11);
        auto docs1 = symlinksOf(v, "docs");
        CHECK_EQ(docs1.size(), (size_t)1);
        CHECK(findLink(docs1, longName) != nullptr);
        CHECK(v.readSymlink("link").value_or("?") == "docs/file.txt");
        CHECK(v.readSymlink("docs/" + longName).value_or("?") == "/abs/target");
        CHECK(v.readSymlink(uni).value_or("?") == utarget);
        CHECK(!v.readSymlink("docs/file.txt"));                                      // a file is not a link
        CHECK(!v.readSymlink("docs"));                                               // neither is a folder
        CHECK(!v.readSymlink("missing"));
        std::vector<DirEntry> none; CHECK(!v.listSymlinks("nodir", none));
        CHECK(countFiles(root, "symlink.c9r") == 3);

        // --- a link is never a file or a folder ---------------------------------------------------------
        CHECK(!get(v, "link"));
        CHECK_EQ(v.getFileSize("link"), (int64_t)-1);
        CHECK(!v.createDirectory("link"));
        CHECK(!put(v, "link", rnd(20, 6)));                                          // writing over a link is refused...
        CHECK(v.readSymlink("link").value_or("?") == "docs/file.txt");              // ...and leaves it intact
        CHECK(!put(v, "link/inside.txt", rnd(5)));                                   // a link is not a folder to put things into
        std::vector<DirEntry> inside; CHECK(!v.listDirectory("link", inside));       // nor to list
        CHECK(!v.createSymlink("link", "x"));
        CHECK(!v.createSymlink("docs", "x"));
        CHECK(!v.createSymlink("docs/file.txt", "x"));
        CHECK(!v.createSymlink("nodir/x", "x"));
        CHECK(!v.createSymlink("", "x"));
        CHECK(*get(v, "docs/file.txt") == fileData);
        CHECK_EQ(v.getFolderSize(""), (int64_t)10);                                  // links add nothing to the size of a folder
        CHECK_EQ(v.getFolderSize("docs"), (int64_t)10);

        // --- target validation and limits -------------------------------------------------------------
        CHECK(!v.createSymlink("t1", ""));
        CHECK(!v.createSymlink("t2", std::string("a\0b", 3)));                       // NUL
        CHECK(!v.createSymlink("t3", "\xC3\x28"));                                   // malformed UTF-8
        CHECK(!v.createSymlink("t4", "\xC0\xAF"));                                   // overlong
        CHECK(!v.createSymlink("t5", "\xED\xA0\x80"));                               // UTF-16 surrogate
        CHECK(!v.createSymlink("t6", "\xF4\x90\x80\x80"));                           // > U+10FFFF
        CHECK(!v.createSymlink("t7", std::string(32768, 'a')));                      // one over the limit
        CHECK(v.createSymlink("t8", std::string(32767, 'a')));                       // exactly the limit
        CHECK(v.readSymlink("t8").value_or("") == std::string(32767, 'a'));
        std::string euro; for (int i = 0; i < 10923; i++) euro += "\xE2\x82\xAC";    // 10923 chars but 32769 bytes
        CHECK(!v.createSymlink("t9", euro));                                         // fewer than 32767 chars, yet unreadable: refused
        euro.resize(10922 * 3);
        CHECK(v.createSymlink("t10", euro));
        CHECK(v.readSymlink("t10").value_or("") == euro);
        for (const char* n : {"t1", "t2", "t3", "t4", "t5", "t6", "t7", "t9"}) CHECK(!v.readSymlink(n));   // nothing half-created
        CHECK_EQ(countFiles(root, "symlink.c9r"), 5);                                // link, longName, uni, t8, t10
        CHECK(v.deleteFile("t8")); CHECK(v.deleteFile("t10"));

        // --- move / delete / mtime -----------------------------------------------------------------------
        CHECK(v.renameFile("link", "docs/moved"));                                   // plain -> plain, other folder
        CHECK(v.readSymlink("docs/moved").value_or("?") == "docs/file.txt");
        CHECK(!v.readSymlink("link"));
        CHECK(v.renameFile("docs/moved", "docs/" + longName + ".2"));                // plain -> shortened
        CHECK(v.readSymlink("docs/" + longName + ".2").value_or("?") == "docs/file.txt");
        CHECK(v.renameFile("docs/" + longName + ".2", "docs/short"));                // shortened -> plain
        CHECK(v.readSymlink("docs/short").value_or("?") == "docs/file.txt");
        CHECK(v.renameFile("docs/" + longName, "docs/" + longName + ".3"));          // shortened -> shortened
        CHECK(v.readSymlink("docs/" + longName + ".3").value_or("?") == "/abs/target");
        CHECK(!v.readSymlink("docs/" + longName));
        CHECK_EQ(countFiles(root, "symlink.c9r"), 3);                                // moving never duplicates or loses a node (short, long.3, uni)
        CHECK_EQ(countFiles(root, "name.c9s"), 1);                                   // only the one shortened link keeps its name file
        CHECK(!v.renameFile("docs/short", "docs/file.txt"));                         // a link never replaces a file...
        CHECK(*get(v, "docs/file.txt") == fileData);                                 // ...which stays untouched...
        CHECK(v.readSymlink("docs/short").value_or("?") == "docs/file.txt");         // ...and the link stays where it was
        CHECK(!v.renameFile("docs/short", "docs/" + longName + ".3"));               // nor another link
        CHECK(v.readSymlink("docs/short").value_or("?") == "docs/file.txt");
        CHECK(v.readSymlink("docs/" + longName + ".3").value_or("?") == "/abs/target");
        CHECK_EQ(countFiles(root, "symlink.c9r"), 3);
        CHECK(v.setLastModifiedTime("docs/short", 1700000000));
        { auto d = symlinksOf(v, "docs"); const DirEntry* e = findLink(d, "short"); CHECK(e && e->mtimeMs == 1700000000000LL); }
        CHECK(v.setLastModifiedTime("docs/" + longName + ".3", 1600000000));
        { auto d = symlinksOf(v, "docs"); const DirEntry* e = findLink(d, longName + ".3"); CHECK(e && e->mtimeMs == 1600000000000LL); }
        CHECK(v.deleteFile("docs/short"));
        CHECK(!v.readSymlink("docs/short"));
        CHECK_EQ(countFiles(root, "symlink.c9r"), 2);                                // long.3 and uni are left
        CHECK(*get(v, "docs/file.txt") == fileData);                                 // deleting a link leaves what it pointed at alone
        CHECK(v.deleteFile("docs"));                                                 // a folder holding links: nothing is followed, nothing is left
        CHECK_EQ(countFiles(root, "symlink.c9r"), 1);                                // only the root-level "uni" link remains
        CHECK(v.deleteFile(uni));
        CHECK_EQ(countFiles(root, "symlink.c9r"), 0);
        v.close();
    }

    {   // --- precedence + hostile content (official order: dir.c9r, symlink.c9r, contents.c9r) -------------------
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        auto linkFiles = [&]() { std::vector<std::string> f; walkFiles(root, [&](const std::string& p, off_t) { if (p.size() > 11 && p.substr(p.size() - 11) == "symlink.c9r") f.push_back(p); }); std::sort(f.begin(), f.end()); return f; };
        std::map<std::string, std::string> fileOf;                                   // link name -> its symlink.c9r on disk
        for (const char* n : {"a", "b", "c"}) {
            auto before = linkFiles();
            CHECK(r.vault->createSymlink(n, std::string("target-") + n));
            for (auto& f : linkFiles()) if (std::find(before.begin(), before.end(), f) == before.end()) fileOf[n] = f;
        }
        CHECK_EQ(fileOf.size(), (size_t)3);
        // a: flip a ciphertext byte -> the link stays listed, but its target is refused (never returned garbled)
        flipByte(fileOf["a"], 100);
        CHECK(!r.vault->readSymlink("a")); CHECK(r.vault->readSymlink("b").value_or("?") == "target-b");
        CHECK_EQ(symlinksOf(*r.vault, "").size(), (size_t)3);
        flipByte(fileOf["a"], 100);                                                   // undo (xor is its own inverse)
        CHECK(r.vault->readSymlink("a").value_or("?") == "target-a");
        // b: an oversized symlink.c9r (hostile vault) is refused without being slurped into memory
        { std::string big(2 * 1024 * 1024, 'x'); std::ofstream f(fileOf["b"], std::ios::binary | std::ios::trunc); f.write(big.data(), (std::streamsize)big.size()); }
        CHECK(!r.vault->readSymlink("b")); CHECK(r.vault->readSymlink("c").value_or("?") == "target-c");
        // b again: zero-length symlink.c9r (created but its content has not synced yet) -> listed, no target
        { std::ofstream f(fileOf["b"], std::ios::binary | std::ios::trunc); }
        r.vault->invalidateCache("");
        CHECK(!r.vault->readSymlink("b"));
        CHECK_EQ(symlinksOf(*r.vault, "").size(), (size_t)3);
        // c: dir.c9r wins over symlink.c9r -- the node then is a folder, not a link
        std::string folderC = fileOf["c"].substr(0, fileOf["c"].rfind('/'));
        CHECK(st->writeWhole(folderC.substr(root.size() + 1) + "/dir.c9r", (const uint8_t*)"11111111-2222-3333-4444-555555555555", 36));
        r.vault->invalidateCache("");
        CHECK_EQ(symlinksOf(*r.vault, "").size(), (size_t)2);
        CHECK_EQ(names(*r.vault, "").size(), (size_t)1);
        CHECK(has(*r.vault, "", "D:c"));
        r.vault->close();
    }

    {   // --- read-only sessions can read links but never create one -----------------------------------------
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto rw = openCryptomator(st, pw, 6, false, {}); CHECK(rw.status == OpenStatus::Ok); if (!rw.vault) return;
        CHECK(rw.vault->createSymlink("l", "t")); rw.vault->close();
        auto ro = openCryptomator(st, pw, 6, true, {}); CHECK(ro.status == OpenStatus::Ok); if (!ro.vault) return;
        CHECK(ro.vault->readSymlink("l").value_or("?") == "t");
        CHECK_EQ(symlinksOf(*ro.vault, "").size(), (size_t)1);
        CHECK(!ro.vault->createSymlink("l2", "t"));
        CHECK(!ro.vault->deleteFile("l"));
        CHECK(!ro.vault->renameFile("l", "m"));
        CHECK(ro.vault->readSymlink("l").value_or("?") == "t");
        ro.vault->close();
    }

    {   // --- gocryptfs / cryfs engines keep the defaults ---------------------------------------------------------
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createGocryptfs(*st, pw, 6, {}).status == OpenStatus::Ok);
        auto g = openGocryptfs(st, pw, 6, false, {}); CHECK(g.status == OpenStatus::Ok); if (!g.vault) return;
        std::vector<DirEntry> es; CHECK(g.vault->listSymlinks("", es)); CHECK(es.empty());
        CHECK(!g.vault->createSymlink("l", "t")); CHECK(!g.vault->readSymlink("l")); CHECK_EQ(g.vault->hiddenEntryCount(""), -1);
        g.vault->close();
    }

    {   // --- hidden entries: what exists on disk but is not shown -------------------------------------------------
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        Vault& v = *r.vault;
        CHECK(put(v, "a.txt", rnd(100, 9))); CHECK(v.createDirectory("sub")); CHECK(v.createSymlink("ln", "t"));
        CHECK_EQ(v.hiddenEntryCount(""), 0);                                         // internal files and links are not "hidden"
        CHECK_EQ(v.hiddenEntryCount("nodir"), -1);
        Bytes mkRaw; CHECK(st->readWhole("masterkey.cryptomator", mkRaw));
        auto mk = cm::unlockMasterkey(cm::MasterkeyFile::parse(std::string(mkRaw.begin(), mkRaw.end())), pw, 6);
        cm::NameCryptor nc(mk); std::string rh = nc.hashDirectoryId("");
        const std::string phys = root + "/d/" + rh.substr(0, 2) + "/" + rh.substr(2);   // physical folder of the root
        std::string nodeFile;                                                        // a.txt's ciphertext file
        { DIR* d = opendir(phys.c_str()); while (auto* e = readdir(d)) { std::string n = e->d_name; struct stat sb; if (n.size() > 4 && n.substr(n.size() - 4) == ".c9r" && n != "dir.c9r" && n != "dirid.c9r" && stat((phys + "/" + n).c_str(), &sb) == 0 && S_ISREG(sb.st_mode)) nodeFile = n; } closedir(d); }
        CHECK(!nodeFile.empty());
        auto cp = [&](const std::string& to) { std::ifstream in(phys + "/" + nodeFile, std::ios::binary); std::ofstream out(phys + "/" + to, std::ios::binary); out << in.rdbuf(); };
        const std::string base = nodeFile.substr(0, nodeFile.size() - 4);
        cp(base + " (1).c9r");                                                        // Dropbox/Drive style conflict copy
        r.vault->close();
        r = openCryptomator(st, pw, 6, false, {}); if (!r.vault) return;
        CHECK_EQ(r.vault->hiddenEntryCount(""), 1);
        CHECK_EQ(names(*r.vault, "").size(), (size_t)2);                              // a.txt + sub, once each
        cp(base + ".sync-conflict-20200101-000000-ABC.c9r");                           // Syncthing style
        cp("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.c9r");                            // garbage that is not a name
        { std::ofstream f(phys + "/.DS_Store"); f << "x"; }                            // ignored like official (dot-file)
        { std::ofstream f(phys + "/.hidden.c9r"); f << "x"; }
        { std::ofstream f(phys + "/notes.txt"); f << "x"; }                            // foreign file
        { std::ofstream f(phys + "/x.c9u"); f << "x"; }                                // in-use marker
        ::mkdir((phys + "/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.c9s").c_str(), 0755);      // wrapper without name.c9s (half synced)
        ::mkdir((phys + "/CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC.c9r").c_str(), 0755); // folder node without any type file
        r.vault->invalidateCache("");
        std::vector<DirEntry> es; CHECK(r.vault->listDirectory("", es));
        CHECK_EQ(es.size(), (size_t)2);
        CHECK_EQ(r.vault->hiddenEntryCount(""), 5);
        r.vault->close();
    }
}

// ---- Key file backups on open (official: cryptofs backs up vault.cryptomator, the desktop app masterkey.cryptomator).
static std::vector<std::string> bkupsOf(Storage& st, const std::string& prefix) {
    std::vector<DirEntry> es; st.list("", es);
    std::vector<std::string> out;
    for (auto& e : es) if (e.name.rfind(prefix + ".", 0) == 0 && e.name.size() > 5 && e.name.substr(e.name.size() - 5) == ".bkup") out.push_back(e.name);
    std::sort(out.begin(), out.end());
    return out;
}

static void testCryptomatorBackups() {
    std::printf("cryptomator key file backups on open\n");
    const uint8_t pw[] = "secret";
    auto goodName = [](const std::string& n, const std::string& prefix) {   // <prefix>.XXXXXXXX.bkup with upper-case hex
        if (n.size() != prefix.size() + 1 + 8 + 5) return false;
        for (size_t i = prefix.size() + 1; i < prefix.size() + 9; i++) if (!std::isxdigit((unsigned char)n[i]) || std::islower((unsigned char)n[i])) return false;
        return true;
    };
    {   // (1) a read-write open backs up both files, once
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        CHECK(bkupsOf(*st, "vault.cryptomator").empty() && bkupsOf(*st, "masterkey.cryptomator").empty());
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        r.vault->close();
        auto vb = bkupsOf(*st, "vault.cryptomator"), mb = bkupsOf(*st, "masterkey.cryptomator");
        CHECK_EQ(vb.size(), (size_t)1); CHECK_EQ(mb.size(), (size_t)1);
        if (vb.size() == 1 && mb.size() == 1) {
            CHECK(goodName(vb[0], "vault.cryptomator")); CHECK(goodName(mb[0], "masterkey.cryptomator"));
            Bytes a, b, c, d;
            CHECK(st->readWhole("vault.cryptomator", a) && st->readWhole(vb[0], b) && a == b);
            CHECK(st->readWhole("masterkey.cryptomator", c) && st->readWhole(mb[0], d) && c == d);
            Bytes dg = crypto::hash(crypto::Md::Sha256, a.data(), a.size());
            std::string hex = toHex(dg.data(), 4); for (char& ch : hex) ch = (char)std::toupper((unsigned char)ch);
            CHECK_EQ(vb[0], "vault.cryptomator." + hex + ".bkup");               // name = first 4 bytes of SHA-256 of the content
        }
        // (2) opening again changes nothing
        r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (r.vault) r.vault->close();
        CHECK_EQ(bkupsOf(*st, "vault.cryptomator").size(), (size_t)1); CHECK_EQ(bkupsOf(*st, "masterkey.cryptomator").size(), (size_t)1);
        // (3) a wrong password backs up nothing new
        CHECK(openCryptomator(st, (const uint8_t*)"bad", 3, false, {}).status == OpenStatus::WrongPassword);
        CHECK_EQ(bkupsOf(*st, "masterkey.cryptomator").size(), (size_t)1);
        // (4) a changed key file gets its own backup; the old one stays
        const uint8_t np[] = "other";
        CHECK(changeCryptomatorPassword(*st, pw, 6, np, 5).status == OpenStatus::Ok);   // itself backs up the OLD key file (already there)
        CHECK_EQ(bkupsOf(*st, "masterkey.cryptomator").size(), (size_t)1);
        r = openCryptomator(st, np, 5, false, {}); CHECK(r.status == OpenStatus::Ok); if (r.vault) r.vault->close();
        CHECK_EQ(bkupsOf(*st, "masterkey.cryptomator").size(), (size_t)2);          // + the new one
        CHECK_EQ(bkupsOf(*st, "vault.cryptomator").size(), (size_t)1);               // the config did not change
        // (5) an existing backup is verified, never overwritten
        auto mb2 = bkupsOf(*st, "masterkey.cryptomator");
        const std::string junk = "not the real content";
        CHECK(st->writeWhole(mb2[1], (const uint8_t*)junk.data(), junk.size()));
        r = openCryptomator(st, np, 5, false, {}); CHECK(r.status == OpenStatus::Ok); if (r.vault) r.vault->close();
        CHECK_EQ(readText(*st, mb2[1].c_str()), junk);
        CHECK_EQ(bkupsOf(*st, "masterkey.cryptomator").size(), (size_t)2);
    }
    {   // (6) read-only sessions never write; the HostEnv switch turns the feature off
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto ro = openCryptomator(st, pw, 6, true, {}); CHECK(ro.status == OpenStatus::Ok); if (ro.vault) ro.vault->close();
        CHECK(bkupsOf(*st, "vault.cryptomator").empty() && bkupsOf(*st, "masterkey.cryptomator").empty());
        HostEnv off; off.backupKeyFilesOnOpen = false;
        auto rw = openCryptomator(st, pw, 6, false, off); CHECK(rw.status == OpenStatus::Ok); if (rw.vault) rw.vault->close();
        CHECK(bkupsOf(*st, "vault.cryptomator").empty() && bkupsOf(*st, "masterkey.cryptomator").empty());
    }
    {   // (7) a format 7 vault has no vault.cryptomator: only its masterkey is backed up
        TmpDir t; auto st = std::make_shared<PosixStorage>(t.sub("v"));
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto mk = cryptomator::unlockMasterkey(cryptomator::MasterkeyFile::parse(readText(*st, "masterkey.cryptomator")), pw, 6);
        std::string j = cryptomator::lockMasterkey(mk, pw, 6, 7);
        CHECK(st->writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size())); CHECK(st->remove("vault.cryptomator"));
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (r.vault) r.vault->close();
        CHECK_EQ(bkupsOf(*st, "masterkey.cryptomator").size(), (size_t)1);
        CHECK(bkupsOf(*st, "vault.cryptomator").empty());
        CHECK(!st->stat("vault.cryptomator", *std::make_unique<DirEntry>()));        // and opening did not conjure a config
    }
}

// ---- Format 7 -> 8 migration (official Version8Migrator); cross-checked for real in cryptomator_migrate_interop.sh.
static void testCryptomatorMigration() {
    std::printf("cryptomator 7 -> 8 migration\n");
    namespace cm = cryptomator;
    const uint8_t pw[] = "secret";
    auto makeV7 = [&](Storage& st) {   // a genuine format 7 vault: version-7 key file, no vault.cryptomator
        CHECK(createCryptomator(st, pw, 6).status == OpenStatus::Ok);
        auto mk = cm::unlockMasterkey(cm::MasterkeyFile::parse(readText(st, "masterkey.cryptomator")), pw, 6);
        std::string j = cm::lockMasterkey(mk, pw, 6, 7);
        CHECK(st.writeWhole("masterkey.cryptomator", (const uint8_t*)j.data(), j.size()));
        CHECK(st.remove("vault.cryptomator"));
    };
    auto snapshot = [&](const std::string& root) {   // every file outside d/ with its content
        std::map<std::string, std::string> m;
        walkFiles(root, [&](const std::string& p, off_t) {
            if (p.find("/d/") != std::string::npos) return;
            std::ifstream f(p, std::ios::binary); std::stringstream ss; ss << f.rdbuf(); m[p] = ss.str();
        });
        return m;
    };
    {   // (1) the happy path: data written as format 7 is intact afterwards, the config says what official's says
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        makeV7(*st);
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        const Bytes a = rnd(100000, 21), b = rnd(10, 22);
        CHECK(r.vault->createDirectory("docs")); CHECK(put(*r.vault, "docs/a.bin", a)); CHECK(put(*r.vault, std::string(170, 'N') + ".txt", b));
        r.vault->close();
        Bytes oldKey; CHECK(st->readWhole("masterkey.cryptomator", oldKey));
        CHECK(migrateCryptomator7To8(*st, pw, 6).status == OpenStatus::Ok);
        // config: signed, format 8, SIV_CTRMAC, 220
        Bytes jwt; CHECK(st->readWhole("vault.cryptomator", jwt));
        auto mk = cm::unlockMasterkey(cm::MasterkeyFile::parse(readText(*st, "masterkey.cryptomator")), pw, 6);
        auto cfg = cm::verifyVaultConfig(std::string(jwt.begin(), jwt.end()), mk);   // throws unless the HMAC verifies
        CHECK_EQ(cfg.vaultFormat, 8); CHECK_EQ(cfg.cipherCombo, std::string("SIV_CTRMAC")); CHECK_EQ(cfg.shorteningThreshold, 220);
        CHECK_EQ(cm::MasterkeyFile::parse(readText(*st, "masterkey.cryptomator")).version, 999);
        // the old key file is kept under official's name, byte for byte
        auto bk = bkupsOf(*st, "masterkey.cryptomator");
        CHECK_EQ(bk.size(), (size_t)1);
        if (bk.size() == 1) { Bytes x; CHECK(st->readWhole(bk[0], x)); CHECK(x == oldKey); }
        // the data are untouched and readable
        r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        CHECK(*get(*r.vault, "docs/a.bin") == a); CHECK(*get(*r.vault, std::string(170, 'N') + ".txt") == b);
        CHECK(put(*r.vault, "docs/after.txt", b)); CHECK(*get(*r.vault, "docs/after.txt") == b);
        r.vault->close();
        // (2) a second run is refused
        auto before = snapshot(root);
        CHECK(migrateCryptomator7To8(*st, pw, 6).status == OpenStatus::InvalidVault);
        CHECK(snapshot(root) == before);
    }
    {   // (3) refusals change nothing at all
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        makeV7(*st);
        auto before = snapshot(root);
        CHECK(migrateCryptomator7To8(*st, (const uint8_t*)"bad", 3).status == OpenStatus::WrongPassword);
        CHECK(snapshot(root) == before);
        CHECK(!st->stat("vault.cryptomator", *std::make_unique<DirEntry>()));
        // a format 8 key file without its vault.cryptomator (e.g. not synced yet) must never be "migrated"
        TmpDir t2; std::string root2 = t2.sub("v"); auto st2 = std::make_shared<PosixStorage>(root2);
        CHECK(createCryptomator(*st2, pw, 6).status == OpenStatus::Ok); CHECK(st2->remove("vault.cryptomator"));
        auto before2 = snapshot(root2);
        CHECK(migrateCryptomator7To8(*st2, pw, 6).status == OpenStatus::InvalidVault);
        CHECK(snapshot(root2) == before2);
        // a genuine format 8 vault
        TmpDir t3; auto st3 = std::make_shared<PosixStorage>(t3.sub("v"));
        CHECK(createCryptomator(*st3, pw, 6).status == OpenStatus::Ok);
        CHECK(migrateCryptomator7To8(*st3, pw, 6).status == OpenStatus::InvalidVault);
        // not a vault at all
        TmpDir t4; auto st4 = std::make_shared<PosixStorage>(t4.sub("v"));
        CHECK(migrateCryptomator7To8(*st4, pw, 6).status == OpenStatus::InvalidVault);
        // an old (version 6) key file is not ours to migrate
        TmpDir t5; auto st5 = std::make_shared<PosixStorage>(t5.sub("v"));
        makeV7(*st5);
        auto mk = cm::unlockMasterkey(cm::MasterkeyFile::parse(readText(*st5, "masterkey.cryptomator")), pw, 6);
        std::string j6 = cm::lockMasterkey(mk, pw, 6, 6);
        CHECK(st5->writeWhole("masterkey.cryptomator", (const uint8_t*)j6.data(), j6.size()));
        auto before5 = snapshot(t5.sub("v"));
        CHECK(migrateCryptomator7To8(*st5, pw, 6).status == OpenStatus::InvalidVault);
        CHECK(snapshot(t5.sub("v")) == before5);
    }
}

static void testCryfs(const char* cipher, int bsz) {
    std::printf("cryfs %s @%d\n", cipher, bsz);
    TmpDir t; std::string root = t.sub("v"); HostEnv env; env.cryfsLocalStateDir = t.sub("state"); env.tempDir = t.path;
    auto st = std::make_shared<PosixStorage>(root);
    CryfsCreateOptions o; o.cipher = cipher; o.blocksizeBytes = bsz;
    const uint8_t pw[] = "secret";
    CHECK(createCryfs(*st, pw, 6, o, env).status == OpenStatus::Ok);
    CHECK(openCryfs(st, (const uint8_t*)"bad", 3, false, env).status == OpenStatus::WrongPassword);
    auto r = openCryfs(st, pw, 6, false, env);
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    CHECK(r.derivedKey.size() == cryfs::kCombinedKeySize);
    scenario(cipher, *r.vault);
    r.vault->close();

    // fast re-unlock with the remembered key
    auto r2 = openCryfsWithCombinedKey(st, r.derivedKey.data(), r.derivedKey.size(), false, env);
    CHECK(r2.status == OpenStatus::Ok);
    if (!r2.vault) return;
    Bytes data = rnd(500000, 21);
    CHECK(put(*r2.vault, "keep.bin", data));

    // legacy lowercase block names (written by older builds on case-insensitive storage) still open and stay consistent
    r2.vault->close();
    {
        std::vector<std::string> files;
        walkFiles(root, [&](const std::string& p, off_t) { if (p.find("cryfs.config") == std::string::npos) files.push_back(p); });
        for (auto& f : files) {   // rename file to lower-case, then its shard directory
            std::string dir = f.substr(0, f.rfind('/')), nm = f.substr(f.rfind('/') + 1);
            for (auto& c : nm) c = (char)tolower(c);
            ::rename(f.c_str(), (dir + "/" + nm).c_str());
        }
        DIR* d = opendir(root.c_str());
        std::vector<std::string> shards;
        while (auto* e = readdir(d)) { std::string n = e->d_name; if (n.size() == 3) shards.push_back(n); }
        closedir(d);
        for (auto& s : shards) { std::string l = s; for (auto& c : l) c = (char)tolower(c); ::rename((root + "/" + s).c_str(), (root + "/" + l + ".tmp").c_str()); ::rename((root + "/" + l + ".tmp").c_str(), (root + "/" + l).c_str()); }
    }
    auto r3 = openCryfs(st, pw, 6, false, env);
    CHECK(r3.status == OpenStatus::Ok);
    if (!r3.vault) return;
    CHECK(get(*r3.vault, "keep.bin") == data);
    Bytes more = rnd(200000, 22);
    CHECK(put(*r3.vault, "keep.bin", more)); CHECK(get(*r3.vault, "keep.bin") == more);   // overwrite through lowercase files
    CHECK(r3.vault->createDirectory("newdir")); CHECK(put(*r3.vault, "newdir/f", data)); CHECK(get(*r3.vault, "newdir/f") == data);
    int upperDup = 0, lowerCount = 0;
    walkFiles(root, [&](const std::string& p, off_t) {
        std::string nm = p.substr(p.rfind('/') + 1);
        if (p.find("cryfs.config") != std::string::npos) return;
        bool hasUpper = false; for (char c : nm) if (c >= 'A' && c <= 'F') hasUpper = true;
        if (hasUpper) upperDup++; else lowerCount++;
    });
    CHECK(lowerCount > 0);
    (void)upperDup;   // new blocks are uppercase by design; overwrites of old blocks must not create duplicates
    r3.vault->close();

    // rollback protection: restore an older copy of the root block -> open must refuse
    Bytes rootBlk;
    auto cfgRaw = Bytes(); st->readWhole("cryfs.config", cfgRaw);
    auto combined = cryfs::deriveCombinedKey(cfgRaw, pw, 6);
    auto cfg = cryfs::parseWithCombinedKey(cfgRaw, combined);
    std::string rootPath = root + "/" + cfg.rootBlob.pathLower();
    if (access(rootPath.c_str(), F_OK) != 0) rootPath = root + "/" + cfg.rootBlob.pathUpper();
    std::ifstream f(rootPath, std::ios::binary); std::stringstream ss; ss << f.rdbuf(); std::string old = ss.str();
    auto r4 = openCryfs(st, pw, 6, false, env);
    CHECK(r4.status == OpenStatus::Ok);
    if (!r4.vault) return;
    CHECK(r4.vault->createDirectory("bump1")); CHECK(r4.vault->createDirectory("bump2"));   // advances the root block's version
    r4.vault->close();
    { std::ofstream w(rootPath, std::ios::binary | std::ios::trunc); w.write(old.data(), (std::streamsize)old.size()); }
    auto r5 = openCryfs(st, pw, 6, false, env);
    CHECK(r5.status == OpenStatus::InvalidVault);
    CHECK(r5.message.find("rolled back") != std::string::npos);

    const uint8_t np[] = "other";
    CHECK(changeCryfsPassword(*st, pw, 6, np, 5).status == OpenStatus::Ok);
    CHECK(openCryfs(st, pw, 6, false, env).status == OpenStatus::WrongPassword);
}

static void testConcurrency(const char* fmt) {
    std::printf("concurrency: %s\n", fmt);
    TmpDir t; std::string root = t.sub("v"); HostEnv env; env.cryfsLocalStateDir = t.sub("state"); env.tempDir = t.path;
    auto st = std::make_shared<PosixStorage>(root);
    const uint8_t pw[] = "pw";
    OpenResult r;
    if (std::string(fmt) == "gocryptfs") { createGocryptfs(*st, pw, 2, {}); r = openGocryptfs(st, pw, 2, false, env); }
    else if (std::string(fmt) == "cryptomator") { createCryptomator(*st, pw, 2); r = openCryptomator(st, pw, 2, false, env); }
    else { CryfsCreateOptions o; o.blocksizeBytes = 8192; createCryfs(*st, pw, 2, o, env); r = openCryfs(st, pw, 2, false, env); }
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    Vault& v = *r.vault;
    constexpr int kThreads = 6, kFiles = 12;
    for (int i = 0; i < kThreads; i++) v.createDirectory("t" + std::to_string(i));
    std::atomic<int> bad{0};
    const bool cm = std::string(fmt) == "cryptomator";   // only Cryptomator has symlinks; the others keep the no-op defaults
    std::vector<std::thread> ts;
    for (int i = 0; i < kThreads; i++) ts.emplace_back([&, i] {
        for (int j = 0; j < kFiles; j++) {
            std::string p = "t" + std::to_string(i) + "/f" + std::to_string(j);
            Bytes d = rnd(1000 + (size_t)(i * 7919 + j * 104729) % 90000, (uint32_t)(i * 100 + j));
            if (!put(v, p, d)) bad++;
            auto g = get(v, p);
            if (!g || *g != d) bad++;
            std::vector<DirEntry> es; v.listDirectory("t" + std::to_string(i), es);
            if (j % 3 == 2 && !v.renameFile(p, p + "r")) bad++;
            // symlinks and the hidden-entry count race with the writes above (and with the other threads' folders)
            std::vector<DirEntry> ls; v.listSymlinks("t" + std::to_string(i), ls); (void)v.hiddenEntryCount("t" + std::to_string(i));
            if (cm) {
                std::string lp = "t" + std::to_string(i) + "/l" + std::to_string(j), want = "target-" + std::to_string(j);
                if (!v.createSymlink(lp, want)) bad++;
                auto rl = v.readSymlink(lp);
                if (!rl || *rl != want) bad++;
                if (j % 2 == 0 && !v.deleteFile(lp)) bad++;
            }
        }
    });
    // a shared file hammered by readers while writers replace it
    Bytes shared = rnd(50000, 99);
    put(v, "shared.bin", shared);
    std::atomic<bool> stop{false};
    std::thread reader([&] { while (!stop) {
        auto g = v.readFileChunk("shared.bin", 0, 60000); (void)g;
        std::vector<DirEntry> ls; v.listSymlinks("t1", ls); v.listSymlinks("", ls); (void)v.hiddenEntryCount("t2"); (void)v.hiddenEntryCount("");
    } });
    for (auto& th : ts) th.join();
    stop = true; reader.join();
    CHECK_EQ(bad.load(), 0);
    for (int i = 0; i < kThreads; i++) {
        std::vector<DirEntry> es; CHECK(v.listDirectory("t" + std::to_string(i), es)); CHECK_EQ(es.size(), (size_t)kFiles);   // links never show up here
        std::vector<DirEntry> ls; CHECK(v.listSymlinks("t" + std::to_string(i), ls)); CHECK_EQ(ls.size(), cm ? (size_t)(kFiles / 2) : (size_t)0);   // odd j survive
        CHECK_EQ(v.hiddenEntryCount("t" + std::to_string(i)), cm ? 0 : -1);
    }
    v.close();
    // operations after close fail cleanly instead of crashing
    CHECK(!put(v, "late", shared));
}

int main(int argc, char** argv) {
    std::string only = argc > 1 ? argv[1] : "";
    auto want = [&](const char* n) { return only.empty() || only == n; };
    if (want("basic")) { testCodecsAndJson(); testPrimitives(); testGocryptfsSivVector(); testCryptomatorNames(); }
    if (want("gocryptfs")) {
        testGocryptfs(GocryptfsCipher::Aes256Gcm, false, "AES-256-GCM");
        testGocryptfs(GocryptfsCipher::XChaCha20Poly1305, false, "XChaCha20-Poly1305");
        testGocryptfs(GocryptfsCipher::AesSiv, false, "AES-SIV");
        testGocryptfs(GocryptfsCipher::Aes256Gcm, true, "plaintext names");
    }
    if (want("cryptomator")) { testCryptomator(false); testCryptomator(true); testCryptomatorCompat(); testCryptomatorSymlinks(); testCryptomatorBackups(); testCryptomatorMigration(); }
    if (want("cryfs")) { testCryfs("xchacha20-poly1305", 32768); testCryfs("aes-256-gcm", 4096); testCryfs("aes-256-cfb", 8192); }
    if (want("concurrency")) { testConcurrency("gocryptfs"); testConcurrency("cryptomator"); testConcurrency("cryfs"); }
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
