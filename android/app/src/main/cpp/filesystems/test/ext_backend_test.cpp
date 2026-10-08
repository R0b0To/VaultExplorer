// Host-side tests for filesystems/ext_backend.cpp -- the real backend code, run
// against real ext2/3/4 images, with e2fsck as the oracle.
//
// What is real here: ext_backend.cpp itself, its encrypted-sector I/O manager
// (extIoOpen/extTransfer/...), and libext2fs. What is faked: the bottom of the
// stack. disk_read()/disk_write() (FatFs's diskio layer, which in the app
// decrypts sectors from a container) are implemented over plain host files, so
// "volume N" is just an image file. Everything above that seam is production
// code, which is the point: these tests exercise the same path the app uses for
// mount, format, directory/file operations and chunked/streamed I/O.
//
// After mutating operations the tests close the filesystem and run
// `e2fsck -fn` on the image. That check is what caught the bugs these tests
// now pin (directory delete leaking its inode, directory moves into their own
// subtree, writes into directories, over-long names). If e2fsck isn't on PATH
// the tests still run but print a loud SKIP for each fsck check.
//
// Build + run (Debian/Ubuntu: apt-get install g++ libext2fs-dev e2fsprogs
// libssl-dev libmbedtls-dev):
//   filesystems/test/run_ext_backend_test.sh
// The CMake build also registers it (see CMakeLists.txt, host tests block).
//
// NOT covered here: the NTFS backend (needs the ntfs-3g tree and an NTFS image
// maker) and FAT. See docs/architecture.md section 5.3 for the shared contract.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "diskio.h"
#include "filesystems/ext_backend.h"
#include "session/volume_state.h"

// ---- The pieces of the app this test stands in for ----------------------------------
VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;
bool CompositeBlockDevice::sync() { return true; }

static FILE* g_images[FF_VOLUMES] = {};

DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    FILE* f = g_images[pdrv];
    if (!f || fseeko(f, static_cast<off_t>(sector) * 512, SEEK_SET) != 0) return RES_ERROR;
    return fread(buff, 512, count, f) == count ? RES_OK : RES_ERROR;
}
DRESULT disk_write(BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
    FILE* f = g_images[pdrv];
    if (!f || fseeko(f, static_cast<off_t>(sector) * 512, SEEK_SET) != 0) return RES_ERROR;
    const size_t written = fwrite(buff, 512, count, f);
    fflush(f);
    return written == count ? RES_OK : RES_ERROR;
}

#include "fs_test_support.h"

static const bool g_haveFsck = commandExists("e2fsck");
static const bool g_haveMkfs = commandExists("mkfs.ext4");

// One image file bound to a volume slot.
struct Vol {
    int id = 0;
    std::string path;

    void attach() {
        if (g_images[id]) fclose(g_images[id]);
        g_images[id] = fopen(path.c_str(), "r+b");
        fseeko(g_images[id], 0, SEEK_END);
        VolumeState& v = volumes[id];
        v.dataAreaLengthBytes = static_cast<uint64_t>(ftello(g_images[id]));
        v.readOnly = false;
        v.fd = -1;
        v.luksSectorSize = 512;
    }
    void closeFs() {
        VolumeState& v = volumes[id];
        if (v.extFs) { ext2fs_close(v.extFs); v.extFs = nullptr; }
        v.extBitmapsLoaded = false;
        v.fsMounted = false;
        v.fsType = VolumeState::FS_UNKNOWN;
    }
    bool mount() { return mountExtVolume(id); }

