// Host-side tests for filesystems/ntfs_backend.cpp -- the real backend, the real
// ntfs-3g library (at the commit CMakeLists.txt pins) and the app's own embedded
// mkntfs, run against image files.
//
// Same idea as ext_backend_test.cpp: only the bottom of the I/O stack is faked.
// physicalRead()/physicalWrite() are implemented over plain host files, and the
// volume is configured as an unencrypted flat container, so the backend's
// "no encryption layer at all -- pass bytes straight through" path is what runs.
// BitLocker, VHD/VHDX and the cipher cascade are stubbed out; the NTFS logic
// above them is the same code that runs on top of a decrypted BitLocker volume.
//
// Oracles are *independent* programs, not the backend reading back its own
// output: ntfsfix -n for volume sanity, and ntfsls / ntfscat (system ntfs-3g
// tools) to list directories and read file contents. If those aren't on PATH the
// tests still run, with a loud SKIP for each independent check.
//
// Paths are relative to the volume root with no leading slash ("dir/file"), the
// form the backend's callers use.
//
// Build + run: filesystems/test/run_ntfs_backend_test.sh (it fetches and builds
// the pinned ntfs-3g into a cache directory the first time).
//
// NOT covered: BitLocker/VHD layers, FAT, and Windows' own chkdsk (nothing here
// can run it). ntfsfix is a much weaker check than e2fsck is for ext.
#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

extern "C" {
#include <ntfs-3g/device.h>
#include <ntfs-3g/volume.h>
}

#include "bitlocker_backend.h"
#include "block_io.h"
#include "containers/vhd_image.h"
#include "containers/vhdx_image.h"
#include "crypto/cascade.h"
#include "diskio.h"
#include "filesystems/ntfs_backend.h"
#include "session/volume_state.h"

#include "fs_test_support.h"

// ---- The pieces of the app this test stands in for ----------------------------------
VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;
bool CompositeBlockDevice::sync() { return true; }
bool VhdImage::pread(uint64_t, unsigned char*, size_t) { return false; }
bool VhdImage::pwrite(uint64_t, const unsigned char*, size_t) { return false; }
bool VhdxImage::pread(uint64_t, unsigned char*, size_t) { return false; }
bool VhdxImage::pwrite(uint64_t, const unsigned char*, size_t) { return false; }
bool bitlockerRead(int, uint64_t, unsigned char*, size_t) { return false; }
bool bitlockerWrite(int, uint64_t, const unsigned char*, size_t) { return false; }
void cascadeEncryptSector(const CascadeContext&, uint64_t, const unsigned char*, unsigned char*) {}
void cascadeDecryptSector(const CascadeContext&, uint64_t, const unsigned char*, unsigned char*) {}
void blockCipherEncryptBlock(const BlockCipherContext&, const unsigned char*, unsigned char*) {}
void blockCipherDecryptBlock(const BlockCipherContext&, const unsigned char*, unsigned char*) {}
bool usbFlushAndSync(int) { return true; }

static int g_fd[FF_VOLUMES] = {-1, -1, -1, -1, -1, -1, -1, -1};
static int g_deviceId[FF_VOLUMES] = {0, 1, 2, 3, 4, 5, 6, 7};

bool physicalRead(int volumeId, uint64_t offset, unsigned char* buffer, size_t count) {
    return g_fd[volumeId] >= 0 && pread(g_fd[volumeId], buffer, count, static_cast<off_t>(offset)) == static_cast<ssize_t>(count);
}
bool physicalWrite(int volumeId, uint64_t offset, const unsigned char* buffer, size_t count) {
    if (volumes[volumeId].readOnly) return false;   // as io/block_io.cpp does
    return g_fd[volumeId] >= 0 && pwrite(g_fd[volumeId], buffer, count, static_cast<off_t>(offset)) == static_cast<ssize_t>(count);
}

extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);

static const bool g_haveFix = commandExists("ntfsfix");
static const bool g_haveLs = commandExists("ntfsls") && commandExists("ntfscat");

// ---- Volume fixture -----------------------------------------------------------------
struct Vol {
    int id = 0;
    std::string path;

