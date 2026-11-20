// Host-side tests for the transfer helpers (hashing, split/join). No Android, no network.
// Hash vectors were produced with Python's hashlib; the Kotlin tests of the handlers this
// replaces on other platforms (guessFormat, algorithm names, toHex) are carried over.
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <random>
#include <set>
#include <sstream>
#include <unistd.h>

#include "../xfer_hash.h"
#include "../xfer_host.h"
#include "../xfer_io.h"
#include "../xfer_split.h"

using namespace xfer;
namespace fs = std::filesystem;

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { g_checks++; if (!((a) == (b))) { g_failed++; std::printf("  FAIL %s:%d  %s == %s\n", __FILE__, __LINE__, #a, #b); } } while (0)

using Bytes = std::vector<uint8_t>;
static Bytes rnd(size_t n, uint32_t seed = 1) { std::mt19937 g(seed); Bytes b(n); for (auto& x : b) x = static_cast<uint8_t>(g()); return b; }
static Bytes bytesOf(const std::string& s) { return Bytes(s.begin(), s.end()); }

struct BytesSource final : ByteSource {
    const Bytes& d; size_t pos = 0;
    int64_t failAfter = -1;          // fail once this many bytes were delivered
    size_t maxPerRead = SIZE_MAX;    // trickle
    explicit BytesSource(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override {
        if (failAfter >= 0 && static_cast<int64_t>(pos) >= failAfter) return -1;
        size_t k = std::min({n, d.size() - pos, maxPerRead});
        if (k) std::memcpy(buf, d.data() + pos, k);
        pos += k;
        return static_cast<int64_t>(k);
    }
};

struct Obs final : Observer {
    uint64_t lastDone = 0, lastTotal = 0; int calls = 0; bool monotone = true;
    int64_t cancelAfter = -1;
    void onProgress(uint64_t d, uint64_t t) override { if (d < lastDone) monotone = false; lastDone = d; lastTotal = t; ++calls; }
    bool cancelled() override { return cancelAfter >= 0 && static_cast<int64_t>(lastDone) >= cancelAfter; }
};

static std::string hexOf(const std::vector<Digest>& ds, HashAlgo a) {
    for (auto& d : ds) if (d.algo == a) return d.hex();
    return "<missing>";
}

// ------------------------------------------------------------------ hashing --

static void testHashVectors() {
    std::printf("hash known answers\n");
    struct V { const char* name; Bytes data; const char* md5; const char* sha1; const char* sha256; const char* sha512; };
    std::vector<V> vs = {
        {"empty", {}, "d41d8cd98f00b204e9800998ecf8427e", "da39a3ee5e6b4b0d3255bfef95601890afd80709",
         "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
         "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"},
        {"abc", bytesOf("abc"), "900150983cd24fb0d6963f7d28e17f72", "a9993e364706816aba3e25717850c26c9cd0d89d",
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
         "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"},
        {"fox", bytesOf("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6",
         "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
         "07e547d9586f6a73f73fbac0435ed76951218fb7d0c8d788a309d785436bbb642e93a252a954f23912547d1e8a3b5ed6e1bfd7097821233fa0538f3db854fee6"},
        {"million a", Bytes(1000000, 'a'), "7707d6ae4e027c70eea2a935c2296f21", "34aa973cd4c4daa4f61eeb2bdbad27316534016f",
         "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
         "e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973ebde0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b"},
    };
    const std::vector<HashAlgo> all = {HashAlgo::Md5, HashAlgo::Sha1, HashAlgo::Sha256, HashAlgo::Sha512};
    for (auto& v : vs) {
        BytesSource src(v.data);
        std::vector<Digest> out;
        CHECK(hashStream(src, all, v.data.size(), nullptr, out) == Result::Ok);
        CHECK_EQ(out.size(), 4u);
        CHECK_EQ(hexOf(out, HashAlgo::Md5), std::string(v.md5));
        CHECK_EQ(hexOf(out, HashAlgo::Sha1), std::string(v.sha1));
        CHECK_EQ(hexOf(out, HashAlgo::Sha256), std::string(v.sha256));
        CHECK_EQ(hexOf(out, HashAlgo::Sha512), std::string(v.sha512));
        CHECK_EQ(out[0].bytes.size(), 16u); CHECK_EQ(out[1].bytes.size(), 20u);
        CHECK_EQ(out[2].bytes.size(), 32u); CHECK_EQ(out[3].bytes.size(), 64u);

        // one algorithm alone gives the same digest as in a four-way pass
        BytesSource again(v.data);
        std::vector<Digest> one;
        CHECK(hashStream(again, {HashAlgo::Sha256}, 0, nullptr, one) == Result::Ok);
        CHECK(one.size() == 1 && one[0].hex() == v.sha256);

        // trickled in odd pieces, and one byte at a time, gives the same digests
        BytesSource slow(v.data); slow.maxPerRead = 7;
        std::vector<Digest> o2;
        CHECK(hashStream(slow, all, 0, nullptr, o2) == Result::Ok && hexOf(o2, HashAlgo::Sha512) == v.sha512);
        if (v.data.size() <= 100) {
            MultiHasher mh(all);
            for (uint8_t b : v.data) mh.update(&b, 1);
            auto d = mh.finish();
            CHECK(d.size() == 4 && d[0].hex() == v.md5 && d[3].hex() == v.sha512);
        }
    }
}

static void testHashApi() {
    std::printf("hash api\n");
    HashAlgo a;
    CHECK(parseHashAlgo("MD5", a) && a == HashAlgo::Md5);
    CHECK(parseHashAlgo("SHA-1", a) && a == HashAlgo::Sha1);
    CHECK(parseHashAlgo("SHA-256", a) && a == HashAlgo::Sha256);
    CHECK(parseHashAlgo("SHA-512", a) && a == HashAlgo::Sha512);
    for (const char* bad : {"md5", "SHA256", "SHA-384", "", "SHA-1 ", "sha-1", "CRC32"}) CHECK(!parseHashAlgo(bad, a));
    CHECK_EQ(std::string(hashWireName(HashAlgo::Sha1)), std::string("SHA-1"));
    CHECK_EQ(std::string(hashWireName(HashAlgo::Sha512)), std::string("SHA-512"));

    const uint8_t raw[] = {0x00, 0x0a, 0x80, 0xff, 0x7f, 0xde, 0xad, 0xbe, 0xef};   // the Kotlin toHex test
    CHECK_EQ(toHex(raw, sizeof raw), std::string("000a80ff7fdeadbeef"));
    CHECK_EQ(toHex(raw, 0), std::string(""));

    // duplicates collapse, request order is kept
    MultiHasher mh({HashAlgo::Sha256, HashAlgo::Md5, HashAlgo::Sha256});
    CHECK(mh.ok());
    mh.update(reinterpret_cast<const uint8_t*>("abc"), 3);
    auto d = mh.finish();
    CHECK(d.size() == 2 && d[0].algo == HashAlgo::Sha256 && d[1].algo == HashAlgo::Md5);
    CHECK(mh.finish().empty());                          // finished once
    mh.update(reinterpret_cast<const uint8_t*>("x"), 1); // ignored, no crash

    // progress, cancel, errors
    const Bytes data = rnd(3 * 1024 * 1024 + 5, 3);
    BytesSource s1(data); Obs o1; std::vector<Digest> out;
    CHECK(hashStream(s1, {HashAlgo::Sha256}, data.size(), &o1, out) == Result::Ok);
    CHECK(o1.monotone && o1.lastDone == data.size() && o1.lastTotal == data.size() && o1.calls >= 3);
    BytesSource s2(data); Obs o2; o2.cancelAfter = 1;
    CHECK(hashStream(s2, {HashAlgo::Sha256}, 0, &o2, out) == Result::Cancelled);
    CHECK(out.empty());
    BytesSource s3(data); s3.failAfter = 1024 * 1024;
    CHECK(hashStream(s3, {HashAlgo::Md5}, 0, nullptr, out) == Result::Failed);
    CHECK(out.empty());
    BytesSource s4(data);
    CHECK(hashStream(s4, {}, 0, nullptr, out) == Result::Ok && out.empty());
}

// ------------------------------------------------------------ names & manifest --

static void testNames() {
    std::printf("part names, sequence resolution, format, manifest\n");
    CHECK_EQ(partName("a.hc", 1), std::string("a.hc.001"));
    CHECK_EQ(partName("a.hc", 12), std::string("a.hc.012"));
    CHECK_EQ(partName("a.hc", 123), std::string("a.hc.123"));
    CHECK_EQ(partName("a.hc", 1000), std::string("a.hc.1000"));

    auto resolve = [](const std::string& first, std::set<std::string> existing) {
        return resolvePartSequence(first, [&](const std::string& n) { return existing.count(n) > 0; });
    };
    using V = std::vector<std::string>;
    CHECK((resolve("disk", {"disk"}) == V{"disk"}));                                  // no dot
    CHECK((resolve("disk.img", {"disk.img", "disk.img.001"}) == V{"disk.img"}));      // not a part suffix
    CHECK((resolve("disk.img.002", {"disk.img.001", "disk.img.002", "disk.img.003"}) ==
           V{"disk.img.001", "disk.img.002", "disk.img.003"}));                       // starts at 1 whichever was picked
    CHECK((resolve("disk.img.001", {"disk.img.001", "disk.img.002", "disk.img.004"}) ==
           V{"disk.img.001", "disk.img.002"}));                                       // stops at the first gap
    CHECK((resolve("disk.img.002", {"disk.img.002", "disk.img.003"}) == V{"disk.img.002"}));   // part 1 missing: just the pick
    CHECK((resolve("x.0001", {"x.0001", "x.0002", "x.001"}) == V{"x.0001", "x.0002"}));        // keeps the picked width
    CHECK((resolve("x.1", {"x.1", "x.2", "x.3"}) == V{"x.1", "x.2", "x.3"}));
    std::set<std::string> nine; for (int i = 1; i <= 12; ++i) nine.insert("x." + std::to_string(i));
    CHECK_EQ(resolve("x.1", nine).size(), 12u);                                       // width 1 grows past 9
    CHECK((resolve("x.part2", {"x.part1", "x.part2", "x.part3"}) == V{"x.part1", "x.part2", "x.part3"}));
    CHECK((resolve("x.PART2", {"x.part1", "x.part2"}) == V{"x.part1", "x.part2"}));   // looked up as lower-case ".partN"
    CHECK((resolve("x.PART1", {"x.PART1"}) == V{"x.PART1"}));                         // ...so an upper-case-only set is just the pick
    CHECK((resolve("x.part", {"x.part", "x.part1"}) == V{"x.part"}));                 // ".part" alone is no part suffix
    CHECK((resolve("x.part1x", {"x.part1x"}) == V{"x.part1x"}));
    CHECK((resolve("a.b.c.001", {"a.b.c.001", "a.b.c.002"}) == V{"a.b.c.001", "a.b.c.002"}));
    CHECK((resolve(".001", {".001", ".002"}) == V{".001", ".002"}));                  // empty base still matches

    // guessFormat: the cases of the Kotlin SplitJoinHandlersGuessFormatTest
    CHECK_EQ(guessFormat("backup.luks.img"), std::string("LUKS"));
    CHECK_EQ(guessFormat("BACKUP.LUKS.IMG"), std::string("LUKS"));
    CHECK_EQ(guessFormat("Windows-BitLocker-Drive.vhd"), std::string("BITLOCKER"));
    CHECK_EQ(guessFormat("my_container.hc"), std::string("VERACRYPT"));
    CHECK_EQ(guessFormat(""), std::string("VERACRYPT"));
    CHECK_EQ(guessFormat("luks-bitlocker"), std::string("LUKS"));                     // first match wins, as in the handler

    CHECK_EQ(manifestJson("c.hc", "VERACRYPT", 10, 4),
             std::string("{\"displayName\":\"c.hc\",\"format\":\"VERACRYPT\",\"totalSizeBytes\":10,\"chunkSizeBytes\":4}"));
    CHECK_EQ(manifestJson("a\"b\\c\nd\te\x01", "X", 0, 0),
             std::string("{\"displayName\":\"a\\\"b\\\\c\\nd\\te\\u0001\",\"format\":\"X\",\"totalSizeBytes\":0,\"chunkSizeBytes\":0}"));
    CHECK(manifestJson("d\xc3\xa4t\xc3\xa4", "X", 18446744073709551615ULL, 1).find("d\xc3\xa4t\xc3\xa4") != std::string::npos);
    CHECK(manifestJson("n", "X", 18446744073709551615ULL, 1).find("18446744073709551615") != std::string::npos);
}

// --------------------------------------------------------- stream split / join --

struct MemParts {
    std::map<int, Bytes> data;
    std::set<int> closed, discarded;
    int opened = 0;
    int failWriteInPart = -1, failCloseOfPart = -1, failOpenOfPart = -1;
};

struct MemSink final : ByteSink {
    MemParts& p; int idx;
    MemSink(MemParts& parts, int i) : p(parts), idx(i) {}
    bool write(const uint8_t* d, size_t n) override {
        if (p.failWriteInPart == idx) return false;
        p.data[idx].insert(p.data[idx].end(), d, d + n); return true;
    }
    bool close() override { if (p.failCloseOfPart == idx) return false; p.closed.insert(idx); return true; }
    void discard() override { if (!p.closed.count(idx)) { p.discarded.insert(idx); p.data.erase(idx); } }
};
static PartOpener opener(MemParts& p) {
    return [&p](int i) -> std::unique_ptr<ByteSink> {
        ++p.opened;
        if (p.failOpenOfPart == i) return nullptr;
        p.data[i];
        return std::make_unique<MemSink>(p, i);
    };
}
static size_t partSize(MemParts& p, int i) { return p.data.count(i) ? p.data[i].size() : size_t(-1); }

struct VecSink final : ByteSink {
    Bytes data; bool closedOk = false, discarded = false; bool failWrite = false, failClose = false;
    bool write(const uint8_t* d, size_t n) override { if (failWrite) return false; data.insert(data.end(), d, d + n); return true; }
    bool close() override { if (failClose) return false; closedOk = true; return true; }
    void discard() override { discarded = true; }
};

static void testSplitStream() {
    std::printf("split stream\n");
    std::string err; int parts = 0;
    {   // 10 bytes in parts of 4: 4 + 4 + 2
        Bytes d = rnd(10, 1); BytesSource s(d); MemParts p; Obs o;
        CHECK(splitStream(s, d.size(), 4, opener(p), &o, &parts, &err) == Result::Ok);
        CHECK_EQ(parts, 3);
        CHECK(partSize(p, 1) == 4 && partSize(p, 2) == 4 && partSize(p, 3) == 2);
        CHECK((p.closed == std::set<int>{1, 2, 3}) && p.discarded.empty());
        Bytes all; for (int i = 1; i <= 3; ++i) all.insert(all.end(), p.data[i].begin(), p.data[i].end());
        CHECK(all == d);
        CHECK(o.monotone && o.lastDone == 10 && o.lastTotal == 10);
    }
    {   // an exact multiple never opens an empty trailing part
        Bytes d = rnd(8, 2); BytesSource s(d); MemParts p;
        CHECK(splitStream(s, d.size(), 4, opener(p), nullptr, &parts, nullptr) == Result::Ok);
        CHECK_EQ(parts, 2); CHECK_EQ(p.opened, 2);
        CHECK(partSize(p, 3) == size_t(-1));
    }
    {   // part size larger than the source: one part; part size 1: one part per byte
        Bytes d = rnd(5, 3); BytesSource s(d); MemParts p;
        CHECK(splitStream(s, d.size(), 1000, opener(p), nullptr, &parts) == Result::Ok && parts == 1 && partSize(p, 1) == 5);
        BytesSource s2(d); MemParts p2;
        CHECK(splitStream(s2, d.size(), 1, opener(p2), nullptr, &parts) == Result::Ok && parts == 5);
    }
    {   // several megabytes across the internal chunk size, trickling source
        Bytes d = rnd(3 * 1024 * 1024 + 123456, 4); BytesSource s(d); s.maxPerRead = 100000; MemParts p; Obs o;
        const uint64_t chunk = 1024 * 1024 + 7;
        CHECK(splitStream(s, d.size(), chunk, opener(p), &o, &parts) == Result::Ok);
        CHECK_EQ(parts, 4);
        Bytes all; for (int i = 1; i <= parts; ++i) { CHECK(i == parts || p.data[i].size() == chunk); all.insert(all.end(), p.data[i].begin(), p.data[i].end()); }
        CHECK(all == d);
        CHECK(o.monotone && o.lastDone == d.size());
        // join it back
        MemParts& pp = p; std::vector<std::unique_ptr<BytesSource>> srcs; std::vector<ByteSource*> ptrs;
        for (int i = 1; i <= parts; ++i) { srcs.push_back(std::make_unique<BytesSource>(pp.data[i])); ptrs.push_back(srcs.back().get()); }
        VecSink out; Obs jo;
        CHECK(joinStreams(ptrs, d.size(), out, &jo) == Result::Ok);
        CHECK(out.data == d && out.closedOk && !out.discarded);
        CHECK(jo.monotone && jo.lastDone == d.size() && jo.lastTotal == d.size());
    }
    {   // invalid input fails before any part is opened
        Bytes d = rnd(10, 5); Bytes none;
        BytesSource s(d); MemParts p;
        CHECK(splitStream(s, d.size(), 0, opener(p), nullptr, &parts, &err) == Result::Failed && p.opened == 0 && !err.empty());
        BytesSource s2(d);
        CHECK(splitStream(s2, 0, 4, opener(p), nullptr, &parts, &err) == Result::Failed && p.opened == 0);
        BytesSource s3(none);
        CHECK(splitStream(s3, 10, 4, opener(p), nullptr, &parts, &err) == Result::Failed && p.opened == 0 && err == "source is empty");
    }
    {   // cancelled in part 2: part 1 stays finished, the unfinished part 2 is removed
        Bytes d = rnd(100, 6); BytesSource s(d); s.maxPerRead = 10; MemParts p; Obs o; o.cancelAfter = 45;   // 50 bytes in: part 2 holds 20 of 30
        CHECK(splitStream(s, d.size(), 30, opener(p), &o, &parts, &err) == Result::Cancelled);
        CHECK(p.closed.count(1) && partSize(p, 1) == 30);
        CHECK(p.discarded.count(2) && partSize(p, 2) == size_t(-1));
        CHECK_EQ(parts, 0);
    }
    {   // a write failing in part 2
        Bytes d = rnd(100, 7); BytesSource s(d); MemParts p; p.failWriteInPart = 2;
        CHECK(splitStream(s, d.size(), 30, opener(p), nullptr, &parts, &err) == Result::Failed);
        CHECK(p.closed.count(1) && p.discarded.count(2) && err == "write error");
    }
    {   // part 2 cannot be created
        Bytes d = rnd(100, 8); BytesSource s(d); MemParts p; p.failOpenOfPart = 2;
        CHECK(splitStream(s, d.size(), 30, opener(p), nullptr, &parts, &err) == Result::Failed);
        CHECK(p.closed.count(1) && !p.data.count(2) && err == "could not create part");
    }
    {   // a part that will not finish (full part, then the last one)
        Bytes d = rnd(100, 9); BytesSource s(d); MemParts p; p.failCloseOfPart = 1;
        CHECK(splitStream(s, d.size(), 30, opener(p), nullptr, &parts, &err) == Result::Failed && p.discarded.count(1));
        Bytes d2 = rnd(50, 9); BytesSource s2(d2); MemParts p2; p2.failCloseOfPart = 2;            // the final, partial part
        CHECK(splitStream(s2, d2.size(), 30, opener(p2), nullptr, &parts, &err) == Result::Failed && p2.discarded.count(2) && p2.closed.count(1));
    }
    {   // a read error mid-part
        Bytes d = rnd(100, 10); BytesSource s(d); s.failAfter = 40; s.maxPerRead = 10; MemParts p;   // dies with 10 bytes in part 2
        CHECK(splitStream(s, d.size(), 30, opener(p), nullptr, &parts, &err) == Result::Failed && err == "read error");
        CHECK(p.closed.count(1) && p.discarded.count(2));
    }
}

static void testJoinStream() {
    std::printf("join stream\n");
    Bytes a = rnd(100, 11), b = rnd(50, 12), c = rnd(7, 13);
    auto mk = [&](std::vector<Bytes*> v, std::vector<std::unique_ptr<BytesSource>>& own) {
        std::vector<ByteSource*> out; for (auto* x : v) { own.push_back(std::make_unique<BytesSource>(*x)); out.push_back(own.back().get()); } return out;
    };
    std::vector<std::unique_ptr<BytesSource>> own;
    {
        auto parts = mk({&a, &b, &c}, own); VecSink out;
        CHECK(joinStreams(parts, 157, out, nullptr) == Result::Ok);
        Bytes want = a; want.insert(want.end(), b.begin(), b.end()); want.insert(want.end(), c.begin(), c.end());
        CHECK(out.data == want && out.closedOk);
    }
    {   // cancel -> output discarded
        auto parts = mk({&a, &b}, own); VecSink out; Obs o; o.cancelAfter = 120;
        CHECK(joinStreams(parts, 150, out, &o) == Result::Cancelled && out.discarded && !out.closedOk);
    }
    {   // write failure, close failure, read failure, null part -> output discarded each time
        auto parts = mk({&a}, own); VecSink w; w.failWrite = true; std::string err;
        CHECK(joinStreams(parts, 100, w, nullptr, &err) == Result::Failed && w.discarded && err == "write error");
        auto parts2 = mk({&a}, own); VecSink cl; cl.failClose = true;
        CHECK(joinStreams(parts2, 100, cl, nullptr, &err) == Result::Failed && cl.discarded && err == "could not finish output");
        BytesSource bad(a); bad.failAfter = 10; std::vector<ByteSource*> p3{&bad}; VecSink r;
        CHECK(joinStreams(p3, 100, r, nullptr, &err) == Result::Failed && r.discarded && err == "read error");
        std::vector<ByteSource*> p4{nullptr}; VecSink n;
        CHECK(joinStreams(p4, 0, n, nullptr, &err) == Result::Failed && n.discarded);
    }
}

// ------------------------------------------------------------------- host files --

struct TmpDir {
    fs::path path;
    TmpDir() { char t[] = "/tmp/xfertestXXXXXX"; path = mkdtemp(t); }
    ~TmpDir() { std::error_code ec; fs::remove_all(path, ec); }
};
static void writeFile(const fs::path& p, const Bytes& d) { std::ofstream f(p, std::ios::binary); f.write(reinterpret_cast<const char*>(d.data()), static_cast<std::streamsize>(d.size())); }
static Bytes readFile(const fs::path& p) { std::ifstream f(p, std::ios::binary); return Bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>()); }
static std::set<std::string> listing(const fs::path& d) { std::set<std::string> s; for (auto& e : fs::directory_iterator(d)) s.insert(utf8FromPath(e.path().filename())); return s; }

static void testHostFiles() {
    std::printf("host files\n");
    TmpDir t;
    std::string err;

    // split / join round trip, odd size
    const Bytes data = rnd(2 * 1024 * 1024 + 4321, 21);
    writeFile(t.path / "disk.hc", data);
    SplitSummary sum; Obs so;
    CHECK(splitFile(t.path / "disk.hc", t.path / "out", 1024 * 1024, &so, &sum, &err) == Result::Ok);
    CHECK((listing(t.path / "out") == std::set<std::string>{"disk.hc.001", "disk.hc.002", "disk.hc.003", "manifest.json"}));
    CHECK(sum.parts == 3 && sum.totalSize == data.size() && sum.displayName == "disk.hc");
    CHECK(fs::file_size(t.path / "out" / "disk.hc.001") == 1024 * 1024 && fs::file_size(t.path / "out" / "disk.hc.003") == 4321 + 0 * 1 + 0);
    CHECK(so.monotone && so.lastDone == data.size());
    const Bytes man = readFile(t.path / "out" / "manifest.json");
    CHECK_EQ(std::string(man.begin(), man.end()), manifestJson("disk.hc", "VERACRYPT", data.size(), 1024 * 1024));

    // joining from any picked part gives the original back
    for (const char* pick : {"disk.hc.001", "disk.hc.002", "disk.hc.003"}) {
        const fs::path outp = t.path / (std::string("joined-") + pick);
        Obs jo;
        CHECK(joinFiles(t.path / "out" / pick, outp, &jo, &err) == Result::Ok);
        CHECK(readFile(outp) == data);
        CHECK(jo.lastDone == data.size() && jo.lastTotal == data.size());
    }

    // an exact multiple of the part size leaves no empty trailing part
    const Bytes exact = rnd(4096, 22);
    writeFile(t.path / "exact.img", exact);
    CHECK(splitFile(t.path / "exact.img", t.path / "ex", 1024, nullptr, &sum, &err) == Result::Ok && sum.parts == 4);
    CHECK((listing(t.path / "ex") == std::set<std::string>{"exact.img.001", "exact.img.002", "exact.img.003", "exact.img.004", "manifest.json"}));
    CHECK(joinFiles(t.path / "ex" / "exact.img.002", t.path / "exact-back", nullptr, &err) == Result::Ok && readFile(t.path / "exact-back") == exact);

    // format guess lands in the manifest
    writeFile(t.path / "backup.LUKS.img", rnd(10, 23));
    CHECK(splitFile(t.path / "backup.LUKS.img", t.path / "lx", 4, nullptr, nullptr, &err) == Result::Ok);
    const Bytes m2 = readFile(t.path / "lx" / "manifest.json");
    CHECK(std::string(m2.begin(), m2.end()).find("\"format\":\"LUKS\"") != std::string::npos);

    // UTF-8 names survive (accents, emoji)
    const std::string uname = "d\xc3\xa4t\xc3\xa4-\xf0\x9f\x99\x82.hc";
    writeFile(t.path / pathFromUtf8(uname), exact);
    CHECK(splitFile(t.path / pathFromUtf8(uname), t.path / "u", 1500, nullptr, &sum, &err) == Result::Ok);
    CHECK(sum.displayName == uname && sum.parts == 3);
    CHECK(fs::exists(t.path / "u" / pathFromUtf8(uname + ".001")));
    CHECK(joinFiles(t.path / "u" / pathFromUtf8(uname + ".002"), t.path / pathFromUtf8("joined-\xc3\xa4.bin"), nullptr, &err) == Result::Ok);
    CHECK(readFile(t.path / pathFromUtf8("joined-\xc3\xa4.bin")) == exact);

    // split failures
    CHECK(splitFile(t.path / "missing", t.path / "o1", 10, nullptr, nullptr, &err) == Result::Failed && !fs::exists(t.path / "o1"));
    writeFile(t.path / "empty", Bytes());
    CHECK(splitFile(t.path / "empty", t.path / "o2", 10, nullptr, nullptr, &err) == Result::Failed);
    CHECK(listing(t.path / "o2").empty());                                              // no parts, no manifest
    writeFile(t.path / "afile", exact);
    CHECK(splitFile(t.path / "exact.img", t.path / "afile", 10, nullptr, nullptr, &err) == Result::Failed);   // destination is a file
    CHECK(splitFile(t.path / "exact.img", t.path / "o3", 0, nullptr, nullptr, &err) == Result::Failed);
    CHECK(splitFile(t.path, t.path / "o4", 10, nullptr, nullptr, &err) == Result::Failed);   // a folder is not a file

    // cancelled split: finished parts stay, the unfinished one is gone, no manifest. Parts larger than
    // one read (1 MiB) so the cancel really lands in the middle of a part.
    const size_t MiB = 1024 * 1024;
    writeFile(t.path / "big5.img", rnd(5 * MiB, 24));
    Obs co; co.cancelAfter = 2 * static_cast<int64_t>(MiB) + 1;      // 3 MiB read: part 1 (2 MiB) done, part 2 holds 1 MiB
    CHECK(splitFile(t.path / "big5.img", t.path / "cx", 2 * MiB, &co, nullptr, &err) == Result::Cancelled);
    const auto left = listing(t.path / "cx");
    CHECK((left == std::set<std::string>{"big5.img.001"}));          // no unfinished part 2, no manifest
    CHECK(fs::file_size(t.path / "cx" / "big5.img.001") == 2 * MiB);

    // join refuses to overwrite a part, and a plain file with no sequence is copied as is
    const Bytes before = readFile(t.path / "ex" / "exact.img.001");
    CHECK(joinFiles(t.path / "ex" / "exact.img.001", t.path / "ex" / "exact.img.002", nullptr, &err) == Result::Failed);
    CHECK(readFile(t.path / "ex" / "exact.img.001") == before && fs::file_size(t.path / "ex" / "exact.img.002") == 1024);
    CHECK(joinFiles(t.path / "exact.img", t.path / "copy.bin", nullptr, &err) == Result::Ok && readFile(t.path / "copy.bin") == exact);
    // a missing first part, unwritable output
    CHECK(joinFiles(t.path / "nothing.001", t.path / "x.bin", nullptr, &err) == Result::Failed && !fs::exists(t.path / "x.bin"));
    CHECK(joinFiles(t.path / "ex" / "exact.img.001", t.path / "no-such-dir" / "x.bin", nullptr, &err) == Result::Failed);
    // cancelled join removes its output
    Obs cj; cj.cancelAfter = 1500;
    CHECK(joinFiles(t.path / "ex" / "exact.img.001", t.path / "cj.bin", &cj, &err) == Result::Cancelled && !fs::exists(t.path / "cj.bin"));

    // hashFile
    writeFile(t.path / "abc.txt", bytesOf("abc"));
    std::vector<Digest> d;
    CHECK(hashFile(t.path / "abc.txt", {HashAlgo::Sha256, HashAlgo::Md5}, nullptr, d, &err) == Result::Ok);
    CHECK(hexOf(d, HashAlgo::Sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    CHECK(hexOf(d, HashAlgo::Md5) == "900150983cd24fb0d6963f7d28e17f72");
    CHECK(hashFile(t.path / "missing", {HashAlgo::Md5}, nullptr, d, &err) == Result::Failed);
    CHECK(hashFile(t.path, {HashAlgo::Md5}, nullptr, d, &err) == Result::Failed);

    // a sink dropped without close() leaves no partial file; discard() after close() keeps the file
    {
        auto sink = createFileSink(t.path / "dropped.bin");
        CHECK(sink != nullptr);
        const uint8_t x = 1; sink->write(&x, 1);
    }
    CHECK(!fs::exists(t.path / "dropped.bin"));
    {
        auto sink = createFileSink(t.path / "kept.bin");
        const uint8_t x = 1; sink->write(&x, 1);
        CHECK(sink->close());
        sink->discard();
    }
    CHECK(fs::exists(t.path / "kept.bin"));
    CHECK(createFileSink(t.path / "no-such-dir" / "f", &err) == nullptr && !err.empty());
}

int main() {
    testHashVectors();
    testHashApi();
    testNames();
    testSplitStream();
    testJoinStream();
    testHostFiles();
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