    // New zero-filled image formatted by the product's own formatExtVolume().
    bool format(const char* variant, uint64_t mib) {
        closeFs();
        path = g_tmp + "/vol" + std::to_string(id) + ".img";
        const std::string cmd = "rm -f '" + path + "'; truncate -s " + std::to_string(mib) + "M '" + path + "'";
        if (std::system(cmd.c_str()) != 0) return false;
        attach();
        return formatExtVolume(id, variant) && mount();
    }
    // New image made by the system mkfs (a different producer than formatExtVolume).
    bool mkfs(const char* tool, const char* opts, uint64_t mib) {
        closeFs();
        path = g_tmp + "/vol" + std::to_string(id) + ".img";
        const std::string cmd = "rm -f '" + path + "'; truncate -s " + std::to_string(mib) + "M '" + path + "'; " +
                                tool + " -F -q " + opts + " '" + path + "' >/dev/null 2>&1";
        if (std::system(cmd.c_str()) != 0) return false;
        attach();
        return mount();
    }
    // Close the filesystem and let e2fsck judge the image; then mount it again.
    bool fsckClean(const char* what) {
        closeFs();
        fflush(g_images[id]);
        bool clean = true;
        if (g_haveFsck) {
            const std::string log = g_tmp + "/fsck.log";
            const std::string cmd = "e2fsck -fn '" + path + "' >'" + log + "' 2>&1";
            const int rc = std::system(cmd.c_str());
            clean = rc == 0;
            if (!clean) {
                std::printf("    e2fsck found problems after '%s' (exit %d):\n", what, rc);
                const std::string show = "grep -v '^e2fsck [0-9]\\|^Pass [0-9]' '" + log + "' | head -12 | sed 's/^/        /'";
                std::system(show.c_str());
            }
        } else {
            ++g_skips;
            std::printf("    SKIP fsck check '%s' (e2fsck not on PATH)\n", what);
        }
        attach();
        mount();
        ++g_checks;
        if (!clean) { ++g_failures; std::printf("    FAIL fsck clean: %s\n", what); }
        return clean;
    }
};

// ---- Helpers over the production API ------------------------------------------------
struct Entry { bool isDir; uint64_t size; uint64_t mtime; std::string name; };

static std::vector<Entry> list(int vol, const std::string& dir) {
    std::vector<std::string> raw;
    extListDirectory(vol, dir, raw);
    std::vector<Entry> out;
    for (const auto& line : raw) {
        const size_t p1 = line.find('|');
        const size_t p2 = line.find('|', p1 + 1);
        const size_t p3 = line.find('|', p2 + 1);
        if (p1 == std::string::npos || p2 == std::string::npos || p3 == std::string::npos) continue;
        out.push_back({line[0] == 'D', std::stoull(line.substr(p1 + 1, p2 - p1 - 1)),
                       std::stoull(line.substr(p2 + 1, p3 - p2 - 1)), line.substr(p3 + 1)});
    }
    return out;
}
static std::vector<std::string> names(int vol, const std::string& dir) {
    std::vector<std::string> out;
    for (const auto& e : list(vol, dir)) out.push_back(e.name);
    std::sort(out.begin(), out.end());
    return out;
}
static bool has(int vol, const std::string& dir, const std::string& name) {
    for (const auto& e : list(vol, dir)) if (e.name == name) return true;
    return false;
}
static const Entry* find(const std::vector<Entry>& es, const std::string& name) {
    for (const auto& e : es) if (e.name == name) return &e;
    return nullptr;
}
static bool putFile(int vol, const std::string& path, const Bytes& data) {
    return extWriteFileChunk(vol, path, 0, data.data(), data.size());
}
static Bytes getFile(int vol, const std::string& path) {
    Bytes out, chunk;
    uint64_t offset = 0;
    while (extReadFileChunk(vol, path, offset, 100000, chunk)) { out.insert(out.end(), chunk.begin(), chunk.end()); offset += chunk.size(); }
    return out;
}
static uint64_t freeBytes(int vol) {
    uint64_t total = 0, free = 0;
    extGetSpaceInfo(vol, total, free);
    return free;
}
static uint32_t linksOf(int vol, const std::string& path) {
    ext2_ino_t ino = 0;
    struct ext2_inode inode{};
    if (!extResolvePath(volumes[vol].extFs, path, &ino) || ext2fs_read_inode(volumes[vol].extFs, ino, &inode) != 0) return 0xFFFFFFFFu;
    return inode.i_links_count;
}
static ext2_ino_t dotdotOf(int vol, const std::string& dirPath) {
    ext2_ino_t ino = 0, parent = 0;
    if (!extResolvePath(volumes[vol].extFs, dirPath, &ino)) return 0;
    if (ext2fs_lookup(volumes[vol].extFs, ino, "..", 2, nullptr, &parent) != 0) return 0;
    return parent;
}
static ext2_ino_t inoOf(int vol, const std::string& path) {
    ext2_ino_t ino = 0;
    return extResolvePath(volumes[vol].extFs, path, &ino) ? ino : 0;
}

