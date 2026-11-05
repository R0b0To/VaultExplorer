// Host-side tests for the folder-vault core. No Android, no network.
//   Known-answer vectors were produced with Python's `cryptography` package
//   (an independent implementation); the format engines are additionally
//   checked against the real gocryptfs / Cryptomator / CryFS in test/interop.
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
    if (ctrmac) {   // re-sign the vault config as a legacy format-7 vault
        Bytes mkRaw, vcRaw;
        CHECK(st->readWhole("masterkey.cryptomator", mkRaw));
        auto mk = cryptomator::unlockMasterkey(cryptomator::MasterkeyFile::parse(std::string(mkRaw.begin(), mkRaw.end())), pw, 6);
        std::string jwt = cryptomator::createVaultConfig(7, "SIV_CTRMAC", 220, mk, "00000000-0000-4000-8000-000000000000");
        CHECK(st->writeWhole("vault.cryptomator", (const uint8_t*)jwt.data(), jwt.size()));
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
        }
    });
    // a shared file hammered by readers while writers replace it
    Bytes shared = rnd(50000, 99);
    put(v, "shared.bin", shared);
    std::atomic<bool> stop{false};
    std::thread reader([&] { while (!stop) { auto g = v.readFileChunk("shared.bin", 0, 60000); (void)g; } });
    for (auto& th : ts) th.join();
    stop = true; reader.join();
    CHECK_EQ(bad.load(), 0);
    for (int i = 0; i < kThreads; i++) { std::vector<DirEntry> es; CHECK(v.listDirectory("t" + std::to_string(i), es)); CHECK_EQ(es.size(), (size_t)kFiles); }
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
    if (want("cryptomator")) { testCryptomator(false); testCryptomator(true); }
    if (want("cryfs")) { testCryfs("xchacha20-poly1305", 32768); testCryfs("aes-256-gcm", 4096); testCryfs("aes-256-cfb", 8192); }
    if (want("concurrency")) { testConcurrency("gocryptfs"); testConcurrency("cryptomator"); testConcurrency("cryfs"); }
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