    void attach() {
        if (g_fd[id] >= 0) close(g_fd[id]);
        g_fd[id] = open(path.c_str(), O_RDWR);
        VolumeState& v = volumes[id];
        v.containerFormat = ContainerFormat::kPlain;
        v.plainBacking = VolumeState::PlainBacking::kFlatFile;
        v.dataOffset = 0;
        v.dataAreaLengthBytes = static_cast<uint64_t>(lseek(g_fd[id], 0, SEEK_END));
        v.readOnly = false;
        v.fd = -1;
    }
    // Same sequence the app uses (io/virtual_block_device.cpp): wrap the volume id in an
    // ntfs_device backed by vExplorer_ntfs_ops, then ntfs_device_mount().
    bool mount(bool readOnly = false) {
        VolumeState& v = volumes[id];
        v.readOnly = readOnly;
        v.fsType = VolumeState::FS_NTFS;
        struct ntfs_device* dev = ntfs_device_alloc("vaultexplorer", 0, &vExplorer_ntfs_ops, &g_deviceId[id]);
        if (!dev) return false;
        v.ntfsVol = ntfs_device_mount(dev, readOnly ? NTFS_MNT_RDONLY : 0);
        if (!v.ntfsVol) return false;
        v.fsMounted = true;
        return true;
    }
    void closeFs() {
        VolumeState& v = volumes[id];
        if (v.ntfsVol) { ntfs_umount(v.ntfsVol, FALSE); v.ntfsVol = nullptr; }
        v.fsMounted = false;
        v.fsType = VolumeState::FS_UNKNOWN;
    }
    // New image formatted by the app's own embedded mkntfs.
    bool format(uint64_t mib) {
        closeFs();
        path = g_tmp + "/vol" + std::to_string(id) + ".img";
        const std::string cmd = "rm -f '" + path + "'; truncate -s " + std::to_string(mib) + "M '" + path + "'";
        if (std::system(cmd.c_str()) != 0) return false;
        attach();
        const std::string dev = "ve" + std::to_string(id);
        char* args[] = {(char*)"mkntfs", (char*)"-F", (char*)"-Q", (char*)"-s", (char*)"512",
                        (char*)"-p",     (char*)"0",  (char*)dev.c_str(), nullptr};
        if (vaultexplorer_mkntfs_main(8, args) != 0) return false;
        volumes[id].fsType = VolumeState::FS_UNKNOWN;
        return mount();
    }
    // ntfsfix -n: sanity-check the unmounted image without writing to it.
    bool fsckClean(const char* what) {
        closeFs();
        bool clean = true;
        if (g_haveFix) {
            const std::string cmd = "ntfsfix -n '" + path + "' >'" + g_tmp + "/fix.log' 2>&1";
            const int rc = std::system(cmd.c_str());
            clean = rc == 0;
            if (!clean) {
                std::printf("    ntfsfix found problems after '%s' (exit %d):\n", what, rc);
                const std::string show = "head -12 '" + g_tmp + "/fix.log' | sed 's/^/        /'";
                std::system(show.c_str());
            }
        } else {
            ++g_skips;
            std::printf("    SKIP ntfsfix check '%s' (ntfsfix not on PATH)\n", what);
        }
        attach();
        mount();
        ++g_checks;
        if (!clean) { ++g_failures; std::printf("    FAIL ntfsfix clean: %s\n", what); }
        return clean;
    }
    // Directory listing / file contents as seen by the system ntfs-3g tools, not by the backend.
    std::vector<std::string> indepList(const std::string& dir) {
        closeFs();
        std::vector<std::string> out;
        if (g_haveLs) {
            const std::string cmd = "ntfsls -f -p '/" + dir + "' '" + path + "' 2>/dev/null";
            FILE* p = popen(cmd.c_str(), "r");
            char line[4096];
            while (p && fgets(line, sizeof(line), p)) {
                std::string name(line);
                while (!name.empty() && (name.back() == '\n' || name.back() == '\r')) name.pop_back();
                if (!name.empty() && name != "." && name != "..") out.push_back(name);
            }
            if (p) pclose(p);
            std::sort(out.begin(), out.end());
        } else {
            ++g_skips;
        }
        attach();
        mount();
        return out;
    }
    Bytes indepCat(const std::string& file) {
        closeFs();
        Bytes out;
        if (g_haveLs) {
            const std::string cmd = "ntfscat -f '" + path + "' '/" + file + "' 2>/dev/null";
            FILE* p = popen(cmd.c_str(), "r");
            uint8_t buf[65536];
            size_t n;
            while (p && (n = fread(buf, 1, sizeof(buf), p)) > 0) out.insert(out.end(), buf, buf + n);
            if (p) pclose(p);
        } else {
            ++g_skips;
        }
        attach();
        mount();
        return out;
    }
};