// ---- Tests --------------------------------------------------------------------------
static void test_format_variants_pass_fsck() {
    struct Case { const char* variant; uint64_t mib; const char* expectLabel; };
    // ext3 at 8 MiB has no room for a journal by design (see formatExtVolume), so it reads as ext2.
    const Case cases[] = {{"ext2", 8, "ext2"},  {"ext2", 64, "ext2"}, {"ext3", 8, "ext2"},
                          {"ext3", 64, "ext3"}, {"ext4", 8, "ext4"},  {"ext4", 64, "ext4"}};
    for (const auto& c : cases) {
        Vol v;
        CHECK(v.format(c.variant, c.mib));
        CHECK_EQ(extGetFilesystemLabel(0), std::string(c.expectLabel));
        CHECK(list(0, "").size() == 1 && has(0, "", "lost+found"));
        const std::string what = std::string("format ") + c.variant + " " + std::to_string(c.mib) + "MiB";
        v.fsckClean(what.c_str());
    }
}

static void test_mounts_images_made_by_system_mkfs() {
    if (!g_haveMkfs) { ++g_skips; std::printf("    SKIP (mkfs.ext4 not on PATH)\n"); return; }
    struct Case { const char* tool; const char* opts; const char* label; };
    const Case cases[] = {{"mkfs.ext4", "-b 4096", "ext4"}, {"mkfs.ext4", "-b 1024", "ext4"},
                          {"mkfs.ext3", "-b 4096", "ext3"}, {"mkfs.ext2", "-b 2048", "ext2"}};
    for (const auto& c : cases) {
        Vol v;
        CHECK(v.mkfs(c.tool, c.opts, 24));
        CHECK_EQ(extGetFilesystemLabel(0), std::string(c.label));
        CHECK(extCreateDirectory(0, "/docs"));
        CHECK(putFile(0, "/docs/a.bin", pseudoRandom(300000, 5)));
        CHECK(extRenameFile(0, "/docs/a.bin", "/b.bin"));
        CHECK(getFile(0, "/b.bin") == pseudoRandom(300000, 5));
        const std::string what = std::string(c.tool) + " " + c.opts;
        v.fsckClean(what.c_str());
    }
}

static void test_mkdir_rules() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/a"));
    CHECK(extCreateDirectory(0, "/a/b"));
    CHECK(!extCreateDirectory(0, "/a"));        // name taken by a directory
    CHECK(!extCreateDirectory(0, "/a/b"));
    CHECK(putFile(0, "/f", pseudoRandom(10, 1)));
    CHECK(!extCreateDirectory(0, "/f"));        // name taken by a file
    CHECK(!extCreateDirectory(0, "/f/sub"));    // parent is a file
    CHECK(!extCreateDirectory(0, "/nope/x"));   // parent missing
    CHECK(!extCreateDirectory(0, ""));
    CHECK(!extCreateDirectory(0, "/"));
    const auto root = list(0, "");
    CHECK(find(root, "a") && find(root, "a")->isDir);
    CHECK(find(root, "f") && !find(root, "f")->isDir && find(root, "f")->size == 10);
    // Each *refused* mkdir above used to leak an unconnected directory inode.
    v.fsckClean("mkdir rules");
}

static void test_names_wire_format_and_limits() {
    Vol v;
    CHECK(v.format("ext4", 16));
    const std::string odd[] = {"pipe|in|name", "sp ace.txt", "\xC3\x9C" "n\xC3\xAF" "code \xE2\x9C\x93.txt", "-dash", ".hidden"};
    for (const auto& n : odd) {
        CHECK(putFile(0, "/" + n, pseudoRandom(100 + n.size(), 2)));
        const auto entries = list(0, "");
        const Entry* e = find(entries, n);
        CHECK(e != nullptr && !e->isDir && e->size == 100 + n.size());  // name preserved byte-for-byte
    }
    const std::string max255(255, 'm');
    CHECK(putFile(0, "/" + max255, pseudoRandom(5, 3)));
    CHECK(has(0, "", max255));
    // Past 255 bytes ext2fs_link() doesn't fail -- the length byte wraps and a
    // different, shorter name is stored -- so the backend must refuse.
    CHECK(!putFile(0, "/" + std::string(256, 'x'), pseudoRandom(5, 4)));
    CHECK(!extCreateDirectory(0, "/" + std::string(300, 'y')));
    CHECK(putFile(0, "/short", pseudoRandom(5, 6)));
    CHECK(!extRenameFile(0, "/short", "/" + std::string(256, 'z')));
    CHECK(has(0, "", "short"));
    for (const auto& e : list(0, "")) CHECK(e.name.size() <= 255);
    v.fsckClean("names");
}

