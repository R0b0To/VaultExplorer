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
#include <filesystem>
#include <sys/stat.h>

#include "../../crypto/eme.h"
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
        return std::string("{\"EncryptedKey\":\"AAAA\",\"ScryptObject\":{\"Salt\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\",\"N\":1024,\"R\":8,\"P\":1,\"KeyLen\":32},\"Version\":2,\"FeatureFlags\":[") + flags + "]}";
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

        // --- links behave like POSIX shortcuts for access, but remain separate directory entries ---------
        CHECK(get(v, "link").has_value());
        CHECK_EQ(v.getFileSize("link"), (int64_t)10);
        CHECK(!v.createDirectory("link"));                                           // target is a file
        Bytes replacement = rnd(20, 6);
        CHECK(put(v, "link", replacement));                                          // writing through the link updates its target
        CHECK(*get(v, "docs/file.txt") == replacement);
        CHECK(v.readSymlink("link").value_or("?") == "docs/file.txt");              // link text itself is unchanged
        CHECK(!put(v, "link/inside.txt", rnd(5)));                                   // a file target cannot have children
        std::vector<DirEntry> inside; CHECK(!v.listDirectory("link", inside));       // nor can it be listed as a folder
        CHECK(v.createSymlink("docs-link", "docs"));
        CHECK_EQ(symlinksOf(v, "").size(), (size_t)3);
        auto folderLink = symlinksOf(v, "");
        const DirEntry* folderLinkEntry = findLink(folderLink, "docs-link");
        CHECK(folderLinkEntry && folderLinkEntry->isSymlink && folderLinkEntry->isDir);
        std::vector<DirEntry> throughLink;
        CHECK(v.listDirectory("docs-link", throughLink) && throughLink.size() == (size_t)1);
        Bytes throughData = rnd(7, 12);
        CHECK(put(v, "docs-link/through.txt", throughData));
        CHECK(*get(v, "docs/through.txt") == throughData);
        CHECK(v.deleteFile("docs-link/through.txt"));
        CHECK(!get(v, "docs/through.txt"));
        CHECK(v.deleteFile("docs-link"));                                          // unlink removes only the shortcut
        CHECK(v.listDirectory("docs", throughLink));                               // target folder remains
        CHECK(v.createSymlink("cycle-a", "cycle-b"));
        CHECK(v.createSymlink("cycle-b", "cycle-a"));
        CHECK(!get(v, "cycle-a"));                                                 // loops fail closed
        CHECK(v.deleteFile("cycle-a"));
        CHECK(v.deleteFile("cycle-b"));
        CHECK(!v.createSymlink("link", "x"));
        CHECK(!v.createSymlink("docs", "x"));
        CHECK(!v.createSymlink("docs/file.txt", "x"));
        CHECK(!v.createSymlink("nodir/x", "x"));
        CHECK(!v.createSymlink("", "x"));
        CHECK(*get(v, "docs/file.txt") == replacement);
        CHECK_EQ(v.getFolderSize(""), (int64_t)20);                                  // links add nothing; target data is counted once
        CHECK_EQ(v.getFolderSize("docs"), (int64_t)20);

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
        CHECK(*get(v, "docs/file.txt") == replacement);                                  // failed link rename leaves the written-through target untouched
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
        CHECK(*get(v, "docs/file.txt") == replacement);                                  // deleting a link leaves its written-through target alone
        CHECK(v.deleteFile("docs"));                                                 // a folder holding links: nothing is followed, nothing is left
        CHECK_EQ(countFiles(root, "symlink.c9r"), 1);                                // only the root-level "uni" link remains
        CHECK(v.deleteFile(uni));
        CHECK_EQ(countFiles(root, "symlink.c9r"), 0);
        v.close();
    }

    {   // --- links and the namespace: mkdir never follows the last name, no folder moves into itself, no alias writes --
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        CHECK(createCryptomator(*st, pw, 6).status == OpenStatus::Ok);
        auto r = openCryptomator(st, pw, 6, false, {});
        CHECK(r.status == OpenStatus::Ok);
        if (!r.vault) return;
        Vault& v = *r.vault;

        // mkdir follows links in the PARENT path only; the last name is never followed, so nothing is ever
        // created at a link's target
        CHECK(v.createDirectory("real"));
        CHECK(v.createSymlink("dirlink", "real"));
        CHECK(v.createDirectory("dirlink"));                                         // link to an existing folder: "mkdir -p" success
        CHECK(v.createSymlink("ghost", "elsewhere"));
        CHECK(!v.createDirectory("ghost"));                                          // dangling: refused...
        CHECK(!has(v, "", "D:elsewhere"));                                           // ...and no folder appears at its target
        CHECK(put(v, "f.txt", rnd(3, 30)));
        CHECK(v.createSymlink("filelink", "f.txt"));
        CHECK(!v.createDirectory("filelink"));                                       // link to a file
        CHECK(v.createSymlink("abs", "/real"));
        CHECK(!v.createDirectory("abs"));                                            // absolute target is never resolved
        CHECK(v.createDirectory("dirlink/sub"));                                     // a link in the parent IS followed
        CHECK(has(v, "real", "D:sub"));
        CHECK(!has(v, "", "D:sub"));
        CHECK(v.createDirectory(""));                                                // the root is always there

        // a folder can never move into itself or one of its own subfolders, directly or through a link that
        // points back at it (the subtree would be cut off from the vault)
        CHECK(v.createDirectory("a"));
        CHECK(v.createDirectory("a/b"));
        const Bytes keepData = rnd(4, 31);
        CHECK(put(v, "a/keep.txt", keepData));
        CHECK(v.createSymlink("toa", "a"));
        CHECK(!v.renameFile("a", "a/inside"));
        CHECK(!v.renameFile("a", "a/b/inside"));
        CHECK(!v.renameFile("a", "toa/inside"));                                     // through the alias
        CHECK(!v.renameFile("a", "toa/b/inside"));
        CHECK(!v.renameFile("a/b", "a/b/inside"));
        CHECK(has(v, "", "D:a"));                                                    // everything is still where it was
        CHECK(has(v, "a", "F:keep.txt"));
        CHECK(has(v, "a", "D:b"));
        CHECK(!has(v, "a", "D:inside"));
        std::vector<DirEntry> rootList; CHECK(v.listDirectory("", rootList));        // and the root still lists
        CHECK(v.renameFile("a/b", "b2"));                                            // a subfolder may leave...
        CHECK(v.renameFile("b2", "a/b3"));                                           // ...and come back under another name
        CHECK(v.createDirectory("ab"));                                              // "ab" merely starts with "a": not inside "a"
        CHECK(v.renameFile("a", "ab/a"));
        CHECK(has(v, "ab", "D:a"));
        CHECK(v.renameFile("ab/a", "a"));
        CHECK(v.renameFile("a", "a2"));                                              // renaming in place is fine
        CHECK(has(v, "a2", "F:keep.txt"));
        CHECK(has(v, "a2", "D:b3"));
        CHECK(v.renameFile("a2/keep.txt", "a2/b3/keep.txt"));                        // files are not folders: no restriction
        CHECK(*get(v, "a2/b3/keep.txt") == keepData);                                // and the content came along

        // two names for one file must not be written at the same time (they share no engine path lock)
        CHECK(put(v, "real/shared.txt", rnd(5, 32)));
        CHECK(v.createSymlink("sharedlink", "real/shared.txt"));
        Bytes w1 = rnd(100, 33), w2 = rnd(100, 34);
        CHECK(v.writeFileChunk("real/shared.txt", 0, w1.data(), w1.size()));         // the first writer is in flight
        CHECK(!v.writeFileChunk("sharedlink", 0, w2.data(), w2.size()));             // another name for the same file: refused
        CHECK(v.finishWrite("real/shared.txt"));
        CHECK(*get(v, "real/shared.txt") == w1);                                     // intact, never interleaved
        CHECK(put(v, "sharedlink", w2));                                             // once the first is done the link may write
        CHECK(*get(v, "real/shared.txt") == w2);
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
        CHECK_EQ(probeCryptomatorFormat(*st), 7);   // password-free, from the files alone
        auto r = openCryptomator(st, pw, 6, false, {}); CHECK(r.status == OpenStatus::Ok); if (!r.vault) return;
        const Bytes a = rnd(100000, 21), b = rnd(10, 22);
        CHECK(r.vault->createDirectory("docs")); CHECK(put(*r.vault, "docs/a.bin", a)); CHECK(put(*r.vault, std::string(170, 'N') + ".txt", b));
        r.vault->close();
        Bytes oldKey; CHECK(st->readWhole("masterkey.cryptomator", oldKey));
        CHECK(migrateCryptomator7To8(*st, pw, 6).status == OpenStatus::Ok);
        CHECK_EQ(probeCryptomatorFormat(*st), 8);   // vault.cryptomator now exists
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
        CHECK_EQ(probeCryptomatorFormat(*st), 8);
        CHECK(snapshot(root) == before);            // probing never writes
    }
    {   // (3) refusals change nothing at all
        TmpDir t; std::string root = t.sub("v"); auto st = std::make_shared<PosixStorage>(root);
        makeV7(*st);
        auto before = snapshot(root);
        CHECK_EQ(probeCryptomatorFormat(*st), 7);
        CHECK(snapshot(root) == before);
        CHECK(migrateCryptomator7To8(*st, (const uint8_t*)"bad", 3).status == OpenStatus::WrongPassword);
        CHECK(snapshot(root) == before);
        CHECK(!st->stat("vault.cryptomator", *std::make_unique<DirEntry>()));
        // a format 8 key file without its vault.cryptomator (e.g. not synced yet) must never be "migrated"
        TmpDir t2; std::string root2 = t2.sub("v"); auto st2 = std::make_shared<PosixStorage>(root2);
        CHECK(createCryptomator(*st2, pw, 6).status == OpenStatus::Ok); CHECK(st2->remove("vault.cryptomator"));
        auto before2 = snapshot(root2);
        CHECK_EQ(probeCryptomatorFormat(*st2), -8);   // the signal the UI uses to say "wait for sync", never "upgrade"
        CHECK(migrateCryptomator7To8(*st2, pw, 6).status == OpenStatus::InvalidVault);
        CHECK(snapshot(root2) == before2);
        // a genuine format 8 vault
        TmpDir t3; auto st3 = std::make_shared<PosixStorage>(t3.sub("v"));
        CHECK(createCryptomator(*st3, pw, 6).status == OpenStatus::Ok);
        CHECK_EQ(probeCryptomatorFormat(*st3), 8);
        CHECK(migrateCryptomator7To8(*st3, pw, 6).status == OpenStatus::InvalidVault);
        // not a vault at all
        TmpDir t4; auto st4 = std::make_shared<PosixStorage>(t4.sub("v"));
        CHECK_EQ(probeCryptomatorFormat(*st4), 0);
        CHECK(migrateCryptomator7To8(*st4, pw, 6).status == OpenStatus::InvalidVault);
        // a key file that is not parseable, and a *directory* named masterkey.cryptomator, are "cannot tell" too
        TmpDir t4b; auto st4b = std::make_shared<PosixStorage>(t4b.sub("v"));
        CHECK(st4b->writeWhole("masterkey.cryptomator", (const uint8_t*)"{ not json", 10));
        CHECK_EQ(probeCryptomatorFormat(*st4b), 0);
        CHECK(migrateCryptomator7To8(*st4b, pw, 6).status == OpenStatus::InvalidVault);
        TmpDir t4c; auto st4c = std::make_shared<PosixStorage>(t4c.sub("v"));
        CHECK(st4c->mkdir("masterkey.cryptomator"));
        CHECK_EQ(probeCryptomatorFormat(*st4c), 0);
        // an old (version 6) key file is not ours to migrate
        TmpDir t5; auto st5 = std::make_shared<PosixStorage>(t5.sub("v"));
        makeV7(*st5);
        auto mk = cm::unlockMasterkey(cm::MasterkeyFile::parse(readText(*st5, "masterkey.cryptomator")), pw, 6);
        std::string j6 = cm::lockMasterkey(mk, pw, 6, 6);
        CHECK(st5->writeWhole("masterkey.cryptomator", (const uint8_t*)j6.data(), j6.size()));
        auto before5 = snapshot(t5.sub("v"));
        CHECK_EQ(probeCryptomatorFormat(*st5), 6);
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
    // pull-to-refresh style invalidation (folder, whole vault, a file) racing all of the above: it must neither
    // break the traffic nor race with it
    std::thread refresher([&] {
        int n = 0;
        while (!stop) {
            v.invalidateCache(n % 4 == 0 ? std::string() : "t" + std::to_string(n % kThreads));
            if (n % 5 == 0) v.invalidateCache("shared.bin");
            n++;
            std::this_thread::yield();
        }
    });
    for (auto& th : ts) th.join();
    stop = true; reader.join(); refresher.join();
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

// ============================================================================
// Compatibility with the *official* gocryptfs (github.com/rfjakob/gocryptfs).
//
// Every rule asserted below is taken from its source: internal/configfile
// (validate.go, scrypt.go, config_file.go), internal/nametransform (names.go,
// valid.go, diriv.go, longnames.go), internal/contentenc, internal/cryptocore
// and internal/fusefrontend. The real binary is exercised against the same
// behaviour in test/interop/gocryptfs_official_compat.py.
// ============================================================================

static std::string slurp(const std::string& p) {
    std::ifstream f(p, std::ios::binary);
    std::stringstream ss; ss << f.rdbuf();
    return ss.str();
}
static void spit(const std::string& p, const std::string& d) {
    std::ofstream f(p, std::ios::binary | std::ios::trunc);
    f.write(d.data(), (std::streamsize)d.size());
}
static std::vector<std::string> physNames(const std::string& dir) {
    std::vector<std::string> o;
    for (auto& e : std::filesystem::directory_iterator(dir)) o.push_back(e.path().filename().string());
    std::sort(o.begin(), o.end());
    return o;
}
static bool hasPhys(const std::string& dir, const std::string& name) {
    auto n = physNames(dir);
    return std::find(n.begin(), n.end(), name) != n.end();
}
static void copyTree(const std::string& from, const std::string& to) {
    std::string cmd = "cp -a '" + from + "/.' '" + to + "'";
    if (system(cmd.c_str())) std::puts("  (cp failed)");
}
static std::string vectorsDir() {
    if (const char* e = std::getenv("FV_VECTORS")) return e;
#ifdef FV_VECTORS_DIR
    // Set by CMake (see foldervault_test): __FILE__ is rewritten to /source_tree/...
    // by -ffile-prefix-map, so it can't be used to find the vectors on disk.
    return FV_VECTORS_DIR;
#else
    std::string f = __FILE__;
    return f.substr(0, f.rfind('/')) + "/vectors/gocryptfs";
#endif
}
static OpenResult openAt(const std::string& dir, const char* pw, bool ro = false) {
    auto st = std::make_shared<PosixStorage>(dir);
    return openGocryptfs(st, (const uint8_t*)pw, std::strlen(pw), ro, {});
}
static PlainResult createAt(const std::string& dir, const GocryptfsCreateOptions& o, const char* pw = "pw") {
    PosixStorage st(dir);
    return createGocryptfs(st, (const uint8_t*)pw, std::strlen(pw), o);
}
static GocryptfsCreateOptions fastOpts() { GocryptfsCreateOptions o; o.scryptLogN = 10; return o; }
static bool infoBool(Vault& v, const std::string& key) {
    for (auto& i : v.info()) if (i.key == key) return i.value == "true";
    return false;
}
static int64_t infoInt(Vault& v, const std::string& key) {
    for (auto& i : v.info()) if (i.key == key) return std::atoll(i.value.c_str());
    return -1;
}
static std::string repeatc(char c, size_t n) { return std::string(n, c); }
static std::vector<std::string> configFlags(const std::string& vaultDir) {
    auto cfg = gocryptfs::Config::parse(slurp(vaultDir + "/gocryptfs.conf"));
    return cfg.featureFlags;
}

// ---- internal/configfile: Validate() + scrypt validateParams() ---------------
static std::string gcCfg(const std::string& flags, const std::string& extraTop = "", const std::string& scrypt = "",
                         int version = 2) {
    std::string defScrypt = "\"Salt\":\"" + repeatc('A', 43) + "=\",\"N\":1024,\"R\":8,\"P\":1,\"KeyLen\":32";
    return "{\"Creator\":\"gocryptfs 2.x\",\"EncryptedKey\":\"" + repeatc('A', 84) + "\",\"ScryptObject\":{" +
           (scrypt.empty() ? defScrypt : scrypt) + "},\"Version\":" + std::to_string(version) + "," + extraTop +
           "\"FeatureFlags\":[" + flags + "]}";
}
static bool cfgOk(const std::string& json, gocryptfs::Config* out = nullptr) {
    try { auto c = gocryptfs::Config::parse(json); if (out) *out = c; return true; }
    catch (const Error& e) { if (e.code() != Err::InvalidVault) CHECK(false); return false; }
}

static void testGocryptfsConfigRules() {
    std::puts("gocryptfs config validation (configfile.Validate)");
    const std::string GCM = "\"GCMIV128\"", HK = "\"HKDF\"";
    gocryptfs::Config c;

    // --- accepted by gocryptfs (see tests/example_filesystems) -----------------
    CHECK(cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"EMENames\",\"LongNames\",\"Raw64\""), &c));
    CHECK(c.cipher == GocryptfsCipher::Aes256Gcm && c.hasHkdf() && c.raw64() && c.hasDirIV() && !c.deterministicNames());
    // v0.7: no HKDF, no Raw64, no LongNames
    CHECK(cfgOk(gcCfg(GCM + ",\"DirIV\",\"EMENames\""), &c));
    CHECK(!c.hasHkdf() && !c.raw64() && c.hasDirIV());
    // v1.1-aessiv: AESSIV without HKDF / Raw64
    CHECK(cfgOk(gcCfg(GCM + ",\"DirIV\",\"EMENames\",\"LongNames\",\"AESSIV\""), &c));
    CHECK(c.cipher == GocryptfsCipher::AesSiv && !c.hasHkdf());
    CHECK(cfgOk(gcCfg(HK + ",\"XChaCha20Poly1305\",\"DirIV\",\"EMENames\",\"LongNames\",\"Raw64\""), &c));
    CHECK(c.cipher == GocryptfsCipher::XChaCha20Poly1305);
    // -deterministic-names: simply no DirIV flag
    CHECK(cfgOk(gcCfg(HK + "," + GCM + ",\"EMENames\",\"LongNames\",\"Raw64\""), &c));
    CHECK(c.deterministicNames() && !c.hasDirIV());
    CHECK(cfgOk(gcCfg(HK + "," + GCM + ",\"PlaintextNames\""), &c));
    CHECK(c.plaintextNames && !c.deterministicNames());
    // gocryptfs never requires EMENames on its own
    CHECK(cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"LongNames\",\"Raw64\"")));
    // -longnamemax: the flag *and* the field
    CHECK(cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"LongNameMax\",\"EMENames\",\"LongNames\",\"Raw64\"", "\"LongNameMax\":100,"), &c));
    CHECK_EQ(c.longNameMax, 100);
    // -fido2 parses (it just cannot be unlocked here)
    CHECK(cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"EMENames\",\"FIDO2\""), &c));
    CHECK(c.fido2());

    // --- refused by gocryptfs --------------------------------------------------
    CHECK(!cfgOk(gcCfg("\"DirIV\",\"EMENames\"")));                                   // AES-GCM requires GCMIV128
    CHECK(!cfgOk(gcCfg(HK)));
    CHECK(!cfgOk(gcCfg(HK + ",\"AESSIV\",\"DirIV\"")));                               // AESSIV requires GCMIV128
    CHECK(!cfgOk(gcCfg(HK + ",\"XChaCha20Poly1305\"," + GCM)));                       // conflicts with GCMIV128
    CHECK(!cfgOk(gcCfg(HK + ",\"XChaCha20Poly1305\",\"AESSIV\"")));                   // both
    CHECK(!cfgOk(gcCfg(HK + ",\"XChaCha20Poly1305\",\"AESSIV\"," + GCM)));
    CHECK(!cfgOk(gcCfg("\"XChaCha20Poly1305\",\"DirIV\",\"EMENames\"")));             // XChaCha requires HKDF
    CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"Bogus\"")));                              // unknown flag
    for (const char* bad : {"EMENames", "DirIV", "LongNames", "Raw64"})               // PlaintextNames conflicts
        CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"PlaintextNames\",\"" + bad + "\"")));
    CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"PlaintextNames\",\"LongNameMax\"", "\"LongNameMax\":100,")));
    CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"EMENames\"", "\"LongNameMax\":100,")));        // value without flag
    CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"EMENames\",\"LongNameMax\"")));                // flag without value
    CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"EMENames\",\"LongNameMax\"", "\"LongNameMax\":300,")));   // not a uint8
    CHECK(!cfgOk(gcCfg(HK + "," + GCM + ",\"DirIV\",\"EMENames\",\"LongNameMax\"", "\"LongNameMax\":-1,")));
    CHECK(!cfgOk(gcCfg(HK + "," + GCM, "", "", 1)));                                  // only format 2
    CHECK(!cfgOk(gcCfg(HK + "," + GCM, "", "", 3)));

    // --- scrypt parameter validation (scrypt.go validateParams) ----------------
    auto sc = [](const std::string& salt43, int N, int R, int P, int keyLen) {
        return "\"Salt\":\"" + salt43 + "\",\"N\":" + std::to_string(N) + ",\"R\":" + std::to_string(R) +
               ",\"P\":" + std::to_string(P) + ",\"KeyLen\":" + std::to_string(keyLen);
    };
    const std::string ok = HK + "," + GCM + ",\"DirIV\",\"EMENames\"";
    const std::string salt32 = repeatc('A', 43) + "=", salt31 = repeatc('A', 41) + "A=";
    CHECK(cfgOk(gcCfg(ok, "", sc(salt32, 1024, 8, 1, 32))));
    CHECK(cfgOk(gcCfg(ok, "", sc(salt32, 65536, 8, 1, 32))));
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt32, 512, 8, 1, 32))));        // N below 2^10
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt32, 3000, 8, 1, 32))));       // not a power of two
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt32, 1024, 7, 1, 32))));       // R below 8
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt32, 1024, 8, 0, 32))));       // P below 1
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt31, 1024, 8, 1, 32))));       // salt shorter than 32 bytes
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt32, 1024, 8, 1, 31))));       // KeyLen below 32
    CHECK(!cfgOk(gcCfg(ok, "", sc(salt32, 1024, 8, 1, 64))));       // gocryptfs itself panics on that
    for (const char* hugeN : {"4294967296", "1099511627776", "9223372036854775807"})   // 2^32, 2^40, > 2^62: must not wrap to 0
        CHECK(!cfgOk(gcCfg(ok, "", "\"Salt\":\"" + salt32 + "\",\"N\":" + hugeN + ",\"R\":8,\"P\":1,\"KeyLen\":32")));
}

