// Host-side test of the archive C ABI (ffi/ve_archive.cpp) against a real libarchive.
//
// The ve_* vault calls the ABI is built on are replaced by an in-memory fake vault (below), so the test needs no
// unlocked container, and so it can check what a real folder vault depends on: that every extracted file is
// finished with ve_fv_finish_write, that nothing is left open or half written after a failure or a cancel, that
// every vault stream is closed, and that a stream which returns short reads in the middle of a file still
// yields a correct archive. Host files go through the real std::filesystem.
//
// g++ -std=c++20 ve_archive_test.cpp ../ve_archive.cpp ../../archive/archive_engine.cpp ../../archive/archive_split.cpp -I.. -larchive -o ve_archive_test && ./ve_archive_test
#include "../ve_engine.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "../../archive/archive_engine.h"
#include "../../platform/engine_hooks.h"

namespace fs = std::filesystem;
using Bytes = std::vector<uint8_t>;

namespace {

int g_failures = 0;
#define CHECK(cond)                                                                      \
    do {                                                                                 \
        if (!(cond)) {                                                                   \
            std::fprintf(stderr, "FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);       \
            ++g_failures;                                                                \
        }                                                                                \
    } while (0)

// ── fake vault: the part of the ve_* ABI that ve_archive.cpp calls ────────────────

struct FakeVault {
    std::map<std::string, Bytes> files;
    std::set<std::string> dirs;
    std::map<int64_t, std::string> streams;
    int64_t nextHandle = 1;
    int streamsOpened = 0;
    int streamsClosed = 0;
    size_t maxRead = 4096;          // every read returns at most this many bytes, even mid-file
    std::set<std::string> unfinished;  // written, ve_fv_finish_write not called yet
    std::vector<std::string> finished;
    bool folderVault = true;        // false: ve_fv_finish_write answers NOT_UNLOCKED, like for a container
    int failWriteAfter = -1;        // >= 0: the Nth ve_write_file_chunk call (0-based) fails
    int writeCalls = 0;

    void reset() { *this = FakeVault(); }
} V;

std::string normalize(const char* path) {
    std::string s = path ? path : "";
    while (!s.empty() && s.front() == '/') s.erase(s.begin());
    return s;
}

int g_progressCalls = 0;
uint64_t g_lastProgress = 0;
int g_cancelAtFiles = -1;  // cancel once this many files were reported

}  // namespace

extern "C" {

VE_API int64_t ve_get_file_size(int32_t, const char* path) {
    const auto it = V.files.find(normalize(path));
    return it == V.files.end() ? -1 : static_cast<int64_t>(it->second.size());
}

VE_API int64_t ve_open_stream(int32_t, const char* path) {
    if (!V.files.count(normalize(path))) return 0;
    const int64_t h = V.nextHandle++;
    V.streams[h] = normalize(path);
    ++V.streamsOpened;
    return h;
}

VE_API int32_t ve_read_stream(int32_t, int64_t handle, int64_t offset, uint8_t* dest, int32_t length) {
    const auto s = V.streams.find(handle);
    if (s == V.streams.end() || length <= 0 || offset < 0) return -1;
    const Bytes& data = V.files[s->second];
    if (static_cast<size_t>(offset) >= data.size()) return 0;
    const size_t n = std::min({static_cast<size_t>(length), data.size() - static_cast<size_t>(offset), V.maxRead});
    std::memcpy(dest, data.data() + offset, n);
    return static_cast<int32_t>(n);
}

VE_API void ve_close_stream(int32_t, int64_t handle) {
    if (V.streams.erase(handle)) ++V.streamsClosed;
}

VE_API int32_t ve_list_directory(int32_t, const char* path, ve_buffer* out) {
    std::string dir = normalize(path);
    while (!dir.empty() && dir.back() == '/') dir.pop_back();
    std::vector<std::string> lines;
    for (const auto& [p, data] : V.files) {
        const size_t slash = p.rfind('/');
        const std::string parent = slash == std::string::npos ? "" : p.substr(0, slash);
        const std::string name = slash == std::string::npos ? p : p.substr(slash + 1);
        if (parent == dir) lines.push_back("F|" + std::to_string(data.size()) + "|0|" + name);
    }
    Bytes b;
    auto u32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) b.push_back(static_cast<uint8_t>(v >> (8 * i))); };
    u32(static_cast<uint32_t>(lines.size()));
    for (const auto& l : lines) {
        u32(static_cast<uint32_t>(l.size()));
        b.insert(b.end(), l.begin(), l.end());
    }
    out->data = static_cast<uint8_t*>(std::malloc(b.size()));
    std::memcpy(out->data, b.data(), b.size());
    out->len = b.size();
    return VE_OK;
}

VE_API int32_t ve_write_file_chunk(int32_t, const char* path, int64_t offset, const uint8_t* data, size_t len) {
    const int call = V.writeCalls++;
    if (V.failWriteAfter >= 0 && call >= V.failWriteAfter) return VE_ERR_FAILED;
    const std::string p = normalize(path);
    if (offset == 0) {
        V.files[p].clear();  // offset 0 replaces the file
        if (V.folderVault) V.unfinished.insert(p);  // a container's writes are complete as they land
    } else if (!V.files.count(p) || V.files[p].size() != static_cast<size_t>(offset)) {
        return VE_ERR_FAILED;  // a folder vault only accepts chunks in order
    }
    if (len) V.files[p].insert(V.files[p].end(), data, data + len);
    return VE_OK;
}

VE_API int32_t ve_fv_finish_write(int32_t, const char* path) {
    if (!V.folderVault) return VE_ERR_NOT_UNLOCKED;
    const std::string p = normalize(path);
    if (V.unfinished.erase(p)) V.finished.push_back(p);
    return VE_OK;
}

VE_API int32_t ve_delete_file(int32_t, const char* path) {
    const std::string p = normalize(path);
    V.unfinished.erase(p);
    return V.files.erase(p) ? VE_OK : VE_ERR_FAILED;
}

VE_API int32_t ve_rename_file(int32_t, const char* from, const char* to) {
    const std::string a = normalize(from), b = normalize(to);
    if (!V.files.count(a) || V.files.count(b)) return VE_ERR_FAILED;  // never onto an existing file
    V.files[b] = std::move(V.files[a]);
    V.files.erase(a);
    V.unfinished.erase(a);
    return VE_OK;
}

VE_API int32_t ve_create_directory(int32_t, const char* path) {
    V.dirs.insert(normalize(path));
    return VE_OK;
}

VE_API void ve_buffer_free(ve_buffer* buf) {
    if (!buf) return;
    std::free(buf->data);
    buf->data = nullptr;
    buf->len = 0;
}

}  // extern "C"

// engine hooks used by the ABI
void reportSplitJoinProgress(int, uint64_t done, uint64_t) {
    ++g_progressCalls;
    g_lastProgress = done;
}
bool isSplitJoinCancelled(int) { return g_cancelAtFiles >= 0 && g_lastProgress >= static_cast<uint64_t>(g_cancelAtFiles); }
bool isCopyCancelled(int) { return false; }

namespace {

// ── result record reader ─────────────────────────────────────────────────

struct Reader {
    const uint8_t* p;
    size_t n;
    size_t pos = 0;
    uint32_t u32() {
        uint32_t v = 0;
        for (int i = 0; i < 4 && pos < n; ++i) v |= static_cast<uint32_t>(p[pos++]) << (8 * i);
        return v;
    }
    uint64_t u64() {
        uint64_t v = 0;
        for (int i = 0; i < 8 && pos < n; ++i) v |= static_cast<uint64_t>(p[pos++]) << (8 * i);
        return v;
    }
    std::string str() {
        const uint32_t len = u32();
        std::string s(reinterpret_cast<const char*>(p + pos), std::min<size_t>(len, n - pos));
        pos += len;
        return s;
    }
};

struct Entry {
    std::string path;
    uint64_t size = 0;
    bool isDir = false;
    int32_t index = -1;
};

struct Record {
    uint32_t status = 99, flags = 0, count = 0;
    std::string message;
    std::vector<Entry> entries;
};

Record parseRecord(ve_buffer& b, bool withEntries) {
    Record r;
    Reader rd{b.data, b.len};
    r.status = rd.u32();
    r.flags = rd.u32();
    r.count = rd.u32();
    r.message = rd.str();
    if (withEntries) {
        for (uint32_t i = 0; i < r.count; ++i) {
            Entry e;
            e.path = rd.str();
            e.size = rd.u64();
            rd.u64();  // compressed
            rd.u64();  // mtime
            e.isDir = (rd.u32() & 2u) != 0;
            e.index = static_cast<int32_t>(rd.u32());
            r.entries.push_back(e);
        }
    }
    ve_buffer_free(&b);
    return r;
}

Record scan(int32_t vol, const std::string& path) {
    ve_buffer b{nullptr, 0};
    CHECK(ve_archive_scan(vol, path.c_str(), nullptr, &b) == VE_OK);
    return parseRecord(b, true);
}

Record extractAll(int32_t srcVol, const std::string& src, const char* sub, int32_t destVol, const std::string& dest,
                  int32_t opId = 0) {
    ve_buffer b{nullptr, 0};
    CHECK(ve_archive_extract_all(srcVol, src.c_str(), nullptr, sub, destVol, dest.c_str(), opId, &b) == VE_OK);
    return parseRecord(b, false);
}

// ── fixtures ─────────────────────────────────────────────────────────────

Bytes pseudoRandom(size_t n, uint32_t seed) {
    Bytes b(n);
    uint32_t x = seed;
    for (auto& c : b) {
        x = x * 1664525u + 1013904223u;
        c = static_cast<uint8_t>(x >> 24);
    }
    return b;
}

struct Fixture {
    std::map<std::string, Bytes> files;  // path in the archive -> content ("dir/" entries have no content)
    std::vector<std::string> dirs;
};

Fixture makeFixture() {
    Fixture f;
    const std::string text = "hello from the archive\n";
    f.files["a.txt"] = Bytes(text.begin(), text.end());
    f.files["empty.txt"] = Bytes();
    f.files["dir/b.bin"] = pseudoRandom(150 * 1000, 7);  // spans many 4 KiB stream reads
    f.files["dir/sub/c.txt"] = Bytes{'c', '\n'};
    f.dirs = {"dir/", "dir/sub/"};
    return f;
}

std::vector<ArchiveSourceEntry> toEntries(const Fixture& f, std::vector<size_t>& offsets) {
    std::vector<ArchiveSourceEntry> entries;
    for (const auto& d : f.dirs) {
        ArchiveSourceEntry e;
        e.pathInArchive = d;
        e.isDirectory = true;
        entries.push_back(e);
    }
    offsets.assign(f.files.size(), 0);
    size_t i = 0;
    for (const auto& [name, content] : f.files) {
        ArchiveSourceEntry e;
        e.pathInArchive = name;
        e.uncompressedSize = content.size();
        const Bytes* data = &content;
        size_t* off = &offsets[i++];
        e.readData = [data, off](uint8_t* dest, size_t length) -> int64_t {
            const size_t n = std::min(length, data->size() - *off);
            std::memcpy(dest, data->data() + *off, n);
            *off += n;
            return static_cast<int64_t>(n);
        };
        entries.push_back(e);
    }
    return entries;
}

Bytes makeZip(const Fixture& f) {
    std::vector<size_t> offsets;
    const auto entries = toEntries(f, offsets);
    Bytes out;
    ArchiveSink sink;
    sink.write = [&out](const uint8_t* d, size_t n) -> int64_t {
        out.insert(out.end(), d, d + n);
        return static_cast<int64_t>(n);
    };
    const auto r = archiveCreate(sink, ArchiveFormat::Zip, entries);
    CHECK(r.status == ArchiveOpenStatus::Ok);
    return out;
}

// A spanned ZIP: parts named name.z01, name.z02, ..., name.zip (store, so the part count is predictable).
std::vector<std::pair<std::string, Bytes>> makeSplitZip(const Fixture& f, const std::string& base, uint64_t partSize) {
    std::vector<size_t> offsets;
    const auto entries = toEntries(f, offsets);
    std::vector<Bytes> parts;
    ArchivePartTarget target;
    target.openPart = [&parts](uint32_t) { parts.emplace_back(); return true; };
    target.writePart = [&parts](const uint8_t* d, size_t n) -> int64_t {
        parts.back().insert(parts.back().end(), d, d + n);
        return static_cast<int64_t>(n);
    };
    target.closePart = [](uint32_t, bool) { return true; };
    const auto r = archiveCreateSplit(target, partSize, ArchiveFormat::Zip, entries, "", false, nullptr, 0);
    CHECK(r.status == ArchiveOpenStatus::Ok);
    std::vector<std::pair<std::string, Bytes>> named;
    for (size_t i = 0; i < parts.size(); ++i) {
        char suffix[32];
        if (i + 1 == parts.size()) {
            std::snprintf(suffix, sizeof suffix, ".zip");
        } else {
            std::snprintf(suffix, sizeof suffix, ".z%02zu", i + 1);
        }
        named.emplace_back(base + suffix, parts[i]);
    }
    return named;
}

void writeFile(const fs::path& p, const Bytes& b) {
    fs::create_directories(p.parent_path());
    std::ofstream o(p, std::ios::binary);
    o.write(reinterpret_cast<const char*>(b.data()), static_cast<std::streamsize>(b.size()));
}

Bytes readFile(const fs::path& p) {
    std::ifstream in(p, std::ios::binary);
    return Bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}

const Entry* find(const Record& r, const std::string& path) {
    for (const auto& e : r.entries) {
        std::string name = e.path;
        while (!name.empty() && name.back() == '/') name.pop_back();
        if (name == path) return &e;
    }
    return nullptr;
}

constexpr int32_t kVol = 3;

// ── tests ────────────────────────────────────────────────────────────────

void testHostScanAndExtract(const fs::path& tmp, const Fixture& fx, const Bytes& zip) {
    const fs::path archive = tmp / "host" / "test.zip";
    writeFile(archive, zip);
    const std::string path = archive.string();

    Record r = scan(-1, path);
    CHECK(r.status == 0);
    CHECK(r.entries.size() == fx.files.size() + fx.dirs.size());
    const Entry* big = find(r, "dir/b.bin");
    CHECK(big && big->size == fx.files.at("dir/b.bin").size() && !big->isDir);
    CHECK(find(r, "dir") && find(r, "dir")->isDir);

    // one entry into memory
    ve_buffer data{nullptr, 0}, res{nullptr, 0};
    CHECK(ve_archive_extract_entry(-1, path.c_str(), big->index, nullptr, -1, nullptr, &data, &res) == VE_OK);
    CHECK(parseRecord(res, false).status == 0);
    CHECK(data.len == fx.files.at("dir/b.bin").size() &&
          std::memcmp(data.data, fx.files.at("dir/b.bin").data(), data.len) == 0);
    ve_buffer_free(&data);

    // one entry into a host file (parent folder created on demand)
    const fs::path staged = tmp / "staged" / "b.bin";
    CHECK(ve_archive_extract_entry(-1, path.c_str(), big->index, nullptr, -1, staged.string().c_str(), nullptr, &res) == VE_OK);
    CHECK(parseRecord(res, false).status == 0);
    CHECK(readFile(staged) == fx.files.at("dir/b.bin"));

    // a bad index fails and leaves no destination behind
    const fs::path bad = tmp / "staged" / "bad.bin";
    CHECK(ve_archive_extract_entry(-1, path.c_str(), 9999, nullptr, -1, bad.string().c_str(), nullptr, &res) == VE_OK);
    CHECK(parseRecord(res, false).status != 0);
    CHECK(!fs::exists(bad));

    // everything
    const fs::path out = tmp / "out_all";
    Record all = extractAll(-1, path, nullptr, -1, out.string());
    CHECK(all.status == 0 && all.count == fx.files.size());
    for (const auto& [name, content] : fx.files) CHECK(readFile(out / name) == content);
    CHECK(fs::exists(out / "empty.txt"));

    // only the entries under a prefix, relative to it
    const fs::path sub = tmp / "out_sub";
    Record part = extractAll(-1, path, "dir", -1, sub.string());
    CHECK(part.status == 0 && part.count == 2);
    CHECK(readFile(sub / "b.bin") == fx.files.at("dir/b.bin"));
    CHECK(readFile(sub / "sub" / "c.txt") == fx.files.at("dir/sub/c.txt"));
    CHECK(!fs::exists(sub / "a.txt"));

    // not an archive
    writeFile(tmp / "host" / "plain.txt", Bytes{'n', 'o', 't', ' ', 'z', 'i', 'p'});
    CHECK(scan(-1, (tmp / "host" / "plain.txt").string()).status != 0);  // the engine says "unrecognized format"
    CHECK(scan(-1, (tmp / "host" / "missing.zip").string()).status == 4);
}

void testVaultSource(const Fixture& fx, const Bytes& zip) {
    V.reset();
    V.files["docs/test.zip"] = zip;
    Record r = scan(kVol, "/docs/test.zip");
    CHECK(r.status == 0 && r.entries.size() == fx.files.size() + fx.dirs.size());
    const Entry* big = find(r, "dir/b.bin");
    CHECK(big != nullptr);
    if (big) {
        ve_buffer data{nullptr, 0}, res{nullptr, 0};
        CHECK(ve_archive_extract_entry(kVol, "docs/test.zip", big->index, nullptr, -1, nullptr, &data, &res) == VE_OK);
        CHECK(parseRecord(res, false).status == 0);
        CHECK(data.len == fx.files.at("dir/b.bin").size() &&
              std::memcmp(data.data, fx.files.at("dir/b.bin").data(), data.len) == 0);
        ve_buffer_free(&data);
    }
    CHECK(V.streamsOpened > 0 && V.streamsOpened == V.streamsClosed);  // no stream leaked
    CHECK(scan(kVol, "docs/nothing.zip").status == 4);
}

void testVaultSinkFolderVault(const Fixture& fx, const Bytes& zip) {
    V.reset();
    V.folderVault = true;
    V.files["in/test.zip"] = zip;
    Record r = extractAll(kVol, "in/test.zip", nullptr, kVol, "/out/dest");
    CHECK(r.status == 0 && r.count == fx.files.size());
    for (const auto& [name, content] : fx.files) CHECK(V.files["out/dest/" + name] == content);
    CHECK(V.unfinished.empty());                       // every file was finished ...
    CHECK(V.finished.size() == fx.files.size());       // ... each exactly once, empty file included
    CHECK(V.dirs.count("out") && V.dirs.count("out/dest") && V.dirs.count("out/dest/dir/sub"));
    CHECK(V.streamsOpened == V.streamsClosed);

    // a single entry streamed into a vault file
    V.reset();
    V.files["in/test.zip"] = zip;
    Record s = scan(kVol, "in/test.zip");
    const Entry* big = find(s, "dir/b.bin");
    ve_buffer res{nullptr, 0};
    CHECK(big && ve_archive_extract_entry(kVol, "in/test.zip", big->index, nullptr, kVol, "/staged/b.bin", nullptr, &res) == VE_OK);
    CHECK(parseRecord(res, false).status == 0);
    CHECK(V.files["staged/b.bin"] == fx.files.at("dir/b.bin"));
    CHECK(V.unfinished.empty() && V.finished.size() == 1);
}

void testVaultSinkContainer(const Fixture& fx, const Bytes& zip) {
    V.reset();
    V.folderVault = false;  // finish answers NOT_UNLOCKED: nothing to finish, and that is fine
    V.files["in/test.zip"] = zip;
    Record r = extractAll(kVol, "in/test.zip", nullptr, kVol, "out");
    CHECK(r.status == 0 && r.count == fx.files.size());
    for (const auto& [name, content] : fx.files) CHECK(V.files["out/" + name] == content);
}

void testFailureLeavesNothingBehind(const Bytes& zip) {
    V.reset();
    V.files["in/test.zip"] = zip;
    V.failWriteAfter = 3;  // the first data chunk of the big file (after a.txt and the big file's own create) fails
    Record r = extractAll(kVol, "in/test.zip", nullptr, kVol, "out");
    CHECK(r.status == 4);
    CHECK(V.unfinished.empty());  // the file that was in flight was finished-or-deleted, never left open
    CHECK(!V.files.count("out/dir/b.bin"));
    CHECK(V.streamsOpened == V.streamsClosed);
}

void testCancel(const fs::path& tmp, const Fixture& fx, const Bytes& zip) {
    V.reset();
    V.files["in/test.zip"] = zip;
    g_progressCalls = 0;
    g_lastProgress = 0;
    g_cancelAtFiles = 2;
    Record r = extractAll(kVol, "in/test.zip", nullptr, kVol, "out", /*opId=*/5);
    g_cancelAtFiles = -1;
    CHECK(r.status == 0 && (r.flags & 4u) != 0);  // reported as cancelled
    CHECK(r.count == 2 && g_progressCalls >= 2);
    CHECK(V.unfinished.empty());
    size_t extracted = 0;
    for (const auto& [name, content] : fx.files) {
        if (V.files.count("out/" + name)) {
            ++extracted;
            CHECK(V.files["out/" + name] == content);  // whatever is there is complete
        }
    }
    CHECK(extracted == 2);

    // same on the host
    const fs::path archive = tmp / "cancel" / "test.zip";
    writeFile(archive, zip);
    g_lastProgress = 0;
    g_cancelAtFiles = 1;
    Record h = extractAll(-1, archive.string(), nullptr, -1, (tmp / "cancel_out").string(), 5);
    g_cancelAtFiles = -1;
    CHECK(h.status == 0 && (h.flags & 4u) != 0 && h.count == 1);
}

void testSplitSet(const fs::path& tmp, const Fixture& fx) {
    // 150 KB of random data stored in 64 KiB parts: at least three parts
    const auto parts = makeSplitZip(fx, "set", 64 * 1024);
    CHECK(parts.size() >= 3);

    // on the host: opening the FIRST part, a middle part and the last all open the whole set
    const fs::path dir = tmp / "split";
    for (const auto& [name, bytes] : parts) writeFile(dir / name, bytes);
    for (const char* opened : {"set.z01", "set.z02", "set.zip"}) {
        Record r = scan(-1, (dir / opened).string());
        CHECK(r.status == 0 && r.entries.size() == fx.files.size() + fx.dirs.size());
    }
    Record all = extractAll(-1, (dir / "set.z01").string(), nullptr, -1, (tmp / "split_out").string());
    CHECK(all.status == 0 && all.count == fx.files.size());
    CHECK(readFile(tmp / "split_out" / "dir" / "b.bin") == fx.files.at("dir/b.bin"));

    // a part is missing: reported, not scanned as a lone piece
    fs::remove(dir / "set.z02");
    Record missing = scan(-1, (dir / "set.z01").string());
    CHECK(missing.status == 4 && !missing.message.empty());

    // in a vault
    V.reset();
    for (const auto& [name, bytes] : parts) V.files["parts/" + name] = bytes;
    Record vr = scan(kVol, "parts/set.z01");
    CHECK(vr.status == 0 && vr.entries.size() == fx.files.size() + fx.dirs.size());
    Record vall = extractAll(kVol, "parts/set.zip", nullptr, kVol, "x");
    CHECK(vall.status == 0 && V.files["x/dir/b.bin"] == fx.files.at("dir/b.bin"));
    CHECK(V.streamsOpened == V.streamsClosed);
}

// ── creating ─────────────────────────────────────────────────────────────

Record create(int32_t srcVol, const std::vector<std::string>& paths, const std::vector<std::string>& names,
              int32_t destVol, const std::string& dest, int32_t format = 0, const char* pass = nullptr,
              bool encryptNames = false, uint64_t split = 0, const char* tempDir = nullptr, int32_t opId = 0,
              const std::vector<int64_t>& mtimes = {}) {
    std::vector<const char*> p, n;
    for (const auto& x : paths) p.push_back(x.c_str());
    for (const auto& x : names) n.push_back(x.c_str());
    ve_buffer b{nullptr, 0};
    CHECK(ve_archive_create(srcVol, p.data(), n.data(), mtimes.empty() ? nullptr : mtimes.data(),
                            static_cast<int32_t>(paths.size()), destVol, dest.c_str(), format, pass,
                            encryptNames ? 1 : 0, -1, 0, split, tempDir, opId, &b) == VE_OK);
    return parseRecord(b, false);
}

// Host files under tmp/src: the fixture's files, plus a folder.
std::vector<std::string> writeHostSources(const fs::path& tmp, const Fixture& fx, std::vector<std::string>& names) {
    std::vector<std::string> paths;
    for (const auto& [name, content] : fx.files) {
        writeFile(tmp / "src" / name, content);
        paths.push_back((tmp / "src" / name).string());
        names.push_back(name);
    }
    fs::create_directories(tmp / "src" / "emptydir");
    paths.push_back((tmp / "src" / "emptydir").string());
    names.push_back("emptydir/");
    return paths;
}

void checkRoundTripFromHost(const fs::path& archive, const Fixture& fx, const fs::path& out) {
    Record scanned = scan(-1, archive.string());
    CHECK(scanned.status == 0);
    CHECK(find(scanned, "emptydir") && find(scanned, "emptydir")->isDir);
    Record all = extractAll(-1, archive.string(), nullptr, -1, out.string());
    CHECK(all.status == 0);
    for (const auto& [name, content] : fx.files) CHECK(readFile(out / name) == content);
    CHECK(fs::is_directory(out / "emptydir"));
}

void testCreateFromHost(const fs::path& tmp, const Fixture& fx) {
    std::vector<std::string> names;
    const auto paths = writeHostSources(tmp, fx, names);

    // zip, host -> host; the file's own modification time is used when none is given
    const fs::path zip = tmp / "created" / "one.zip";
    Record r = create(-1, paths, names, -1, zip.string());
    CHECK(r.status == 0 && r.count == 1);
    checkRoundTripFromHost(zip, fx, tmp / "created_out");

    // 7z with a private spool folder: the process setting follows temp_dir
    const fs::path spool = tmp / "spool";
    fs::create_directories(spool);
    const fs::path sevenZ = tmp / "created" / "one.7z";
    r = create(-1, paths, names, -1, sevenZ.string(), /*7z*/ 1, nullptr, false, 0, spool.string().c_str());
    CHECK(r.status == 0 && r.count == 1);
#ifndef _WIN32
    const char* td = std::getenv("TMPDIR");
    CHECK(td && spool == fs::path(td));
#endif
    checkRoundTripFromHost(sevenZ, fx, tmp / "created7_out");
    CHECK(fs::is_empty(spool));  // the spooled temporary file is gone

    // tar.gz
    const fs::path tgz = tmp / "created" / "one.tar.gz";
    CHECK(create(-1, paths, names, -1, tgz.string(), 3).status == 0);
    checkRoundTripFromHost(tgz, fx, tmp / "created_tgz_out");
}

void testCreateFailures(const fs::path& tmp, const Fixture& fx) {
    std::vector<std::string> names;
    auto paths = writeHostSources(tmp, fx, names);

    // a source that does not exist: reported, nothing written
    std::vector<std::string> badPaths = paths;
    badPaths[0] = (tmp / "src" / "no_such_file").string();
    const fs::path dest = tmp / "failed" / "x.zip";
    Record r = create(-1, badPaths, names, -1, dest.string());
    CHECK(r.status == 4 && !r.message.empty());
    CHECK(!fs::exists(dest));

    // encrypted file names need 7z and a passphrase: refused, and the half-written destination is removed
    r = create(-1, paths, names, -1, dest.string(), /*zip*/ 0, nullptr, /*encryptNames=*/true);
    CHECK(r.status != 0);
    CHECK(!fs::exists(dest));

    // cancel
    g_lastProgress = 0;
    g_cancelAtFiles = 1;
    r = create(-1, paths, names, -1, dest.string(), 0, nullptr, false, 0, nullptr, /*opId=*/3);
    g_cancelAtFiles = -1;
    CHECK(r.status != 0 && (r.flags & 4u) != 0);
    CHECK(!fs::exists(dest));

    // a vault destination that fails halfway through
    V.reset();
    V.failWriteAfter = 2;
    r = create(-1, paths, names, kVol, "out/x.zip");
    CHECK(r.status != 0);
    CHECK(V.unfinished.empty() && !V.files.count("out/x.zip"));
}

void testCreateInVault(const Fixture& fx) {
    for (const bool folderVault : {true, false}) {
        V.reset();
        V.folderVault = folderVault;
        std::vector<std::string> paths, names;
        for (const auto& [name, content] : fx.files) {
            V.files["data/" + name] = content;
            paths.push_back("/data/" + name);
            names.push_back(name);
        }
        paths.push_back("/data");
        names.push_back("data_dir/");

        // vault -> vault
        Record r = create(kVol, paths, names, kVol, "/out/a.zip");
        CHECK(r.status == 0 && r.count == 1);
        CHECK(V.unfinished.empty());
        CHECK(V.dirs.count("out"));
        const Record scanned = scan(kVol, "out/a.zip");
        CHECK(scanned.status == 0 && scanned.entries.size() == fx.files.size() + 1);
        CHECK(find(scanned, "data_dir") && find(scanned, "data_dir")->isDir);
        Record all = extractAll(kVol, "out/a.zip", nullptr, kVol, "restored");
        CHECK(all.status == 0);
        for (const auto& [name, content] : fx.files) CHECK(V.files["restored/" + name] == content);
        CHECK(V.streamsOpened == V.streamsClosed);

        // vault -> host
        // (the fake vault is not a file system: the source paths are read through the stream calls)
        const fs::path hostOut = fs::temp_directory_path() / ("ve_archive_vault_to_host_" + std::to_string(std::rand()) + ".zip");
        r = create(kVol, paths, names, -1, hostOut.string());
        CHECK(r.status == 0);
        CHECK(scan(-1, hostOut.string()).entries.size() == fx.files.size() + 1);
        std::error_code ec;
        fs::remove(hostOut, ec);
        CHECK(V.streamsOpened == V.streamsClosed);

        // a missing vault source
        r = create(kVol, {"/data/missing"}, {"missing"}, kVol, "out/b.zip");
        CHECK(r.status == 4);
        CHECK(!V.files.count("out/b.zip"));
    }
}

void testCreateSplit(const fs::path& tmp, const Fixture& fx) {
    // enough stored data for at least three 64 KiB parts
    Fixture big = fx;
    big.files["dir/b.bin"] = pseudoRandom(260 * 1000, 11);
    std::vector<std::string> names;
    const auto paths = writeHostSources(tmp, big, names);

    // zip -> host: name.z01, name.z02, ..., name.zip
    const fs::path base = tmp / "splitout" / "set";
    Record r = create(-1, paths, names, -1, (base.string() + ".zip"), 0, nullptr, false, 64 * 1024);
    CHECK(r.status == 0 && r.count >= 4);
    CHECK(fs::exists(base.string() + ".z01") && fs::exists(base.string() + ".z02") && fs::exists(base.string() + ".zip"));
    CHECK(!fs::exists(base.string() + ".z" + (r.count < 10 ? "0" : "") + std::to_string(r.count)));  // the last part was renamed
    checkRoundTripFromHost(base.string() + ".z01", big, tmp / "splitout_zip");

    // 7z -> host: name.7z.001, ...
    const fs::path base7 = tmp / "splitout" / "set7.7z";
    r = create(-1, paths, names, -1, base7.string(), 1, nullptr, false, 64 * 1024);
    CHECK(r.status == 0 && r.count >= 2);
    CHECK(fs::exists(base7.string() + ".001") && fs::exists(base7.string() + ".002"));
    checkRoundTripFromHost(base7.string() + ".001", big, tmp / "splitout_7z");

    // a part that would replace an existing file stops the run and removes the parts already written
    const fs::path base2 = tmp / "splitout2" / "set";
    writeFile(base2.string() + ".z02", Bytes{1, 2, 3});
    r = create(-1, paths, names, -1, base2.string() + ".zip", 0, nullptr, false, 64 * 1024);
    CHECK(r.status != 0);
    CHECK(!fs::exists(base2.string() + ".z01") && !fs::exists(base2.string() + ".zip"));
    CHECK(readFile(base2.string() + ".z02") == (Bytes{1, 2, 3}));  // the file that was in the way is untouched

    // zip -> vault
    for (const bool folderVault : {true, false}) {
        V.reset();
        V.folderVault = folderVault;
        r = create(-1, paths, names, kVol, "/parts/v.zip", 0, nullptr, false, 64 * 1024);
        CHECK(r.status == 0 && r.count >= 4);
        CHECK(V.files.count("parts/v.z01") && V.files.count("parts/v.z02") && V.files.count("parts/v.zip"));
        CHECK(V.unfinished.empty());
        Record vr = scan(kVol, "parts/v.z01");
        CHECK(vr.status == 0 && vr.entries.size() == big.files.size() + 1);
        Record vall = extractAll(kVol, "parts/v.zip", nullptr, -1, (tmp / "from_vault_parts").string());
        CHECK(vall.status == 0 && readFile(tmp / "from_vault_parts" / "dir" / "b.bin") == big.files.at("dir/b.bin"));
        fs::remove_all(tmp / "from_vault_parts");

        // creating again into the same place must not replace the parts
        const auto before = V.files;
        r = create(-1, paths, names, kVol, "/parts/v.zip", 0, nullptr, false, 64 * 1024);
        CHECK(r.status != 0);
        CHECK(V.files == before);
        CHECK(V.unfinished.empty());
    }
}

void testCreateArguments() {
    ve_buffer b{nullptr, 0};
    const char* p[] = {"/a"};
    const char* n[] = {"a"};
    CHECK(ve_archive_create(-1, nullptr, n, nullptr, 1, -1, "d.zip", 0, nullptr, 0, -1, 0, 0, nullptr, 0, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_create(-1, p, n, nullptr, 0, -1, "d.zip", 0, nullptr, 0, -1, 0, 0, nullptr, 0, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_create(-1, p, n, nullptr, 1, -1, nullptr, 0, nullptr, 0, -1, 0, 0, nullptr, 0, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_create(-1, p, n, nullptr, 1, -1, "d.zip", 99, nullptr, 0, -1, 0, 0, nullptr, 0, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_create(-1, p, n, nullptr, 1, -1, "d.zip", 0, nullptr, 0, -1, 0, 0, nullptr, 0, nullptr) == VE_ERR_INVALID_ARG);
}

void testArguments() {
    ve_buffer b{nullptr, 0}, c{nullptr, 0};
    CHECK(ve_archive_scan(-1, nullptr, nullptr, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_scan(-1, "x.zip", nullptr, nullptr) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_extract_entry(-1, "x.zip", -1, nullptr, -1, "d", nullptr, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_extract_entry(-1, "x.zip", 0, nullptr, -1, nullptr, nullptr, &b) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_extract_all(-1, "x.zip", nullptr, nullptr, -1, nullptr, 0, &c) == VE_ERR_INVALID_ARG);
    CHECK(ve_archive_extract_all(-1, nullptr, nullptr, nullptr, -1, "d", 0, &c) == VE_ERR_INVALID_ARG);
}

}  // namespace

int main() {
    const fs::path tmp = fs::temp_directory_path() / ("ve_archive_test_" + std::to_string(std::rand()));
    fs::remove_all(tmp);
    fs::create_directories(tmp);

    const Fixture fx = makeFixture();
    const Bytes zip = makeZip(fx);

    testArguments();
    testHostScanAndExtract(tmp, fx, zip);
    testVaultSource(fx, zip);
    testVaultSinkFolderVault(fx, zip);
    testVaultSinkContainer(fx, zip);
    testFailureLeavesNothingBehind(zip);
    testCancel(tmp, fx, zip);
    testSplitSet(tmp, fx);
    testCreateArguments();
    testCreateFromHost(tmp, fx);
    testCreateFailures(tmp, fx);
    testCreateInVault(fx);
    testCreateSplit(tmp, fx);

    std::error_code ec;
    fs::remove_all(tmp, ec);
    if (g_failures == 0) {
        std::puts("ve_archive_test: all passed");
        return 0;
    }
    std::fprintf(stderr, "ve_archive_test: %d check(s) failed\n", g_failures);
    return 1;
}