static void test_chunked_io_roundtrip() {
    Vol v;
    CHECK(v.format("ext4", 32));
    const Bytes data = pseudoRandom(3 * 1024 * 1024 + 777, 11);
    const size_t chunk = 65536;
    for (size_t off = 0; off < data.size(); off += chunk) {
        const size_t n = std::min(chunk, data.size() - off);
        CHECK(extWriteFileChunk(0, "/big.bin", off, data.data() + off, n));
    }
    CHECK_EQ(extGetFileSize(0, "/big.bin"), static_cast<uint64_t>(data.size()));
    CHECK(getFile(0, "/big.bin") == data);
    Bytes tail;
    CHECK(extReadFileChunk(0, "/big.bin", data.size() - 10, 100, tail));
    CHECK_EQ(tail.size(), static_cast<size_t>(10));
    CHECK(std::equal(tail.begin(), tail.end(), data.end() - 10));
    CHECK(!extReadFileChunk(0, "/missing.bin", 0, 10, tail));
    v.fsckClean("chunked io");
}

static void test_write_offset_rules() {
    Vol v;
    CHECK(v.format("ext4", 16));
    Bytes a(20000, 'A'), b(100, 'B'), c(50, 'C');
    CHECK(putFile(0, "/f", a));
    // Offset 0 starts a new file: it truncates (this is how the import path restarts a file).
    CHECK(extWriteFileChunk(0, "/f", 0, b.data(), b.size()));
    CHECK_EQ(extGetFileSize(0, "/f"), static_cast<uint64_t>(100));
    // A write beyond the end extends the file, leaving a hole of zeros.
    CHECK(extWriteFileChunk(0, "/f", 1000, c.data(), c.size()));
    CHECK_EQ(extGetFileSize(0, "/f"), static_cast<uint64_t>(1050));
    Bytes got = getFile(0, "/f");
    CHECK_EQ(got.size(), static_cast<size_t>(1050));
    CHECK(std::all_of(got.begin(), got.begin() + 100, [](uint8_t x) { return x == 'B'; }));
    CHECK(std::all_of(got.begin() + 100, got.begin() + 1000, [](uint8_t x) { return x == 0; }));
    CHECK(std::all_of(got.begin() + 1000, got.end(), [](uint8_t x) { return x == 'C'; }));
    // An overwrite inside the file keeps its size.
    CHECK(extWriteFileChunk(0, "/f", 10, c.data(), c.size()));
    CHECK_EQ(extGetFileSize(0, "/f"), static_cast<uint64_t>(1050));
    v.fsckClean("write offsets");
}

static void test_host_file_roundtrip_overwrite_and_cancel() {
    Vol v;
    CHECK(v.format("ext4", 32));
    const Bytes big = pseudoRandom(5 * 1024 * 1024 + 13, 21);
    CHECK(writeHostFile(g_tmp + "/big.src", big));
    uint64_t reported = 0;
    CHECK(extWriteBackFile(0, "/dir-less.bin", g_tmp + "/big.src", [&](uint64_t n) { reported += n; return true; }));
    CHECK_EQ(reported, static_cast<uint64_t>(big.size()));
    CHECK(extExtractFile(0, "/dir-less.bin", g_tmp + "/big.out"));
    CHECK(readHostFile(g_tmp + "/big.out") == big);

    // Replacing a file with a shorter one must not leave the old tail behind.
    CHECK(writeHostFile(g_tmp + "/small.src", pseudoRandom(1024, 22)));
    CHECK(extWriteBackFile(0, "/dir-less.bin", g_tmp + "/small.src"));
    CHECK_EQ(extGetFileSize(0, "/dir-less.bin"), static_cast<uint64_t>(1024));
    CHECK(getFile(0, "/dir-less.bin") == pseudoRandom(1024, 22));

    // Cancelling (callback returns false) aborts and reports failure.
    CHECK(!extWriteBackFile(0, "/cancelled.bin", g_tmp + "/big.src", [](uint64_t) { return false; }));
    CHECK(!extWriteBackFile(0, "/nosource.bin", g_tmp + "/does-not-exist"));
    v.fsckClean("host file io");
}