// ---- Helpers over the production API ------------------------------------------------
struct Entry { bool isDir; uint64_t size; uint64_t mtime; std::string name; };

static std::vector<Entry> list(int vol, const std::string& dir) {
    std::vector<std::string> raw;
    listNtfsDirectory(vol, dir, raw);
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
    return ntfsWriteFileChunk(vol, path, 0, data.data(), data.size());
}
static Bytes getFile(int vol, const std::string& path) {
    Bytes out, chunk;
    uint64_t offset = 0;
    while (ntfsReadFileChunk(vol, path, offset, 100000, chunk) && !chunk.empty()) {
        out.insert(out.end(), chunk.begin(), chunk.end());
        offset += chunk.size();
    }
    return out;
}
static uint64_t freeBytes(int vol) {
    uint64_t total = 0, free = 0;
    ntfsGetSpaceInfo(vol, total, free);
    return free;
}

// ---- Tests --------------------------------------------------------------------------
static void test_product_mkntfs_can_run_repeatedly() {
    // The app formats every NTFS volume in-process, one call after another.
    // mkntfs keeps getopt() state and a freed allocation list in globals, so before
    // the wrapper in mkntfs_embedded.c.in reset them the second call in a process
    // failed (glibc) or walked freed memory (use-after-free).
    for (int round = 0; round < 3; ++round) {
        for (uint64_t mib : {8, 32, 96}) {
            Vol v;
            CHECK(v.format(mib));
            CHECK(list(0, "").empty());   // a fresh volume has an empty root (system files are hidden)
            CHECK(!ntfsIsDirty(0));
            CHECK(!ntfsHasCorruptDirectoryEntries(0));
            uint64_t total = 0, free = 0;
            ntfsGetSpaceInfo(0, total, free);
            CHECK(total > (mib - 1) * 1024 * 1024 / 2 && total <= mib * 1024 * 1024);
            CHECK(free > total / 2);
            const std::string what = "mkntfs " + std::to_string(mib) + "MiB round " + std::to_string(round);
            v.fsckClean(what.c_str());
        }
    }
}

static void test_mkdir_rules() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "a"));
    CHECK(ntfsCreateDirectory(0, "a/b"));
    CHECK(!ntfsCreateDirectory(0, "a"));          // name taken by a directory
    CHECK(!ntfsCreateDirectory(0, "a/b"));
    CHECK(putFile(0, "f", pseudoRandom(10, 1)));
    CHECK(!ntfsCreateDirectory(0, "f"));          // name taken by a file
    CHECK(!ntfsCreateDirectory(0, "f/sub"));      // parent is a file
    CHECK(!ntfsCreateDirectory(0, "nope/x"));     // parent missing
    CHECK(!ntfsCreateDirectory(0, ""));
    const auto root = list(0, "");
    CHECK(find(root, "a") && find(root, "a")->isDir);
    CHECK(find(root, "f") && !find(root, "f")->isDir && find(root, "f")->size == 10);
    CHECK((v.indepList("") == std::vector<std::string>{"a", "f"}) || !g_haveLs);
    CHECK((v.indepList("a") == std::vector<std::string>{"b"}) || !g_haveLs);
    v.fsckClean("mkdir rules");
}