// ---- internal/nametransform ---------------------------------------------------
static void testGocryptfsNameRules() {
    std::puts("gocryptfs names (IsValidName, strict base64, long names)");
    using gocryptfs::NameCryptor;
    Secret key{Bytes(32, 0x42)};
    uint8_t iv[16]; std::memset(iv, 0x11, 16);
    NameCryptor nc(key, 0, false, /*raw64*/ true);

    // everything IsValidName allows must round-trip -- including names this app used to hide
    const std::vector<std::string> good = {
        "a", "hello world", repeatc('n', 255), "nl\nname", "cr\rname", "crlf\r\nname", "repl-" "\xEF\xBF\xBD" "-char",
        "ünï.txt", " lead trail ", "...", ".hidden", "a.b", "tab\tname", "a=b", "gocryptfs.conf", "gocryptfs.diriv",
        "gocryptfs.longname.abc", "x.name"};
    for (auto& n : good) {
        std::string c = nc.encryptName(n, iv);
        CHECK(NameCryptor::isValidName(n));
        std::string back;
        try { back = nc.decryptName(c, iv); } catch (const Error&) {}
        CHECK(back == n);
    }
    auto encFails = [&](const std::string& n) { try { nc.encryptName(n, iv); return false; } catch (const Error&) { return true; } };
    CHECK(encFails("")); CHECK(encFails(".")); CHECK(encFails("..")); CHECK(encFails("a/b"));
    CHECK(encFails(std::string("a\0b", 3))); CHECK(encFails(repeatc('n', 256)));
    CHECK(!NameCryptor::isValidName("") && !NameCryptor::isValidName("..") && !NameCryptor::isValidName(repeatc('n', 256)));

    auto decFails = [&](const NameCryptor& n, const std::string& s) { try { n.decryptName(s, iv); return false; } catch (const Error&) { return true; } };
    // decrypting what a valid-but-forbidden plaintext would produce: forge ciphertexts for arbitrary padded blocks
    auto forge = [&](const std::string& plain) {
        size_t pad = 16 - plain.size() % 16;
        Bytes p(plain.begin(), plain.end()); p.insert(p.end(), pad, (uint8_t)pad);
        Bytes o(p.size());
        eme_transform(key.data(), key.size(), iv, p.data(), o.data(), p.size(), true);
        return base64Encode(o.data(), o.size(), true, false);
    };
    CHECK(!decFails(nc, forge("fine")));
    CHECK(decFails(nc, forge("")));              // a block of pure padding: empty name
    CHECK(decFails(nc, forge(".")));
    CHECK(decFails(nc, forge("..")));
    CHECK(decFails(nc, forge("a/b")));
    CHECK(decFails(nc, forge(std::string("a\0b", 3))));
    CHECK(decFails(nc, forge(repeatc('n', 256))));
    CHECK(!decFails(nc, forge(repeatc('n', 255))));
    CHECK(decFails(nc, forge("bad\xFF\xFE")));   // valid for gocryptfs, but not representable as a Java/Dart string
    // bad PKCS#7 padding
    {
        Bytes p(16, 3); p[15] = 5;   // claims 5 bytes of padding, only the last one says so
        Bytes o(16);
        eme_transform(key.data(), key.size(), iv, p.data(), o.data(), 16, true);
        CHECK(decFails(nc, base64Encode(o.data(), o.size(), true, false)));
    }

    // base64 must be canonical (gocryptfs decodes with base64.Strict())
    std::string c = nc.encryptName("x", iv);
    CHECK_EQ(c.size(), (size_t)22);
    static const std::string alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    size_t idx = alpha.find(c.back());
    CHECK(idx != std::string::npos && (idx & 0x0F) == 0);          // the last sextet carries 4 zero bits
    std::string malleable = c; malleable.back() = alpha[idx | 1];
    Bytes lenient; CHECK(base64Decode(malleable, lenient));        // the app's lenient codec would take it ...
    CHECK(decFails(nc, malleable));                                // ... but it is not a gocryptfs name
    CHECK(decFails(nc, c + "="));                                  // Raw64 has no padding
    CHECK(decFails(nc, c.substr(0, 10) + "\n" + c.substr(10)));    // Go's decoder skips newlines; gocryptfs rejects them
    CHECK(decFails(nc, c.substr(0, 10) + "\r\n" + c.substr(10)));
    CHECK(decFails(nc, c + "A"));                                  // 23 chars: not a whole number of blocks
    CHECK(decFails(nc, ""));
    CHECK(decFails(nc, "gocryptfs.diriv"));
    CHECK(decFails(nc, "!!notbase64!!"));

    // legacy vaults (no Raw64): padded base64 for names, and for the long-name hash
    NameCryptor np(key, 0, false, /*raw64*/ false);
    std::string cp = np.encryptName("x", iv);
    CHECK_EQ(cp.size(), (size_t)24);
    CHECK(cp.substr(22) == "==");
    CHECK(np.decryptName(cp, iv) == "x");
    CHECK(decFails(np, cp.substr(0, 22)));                         // padding is mandatory there
    CHECK(decFails(nc, cp));                                       // and forbidden with Raw64
    const size_t prefix = std::strlen(gocryptfs::kLongNamePrefix);
    CHECK_EQ(nc.hashLongName("abc").size(), prefix + 43);
    CHECK_EQ(np.hashLongName("abc").size(), prefix + 44);
    CHECK(np.hashLongName("abc").back() == '=');

    // long-name threshold: 255 by default, -longnamemax otherwise
    NameCryptor n100(key, 100, false, true);
    CHECK(!nc.isOverLongNameLimit(repeatc('a', 255)));  CHECK(nc.isOverLongNameLimit(repeatc('a', 256)));
    CHECK(!n100.isOverLongNameLimit(repeatc('a', 100))); CHECK(n100.isOverLongNameLimit(repeatc('a', 101)));
    NameCryptor npl(Secret(), 0, true, true);
    CHECK(!npl.isOverLongNameLimit(repeatc('a', 300)));            // plaintext names are never hashed
    CHECK(npl.encryptName("plain.txt", iv) == "plain.txt");

    // classification of physical names (nametransform.NameType)
    CHECK(NameCryptor::isLongNameContent("gocryptfs.longname.abc") && !NameCryptor::isLongNameFile("gocryptfs.longname.abc"));
    CHECK(NameCryptor::isLongNameFile("gocryptfs.longname.abc.name") && !NameCryptor::isLongNameContent("gocryptfs.longname.abc.name"));
    CHECK(!NameCryptor::isLongNameFile("foo.name") && !NameCryptor::isLongNameContent("foo.name"));
    CHECK(!NameCryptor::isLongNameFile("gocryptfs.diriv") && !NameCryptor::isLongNameContent("gocryptfs.diriv"));
}