static void test_rename_rules() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/d"));
    CHECK(putFile(0, "/f", pseudoRandom(5000, 31)));
    CHECK(putFile(0, "/d/g", pseudoRandom(6000, 32)));
    CHECK(extRenameFile(0, "/f", "/f2"));                   // same directory
    CHECK(!has(0, "", "f") && has(0, "", "f2"));
    CHECK(extRenameFile(0, "/f2", "/d/f3"));                // across directories
    CHECK(getFile(0, "/d/f3") == pseudoRandom(5000, 31));
    CHECK(!extRenameFile(0, "/d/f3", "/d/g"));              // never overwrite an existing name
    CHECK(getFile(0, "/d/g") == pseudoRandom(6000, 32));
    CHECK(getFile(0, "/d/f3") == pseudoRandom(5000, 31));
    CHECK(!extRenameFile(0, "/missing", "/x"));
    CHECK(!extRenameFile(0, "/d/f3", "/nope/x"));
    CHECK(!extRenameFile(0, "/d/f3", ""));
    CHECK(!extRenameFile(0, "/d/f3", "/"));
    CHECK(extCreateDirectory(0, "/e"));
    CHECK(!extRenameFile(0, "/d/f3", "/e/.."));  // ".." already exists in /e; it must not be clobbered
    CHECK(!extRenameFile(0, "/d/g", "/d"));      // file onto an existing directory
    CHECK(!extRenameFile(0, "/e", "/d/g"));      // directory onto an existing file
    CHECK(!extRenameFile(0, "/e", "/d"));        // directory onto an existing directory
    CHECK(extRenameFile(0, "/d", "/d"));         // renaming to itself is a harmless no-op
    CHECK(names(0, "/d") == (std::vector<std::string>{"f3", "g"}));
    v.fsckClean("rename rules");
}

static void test_directory_move_repoints_dotdot() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/p1"));
    CHECK(extCreateDirectory(0, "/p2"));
    CHECK(extCreateDirectory(0, "/p1/c"));
    CHECK(putFile(0, "/p1/c/inside.txt", pseudoRandom(777, 41)));
    const uint32_t p1Before = linksOf(0, "/p1"), p2Before = linksOf(0, "/p2");
    CHECK(extRenameFile(0, "/p1/c", "/p2/c"));
    CHECK_EQ(dotdotOf(0, "/p2/c"), inoOf(0, "/p2"));       // ".." follows the move
    CHECK_EQ(linksOf(0, "/p1"), p1Before - 1);             // old parent lost c's ".." link
    CHECK_EQ(linksOf(0, "/p2"), p2Before + 1);             // new parent gained it
    CHECK(getFile(0, "/p2/c/inside.txt") == pseudoRandom(777, 41));
    const uint32_t rootBefore = linksOf(0, "/");
    CHECK(extRenameFile(0, "/p2/c", "/c"));                // up to the root
    CHECK_EQ(dotdotOf(0, "/c"), inoOf(0, "/"));
    CHECK_EQ(linksOf(0, "/"), rootBefore + 1);
    v.fsckClean("directory moves");
}