static void test_names_and_limits() {
    Vol v;
    CHECK(v.format(32));
    // Names the backend must hand back byte-for-byte, including non-BMP characters (UTF-16 pairs)
    // and the '|' the directory wire format uses as a separator.
    const std::string odd[] = {"pipe|in|name", "sp ace.txt", "\xC3\x9C" "n\xC3\xAF" "code.txt",
                               "smile \xF0\x9F\x98\x80.txt", "-dash", ".hidden"};
    for (const auto& n : odd) {
        CHECK(putFile(0, n, pseudoRandom(100 + n.size(), 2)));
        const auto entries = list(0, "");
        const Entry* e = find(entries, n);
        CHECK(e != nullptr && !e->isDir && e->size == 100 + n.size());
    }
    if (g_haveLs) {
        const auto indep = v.indepList("");
        for (const auto& n : odd) CHECK(std::find(indep.begin(), indep.end(), n) != indep.end());
    }
    // NTFS names are at most 255 UTF-16 units. Beyond that the u8 length handed to
    // ntfs_create()/ntfs_link() wraps, and a *different*, shorter name used to be stored.
    const std::string max255(255, 'm');
    CHECK(putFile(0, max255, pseudoRandom(5, 3)));
    CHECK(has(0, "", max255));
    CHECK(!putFile(0, std::string(256, 'x'), pseudoRandom(5, 4)));
    CHECK(!putFile(0, std::string(300, 'y'), pseudoRandom(5, 4)));
    CHECK(!ntfsCreateDirectory(0, std::string(300, 'q')));
    CHECK(putFile(0, "short", pseudoRandom(5, 6)));
    CHECK(!ntfsRenameFile(0, "short", std::string(300, 'z')));
    CHECK(has(0, "", "short"));
    for (const auto& e : list(0, "")) CHECK(e.name != std::string(44, 'q') && e.name != std::string(44, 'y') && e.name != std::string(44, 'z'));
    v.fsckClean("names");
}

static void test_chunked_io_roundtrip() {
    Vol v;
    CHECK(v.format(48));
    const Bytes data = pseudoRandom(3 * 1024 * 1024 + 777, 11);
    const size_t chunk = 65536;
    for (size_t off = 0; off < data.size(); off += chunk) {
        const size_t n = std::min(chunk, data.size() - off);
        CHECK(ntfsWriteFileChunk(0, "big.bin", off, data.data() + off, n));
    }
    CHECK_EQ(ntfsGetFileSize(0, "big.bin"), static_cast<uint64_t>(data.size()));
    CHECK(getFile(0, "big.bin") == data);
    Bytes tail;
    CHECK(ntfsReadFileChunk(0, "big.bin", data.size() - 10, 100, tail));
    CHECK_EQ(tail.size(), static_cast<size_t>(10));
    CHECK(std::equal(tail.begin(), tail.end(), data.end() - 10));
    CHECK(!ntfsReadFileChunk(0, "missing.bin", 0, 10, tail));
    if (g_haveLs) CHECK(v.indepCat("big.bin") == data);   // the system ntfs-3g reads the same bytes back
    v.fsckClean("chunked io");
}

static void test_write_offset_rules() {
    Vol v;
    CHECK(v.format(32));
    Bytes a(20000, 'A'), b(100, 'B'), c(50, 'C');
    CHECK(putFile(0, "f", a));
    // Offset 0 starts a new file: it truncates (this is how the import path restarts a file).
    CHECK(ntfsWriteFileChunk(0, "f", 0, b.data(), b.size()));
    CHECK_EQ(ntfsGetFileSize(0, "f"), static_cast<uint64_t>(100));
    // A write inside the file keeps its size and doesn't disturb the rest.
    CHECK(ntfsWriteFileChunk(0, "f", 10, c.data(), c.size()));
    CHECK_EQ(ntfsGetFileSize(0, "f"), static_cast<uint64_t>(100));
    Bytes got = getFile(0, "f");
    CHECK_EQ(got.size(), static_cast<size_t>(100));
    CHECK(std::all_of(got.begin(), got.begin() + 10, [](uint8_t x) { return x == 'B'; }));
    CHECK(std::all_of(got.begin() + 10, got.begin() + 60, [](uint8_t x) { return x == 'C'; }));
    CHECK(std::all_of(got.begin() + 60, got.end(), [](uint8_t x) { return x == 'B'; }));
    // Appending at the end extends it.
    CHECK(ntfsWriteFileChunk(0, "f", 100, c.data(), c.size()));
    CHECK_EQ(ntfsGetFileSize(0, "f"), static_cast<uint64_t>(150));
    v.fsckClean("write offsets");
}

