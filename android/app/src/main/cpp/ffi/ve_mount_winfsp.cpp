// OS mount (Windows) through WinFsp's FUSE 3 compatibility API. The same MountFs (ve_mount_fs.h) as the
// Linux glue sits underneath; this file only translates WinFsp's FUSE callbacks and runs the mount
// lifecycle. Public C ABI: ve_engine.h ("OS mounts").
//
// STATUS: compiles (MinGW cross-build) but has NOT been run on Windows -- there is no WinFsp driver in
// the environment it was written in. Treat it as a careful first draft and test it on a real machine.
//
// How it works / lessons taken from Cryptomator's jfuse-win + fuse-nio-adapter:
//   * winfsp-x64.dll is loaded at runtime from WinFsp's install dir (registry
//     HKLM\SOFTWARE\WOW6432Node\WinFsp\InstallDir), so the engine DLL loads -- and everything else works --
//     without WinFsp; ve_mount_supported() then says why mounting is unavailable. WinFsp's own header is
//     designed for this: FSP_FUSE_API_CALL is overridden to resolve each function lazily.
//   * The loop is fuse3_loop (WinFsp: one dispatcher thread, coarse operation guard) -- like the Linux glue.
//   * Teardown order matters on WinFsp (jfuse#176): fuse3_exit only stops the loop; fuse3_unmount and
//     fuse3_destroy happen after the loop thread has exited, never while it is still running.
//   * Mount point: a drive letter ("X:") or a directory that does NOT exist yet (WinFsp creates it as a
//     reparse point; an existing empty directory is removed first).
//   * Errors: the glue returns -errno as MountFs does. WinFsp's "Windows" environment (what the header's
//     fsp_fuse_env() declares) maps the CRT's errno values, which are what MinGW's errno.h uses.

#include "ve_engine.h"
#include "ve_mount_internal.h"

#if defined(_WIN32) && defined(VE_HAVE_WINFSP)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "ve_mount_fs.h"

// ── lazy access to winfsp-x64.dll ───────────────────────────────────────────────────────────────────
// WinFsp's headers call every exported function through FSP_FUSE_API_CALL(name); redirect that to a
// per-call-site cached GetProcAddress, and declare the functions without dllimport so nothing is linked.
namespace vewinfsp {
void* symbol(const char* name);
template <class F>
F* load(const char* name) {
    return reinterpret_cast<F*>(symbol(name));
}
}  // namespace vewinfsp

#define FSP_FUSE_API
#define FSP_FUSE_API_NAME(n) n
#define FSP_FUSE_API_CALL(n) \
    ([]() -> decltype(n)* { static decltype(n)* p = vewinfsp::load<decltype(n)>(#n); return p; }())
#include <fuse3/fuse.h>

namespace {

constexpr const char* kProbePath = "/.ve_mount_probe";

// ── DLL discovery ───────────────────────────────────────────────────────────────────────────────────

std::once_flag gOnce;
HMODULE gModule = nullptr;
std::string gLoadError;

std::wstring widen(const std::string& s) {
    if (s.empty()) return std::wstring();
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), &w[0], n);
    return w;
}

std::string narrow(const std::wstring& w) {
    if (w.empty()) return std::string();
    const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), &s[0], n, nullptr, nullptr);
    return s;
}

void loadModule() {
    std::wstring dir;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WOW6432Node\\WinFsp", 0, KEY_READ, &key) == ERROR_SUCCESS) {
        DWORD type = 0, bytes = 0;
        if (RegQueryValueExW(key, L"InstallDir", nullptr, &type, nullptr, &bytes) == ERROR_SUCCESS &&
            type == REG_SZ && bytes >= sizeof(wchar_t)) {
            std::vector<wchar_t> buf(bytes / sizeof(wchar_t) + 1, L'\0');
            DWORD got = bytes;
            if (RegQueryValueExW(key, L"InstallDir", nullptr, nullptr, reinterpret_cast<LPBYTE>(buf.data()), &got) ==
                ERROR_SUCCESS) {
                dir = buf.data();
            }
        }
        RegCloseKey(key);
    }
    if (dir.empty()) dir = L"C:\\Program Files (x86)\\WinFsp\\";
    if (dir.back() != L'\\') dir.push_back(L'\\');
#if defined(__aarch64__) || defined(_M_ARM64)
    const wchar_t* dll = L"bin\\winfsp-a64.dll";
#else
    const wchar_t* dll = L"bin\\winfsp-x64.dll";