static void test_directory_cannot_move_into_itself() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/a"));
    CHECK(extCreateDirectory(0, "/a/b"));
    CHECK(extCreateDirectory(0, "/ab"));   // shares a name *prefix* with /a, but isn't inside it
    CHECK(putFile(0, "/a/b/keep.txt", pseudoRandom(100, 51)));
    CHECK(!extRenameFile(0, "/a", "/a/b/a"));
    CHECK(!extRenameFile(0, "/a", "/a/a"));
    CHECK(!extRenameFile(0, "/a/b", "/a/b/b"));
    CHECK(has(0, "", "a"));                                   // still attached to the root
    CHECK(getFile(0, "/a/b/keep.txt") == pseudoRandom(100, 51));
    CHECK(extRenameFile(0, "/a", "/ab/a"));                   // a sibling that merely shares a prefix is fine
    CHECK(getFile(0, "/ab/a/b/keep.txt") == pseudoRandom(100, 51));
    // Deep chain: the top can't move under its own bottom.
    std::string deep;
    for (int i = 0; i < 20; ++i) { deep += "/L" + std::to_string(i); CHECK(extCreateDirectory(0, deep)); }
    CHECK(!extRenameFile(0, "/L0", deep + "/L0"));
    CHECK(has(0, "", "L0"));
    v.fsckClean("directory into itself");
}

static void test_delete_rules() {
    Vol v;
    CHECK(v.format("ext4", 16));
    const uint64_t freeAtStart = freeBytes(0);
    const uint32_t rootLinksAtStart = linksOf(0, "/");

    // A file's blocks come back.
    CHECK(putFile(0, "/f", pseudoRandom(1024 * 1024, 61)));
    CHECK(freeBytes(0) < freeAtStart);
    CHECK(extDeleteFile(0, "/f"));
    CHECK_EQ(freeBytes(0), freeAtStart);
    CHECK(!has(0, "", "f"));

    // An empty directory's inode, block and parent link come back. (It used to
    // be unlinked but kept allocated: e2fsck "Unconnected directory inode".)
    CHECK(extCreateDirectory(0, "/d"));
    CHECK_EQ(linksOf(0, "/"), rootLinksAtStart + 1);
    CHECK(extDeleteFile(0, "/d"));
    CHECK_EQ(freeBytes(0), freeAtStart);
    CHECK_EQ(linksOf(0, "/"), rootLinksAtStart);
    v.fsckClean("rmdir of an empty directory");

    // Bottom-up removal, which is what the Dart layer does for a folder.
    CHECK(extCreateDirectory(0, "/x"));
    CHECK(extCreateDirectory(0, "/x/y"));
    CHECK(extCreateDirectory(0, "/x/y/z"));
    CHECK(putFile(0, "/x/y/z/file", pseudoRandom(50000, 62)));
    CHECK(!extDeleteFile(0, "/x"));          // not empty: refused, nothing stranded
    CHECK(!extDeleteFile(0, "/x/y/z"));
    CHECK(getFile(0, "/x/y/z/file") == pseudoRandom(50000, 62));
    CHECK(extDeleteFile(0, "/x/y/z/file"));
    CHECK(extDeleteFile(0, "/x/y/z"));
    CHECK(extDeleteFile(0, "/x/y"));
    CHECK(extDeleteFile(0, "/x"));
    CHECK_EQ(freeBytes(0), freeAtStart);
    CHECK_EQ(linksOf(0, "/"), rootLinksAtStart);

    CHECK(!extDeleteFile(0, "/missing"));
    CHECK(!extDeleteFile(0, "/"));
    CHECK(!extDeleteFile(0, ""));
    CHECK(extCreateDirectory(0, "/d"));       // the name is reusable
    v.fsckClean("bottom-up delete");
}

static void test_writes_refuse_non_regular_targets() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/d"));
    CHECK(putFile(0, "/d/inner", pseudoRandom(100, 71)));
    const uint64_t dirSize = extGetFileSize(0, "/d");
    // ext2fs_file_open() would happily open a directory inode for writing.
    CHECK(!putFile(0, "/d", pseudoRandom(9000, 72)));
    CHECK(writeHostFile(g_tmp + "/x.src", pseudoRandom(100, 73)));
    CHECK(!extWriteBackFile(0, "/d", g_tmp + "/x.src"));
    CHECK(!extWriteFileChunk(0, "/", 0, pseudoRandom(10, 74).data(), 10));
    CHECK_EQ(extGetFileSize(0, "/d"), dirSize);
    CHECK(getFile(0, "/d/inner") == pseudoRandom(100, 71));
    CHECK(putFile(0, "/f", pseudoRandom(10, 75)));
    CHECK(!putFile(0, "/f/under-a-file", pseudoRandom(10, 76)));
    v.fsckClean("writes onto directories");
}