static void test_host_file_roundtrip_overwrite_and_cancel() {
    Vol v;
    CHECK(v.format(48));
    const Bytes big = pseudoRandom(5 * 1024 * 1024 + 13, 21);
    CHECK(writeHostFile(g_tmp + "/big.src", big));
    uint64_t reported = 0;
    CHECK(ntfsWriteBackFile(0, "big.bin", g_tmp + "/big.src", [&](uint64_t n) { reported += n; return true; }));
    CHECK_EQ(reported, static_cast<uint64_t>(big.size()));
    CHECK(ntfsExtractFile(0, "big.bin", g_tmp + "/big.out"));
    CHECK(readHostFile(g_tmp + "/big.out") == big);

    // Replacing a file with a shorter one must not leave the old tail behind.
    CHECK(writeHostFile(g_tmp + "/small.src", pseudoRandom(1024, 22)));
    CHECK(ntfsWriteBackFile(0, "big.bin", g_tmp + "/small.src"));
    CHECK_EQ(ntfsGetFileSize(0, "big.bin"), static_cast<uint64_t>(1024));
    CHECK(getFile(0, "big.bin") == pseudoRandom(1024, 22));

    CHECK(!ntfsWriteBackFile(0, "cancelled.bin", g_tmp + "/big.src", [](uint64_t) { return false; }));
    CHECK(!ntfsWriteBackFile(0, "nosource.bin", g_tmp + "/does-not-exist"));
    v.fsckClean("host file io");
}

static void test_rename_rules() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "d"));
    CHECK(putFile(0, "f", pseudoRandom(5000, 31)));
    CHECK(putFile(0, "d/g", pseudoRandom(6000, 32)));
    CHECK(ntfsRenameFile(0, "f", "f2"));                    // same directory
    CHECK(!has(0, "", "f") && has(0, "", "f2"));
    CHECK(ntfsRenameFile(0, "f2", "d/f3"));                 // across directories
    CHECK(getFile(0, "d/f3") == pseudoRandom(5000, 31));
    CHECK(!ntfsRenameFile(0, "d/f3", "d/g"));               // never overwrite an existing name
    CHECK(getFile(0, "d/g") == pseudoRandom(6000, 32));
    CHECK(getFile(0, "d/f3") == pseudoRandom(5000, 31));
    CHECK(!ntfsRenameFile(0, "missing", "x"));
    CHECK(!ntfsRenameFile(0, "d/f3", "nope/x"));
    CHECK(!ntfsRenameFile(0, "d/f3", ""));
    CHECK(!ntfsRenameFile(0, "d/g", "d"));                  // file onto an existing directory
    CHECK(names(0, "d") == (std::vector<std::string>{"f3", "g"}));
    if (g_haveLs) CHECK((v.indepList("d") == std::vector<std::string>{"f3", "g"}));
    v.fsckClean("rename rules");
}

static void test_rename_reports_success_and_changes_only_the_name() {
    // Regression test for a "Move failed" shown on moves that had in fact completed (seen
    // on BitLocker volumes, whose NTFS layer is this same code): the result must be true
    // exactly when the file is at the new path and gone from the old one.
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "from"));
    CHECK(ntfsCreateDirectory(0, "to"));
    for (int i = 0; i < 40; ++i) {
        const std::string name = "file_" + std::to_string(i) + ".bin";
        CHECK(putFile(0, "from/" + name, pseudoRandom(1000 + i, 200 + i)));
    }
    for (int i = 0; i < 40; ++i) {
        const std::string name = "file_" + std::to_string(i) + ".bin";
        const bool ok = ntfsRenameFile(0, "from/" + name, "to/" + name);
        CHECK(ok);
        CHECK(ok == (has(0, "to", name) && !has(0, "from", name)));
    }
    CHECK(list(0, "from").empty());
    CHECK_EQ(list(0, "to").size(), static_cast<size_t>(40));
    for (int i = 0; i < 40; i += 7) CHECK(getFile(0, "to/file_" + std::to_string(i) + ".bin") == pseudoRandom(1000 + i, 200 + i));
    // A case-only rename is a rename, not a collision with itself.
    CHECK(putFile(0, "Foo.txt", pseudoRandom(10, 5)));
    CHECK(ntfsRenameFile(0, "Foo.txt", "foo.txt"));
    CHECK(has(0, "", "foo.txt") && !has(0, "", "Foo.txt"));
    v.fsckClean("move batch");
    if (g_haveLs) CHECK((v.indepList("from").empty()));
}