#endif
    const std::wstring dllPath = dir + dll;
    gModule = LoadLibraryExW(dllPath.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!gModule) {
        const DWORD err = GetLastError();
        if (GetFileAttributesW(dllPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
            gLoadError = "WinFsp is not installed (looked for " + narrow(dllPath) +
                         "; get it from https://winfsp.dev, install the Core component)";
        } else {
            // present but refused to load (a missing dependency also reports ERROR_MOD_NOT_FOUND)
            gLoadError = "could not load " + narrow(dllPath) + " (Windows error " + std::to_string(err) + ")";
        }
        return;
    }
    static const char* required[] = {"fsp_fuse3_new", "fsp_fuse3_mount", "fsp_fuse3_unmount", "fsp_fuse3_destroy",
                                     "fsp_fuse3_exit", "fsp_fuse3_loop", "fsp_fuse3_get_context",
                                     "fsp_fuse_opt_add_arg", "fsp_fuse_opt_free_args"};
    std::string missing;
    for (const char* name : required) {
        if (!GetProcAddress(gModule, name)) {
            if (!missing.empty()) missing += ", ";
            missing += name;
        }
    }
    if (!missing.empty()) {
        gLoadError = "the WinFsp at " + narrow(dllPath) + " is missing: " + missing +
                     " (the FUSE 3 API needs a recent WinFsp; please update it)";
        FreeLibrary(gModule);
        gModule = nullptr;
    }
}

}  // namespace

void* vewinfsp::symbol(const char* name) {
    std::call_once(gOnce, loadModule);
    return gModule ? reinterpret_cast<void*>(GetProcAddress(gModule, name)) : nullptr;
}