// ---- the official example filesystems (tests/example_filesystems) ----------------
struct VectorCase {
    const char* dir;
    bool opens;                // false: gocryptfs itself refuses ("too old")
    bool hkdf, raw64, deterministic, plain;
    GocryptfsCipher cipher;
    bool longname;             // has the 255-byte "longname_255_xxx..." file
};

static void testGocryptfsOfficialVectors() {
    std::puts("gocryptfs official example filesystems");
    const GocryptfsCipher GCM = GocryptfsCipher::Aes256Gcm, SIV = GocryptfsCipher::AesSiv, XC = GocryptfsCipher::XChaCha20Poly1305;
    const VectorCase cases[] = {
        {"v0.4", false, 0, 0, 0, 0, GCM, false}, {"v0.5", false, 0, 0, 0, 0, GCM, false},
        {"v0.6", false, 0, 0, 0, 0, GCM, false}, {"v0.6-plaintextnames", false, 0, 0, 0, 1, GCM, false},
        {"v0.7", true, 0, 0, 0, 0, GCM, false},  {"v0.7-plaintextnames", true, 0, 0, 0, 1, GCM, false},
        {"v0.9", true, 0, 0, 0, 0, GCM, true},   {"v1.1-aessiv", true, 0, 0, 0, 0, SIV, true},
        {"v1.3", true, 1, 1, 0, 0, GCM, true},   {"v2.2-deterministic-names", true, 1, 1, 1, 0, GCM, true},
        {"v2.2-xchacha", true, 1, 1, 0, 0, XC, true}, {"v2.2-xchacha-deterministic-names", true, 1, 1, 1, 0, XC, true},
    };
    const std::string longName = "longname_255_" + repeatc('x', 242);
    const std::string vroot = vectorsDir();
    for (const VectorCase& vc : cases) {
        std::printf("  %s\n", vc.dir);
        if (!std::filesystem::exists(vroot + "/" + vc.dir)) { CHECK(false); continue; }
        TmpDir t; std::string d = t.sub("v");
        copyTree(vroot + "/" + vc.dir, d);
        auto r = openAt(d, "test");
        if (!vc.opens) { CHECK(r.status == OpenStatus::InvalidVault); continue; }
        CHECK(r.status == OpenStatus::Ok);
        if (!r.vault) continue;
        Vault& v = *r.vault;
        CHECK(openAt(d, "wrong").status == OpenStatus::WrongPassword);
        CHECK_EQ(infoBool(v, "hkdf"), (bool)vc.hkdf);
        CHECK_EQ(infoBool(v, "raw64"), vc.plain ? false : (bool)vc.raw64);
        CHECK_EQ(infoBool(v, "deterministicNames"), (bool)vc.deterministic);
        CHECK_EQ(infoBool(v, "plaintextNames"), (bool)vc.plain);
        auto st = get(v, "status.txt");
        CHECK(st.has_value() && std::string(st->begin(), st->end()) == "It works!\n");
        if (vc.longname) {
            auto ln = get(v, longName);
            CHECK(ln.has_value() && std::string(ln->begin(), ln->end()) == "It works!\n");
            CHECK(has(v, "", "F:" + longName));
        }
        CHECK(has(v, "", "F:status.txt"));

        // --- write into it the way gocryptfs would ---
        const std::string payload(5000, 'q');
        CHECK(v.createDirectory("sub"));
        CHECK(v.createDirectory("sub/inner"));
        CHECK(put(v, "sub/new.txt", Bytes(payload.begin(), payload.end())));
        CHECK(put(v, "sub/" + repeatc('L', 200) + ".txt", Bytes(payload.begin(), payload.end())));   // forces a long name
        CHECK(v.renameFile("sub/new.txt", "sub/renamed.txt"));
        CHECK(v.createDirectory("sub/" + repeatc('D', 230)));                                         // long-named folder
        CHECK(put(v, "sub/" + repeatc('D', 230) + "/f", Bytes(payload.begin(), payload.end())));
        auto back = get(v, "sub/renamed.txt");
        CHECK(back.has_value() && std::string(back->begin(), back->end()) == payload);
        v.close();

        auto r2 = openAt(d, "test");
        CHECK(r2.status == OpenStatus::Ok);
        if (r2.vault) {
            Vault& w = *r2.vault;
            CHECK(has(w, "sub", "F:renamed.txt") && has(w, "sub", "F:" + repeatc('L', 200) + ".txt") && has(w, "sub", "D:inner"));
            CHECK(has(w, "sub", "D:" + repeatc('D', 230)));
            auto lf = get(w, "sub/" + repeatc('L', 200) + ".txt");
            CHECK(lf.has_value() && std::string(lf->begin(), lf->end()) == payload);
            CHECK(w.deleteFile("sub/" + repeatc('L', 200) + ".txt"));
            CHECK(w.deleteFile("sub/" + repeatc('D', 230)));
            CHECK(get(w, "status.txt").has_value());
            w.close();
        }

        // --- password change must keep the vault's own wrap format (nonce size, key expansion) ---
        PosixStorage st2(d);
        CHECK(changeGocryptfsPassword(st2, (const uint8_t*)"test", 4, (const uint8_t*)"newpw", 5).status == OpenStatus::Ok);
        auto cfg = gocryptfs::Config::parse(slurp(d + "/gocryptfs.conf"));
        CHECK_EQ(cfg.encryptedKey.size(), (size_t)(vc.hkdf ? 16 + 32 + 16 : 12 + 32 + 16));
        CHECK_EQ(cfg.hasHkdf(), (bool)vc.hkdf);
        CHECK(openAt(d, "test").status == OpenStatus::WrongPassword);
        auto r3 = openAt(d, "newpw");
        CHECK(r3.status == OpenStatus::Ok);
        if (r3.vault) CHECK(get(*r3.vault, "status.txt").has_value());
    }

    // known answer: the hash in a legacy (padded-base64) long name is the padded sha256 of the *encrypted* name
    {
        TmpDir t; std::string d = t.sub("v");
        copyTree(vroot + "/v0.9", d);
        gocryptfs::Config cfg = gocryptfs::Config::parse(slurp(d + "/gocryptfs.conf"));
        Secret mk = gocryptfs::unlockMasterkey(cfg, (const uint8_t*)"test", 4);
        auto keys = gocryptfs::deriveSessionKeys(cfg, mk);
        gocryptfs::NameCryptor nc(keys.nameKey, cfg.longNameMax, false, cfg.raw64());
        const std::string h = "gocryptfs.longname.y4J-w3LBX165Mn_pGdDRY7Gb6EgHcTrdWjME3WGu-CQ=";
        std::string sidecar = slurp(d + "/" + h + ".name");
        CHECK_EQ(nc.hashLongName(sidecar), h);
        std::string iv = slurp(d + "/gocryptfs.diriv");
        CHECK_EQ(iv.size(), (size_t)16);
        CHECK_EQ(nc.decryptName(sidecar, (const uint8_t*)iv.data()), longName);
        CHECK(nc.isOverLongNameLimit(sidecar));
    }
}