static void test_directory_move_keeps_contents() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "p1"));
    CHECK(ntfsCreateDirectory(0, "p2"));
    CHECK(ntfsCreateDirectory(0, "p1/c"));
    CHECK(ntfsCreateDirectory(0, "p1/c/sub"));
    CHECK(putFile(0, "p1/c/inside.txt", pseudoRandom(777, 41)));
    CHECK(putFile(0, "p1/c/sub/deep.txt", pseudoRandom(888, 42)));
    CHECK(ntfsRenameFile(0, "p1/c", "p2/c"));
    CHECK(!has(0, "p1", "c") && has(0, "p2", "c"));
    CHECK(getFile(0, "p2/c/inside.txt") == pseudoRandom(777, 41));
    CHECK(getFile(0, "p2/c/sub/deep.txt") == pseudoRandom(888, 42));
    CHECK(ntfsRenameFile(0, "p2/c", "c"));                 // up to the root
    CHECK(getFile(0, "c/sub/deep.txt") == pseudoRandom(888, 42));
    if (g_haveLs) {
        CHECK((v.indepList("c") == std::vector<std::string>{"inside.txt", "sub"}));
        CHECK(v.indepCat("c/sub/deep.txt") == pseudoRandom(888, 42));
        CHECK(v.indepList("p2").empty() && v.indepList("p1").empty());
    }
    v.fsckClean("directory moves");
}

static void test_directory_cannot_move_into_itself() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "a"));
    CHECK(ntfsCreateDirectory(0, "a/b"));
    CHECK(ntfsCreateDirectory(0, "ab"));    // shares a name *prefix* with a, but isn't inside it
    CHECK(putFile(0, "a/b/keep.txt", pseudoRandom(100, 51)));
    CHECK(!ntfsRenameFile(0, "a", "a/b/a"));
    CHECK(!ntfsRenameFile(0, "a", "a/a"));
    CHECK(!ntfsRenameFile(0, "a/b", "a/b/b"));
    CHECK(has(0, "", "a"));                                   // still attached to the root
    CHECK(getFile(0, "a/b/keep.txt") == pseudoRandom(100, 51));
    CHECK(ntfsRenameFile(0, "a", "ab/a"));                    // a sibling that merely shares a prefix is fine
    CHECK(getFile(0, "ab/a/b/keep.txt") == pseudoRandom(100, 51));
    std::string deep;
    for (int i = 0; i < 20; ++i) { deep += (deep.empty() ? "" : "/") + std::string("L") + std::to_string(i); CHECK(ntfsCreateDirectory(0, deep)); }
    CHECK(!ntfsRenameFile(0, "L0", deep + "/L0"));
    CHECK(has(0, "", "L0"));
    if (g_haveLs) CHECK((v.indepList("") == std::vector<std::string>{"ab", "L0"}) || (v.indepList("") == std::vector<std::string>{"L0", "ab"}));
    v.fsckClean("directory into itself");
}

static void test_delete_rules() {
    Vol v;
    CHECK(v.format(48));
    const uint64_t freeAtStart = freeBytes(0);
    // A file's data clusters come back. (The MFT itself may have grown, and never shrinks, so a
    // small allowance is expected.)
    CHECK(putFile(0, "f", pseudoRandom(2 * 1024 * 1024, 61)));
    CHECK(freeBytes(0) + 2 * 1024 * 1024 <= freeAtStart + 64 * 1024);
    CHECK(ntfsDeleteFile(0, "f"));
    CHECK(freeBytes(0) + 128 * 1024 >= freeAtStart);
    CHECK(!has(0, "", "f"));

    CHECK(ntfsCreateDirectory(0, "x"));
    CHECK(ntfsCreateDirectory(0, "x/y"));
    CHECK(putFile(0, "x/y/file", pseudoRandom(50000, 62)));
    CHECK(!ntfsDeleteFile(0, "x"));              // not empty: refused, nothing stranded
    CHECK(!ntfsDeleteFile(0, "x/y"));
    CHECK(getFile(0, "x/y/file") == pseudoRandom(50000, 62));
    CHECK(ntfsDeleteFile(0, "x/y/file"));        // bottom-up, as the Dart layer does for a folder
    CHECK(ntfsDeleteFile(0, "x/y"));
    CHECK(ntfsDeleteFile(0, "x"));
    CHECK(list(0, "").empty());
    CHECK(!ntfsDeleteFile(0, "missing"));
    CHECK(!ntfsDeleteFile(0, ""));
    CHECK(ntfsCreateDirectory(0, "x"));          // the name is reusable
    if (g_haveLs) CHECK((v.indepList("") == std::vector<std::string>{"x"}));
    v.fsckClean("deletes");
}