namespace {

// ── one mount ───────────────────────────────────────────────────────────────────────────────────────

struct Mount {
    int64_t id = 0;
    int32_t vol = -1;
    std::string mountPoint;  // UTF-8: "X:" or a directory path
    bool readOnly = false;
    std::unique_ptr<vemount::MountFs> fs;
    struct fuse3* fuse = nullptr;
    std::thread loop;
    std::atomic<bool> unmountRequested{false};
    std::atomic<bool> loopEnded{false};
    std::atomic<bool> probeSeen{false};
    std::atomic<bool> reaped{false};
};

std::mutex gMu;
std::map<int64_t, std::shared_ptr<Mount>> gMounts;
std::atomic<int64_t> gNextId{1};
std::mutex gCbMu;
void (*gCallback)(int64_t, int32_t) = nullptr;

Mount* current() { return static_cast<Mount*>(fuse3_get_context()->private_data); }

void fireCallback(int64_t id, int32_t event) {
    void (*cb)(int64_t, int32_t) = nullptr;
    {
        std::lock_guard<std::mutex> g(gCbMu);
        cb = gCallback;
    }
    if (cb) cb(id, event);
}

void fillStat(const Mount* m, const vemount::Attr& a, struct fuse_stat* st) {
    std::memset(st, 0, sizeof(*st));
    switch (a.type) {
        case vemount::NodeType::Dir:
            st->st_mode = 0040000 | (m->readOnly ? 0555 : 0755);
            st->st_nlink = 2;
            break;
        case vemount::NodeType::Symlink:
            st->st_mode = 0120000 | 0777;
            st->st_nlink = 1;
            st->st_size = static_cast<fuse_off_t>(a.size);
            break;
        default:
            st->st_mode = 0100000 | (m->readOnly ? 0444 : 0644);
            st->st_nlink = 1;
            st->st_size = static_cast<fuse_off_t>(a.size);
            break;
    }
    st->st_blksize = 4096;
    st->st_blocks = static_cast<fuse_blkcnt_t>((a.size + 511) / 512);
    st->st_atim.tv_sec = a.mtime;
    st->st_mtim.tv_sec = a.mtime;
    st->st_ctim.tv_sec = a.mtime;
    st->st_birthtim.tv_sec = a.mtime;
}

// WinFsp composes fi->flags from the CRT's O_* values: 0 = read, 1 = write, 2 = read/write; create comes
// with O_CREAT|O_EXCL. Overwrite arrives as truncate(path, 0), not as O_TRUNC.
int toOpenFlags(int flags, bool creating) {
    int f = 0;
    switch (flags & 3) {
        case 0: f |= vemount::kOpenRead; break;
        case 1: f |= vemount::kOpenWrite; break;
        default: f |= vemount::kOpenRead | vemount::kOpenWrite; break;
    }
    if (flags & 0x0200) f |= vemount::kOpenTrunc;  // _O_TRUNC
    if (creating && (flags & 0x0400)) f |= vemount::kOpenExcl;  // _O_EXCL
    return f;
}

#define GUARD(expr)   \
    try {             \
        expr;         \
    } catch (...) {   \
        return -EIO;  \
    }

// ── FUSE operations ─────────────────────────────────────────────────────────────────────────────────

int opGetattr(const char* path, struct fuse_stat* st, struct fuse3_file_info*) {
    Mount* m = current();
    if (std::strcmp(path, kProbePath) == 0) {
        m->probeSeen.store(true);
        return -ENOENT;
    }
    vemount::Attr a;
    int rc = 0;
    GUARD(rc = m->fs->getattr(path, a));
    if (rc != 0) return rc;
    fillStat(m, a, st);
    return 0;
}

int opReadlink(const char* path, char* buf, size_t size) {
    std::string target;
    int rc = 0;
    GUARD(rc = current()->fs->readlink(path, target));
    if (rc != 0) return rc;
    if (size == 0) return -EINVAL;
    const size_t n = std::min(target.size(), size - 1);
    std::memcpy(buf, target.data(), n);
    buf[n] = '\0';
    return 0;
}

int opMkdir(const char* path, fuse_mode_t) { GUARD(return current()->fs->mkdir(path)); }
int opUnlink(const char* path) { GUARD(return current()->fs->unlink(path)); }
int opRmdir(const char* path) { GUARD(return current()->fs->rmdir(path)); }
int opSymlink(const char* target, const char* link) { GUARD(return current()->fs->symlink(target, link)); }
int opRename(const char* from, const char* to, unsigned int flags) {
    GUARD(return current()->fs->rename(from, to, flags));
}
int opChmod(const char*, fuse_mode_t, struct fuse3_file_info*) { return 0; }
int opChown(const char*, fuse_uid_t, fuse_gid_t, struct fuse3_file_info*) { return 0; }

int opTruncate(const char* path, fuse_off_t size, struct fuse3_file_info* fi) {
    if (size < 0) return -EINVAL;
    Mount* m = current();
    if (fi && fi->fh != 0 && fi->fh != static_cast<uint64_t>(-1)) {
        GUARD(return m->fs->ftruncate(fi->fh, static_cast<uint64_t>(size)));
    }
    GUARD(return m->fs->truncate(path, static_cast<uint64_t>(size)));
}

int opOpen(const char* path, struct fuse3_file_info* fi) {
    uint64_t fh = 0;
    int rc = 0;
    GUARD(rc = current()->fs->open(path, toOpenFlags(fi->flags, false), fh));
    if (rc != 0) return rc;
    fi->fh = fh;
    return 0;
}

int opCreate(const char* path, fuse_mode_t, struct fuse3_file_info* fi) {
    uint64_t fh = 0;
    int rc = 0;
    GUARD(rc = current()->fs->create(path, toOpenFlags(fi->flags, true), fh));
    if (rc != 0) return rc;
    fi->fh = fh;
    return 0;
}

int opRead(const char*, char* buf, size_t size, fuse_off_t off, struct fuse3_file_info* fi) {
    if (off < 0) return -EINVAL;
    GUARD(return current()->fs->read(fi->fh, reinterpret_cast<uint8_t*>(buf), size, static_cast<uint64_t>(off)));
}

int opWrite(const char*, const char* buf, size_t size, fuse_off_t off, struct fuse3_file_info* fi) {
    if (off < 0) return -EINVAL;
    GUARD(return current()->fs->write(fi->fh, reinterpret_cast<const uint8_t*>(buf), size, static_cast<uint64_t>(off)));
}

int opFlush(const char*, struct fuse3_file_info* fi) { GUARD(return current()->fs->flush(fi->fh)); }
int opFsync(const char*, int, struct fuse3_file_info* fi) { GUARD(return current()->fs->flush(fi->fh)); }
int opRelease(const char*, struct fuse3_file_info* fi) {
    try { current()->fs->release(fi->fh); } catch (...) {}
    return 0;
}

int opStatfs(const char*, struct fuse_statvfs* sv) {
    vemount::StatFsInfo info;
    int rc = 0;
    GUARD(rc = current()->fs->statfs(info));
    if (rc != 0) return rc;
    std::memset(sv, 0, sizeof(*sv));
    sv->f_bsize = info.blockSize;
    sv->f_frsize = info.blockSize;
    sv->f_blocks = info.blocks;
    sv->f_bfree = info.blocksFree;
    sv->f_bavail = info.blocksFree;
    sv->f_namemax = info.nameMax;
    return 0;
}

// WinFsp fills in unchanged timestamps itself, so tv[1] is always the value to store.
int opUtimens(const char* path, const struct fuse_timespec tv[2], struct fuse3_file_info*) {
    GUARD(return current()->fs->setMtime(path, static_cast<int64_t>(tv[1].tv_sec)));
}

int opReaddir(const char* path, void* buf, fuse3_fill_dir_t filler, fuse_off_t, struct fuse3_file_info*,
              enum fuse3_readdir_flags flags) {
    Mount* m = current();
    std::vector<vemount::DirItem> items;
    int rc = 0;
    GUARD(rc = m->fs->readdir(path, items));
    if (rc != 0) return rc;
    const enum fuse3_fill_dir_flags fill =
        (flags & FUSE_READDIR_PLUS) ? FUSE_FILL_DIR_PLUS : static_cast<enum fuse3_fill_dir_flags>(0);
    struct fuse_stat dirSt;
    fillStat(m, vemount::Attr{vemount::NodeType::Dir, 0, static_cast<int64_t>(std::time(nullptr))}, &dirSt);
    filler(buf, ".", &dirSt, 0, fill);
    filler(buf, "..", &dirSt, 0, fill);
    for (const auto& item : items) {
        if (item.name.empty() || item.name.size() > 255) continue;
        struct fuse_stat st;
        fillStat(m, item.attr, &st);
        if (filler(buf, item.name.c_str(), &st, 0, fill) != 0) break;
    }
    return 0;
}

void* opInit(struct fuse3_conn_info* conn, struct fuse3_config*) {
    conn->want |= (conn->capable & FUSE_CAP_READDIRPLUS);
    return fuse3_get_context()->private_data;
}

void fillOps(struct fuse3_operations& ops) {
    std::memset(&ops, 0, sizeof(ops));
    ops.getattr = opGetattr;
    ops.readlink = opReadlink;
    ops.mkdir = opMkdir;
    ops.unlink = opUnlink;
    ops.rmdir = opRmdir;
    ops.symlink = opSymlink;
    ops.rename = opRename;
    ops.chmod = opChmod;
    ops.chown = opChown;
    ops.truncate = opTruncate;
    ops.open = opOpen;
    ops.read = opRead;
    ops.write = opWrite;
    ops.statfs = opStatfs;
    ops.flush = opFlush;
    ops.release = opRelease;
    ops.fsync = opFsync;
    ops.readdir = opReaddir;
    ops.init = opInit;
    ops.create = opCreate;
    ops.utimens = opUtimens;
}

// ── mount point ─────────────────────────────────────────────────────────────────────────────────────

bool isDriveLetter(const std::string& mp) {
    return mp.size() == 2 && mp[1] == ':' && ((mp[0] >= 'A' && mp[0] <= 'Z') || (mp[0] >= 'a' && mp[0] <= 'z'));
}

std::string probePathOf(const std::string& mp) { return mp + "\\.ve_mount_probe"; }

// Validates the target and prepares it for WinFsp. Returns "" or a reason.
std::string prepareMountPoint(std::string& mp) {
    while (mp.size() > 3 && (mp.back() == '\\' || mp.back() == '/')) mp.pop_back();
    if (mp.size() == 3 && mp[1] == ':' && (mp[2] == '\\' || mp[2] == '/')) mp.pop_back();  // "X:\" -> "X:"
    if (isDriveLetter(mp)) {
        mp[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(mp[0])));
        const DWORD used = GetLogicalDrives();
        if (used & (1u << (mp[0] - 'A'))) return "drive letter " + mp + " is already in use";
        return "";
    }
    // A directory path: WinFsp creates the leaf itself, so it must not exist; the parent must.
    const std::wstring w = widen(mp);
    if (w.size() < 4 || w[1] != L':' ) return "mount point must be a drive letter (X:) or an absolute directory path";
    const DWORD attrs = GetFileAttributesW(w.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES) {
        if (!(attrs & FILE_ATTRIBUTE_DIRECTORY)) return "mount point exists and is not a directory";
        if (attrs & FILE_ATTRIBUTE_REPARSE_POINT) return "something is already mounted there";
        if (!RemoveDirectoryW(w.c_str())) return "mount point exists and is not empty";  // empty ones are removed
    }
    const size_t slash = w.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return "invalid mount point";
    const DWORD parent = GetFileAttributesW(w.substr(0, slash).c_str());
    if (parent == INVALID_FILE_ATTRIBUTES || !(parent & FILE_ATTRIBUTE_DIRECTORY)) return "the parent folder of the mount point does not exist";
    return "";
}