// ---- -init options: -deterministic-names, -longnamemax, -scryptn ----------------
static void testGocryptfsCreateOptions() {
    std::puts("gocryptfs create options (-deterministic-names, -longnamemax, -scryptn)");
    using V = std::vector<std::string>;
    auto flagsOf = [&](const GocryptfsCreateOptions& o, std::string* dirOut = nullptr) {
        TmpDir t; std::string d = t.sub("v");
        CHECK(createAt(d, o).status == OpenStatus::Ok);
        auto f = configFlags(d);
        auto r = openAt(d, "pw");
        CHECK(r.status == OpenStatus::Ok);
        if (dirOut) *dirOut = hasPhys(d, "gocryptfs.diriv") ? "diriv" : "nodiriv";
        return f;
    };
    // the exact flag set and order `gocryptfs -init` writes
    std::string dv;
    GocryptfsCreateOptions o = fastOpts();
    CHECK(flagsOf(o, &dv) == (V{"HKDF", "GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64"})); CHECK_EQ(dv, std::string("diriv"));
    o.cipher = GocryptfsCipher::AesSiv;
    CHECK(flagsOf(o) == (V{"HKDF", "GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "AESSIV"}));
    o.cipher = GocryptfsCipher::XChaCha20Poly1305;
    CHECK(flagsOf(o) == (V{"HKDF", "XChaCha20Poly1305", "DirIV", "EMENames", "LongNames", "Raw64"}));
    o = fastOpts(); o.deterministicNames = true;
    CHECK(flagsOf(o, &dv) == (V{"HKDF", "GCMIV128", "EMENames", "LongNames", "Raw64"})); CHECK_EQ(dv, std::string("nodiriv"));
    o = fastOpts(); o.longNameMax = 100;
    CHECK(flagsOf(o) == (V{"HKDF", "GCMIV128", "DirIV", "LongNameMax", "EMENames", "LongNames", "Raw64"}));
    o = fastOpts(); o.longNameMax = 255;                      // the default is not recorded
    CHECK(flagsOf(o) == (V{"HKDF", "GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64"}));
    o = fastOpts(); o.plaintextNames = true; o.deterministicNames = true; o.longNameMax = 100;   // ignored, like -init
    CHECK(flagsOf(o, &dv) == (V{"HKDF", "GCMIV128", "PlaintextNames"})); CHECK_EQ(dv, std::string("nodiriv"));

    // limits enforced by the official CLI
    for (int bad : {1, 61, 256, 1000, -5}) { o = fastOpts(); o.longNameMax = bad; TmpDir t; CHECK(createAt(t.sub("v"), o).status == OpenStatus::InvalidVault); }
    for (int bad : {62, 63, 100, 255}) { o = fastOpts(); o.longNameMax = bad; TmpDir t; CHECK(createAt(t.sub("v"), o).status == OpenStatus::Ok); }
    for (int bad : {0, 9, 29, 100}) { o = fastOpts(); o.scryptLogN = bad; TmpDir t; CHECK(createAt(t.sub("v"), o).status == OpenStatus::InvalidVault); }
    { o = fastOpts(); TmpDir t; std::string d = t.sub("v"); CHECK(createAt(d, o).status == OpenStatus::Ok);
      CHECK_EQ(gocryptfs::Config::parse(slurp(d + "/gocryptfs.conf")).scryptN, (uint32_t)1024);
      CHECK_EQ(gocryptfs::Config::parse(slurp(d + "/gocryptfs.conf")).creator, std::string("VaultExplorer")); }

    // ---- deterministic names: no gocryptfs.diriv anywhere, same name => same ciphertext name ----
    for (GocryptfsCipher cipher : {GocryptfsCipher::Aes256Gcm, GocryptfsCipher::XChaCha20Poly1305, GocryptfsCipher::AesSiv}) {
        o = fastOpts(); o.deterministicNames = true; o.cipher = cipher;
        TmpDir t; std::string d = t.sub("v");
        CHECK(createAt(d, o).status == OpenStatus::Ok);
        auto r = openAt(d, "pw");
        CHECK(r.status == OpenStatus::Ok);
        if (!r.vault) continue;
        Vault& v = *r.vault;
        CHECK(infoBool(v, "deterministicNames"));
        CHECK(v.createDirectory("a")); CHECK(v.createDirectory("b")); CHECK(v.createDirectory("a/deep"));
        CHECK(put(v, "a/same.txt", rnd(6000, 1))); CHECK(put(v, "b/same.txt", rnd(6000, 2)));
        CHECK(put(v, "a/deep/same.txt", rnd(10, 3)));
        CHECK(put(v, repeatc('L', 240), rnd(100, 4)));            // long name without any diriv
        CHECK(v.renameFile("a/same.txt", "a/other.txt"));
        CHECK(v.renameFile("a/other.txt", "a/same.txt"));
        // physical layout: nothing called gocryptfs.diriv, and "same.txt" has one ciphertext name everywhere
        int dirivFiles = 0;
        for (auto& e : std::filesystem::recursive_directory_iterator(d)) if (e.path().filename() == "gocryptfs.diriv") dirivFiles++;
        CHECK_EQ(dirivFiles, 0);
        // "a" holds {deep, same.txt}, "b" holds {same.txt}, "a/deep" holds {same.txt}
        std::string aDir, bDir;
        for (auto& n : physNames(d)) {
            if (!std::filesystem::is_directory(d + "/" + n) || gocryptfs::NameCryptor::isLongNameContent(n)) continue;
            (physNames(d + "/" + n).size() == 2 ? aDir : bDir) = n;
        }
        CHECK(!aDir.empty() && !bDir.empty());
        std::string inA, inDeep;
        for (auto& n : physNames(d + "/" + aDir)) { if (std::filesystem::is_directory(d + "/" + aDir + "/" + n)) inDeep = n; else inA = n; }
        auto phB = physNames(d + "/" + bDir);
        auto phDeep = physNames(d + "/" + aDir + "/" + inDeep);
        CHECK(phB.size() == 1 && phDeep.size() == 1 && phB[0] == phDeep[0] && phB[0] == inA);
        // and it survives a re-open and re-listing
        v.close();
        auto r2 = openAt(d, "pw");
        CHECK(r2.status == OpenStatus::Ok);
        if (r2.vault) { CHECK(get(*r2.vault, "b/same.txt") == rnd(6000, 2)); CHECK(has(*r2.vault, "a", "D:deep")); }
    }

    // ---- the synchronisation scenario that motivates the flag --------------------------------
    // Two devices start from the same ciphertext folder, go offline, and both create folder "FD0".
    for (bool deterministic : {true, false}) {
        o = fastOpts(); o.deterministicNames = deterministic;
        TmpDir t; std::string base = t.sub("base"), devA = t.sub("A"), devB = t.sub("B");
        CHECK(createAt(base, o).status == OpenStatus::Ok);
        copyTree(base, devA); copyTree(base, devB);
        { auto a = openAt(devA, "pw"); CHECK(a.status == OpenStatus::Ok); if (!a.vault) continue;
          CHECK(put(*a.vault, "F0", rnd(100, 1))); CHECK(a.vault->createDirectory("FD0")); CHECK(put(*a.vault, "FD0/FF0", rnd(5000, 2))); }
        { auto b = openAt(devB, "pw"); CHECK(b.status == OpenStatus::Ok); if (!b.vault) continue;
          CHECK(b.vault->createDirectory("FD0")); CHECK(put(*b.vault, "FD0/FF1", rnd(7000, 3))); }
        // the sync tool copies B's new files into A without overwriting anything A has
        std::string cmd = "cp -an '" + devB + "/.' '" + devA + "/'";
        if (system(cmd.c_str())) {}
        auto m = openAt(devA, "pw");
        CHECK(m.status == OpenStatus::Ok);
        if (!m.vault) continue;
        bool f0 = get(*m.vault, "F0") == rnd(100, 1);
        bool ff0 = get(*m.vault, "FD0/FF0") == rnd(5000, 2);
        bool ff1 = get(*m.vault, "FD0/FF1") == rnd(7000, 3);
        CHECK(f0 && ff0);
        if (deterministic) CHECK(ff1);          // both files are there: the folders were the same folder
        else CHECK(!ff1);                       // random diriv: B's file was encrypted under a diriv that lost
    }
}

// ---- plaintext-names listing rules (fusefrontend Readdirent) -------------------------
static void testGocryptfsPlaintextNamesRules() {
    std::puts("gocryptfs plaintext names: only the root config is special");
    GocryptfsCreateOptions o = fastOpts(); o.plaintextNames = true;
    TmpDir t; std::string d = t.sub("v");
    CHECK(createAt(d, o).status == OpenStatus::Ok);
    auto r = openAt(d, "pw");
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    Vault& v = *r.vault;
    const Bytes data(10, 'p');
    // names that mean something to gocryptfs with encrypted names are ordinary names here
    for (const char* n : {"data.name", "gocryptfs.diriv", "gocryptfs.longname.abc", "gocryptfs.longname.abc.name", "plain.txt"})
        CHECK(put(v, n, data));
    CHECK(v.createDirectory("sub"));
    CHECK(put(v, "sub/gocryptfs.conf", data));
    CHECK(put(v, "sub/gocryptfs.conf.bak", data));
    auto root = names(v, "");
    CHECK(has(v, "", "F:data.name") && has(v, "", "F:gocryptfs.diriv") && has(v, "", "F:gocryptfs.longname.abc") &&
          has(v, "", "F:gocryptfs.longname.abc.name") && has(v, "", "F:plain.txt") && has(v, "", "D:sub"));
    CHECK(!has(v, "", "F:gocryptfs.conf"));                                  // the real config stays hidden
    CHECK(has(v, "sub", "F:gocryptfs.conf") && has(v, "sub", "F:gocryptfs.conf.bak"));   // ... but only in the root
    auto g = get(v, "gocryptfs.longname.abc");
    CHECK(g.has_value() && *g == data);
    // the config cannot be reached, replaced, deleted or shadowed through the plaintext view
    const std::string before = slurp(d + "/gocryptfs.conf");
    CHECK(!put(v, "gocryptfs.conf", data));
    CHECK(!v.createDirectory("gocryptfs.conf"));
    CHECK(!v.renameFile("plain.txt", "gocryptfs.conf"));
    CHECK(!v.deleteFile("gocryptfs.conf"));
    CHECK(!get(v, "gocryptfs.conf").has_value());
    CHECK_EQ(v.getFileSize("gocryptfs.conf"), (int64_t)-1);
    CHECK_EQ(slurp(d + "/gocryptfs.conf"), before);
    // symlinks are neither listed nor addressable (gocryptfs stores them as symlinks; Android has none) -- even one
    // that resolves, which with plaintext names is the normal case -- but they are cleaned up with their folder
    std::filesystem::create_symlink("plain.txt", d + "/rel");
    std::filesystem::create_symlink("/no/such/target", d + "/dangling");
    std::filesystem::create_directory(d + "/real-dir");
    std::filesystem::create_symlink("real-dir", d + "/dir-link");
    spit(d + "/real-dir/inner", "x");
    std::filesystem::create_symlink("inner", d + "/real-dir/inner-link");
    CHECK(!has(v, "", "F:rel") && !has(v, "", "F:dangling") && !has(v, "", "D:dir-link") && !has(v, "", "F:dir-link"));
    CHECK(!get(v, "rel").has_value() && !get(v, "dir-link/inner").has_value());
    CHECK(has(v, "", "D:real-dir") && has(v, "real-dir", "F:inner") && !has(v, "real-dir", "F:inner-link"));
    const std::string plainBefore = slurp(d + "/plain.txt");
    CHECK(!put(v, "rel", Bytes(777, 'z')));              // not writable through the link either ...
    CHECK(!v.createDirectory("dir-link"));               // ... nor can a folder be made over a link to one
    CHECK_EQ(slurp(d + "/plain.txt"), plainBefore);      // and the link's target was left alone
    CHECK(get(v, "plain.txt") == data);
    CHECK(!hasPhys(d + "/real-dir", "gocryptfs.diriv"));
    CHECK(v.deleteFile("real-dir"));
    CHECK(!hasPhys(d, "real-dir"));
    // deleting an ordinary file whose name looks like a long-name file must not touch a sibling ".name" file
    CHECK(v.deleteFile("gocryptfs.longname.abc"));
    CHECK(has(v, "", "F:gocryptfs.longname.abc.name"));
    CHECK(hasPhys(d, "gocryptfs.longname.abc.name") && !hasPhys(d, "gocryptfs.longname.abc"));
    v.close();
}

// ---- diriv handling (nametransform.ReadDirIVAt) ----------------------------------------------
static void testGocryptfsDirivHandling() {
    std::puts("gocryptfs diriv: validation, re-read on listing, never invented");
    TmpDir t; std::string d = t.sub("v");
    CHECK(createAt(d, fastOpts()).status == OpenStatus::Ok);
    auto r = openAt(d, "pw");
    CHECK(r.status == OpenStatus::Ok);
    if (!r.vault) return;
    Vault& v = *r.vault;
    // deleting a cleartext path that does not exist must not touch gocryptfs' own files with the same *physical*
    // name (an earlier fallback compared physical and cleartext names and deleted the config)
    CHECK(!v.deleteFile("gocryptfs.conf"));
    CHECK(!v.deleteFile("gocryptfs.diriv"));
    CHECK(!v.deleteFile("gocryptfs.conf.bak"));
    CHECK(hasPhys(d, "gocryptfs.conf") && hasPhys(d, "gocryptfs.diriv"));
    CHECK(v.createDirectory("dir")); CHECK(put(v, "dir/file", rnd(100, 7)));
    std::string physDir;
    for (auto& n : physNames(d)) if (std::filesystem::is_directory(d + "/" + n)) physDir = n;
    const std::string dirivPath = d + "/" + physDir + "/gocryptfs.diriv";
    const std::string good = slurp(dirivPath);
    CHECK_EQ(good.size(), (size_t)16);
    std::vector<DirEntry> es;
    CHECK(v.listDirectory("dir", es) && es.size() == 1);

    // official: an all-zero IV is refused (it would silently make the folder deterministic)
    spit(dirivPath, std::string(16, '\0'));
    CHECK(!v.listDirectory("dir", es));
    // wrong length
    spit(dirivPath, good + "x");
    CHECK(!v.listDirectory("dir", es));
    spit(dirivPath, good.substr(0, 15));
    CHECK(!v.listDirectory("dir", es));
    // restored: the very next listing sees it again -- no manual invalidation needed
    spit(dirivPath, good);
    CHECK(v.listDirectory("dir", es) && es.size() == 1);
    // a different, valid IV (what a lost sync conflict leaves behind): the folder is readable but its names are not
    std::string other = good; other[0] ^= 0x55;
    spit(dirivPath, other);
    CHECK(v.listDirectory("dir", es) && es.empty());
    spit(dirivPath, good);
    CHECK(v.listDirectory("dir", es) && es.size() == 1);
    CHECK(get(v, "dir/file") == rnd(100, 7));

    // an existing folder without a diriv is reported, never "repaired" with a made-up one
    std::filesystem::remove(dirivPath);
    v.invalidateCache("");
    CHECK(!v.createDirectory("dir"));
    CHECK(!hasPhys(d + "/" + physDir, "gocryptfs.diriv"));
    spit(dirivPath, good);
    CHECK(v.createDirectory("dir"));
    CHECK_EQ(slurp(dirivPath), good);

    // pull-to-refresh on a sub folder picks up a diriv that changed behind our back -- for listings (which always
    // re-read it) *and* for lookups such as opening a file, which otherwise go by the cached IV like gocryptfs'
    // own dircache does until it expires
    CHECK(get(v, "dir/file") == rnd(100, 7));              // (primes the cached IV)
    spit(dirivPath, other);
    v.invalidateCache("dir");
    CHECK(!get(v, "dir/file").has_value());                // looked up under the new IV: not there (before any listing refreshes the cache)
    CHECK(v.listDirectory("dir", es) && es.empty());
    spit(dirivPath, good);
    v.invalidateCache("dir");
    CHECK(get(v, "dir/file") == rnd(100, 7));
    CHECK(v.listDirectory("dir", es) && es.size() == 1);

    // a file replaced from outside (a sync tool renames the new version over the old one) shows its new content
    // once its folder is refreshed -- the cached read handle of a file below the folder must not survive that
    CHECK(put(v, "dir/other", rnd(5000, 8)));
    {
        std::string physFile, physOther;
        for (auto& n : physNames(d + "/" + physDir)) {
            if (n == "gocryptfs.diriv") continue;
            (std::filesystem::file_size(d + "/" + physDir + "/" + n) < 1000 ? physFile : physOther) = d + "/" + physDir + "/" + n;
        }
        CHECK(!physFile.empty() && !physOther.empty());
        CHECK(get(v, "dir/file") == rnd(100, 7));                  // opens (and caches) a read handle
        spit(physFile + ".incoming", slurp(physOther));
        std::filesystem::rename(physFile + ".incoming", physFile);
        v.invalidateCache("dir");
        CHECK(get(v, "dir/file") == rnd(5000, 8));
        CHECK_EQ(v.getFileSize("dir/file"), (int64_t)5000);
    }

    // every folder the app creates has a valid, non-zero, 16-byte diriv
    for (int i = 0; i < 20; i++) CHECK(v.createDirectory("n" + std::to_string(i)));
    for (auto& n : physNames(d)) {
        if (!std::filesystem::is_directory(d + "/" + n)) continue;
        std::string iv = slurp(d + "/" + n + "/gocryptfs.diriv");
        CHECK(iv.size() == 16 && iv != std::string(16, '\0'));
    }
    v.close();
}

// ---- file header (contentenc.ParseHeader) -----------------------------------------------------
static void testGocryptfsFileHeaderRules() {
    std::puts("gocryptfs file header: all-zero header / file id are corruption");
    TmpDir t; std::string d = t.sub("v");
    CHECK(createAt(d, fastOpts()).status == OpenStatus::Ok);
    auto r = openAt(d, "pw");
    if (r.status != OpenStatus::Ok) { CHECK(false); return; }
    Vault& v = *r.vault;
    CHECK(put(v, "f", rnd(9000, 5)));
    std::string phys;
    for (auto& n : physNames(d)) if (n != "gocryptfs.conf" && n != "gocryptfs.diriv") phys = d + "/" + n;
    const std::string orig = slurp(phys);
    CHECK(orig.size() > 18);
    CHECK(get(v, "f") == rnd(9000, 5));
    auto patched = [&](size_t off, size_t len) { std::string s = orig; for (size_t i = 0; i < len; i++) s[off + i] = '\0'; return s; };
    spit(phys, patched(0, 18));        v.invalidateCache("");  CHECK(!get(v, "f").has_value());   // all-zero header
    spit(phys, patched(2, 16));        v.invalidateCache("");  CHECK(!get(v, "f").has_value());   // all-zero file id
    std::string badVer = orig; badVer[1] = 3;
    spit(phys, badVer);                v.invalidateCache("");  CHECK(!get(v, "f").has_value());   // unknown version
    spit(phys, orig);                  v.invalidateCache("");  CHECK(get(v, "f") == rnd(9000, 5));
    // a header-only file is an empty file (fusefrontend readFileID)
    spit(phys, orig.substr(0, 18));    v.invalidateCache("");
    auto e = get(v, "f"); CHECK(e.has_value() && e->empty());

    // A file that is *validly encrypted under an all-zero file id* is refused as well (ParseHeader): the id is what
    // ties a block to its file, so a zero one must not be allowed to authenticate. (Zeroing the id of a real file,
    // as above, fails authentication anyway; this builds a file that would otherwise decrypt.)
    {
        Bytes contentKey;
        for (auto& f : v.exportKeys().fields) if (f.first == "contentKey") contentKey = f.second;
        gocryptfs::ContentFormat fmt(Secret(contentKey), GocryptfsCipher::Aes256Gcm);
        const Bytes pt = rnd(100, 9);
        uint8_t nonce[16]; std::memset(nonce, 0x42, sizeof nonce);
        auto craft = [&](uint8_t idByte) {
            uint8_t id[16]; std::memset(id, idByte, sizeof id);
            Bytes ct(16 + pt.size() + 16);
            fmt.sealChunk(id, 0, nonce, pt.data(), pt.size(), ct.data());
            std::string file("\x00\x02", 2);
            file.append((const char*)id, 16);
            file.append((const char*)ct.data(), ct.size());
            return file;
        };
        spit(phys, craft(0x07)); v.invalidateCache("");
        CHECK(get(v, "f") == pt);                                    // control: the construction is right
        spit(phys, craft(0x00)); v.invalidateCache("");
        CHECK(!get(v, "f").has_value());                             // the same with an all-zero id is not
    }
    v.close();
}

// A storage whose directory listings do not know file sizes (some document providers report 0): limits that
// gocryptfs applies to what it *reads* must not depend on the listing.
struct BlindSizeStorage : PosixStorage {
    using PosixStorage::PosixStorage;
    bool list(const std::string& dir, std::vector<DirEntry>& out) override {
        bool ok = PosixStorage::list(dir, out);
        for (auto& e : out) e.size = 0;
        return ok;
    }
};

// Fault injection: lets a test make one kind of storage operation fail.
struct FaultStorage : PosixStorage {
    using PosixStorage::PosixStorage;
    bool failDiriv = false, failRename = false, failCreate = false, failMkdir = false;
    bool writeWhole(const std::string& p, const uint8_t* d, size_t n) override {
        const std::string tail = "gocryptfs.diriv";
        if (failDiriv && p.size() >= tail.size() && p.compare(p.size() - tail.size(), tail.size(), tail) == 0) return false;
        return PosixStorage::writeWhole(p, d, n);
    }
    bool rename(const std::string& a, const std::string& b) override { return failRename ? false : PosixStorage::rename(a, b); }
    bool createFile(const std::string& p) override { return failCreate ? false : PosixStorage::createFile(p); }
    bool mkdir(const std::string& p) override { return failMkdir ? false : PosixStorage::mkdir(p); }
};

// gocryptfs undoes the steps of a failed Mkdir / Create / Rename (long-name sidecar, directory, diriv).
static void testGocryptfsFailureRollback() {
    std::puts("gocryptfs: a failed mkdir / create / rename leaves nothing behind");
    TmpDir t; std::string d = t.sub("v");
    GocryptfsCreateOptions o = fastOpts(); o.longNameMax = 100;      // 100-byte names are hashed
    CHECK(createAt(d, o).status == OpenStatus::Ok);
    auto st = std::make_shared<FaultStorage>(d);
    auto r = openGocryptfs(st, (const uint8_t*)"pw", 2, false, {});
    if (r.status != OpenStatus::Ok) { CHECK(false); return; }
    Vault& v = *r.vault;
    const auto before = physNames(d);

    st->failDiriv = true;                                            // the folder is made but its diriv cannot be
    CHECK(!v.createDirectory("short"));
    CHECK(!v.createDirectory(repeatc('D', 100)));                    // ... and for a hashed name the sidecar must go too
    CHECK(physNames(d) == before);
    st->failDiriv = false;
    CHECK(v.createDirectory("short"));                               // nothing stale blocks a retry
    CHECK(v.deleteFile("short"));

    st->failMkdir = true;                                            // the sidecar is written, the directory cannot be made
    CHECK(!v.createDirectory(repeatc('D', 100)));
    CHECK(physNames(d) == before);
    st->failMkdir = false;

    st->failCreate = true;                                           // the sidecar is written, the file cannot be created
    CHECK(!put(v, repeatc('F', 100), rnd(10, 1)));
    CHECK(physNames(d) == before);
    st->failCreate = false;

    CHECK(put(v, "orig", rnd(10, 2)));
    const auto mid = physNames(d);
    st->failRename = true;                                           // the new sidecar is written, the rename fails
    CHECK(!v.renameFile("orig", repeatc('R', 100)));
    CHECK(physNames(d) == mid);
    CHECK(get(v, "orig") == rnd(10, 2));
    st->failRename = false;
    CHECK(v.renameFile("orig", repeatc('R', 100)));
    CHECK(get(v, repeatc('R', 100)) == rnd(10, 2));
    v.close();
}

// ---- long-name sidecars (nametransform.ReadLongNameAt) -----------------------------------------
static void testGocryptfsLongNameFiles() {
    std::puts("gocryptfs long names: sidecar limits, creation order, cleanup");
    TmpDir t; std::string d = t.sub("v");
    GocryptfsCreateOptions o = fastOpts(); o.longNameMax = 100;
    CHECK(createAt(d, o).status == OpenStatus::Ok);
    auto r = openAt(d, "pw");
    if (r.status != OpenStatus::Ok) { CHECK(false); return; }
    Vault& v = *r.vault;
    CHECK(infoInt(v, "longNameMax") == 100);
    auto longCount = [&](const std::string& dir) {
        int n = 0; for (auto& p : physNames(dir)) if (gocryptfs::NameCryptor::isLongNameContent(p)) n++; return n;
    };
    auto sidecarCount = [&](const std::string& dir) {
        int n = 0; for (auto& p : physNames(dir)) if (gocryptfs::NameCryptor::isLongNameFile(p)) n++; return n;
    };
    // 63-byte names encrypt to 86 base64 chars (<= 100); 64 bytes pad to 80 -> 107 chars (> 100): hashed
    CHECK(put(v, repeatc('s', 63), rnd(10, 1)));
    CHECK_EQ(longCount(d), 0);
    CHECK(put(v, repeatc('l', 64), rnd(10, 2)));
    CHECK_EQ(longCount(d), 1); CHECK_EQ(sidecarCount(d), 1);
    CHECK(v.createDirectory(repeatc('d', 100)));
    CHECK_EQ(longCount(d), 2); CHECK_EQ(sidecarCount(d), 2);
    CHECK(put(v, repeatc('d', 100) + "/inner", rnd(10, 3)));
    CHECK(get(v, repeatc('l', 64)) == rnd(10, 2) && get(v, repeatc('s', 63)) == rnd(10, 1));
    // short -> long -> short renames keep exactly one sidecar per long entry
    CHECK(v.renameFile(repeatc('s', 63), repeatc('S', 80)));
    CHECK_EQ(longCount(d), 3); CHECK_EQ(sidecarCount(d), 3);
    CHECK(v.renameFile(repeatc('S', 80), "short"));
    CHECK_EQ(longCount(d), 2); CHECK_EQ(sidecarCount(d), 2);
    CHECK(v.renameFile(repeatc('l', 64), repeatc('m', 64)));
    CHECK_EQ(longCount(d), 2); CHECK_EQ(sidecarCount(d), 2);
    CHECK(get(v, repeatc('m', 64)) == rnd(10, 2) && !get(v, repeatc('l', 64)).has_value());
    // sidecar limits: empty or larger than 344 bytes => gocryptfs does not list the entry
    std::string sc; for (auto& p : physNames(d)) if (gocryptfs::NameCryptor::isLongNameFile(p)) { sc = d + "/" + p; break; }
    CHECK(!sc.empty());
    const std::string scOrig = slurp(sc);
    spit(sc, "");                      size_t visibleEmpty = names(v, "").size();
    spit(sc, repeatc('A', 345));       size_t visibleBig = names(v, "").size();
    spit(sc, scOrig);                  size_t visibleOk = names(v, "").size();
    CHECK(visibleEmpty < visibleOk); CHECK(visibleBig < visibleOk);
    {   // the same limit, enforced after reading when the listing cannot say how big the file is
        auto blind = openGocryptfs(std::make_shared<BlindSizeStorage>(d), (const uint8_t*)"pw", 2, false, {});
        if (blind.status != OpenStatus::Ok) { CHECK(false); }
        else {
            CHECK_EQ(names(*blind.vault, "").size(), visibleOk);
            spit(sc, repeatc('A', 345));
            CHECK(names(*blind.vault, "").size() < visibleOk);
            spit(sc, scOrig);
            CHECK_EQ(names(*blind.vault, "").size(), visibleOk);
            blind.vault->close();
        }
    }
    // deleting removes sidecars too: nothing is left behind
    for (auto& n : names(v, "")) CHECK(v.deleteFile(n.substr(2)));
    CHECK_EQ(longCount(d), 0); CHECK_EQ(sidecarCount(d), 0);
    v.close();
}

// ---- names that used to be hidden, and names that must stay out --------------------------------
static void testGocryptfsUnusualNames() {
    std::puts("gocryptfs unusual names: newline, CR, U+FFFD, 255 bytes, dots");
    TmpDir t; std::string d = t.sub("v");
    CHECK(createAt(d, fastOpts()).status == OpenStatus::Ok);
    auto r = openAt(d, "pw");
    if (r.status != OpenStatus::Ok) { CHECK(false); return; }
    Vault& v = *r.vault;
    const std::vector<std::string> odd = {"nl\nname", "cr\rname", "repl-" "\xEF\xBF\xBD" "-char", " lead-trail ", repeatc('m', 255),
                                          "tab\tname", "...", "gocryptfs.conf", "gocryptfs.diriv", "x.name"};
    int i = 0;
    for (auto& n : odd) {
        CHECK(put(v, n, rnd(50 + i, 100 + i)));
        i++;
    }
    v.close();
    auto r2 = openAt(d, "pw");
    if (r2.status != OpenStatus::Ok) { CHECK(false); return; }
    i = 0;
    for (auto& n : odd) {
        CHECK(has(*r2.vault, "", "F:" + n));
        CHECK(get(*r2.vault, n) == rnd(50 + i, 100 + i));
        i++;
    }
    CHECK(!put(*r2.vault, repeatc('x', 256), rnd(10, 1)));      // longer than NameMax: gocryptfs cannot store it
    CHECK(!r2.vault->createDirectory(repeatc('y', 256)));
    CHECK(!r2.vault->renameFile("...", repeatc('z', 256)));
    CHECK(has(*r2.vault, "", "F:..."));
    r2.vault->close();
}

// ---- legacy vaults: HKDF-less masterkey and key derivation --------------------------------------
static void testGocryptfsLegacyKeys() {
    std::puts("gocryptfs without HKDF: key wrap and key derivation");
    gocryptfs::Config c = gocryptfs::Config::parse(gcCfg("\"GCMIV128\",\"DirIV\",\"EMENames\""));
    Secret mk{Bytes(32, 0x07)};
    auto k = gocryptfs::deriveSessionKeys(c, mk);
    CHECK(k.nameKey.bytes() == mk.bytes() && k.contentKey.bytes() == mk.bytes());          // used as-is
    c = gocryptfs::Config::parse(gcCfg("\"GCMIV128\",\"DirIV\",\"EMENames\",\"AESSIV\""));
    k = gocryptfs::deriveSessionKeys(c, mk);
    CHECK(k.nameKey.bytes() == mk.bytes());
    CHECK_EQ(hexs(k.contentKey.bytes()), hexs(crypto::hash(crypto::Md::Sha512, mk.data(), mk.size())));   // SHA-512(masterkey)
    c = gocryptfs::Config::parse(gcCfg("\"HKDF\",\"GCMIV128\",\"DirIV\",\"EMENames\""));
    k = gocryptfs::deriveSessionKeys(c, mk);
    CHECK_EQ(hexs(k.nameKey.bytes()), hexs(crypto::hkdfSha256(mk.data(), 32, "EME filename encryption", 32).bytes()));
    CHECK_EQ(hexs(k.contentKey.bytes()), hexs(crypto::hkdfSha256(mk.data(), 32, "AES-GCM file content encryption", 32).bytes()));
    // wrap / unwrap round trips for both nonce sizes; the blob sizes are what gocryptfs expects
    for (bool hkdf : {true, false}) {
        Bytes salt(32, 0x33);
        gocryptfs::Config cc;
        cc.version = 2; cc.scryptSalt = salt; cc.scryptN = 1024; cc.scryptR = 8; cc.scryptP = 1; cc.scryptKeyLen = 32;
        cc.featureFlags = hkdf ? std::vector<std::string>{"HKDF", "GCMIV128", "DirIV", "EMENames"} : std::vector<std::string>{"GCMIV128", "DirIV", "EMENames"};
        cc.encryptedKey = gocryptfs::wrapMasterkey(mk, (const uint8_t*)"pw", 2, salt, 1024, 8, 1, 32, hkdf);
        CHECK_EQ(cc.encryptedKey.size(), (size_t)(hkdf ? 64 : 60));
        CHECK(gocryptfs::unlockMasterkey(cc, (const uint8_t*)"pw", 2).bytes() == mk.bytes());
        bool wrong = false;
        try { gocryptfs::unlockMasterkey(cc, (const uint8_t*)"px", 2); } catch (const Error& e) { wrong = e.code() == Err::WrongPassword; }
        CHECK(wrong);
        // unwrapping with the other scheme must fail, not return garbage
        gocryptfs::Config other = cc;
        other.featureFlags = hkdf ? std::vector<std::string>{"GCMIV128", "DirIV", "EMENames"} : std::vector<std::string>{"HKDF", "GCMIV128", "DirIV", "EMENames"};
        bool failed = false;
        try { gocryptfs::unlockMasterkey(other, (const uint8_t*)"pw", 2); } catch (const Error&) { failed = true; }
        CHECK(failed);
    }
    // FIDO2 vaults need a hardware token: refuse with a clear error rather than "wrong password"
    c = gocryptfs::Config::parse(gcCfg("\"HKDF\",\"GCMIV128\",\"DirIV\",\"EMENames\",\"FIDO2\""));
    bool unsupported = false;
    try { gocryptfs::unlockMasterkey(c, (const uint8_t*)"pw", 2); } catch (const Error& e) { unsupported = e.code() == Err::Unsupported; }
    CHECK(unsupported);
    // a master key that is not 32 bytes is corruption (gocryptfs panics on it)
    {
        Bytes salt(32, 0x44);
        gocryptfs::Config cc;
        cc.version = 2; cc.scryptSalt = salt; cc.scryptN = 1024; cc.scryptR = 8; cc.scryptP = 1; cc.scryptKeyLen = 32;
        cc.featureFlags = {"HKDF", "GCMIV128", "DirIV", "EMENames"};
        cc.encryptedKey = gocryptfs::wrapMasterkey(Secret(Bytes(31, 1)), (const uint8_t*)"pw", 2, salt, 1024, 8, 1, 32, true);
        bool bad = false;
        try { gocryptfs::unlockMasterkey(cc, (const uint8_t*)"pw", 2); } catch (const Error& e) { bad = e.code() == Err::InvalidVault; }
        CHECK(bad);
    }
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
        testGocryptfsConfigRules();
        testGocryptfsNameRules();
        testGocryptfsLegacyKeys();
        testGocryptfsOfficialVectors();
        testGocryptfsCreateOptions();
        testGocryptfsPlaintextNamesRules();
        testGocryptfsDirivHandling();
        testGocryptfsFileHeaderRules();
        testGocryptfsLongNameFiles();
        testGocryptfsFailureRollback();
        testGocryptfsUnusualNames();
    }
    if (want("cryptomator")) { testCryptomator(false); testCryptomator(true); testCryptomatorCompat(); testCryptomatorSymlinks(); testCryptomatorBackups(); testCryptomatorMigration(); }
    if (want("cryfs")) { testCryfs("xchacha20-poly1305", 32768); testCryfs("aes-256-gcm", 4096); testCryfs("aes-256-cfb", 8192); }
    if (want("concurrency")) { testConcurrency("gocryptfs"); testConcurrency("cryptomator"); testConcurrency("cryfs"); }
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