static void test_large_directory_grows() {
    Vol v;
    CHECK(v.format("ext4", 64));
    CHECK(extCreateDirectory(0, "/big"));
    const int kFiles = 600;
    auto nameOf = [](int i) { return "entry_" + std::to_string(i) + "_" + std::string(40, 'p'); };
    for (int i = 0; i < kFiles; ++i) CHECK(putFile(0, "/big/" + nameOf(i), Bytes(i % 7 + 1, static_cast<uint8_t>(i))));
    CHECK_EQ(list(0, "/big").size(), static_cast<size_t>(kFiles));
    for (int i = 0; i < kFiles; i += 97) CHECK_EQ(extGetFileSize(0, "/big/" + nameOf(i)), static_cast<uint64_t>(i % 7 + 1));
    v.fsckClean("directory growth");
    for (int i = 0; i < kFiles; i += 2) CHECK(extDeleteFile(0, "/big/" + nameOf(i)));
    CHECK_EQ(list(0, "/big").size(), static_cast<size_t>(kFiles / 2));
    for (int i = 1; i < kFiles; i += 2) CHECK(extDeleteFile(0, "/big/" + nameOf(i)));
    CHECK(extDeleteFile(0, "/big"));
    v.fsckClean("directory shrink");
}

static void test_set_last_modified_time() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/d"));
    CHECK(putFile(0, "/f", pseudoRandom(10, 81)));
    const uint64_t stamp = 1600000000;
    CHECK(extSetLastModifiedTime(0, "/f", stamp));
    CHECK(extSetLastModifiedTime(0, "/d", stamp + 5));
    CHECK(!extSetLastModifiedTime(0, "/missing", stamp));
    const auto root = list(0, "");
    CHECK(find(root, "f") && find(root, "f")->mtime == stamp);
    CHECK(find(root, "d") && find(root, "d")->mtime == stamp + 5);
    v.fsckClean("mtime");
}

static void test_space_info_tracks_usage() {
    Vol v;
    CHECK(v.format("ext4", 32));
    uint64_t total = 0, free0 = 0;
    extGetSpaceInfo(0, total, free0);
    CHECK_EQ(total, static_cast<uint64_t>(32) * 1024 * 1024);
    CHECK(free0 < total && free0 > total / 2);
    CHECK(putFile(0, "/one-mib", pseudoRandom(1024 * 1024, 91)));
    const uint64_t used = free0 - freeBytes(0);
    CHECK(used >= 1024 * 1024 && used <= 1024 * 1024 + 64 * 1024);   // data plus a little mapping overhead
    CHECK(extDeleteFile(0, "/one-mib"));
    CHECK_EQ(freeBytes(0), free0);
    v.fsckClean("space accounting");
}

static void test_copy_between_and_within_volumes() {
    Vol a, b;
    a.id = 0; b.id = 1;
    CHECK(a.format("ext4", 32));
    CHECK(b.format("ext2", 32));
    const Bytes data = pseudoRandom(2 * 1024 * 1024 + 5, 101);
    CHECK(putFile(0, "/src.bin", data));
    uint64_t reported = 0;
    CHECK(extCopyFile(0, "/src.bin", 1, "/dst.bin", [&](uint64_t n) { reported += n; return true; }));
    CHECK_EQ(reported, static_cast<uint64_t>(data.size()));
    CHECK(getFile(1, "/dst.bin") == data);
    CHECK(extCopyFile(0, "/src.bin", 0, "/copy.bin"));
    CHECK(getFile(0, "/copy.bin") == data);
    CHECK(extCreateDirectory(0, "/dir"));
    CHECK(!extCopyFile(0, "/src.bin", 0, "/dir"));           // can't copy a file over a directory
    CHECK(!extCopyFile(0, "/missing", 1, "/x"));
    CHECK(!extCopyFile(0, "/src.bin", 1, "/cancelled.bin", [](uint64_t) { return false; }));
    // Copying a file onto itself must be refused rather than lose the data (the destination is truncated first).
    CHECK(!extCopyFile(0, "/src.bin", 0, "/src.bin"));
    CHECK(getFile(0, "/src.bin") == data);
    a.fsckClean("copy source volume");
    b.fsckClean("copy destination volume");
}