std::string sanitizeName(const char* name) {
    std::string out = name && *name ? name : "VaultExplorer";
    for (char& c : out) {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ' ||
                        c == '_' || c == '-' || c == '.';
        if (!ok) c = '_';
    }
    if (out.size() > 32) out.resize(32);  // WinFsp volume labels are short
    return out;
}

// Tears one mount down. force=false refuses (VE_ERR_BUSY) while files are open.
int32_t unmountOne(const std::shared_ptr<Mount>& m, bool force) {
    if (m->reaped.load()) return VE_OK;
    if (!m->loopEnded.load()) {
        if (!force && m->fs->openHandleCount() > 0) {
            ve_mount_set_error("the vault is in use (files are open)");
            return VE_ERR_BUSY;
        }
        m->unmountRequested.store(true);
        fuse3_exit(m->fuse);  // only stops the loop; the volume is detached below, after the loop has exited
    } else {
        m->unmountRequested.store(true);
    }
    for (int i = 0; i < 200 && !m->loopEnded.load(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    if (m->loop.joinable()) {
        if (m->loopEnded.load()) m->loop.join();
        else m->loop.detach();  // stuck inside a blocked engine call; do not hang the caller
    }
    try { m->fs->closeAll(); } catch (...) {}  // commit what is pending while the slot is still open
    fuse3_unmount(m->fuse);
    fuse3_destroy(m->fuse);
    m->fuse = nullptr;
    m->reaped.store(true);
    {
        std::lock_guard<std::mutex> g(gMu);
        gMounts.erase(m->id);
    }
    return VE_OK;
}

}  // namespace

// ── public C ABI ─────────────────────────────────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_mount_supported(char* reason_buf, size_t reason_cap) {
    std::call_once(gOnce, loadModule);
    const std::string reason = gModule ? std::string() : gLoadError;
    if (reason_buf && reason_cap > 0) {
        const size_t n = std::min(reason.size(), reason_cap - 1);
        std::memcpy(reason_buf, reason.data(), n);
        reason_buf[n] = '\0';
    }
    return reason.empty() ? 1 : 0;
}