static void test_writes_refuse_directories() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "d"));
    CHECK(putFile(0, "d/inner", pseudoRandom(100, 71)));
    // Without the guard these succeed and add an unnamed $DATA stream to the directory itself.
    CHECK(!putFile(0, "d", pseudoRandom(9000, 72)));
    CHECK(writeHostFile(g_tmp + "/x.src", pseudoRandom(100, 73)));
    CHECK(!ntfsWriteBackFile(0, "d", g_tmp + "/x.src"));
    CHECK(putFile(0, "f", pseudoRandom(100, 74)));
    CHECK(!ntfsCopyFile(0, "f", 0, "d"));
    CHECK_EQ(ntfsGetFileSize(0, "d"), static_cast<uint64_t>(0));
    CHECK(getFile(0, "d/inner") == pseudoRandom(100, 71));
    CHECK(putFile(0, "f2", pseudoRandom(10, 75)));
    CHECK(!putFile(0, "f2/under-a-file", pseudoRandom(10, 76)));
    v.fsckClean("writes onto directories");
}

static void test_large_directory_grows() {
    Vol v;
    CHECK(v.format(64));
    CHECK(ntfsCreateDirectory(0, "big"));
    const int kFiles = 600;
    auto nameOf = [](int i) { return "entry_" + std::to_string(i) + "_" + std::string(40, 'p'); };
    for (int i = 0; i < kFiles; ++i) CHECK(putFile(0, "big/" + nameOf(i), Bytes(i % 7 + 1, static_cast<uint8_t>(i))));
    CHECK_EQ(list(0, "big").size(), static_cast<size_t>(kFiles));
    for (int i = 0; i < kFiles; i += 97) CHECK_EQ(ntfsGetFileSize(0, "big/" + nameOf(i)), static_cast<uint64_t>(i % 7 + 1));
    CHECK(!ntfsHasCorruptDirectoryEntries(0));
    if (g_haveLs) CHECK_EQ(v.indepList("big").size(), static_cast<size_t>(kFiles));   // the index B-tree is readable by ntfs-3g's own tools
    v.fsckClean("directory growth");
    for (int i = 0; i < kFiles; i += 2) CHECK(ntfsDeleteFile(0, "big/" + nameOf(i)));
    CHECK_EQ(list(0, "big").size(), static_cast<size_t>(kFiles / 2));
    for (int i = 1; i < kFiles; i += 2) CHECK(ntfsDeleteFile(0, "big/" + nameOf(i)));
    CHECK(ntfsDeleteFile(0, "big"));
    v.fsckClean("directory shrink");
}

static void test_set_last_modified_time() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "d"));
    CHECK(putFile(0, "f", pseudoRandom(10, 81)));
    const uint64_t stamp = 1600000000;
    CHECK(ntfsSetLastModifiedTime(0, "f", stamp));
    CHECK(ntfsSetLastModifiedTime(0, "d", stamp + 5));
    CHECK(!ntfsSetLastModifiedTime(0, "missing", stamp));
    const auto root = list(0, "");
    CHECK(find(root, "f") && find(root, "f")->mtime == stamp);
    CHECK(find(root, "d") && find(root, "d")->mtime == stamp + 5);
    v.fsckClean("mtime");
}

static void test_copy_between_and_within_volumes() {
    Vol a, b;
    a.id = 0; b.id = 1;
    CHECK(a.format(48));
    CHECK(b.format(48));
    const Bytes data = pseudoRandom(2 * 1024 * 1024 + 5, 101);
    CHECK(putFile(0, "src.bin", data));
    uint64_t reported = 0;
    CHECK(ntfsCopyFile(0, "src.bin", 1, "dst.bin", [&](uint64_t n) { reported += n; return true; }));
    CHECK_EQ(reported, static_cast<uint64_t>(data.size()));
    CHECK(getFile(1, "dst.bin") == data);
    CHECK(ntfsCopyFile(0, "src.bin", 0, "copy.bin"));
    CHECK(getFile(0, "copy.bin") == data);
    CHECK(!ntfsCopyFile(0, "missing", 1, "x"));
    CHECK(!ntfsCopyFile(0, "src.bin", 1, "cancelled.bin", [](uint64_t) { return false; }));
    // Copying a file onto itself must not lose its data (the destination is truncated first).
    ntfsCopyFile(0, "src.bin", 0, "src.bin");
    CHECK(getFile(0, "src.bin") == data);
    a.fsckClean("copy source volume");
    b.fsckClean("copy destination volume");
}