static void test_streams_read_ranges() {
    Vol v;
    CHECK(v.format("ext4", 16));
    const Bytes data = pseudoRandom(1024 * 1024 + 321, 111);
    CHECK(putFile(0, "/s.bin", data));
    void* h = extOpenStream(0, "/s.bin");
    CHECK(h != nullptr);
    const std::pair<uint64_t, size_t> ranges[] = {{0, 4096}, {12345, 70000}, {data.size() - 100, 100}, {500000, 1}};
    for (const auto& r : ranges) {
        Bytes got(r.second);
        const int32_t n = extReadStream(0, h, r.first, got.data(), got.size());
        CHECK_EQ(n, static_cast<int32_t>(r.second));
        CHECK(std::equal(got.begin(), got.end(), data.begin() + r.first));
    }
    Bytes over(100);
    CHECK_EQ(extReadStream(0, h, data.size() + 10, over.data(), over.size()), 0);   // past EOF: nothing, not an error
    CHECK_EQ(extReadStream(0, reinterpret_cast<void*>(0x1234), 0, over.data(), over.size()), -1);  // unknown handle
    extCloseStream(0, h);
    extCloseStream(0, h);                                                            // double close is harmless
    CHECK(extOpenStream(0, "/missing") == nullptr);
    v.fsckClean("streams");
}

static void test_read_only_mount_changes_nothing() {
    Vol v;
    CHECK(v.format("ext4", 16));
    CHECK(extCreateDirectory(0, "/d"));
    CHECK(putFile(0, "/d/f", pseudoRandom(20000, 121)));
    v.closeFs();
    fflush(g_images[0]);
    const uint64_t before = hashHostFile(v.path);

    volumes[0].readOnly = true;
    CHECK(v.mount());
    CHECK(getFile(0, "/d/f") == pseudoRandom(20000, 121));   // reading works
    CHECK(!extCreateDirectory(0, "/new"));
    CHECK(!putFile(0, "/d/f", pseudoRandom(10, 122)));
    CHECK(!putFile(0, "/d/g", pseudoRandom(10, 123)));
    CHECK(!extRenameFile(0, "/d/f", "/d/h"));
    CHECK(!extDeleteFile(0, "/d/f"));
    CHECK(!extSetLastModifiedTime(0, "/d/f", 1600000000));
    v.closeFs();
    fflush(g_images[0]);
    CHECK_EQ(hashHostFile(v.path), before);                  // not a single byte of the image changed
    volumes[0].readOnly = false;
    CHECK(v.mount());
    CHECK(getFile(0, "/d/f") == pseudoRandom(20000, 121));
    v.fsckClean("read-only session");
}

// ---- Runner -------------------------------------------------------------------------
static void closeAllVolumes() {
    for (int i = 0; i < FF_VOLUMES; ++i) {
        Vol v;
        v.id = i;
        v.closeFs();
        if (g_images[i]) { fclose(g_images[i]); g_images[i] = nullptr; }
    }
}

int main() {
    if (!makeScratchDir("ext_backend_test")) return 2;
    if (!g_haveFsck) std::printf("NOTE: e2fsck not found; filesystem-consistency checks will be skipped.\n");
    const TestCase tests[] = {
        T(test_format_variants_pass_fsck),
        T(test_mounts_images_made_by_system_mkfs),
        T(test_mkdir_rules),
        T(test_names_wire_format_and_limits),
        T(test_chunked_io_roundtrip),
        T(test_write_offset_rules),
        T(test_host_file_roundtrip_overwrite_and_cancel),
        T(test_rename_rules),
        T(test_directory_move_repoints_dotdot),
        T(test_directory_cannot_move_into_itself),
        T(test_delete_rules),
        T(test_writes_refuse_non_regular_targets),
        T(test_large_directory_grows),
        T(test_set_last_modified_time),
        T(test_space_info_tracks_usage),
        T(test_copy_between_and_within_volumes),
        T(test_streams_read_ranges),
        T(test_read_only_mount_changes_nothing),
    };
    return runTests("ext_backend", tests, sizeof(tests) / sizeof(tests[0]), closeAllVolumes);
}