extern "C" VE_API int32_t ve_mount(int32_t vol, const char* mountPointUtf8, const ve_mount_options* opts,
                                   int64_t* outId) {
    if (outId) *outId = 0;
    if (!mountPointUtf8 || !outId) return VE_ERR_INVALID_ARG;
    char reason[256];
    if (!ve_mount_supported(reason, sizeof(reason))) {
        ve_mount_set_error(reason);
        return VE_ERR_UNSUPPORTED;
    }
    bool fv = false, ci = false, ro = false;  // ci: MountFs already matches names case-insensitively
    if (!ve_internal_vol_traits(vol, &fv, &ci, &ro)) return VE_ERR_NOT_UNLOCKED;

    std::string mp = mountPointUtf8;
    const std::string prep = prepareMountPoint(mp);
    if (!prep.empty()) {
        ve_mount_set_error(prep);
        return VE_ERR_INVALID_ARG;
    }
    {
        std::lock_guard<std::mutex> g(gMu);
        for (auto& kv : gMounts) {
            if (kv.second->mountPoint == mp) {
                ve_mount_set_error("something is already mounted there");
                return VE_ERR_INVALID_ARG;
            }
        }
    }

    vemount::FsOptions fo;
    fo.readOnly = (opts && opts->read_only) || ro;
    if (opts && opts->sub_path && opts->sub_path[0] && std::strcmp(opts->sub_path, "/") != 0) fo.root = opts->sub_path;
    if (opts && opts->max_buffer_mb > 0) fo.maxBufferBytes = static_cast<uint64_t>(opts->max_buffer_mb) << 20;

    auto m = std::make_shared<Mount>();
    m->id = gNextId.fetch_add(1);
    m->vol = vol;
    m->mountPoint = mp;
    m->readOnly = fo.readOnly;
    m->fs = std::make_unique<vemount::MountFs>(vol, fo);

    // uid/gid -1: files belong to whoever mounted it; volname is the label Explorer shows.
    std::string optStr = "uid=-1,gid=-1,FileSystemName=VaultExplorer,volname=" +
                         sanitizeName(opts ? opts->volume_name : nullptr) + ",attr_timeout=2";
    struct fuse_args args = FUSE_ARGS_INIT(0, nullptr);
    fuse_opt_add_arg(&args, "vaultexplorer");
    fuse_opt_add_arg(&args, "-o");
    fuse_opt_add_arg(&args, optStr.c_str());
    struct fuse3_operations ops;
    fillOps(ops);
    m->fuse = fuse3_new(&args, &ops, sizeof(ops), m.get());
    fuse_opt_free_args(&args);
    if (!m->fuse) {
        ve_mount_set_error("fuse3_new failed (unsupported mount options?)");
        return VE_ERR_MOUNT_FAILED;
    }
    if (fuse3_mount(m->fuse, m->mountPoint.c_str()) != 0) {
        fuse3_destroy(m->fuse);
        m->fuse = nullptr;
        ve_mount_set_error("WinFsp refused the mount (is the drive letter or folder already in use?)");
        return VE_ERR_MOUNT_FAILED;
    }
    {
        std::lock_guard<std::mutex> g(gMu);
        gMounts[m->id] = m;
    }
    Mount* raw = m.get();
    m->loop = std::thread([raw]() {
        fuse3_loop(raw->fuse);
        raw->loopEnded.store(true);
        if (!raw->unmountRequested.load()) fireCallback(raw->id, 1);  // detached from outside
    });

    // Probe: wait until the file system has really been asked something.
    const std::wstring probe = widen(probePathOf(m->mountPoint));
    for (int i = 0; i < 100 && !m->probeSeen.load() && !m->loopEnded.load(); ++i) {
        GetFileAttributesW(probe.c_str());
        if (!m->probeSeen.load()) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    if (!m->probeSeen.load()) {
        ve_mount_set_error("the mount did not start serving requests");
        unmountOne(m, true);
        return VE_ERR_MOUNT_FAILED;
    }
    *outId = m->id;
    return VE_OK;
}

extern "C" VE_API int32_t ve_unmount(int64_t id, int32_t force) {
    std::shared_ptr<Mount> m;
    {
        std::lock_guard<std::mutex> g(gMu);
        auto it = gMounts.find(id);
        if (it == gMounts.end()) return VE_OK;  // already gone
        m = it->second;
    }
    return unmountOne(m, force != 0);
}

extern "C" VE_API int32_t ve_list_mounts(ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    std::vector<std::string> rows;
    {
        std::lock_guard<std::mutex> g(gMu);
        for (auto& kv : gMounts) {
            const auto& m = kv.second;
            rows.push_back(std::to_string(m->id) + "|" + std::to_string(m->vol) + "|" +
                           (m->loopEnded.load() ? "ended" : "active") + "|" + m->mountPoint);
        }
    }
    std::vector<uint8_t> packed;
    auto putU32 = [&](uint32_t v) {
        for (int i = 0; i < 4; ++i) packed.push_back(static_cast<uint8_t>(v >> (8 * i)));
    };
    putU32(static_cast<uint32_t>(rows.size()));
    for (auto& r : rows) {
        putU32(static_cast<uint32_t>(r.size()));
        packed.insert(packed.end(), r.begin(), r.end());
    }
    out->data = static_cast<uint8_t*>(std::malloc(packed.size()));
    if (!out->data) return VE_ERR_FAILED;
    std::memcpy(out->data, packed.data(), packed.size());
    out->len = packed.size();
    return VE_OK;
}

extern "C" VE_API void ve_set_mount_callback(void (*cb)(int64_t, int32_t)) {
    std::lock_guard<std::mutex> g(gCbMu);
    gCallback = cb;
}

void ve_internal_unmount_volume(int32_t vol) {
    std::vector<std::shared_ptr<Mount>> mine;
    {
        std::lock_guard<std::mutex> g(gMu);
        for (auto& kv : gMounts) {
            if (kv.second->vol == vol) mine.push_back(kv.second);
        }
    }
    for (auto& m : mine) {
        if (unmountOne(m, false) == VE_ERR_BUSY) unmountOne(m, true);  // locking must not leave keys alive
    }
}

#endif  // _WIN32 && VE_HAVE_WINFSP