static void test_streams_read_ranges() {
    Vol v;
    CHECK(v.format(32));
    const Bytes data = pseudoRandom(1024 * 1024 + 321, 111);
    CHECK(putFile(0, "s.bin", data));
    void* h = ntfsOpenStream(0, "s.bin");
    CHECK(h != nullptr);
    const std::pair<uint64_t, size_t> ranges[] = {{0, 4096}, {12345, 70000}, {data.size() - 100, 100}, {500000, 1}};
    for (const auto& r : ranges) {
        Bytes got(r.second);
        const int32_t n = ntfsReadStream(0, h, r.first, got.data(), got.size());
        CHECK_EQ(n, static_cast<int32_t>(r.second));
        CHECK(std::equal(got.begin(), got.end(), data.begin() + r.first));
    }
    Bytes over(100);
    CHECK_EQ(ntfsReadStream(0, reinterpret_cast<void*>(0x1234), 0, over.data(), over.size()), -1);   // unknown handle
    ntfsCloseStream(0, h);
    ntfsCloseStream(0, h);                                                                           // double close is harmless
    CHECK(ntfsOpenStream(0, "missing") == nullptr);
    v.fsckClean("streams");
}

static void test_read_only_mount_changes_nothing() {
    Vol v;
    CHECK(v.format(32));
    CHECK(ntfsCreateDirectory(0, "d"));
    CHECK(putFile(0, "d/f", pseudoRandom(20000, 121)));
    v.closeFs();
    const uint64_t before = hashHostFile(v.path);

    CHECK(v.mount(/*readOnly=*/true));
    CHECK(getFile(0, "d/f") == pseudoRandom(20000, 121));   // reading works
    CHECK(!ntfsCreateDirectory(0, "new"));
    CHECK(!putFile(0, "d/f", pseudoRandom(10, 122)));
    CHECK(!putFile(0, "d/g", pseudoRandom(10, 123)));
    CHECK(!ntfsRenameFile(0, "d/f", "d/h"));
    CHECK(!ntfsDeleteFile(0, "d/f"));
    v.closeFs();
    CHECK_EQ(hashHostFile(v.path), before);                  // not a single byte of the image changed
    CHECK(v.mount());
    CHECK(getFile(0, "d/f") == pseudoRandom(20000, 121));
    v.fsckClean("read-only session");
}

// ---- Runner -------------------------------------------------------------------------
static void closeAllVolumes() {
    for (int i = 0; i < FF_VOLUMES; ++i) {
        Vol v;
        v.id = i;
        v.closeFs();
        if (g_fd[i] >= 0) { close(g_fd[i]); g_fd[i] = -1; }
    }
}

int main() {
    if (!makeScratchDir("ntfs_backend_test")) return 2;
    if (!g_haveFix) std::printf("NOTE: ntfsfix not found; volume-sanity checks will be skipped.\n");
    if (!g_haveLs) std::printf("NOTE: ntfsls/ntfscat not found; independent read-back checks will be skipped.\n");
    const TestCase tests[] = {
        T(test_product_mkntfs_can_run_repeatedly),
        T(test_mkdir_rules),
        T(test_names_and_limits),
        T(test_chunked_io_roundtrip),
        T(test_write_offset_rules),
        T(test_host_file_roundtrip_overwrite_and_cancel),
        T(test_rename_rules),
        T(test_rename_reports_success_and_changes_only_the_name),
        T(test_directory_move_keeps_contents),
        T(test_directory_cannot_move_into_itself),
        T(test_delete_rules),
        T(test_writes_refuse_directories),
        T(test_large_directory_grows),
        T(test_set_last_modified_time),
        T(test_copy_between_and_within_volumes),
        T(test_streams_read_ranges),
        T(test_read_only_mount_changes_nothing),
    };
    return runTests("ntfs_backend", tests, sizeof(tests) / sizeof(tests[0]), closeAllVolumes);
}
