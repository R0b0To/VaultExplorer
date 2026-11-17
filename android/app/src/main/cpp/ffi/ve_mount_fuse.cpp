// OS mount lifecycle + libfuse3 glue (Linux) for the desktop engine. See ve_mount_fs.h for the filesystem
// model and ve_engine.h for the C ABI.
//
// Design notes (each is a lesson from reading Cryptomator's jfuse / fuse-nio-adapter / integrations-linux,
// or from VeraCrypt's FuseService):
//   * libfuse3 is resolved with dlopen at runtime, so the engine library loads -- and everything else
//     works -- on machines without FUSE; ve_mount_supported() then says why mounting is unavailable.
//   * mount() does not return until the kernel has actually asked us for an attribute (a "probe" stat on
//     the new mount). A mount that exists but is not serving yet looks mounted to the caller.
//   * Unmount is graceful first (`fusermount3 -u`, refused while files are open) and only then forced
//     (libfuse's own lazy detach), and always commits pending writes before the keys can be wiped.
//   * -o auto_unmount lets the kernel side clean up if this process dies, so a crash does not leave a
//     stale "Transport endpoint is not connected" mount behind.
//   * A mount that ends on its own (user ejects it from the file manager, `fusermount3 -u`) is reported
//     through ve_set_mount_callback so the app can lock the vault.
//   * The libfuse loop is single-threaded: the engine serialises each volume behind one lock anyway, and a
//     single thread removes a whole class of ordering bugs. (fuse_loop_mt is a later optimisation.)

#include "ve_engine.h"
#include "ve_mount_internal.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

extern "C" void ve_log_dispatch(int prio, const char* tag, const char* message);

namespace {

std::mutex gErrMu;
std::string gLastError;

void setLastError(const std::string& msg) {
    std::lock_guard<std::mutex> g(gErrMu);
    gLastError = msg;
    ve_log_dispatch(5, "VaultExplorer_mount", msg.c_str());
}
}  // namespace

void ve_mount_set_error(const std::string& message) { setLastError(message); }

namespace {

void copyOut(const std::string& s, char* buf, size_t cap) {
    if (!buf || cap == 0) return;
    const size_t n = std::min(s.size(), cap - 1);
    std::memcpy(buf, s.data(), n);
    buf[n] = '\0';
}

}  // namespace

extern "C" VE_API int32_t ve_mount_last_error(char* buf, size_t cap) {
    std::lock_guard<std::mutex> g(gErrMu);
    copyOut(gLastError, buf, cap);
    return static_cast<int32_t>(gLastError.size());
}

#if defined(VE_HAVE_FUSE3) && !defined(_WIN32)

#define FUSE_USE_VERSION 31
#include <fuse3/fuse.h>

#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ve_mount_fs.h"

extern char** environ;

namespace {

constexpr const char* kProbePath = "/.ve_mount_probe";

// ── libfuse3, resolved at runtime ───────────────────────────────────────────────────────────────────

struct FuseApi {
    void* lib = nullptr;
    struct fuse* (*fnNew)(struct fuse_args*, const struct fuse_operations*, size_t, void*) = nullptr;
    int (*fnMount)(struct fuse*, const char*) = nullptr;
    void (*fnUnmount)(struct fuse*) = nullptr;
    void (*fnDestroy)(struct fuse*) = nullptr;
    void (*fnExit)(struct fuse*) = nullptr;
    int (*fnLoop)(struct fuse*) = nullptr;
    struct fuse_context* (*fnContext)(void) = nullptr;
    int (*fnOptAddArg)(struct fuse_args*, const char*) = nullptr;
    void (*fnOptFreeArgs)(struct fuse_args*) = nullptr;
    const char* (*fnPkgVersion)(void) = nullptr;
};

FuseApi gApi;
std::once_flag gApiOnce;
std::string gApiError;

template <typename T>
bool sym(void* lib, const char* name, T& out) {
    out = reinterpret_cast<T>(dlsym(lib, name));
    return out != nullptr;
}

void loadApi() {
    const char* names[] = {"libfuse3.so.4", "libfuse3.so.3", "libfuse3.so"};
    for (const char* n : names) {
        gApi.lib = dlopen(n, RTLD_NOW | RTLD_LOCAL);
        if (gApi.lib) break;
    }
    if (!gApi.lib) {
        gApiError = "libfuse3 not found (install the 'fuse3' package)";
        return;
    }
    const bool ok = sym(gApi.lib, "fuse_new", gApi.fnNew) && sym(gApi.lib, "fuse_mount", gApi.fnMount) &&
                    sym(gApi.lib, "fuse_unmount", gApi.fnUnmount) && sym(gApi.lib, "fuse_destroy", gApi.fnDestroy) &&
                    sym(gApi.lib, "fuse_exit", gApi.fnExit) && sym(gApi.lib, "fuse_loop", gApi.fnLoop) &&
                    sym(gApi.lib, "fuse_get_context", gApi.fnContext) &&
                    sym(gApi.lib, "fuse_opt_add_arg", gApi.fnOptAddArg) &&
                    sym(gApi.lib, "fuse_opt_free_args", gApi.fnOptFreeArgs);
    sym(gApi.lib, "fuse_pkgversion", gApi.fnPkgVersion);
    if (!ok) {
        gApiError = "libfuse3 is installed but missing expected symbols (too old?)";
        dlclose(gApi.lib);
        gApi.lib = nullptr;
    }
}

bool inPath(const char* exe) {
    const char* path = std::getenv("PATH");
    if (!path) path = "/usr/bin:/bin:/usr/sbin:/sbin";
    std::string p(path);
    size_t start = 0;
    while (start <= p.size()) {
        size_t end = p.find(':', start);
        if (end == std::string::npos) end = p.size();
        const std::string dir = p.substr(start, end - start);
        if (!dir.empty() && access((dir + "/" + exe).c_str(), X_OK) == 0) return true;
        start = end + 1;
    }
    return false;
}

// ── one mount ───────────────────────────────────────────────────────────────────────────────────────

struct Mount {
    int64_t id = 0;
    int32_t vol = -1;
    std::string mountPoint;
    std::unique_ptr<vemount::MountFs> fs;
    struct fuse* fuse = nullptr;
    std::thread loop;
    std::atomic<bool> unmountRequested{false};
    std::atomic<bool> loopEnded{false};
    std::atomic<bool> probeSeen{false};
    std::atomic<bool> reaped{false};
    uid_t uid = 0;
    gid_t gid = 0;
};

std::mutex gMu;
std::map<int64_t, std::shared_ptr<Mount>> gMounts;
std::atomic<int64_t> gNextId{1};
std::mutex gCbMu;
void (*gCallback)(int64_t, int32_t) = nullptr;

Mount* current() { return static_cast<Mount*>(gApi.fnContext()->private_data); }

void fillStat(const Mount* m, const vemount::Attr& a, struct stat* st) {
    std::memset(st, 0, sizeof(*st));
    st->st_uid = m->uid;
    st->st_gid = m->gid;
    switch (a.type) {
        case vemount::NodeType::Dir:
            st->st_mode = S_IFDIR | 0755;
            st->st_nlink = 2;
            break;
        case vemount::NodeType::Symlink:
            st->st_mode = S_IFLNK | 0777;
            st->st_nlink = 1;
            st->st_size = static_cast<off_t>(a.size);
            break;
        default:
            st->st_mode = S_IFREG | 0644;
            st->st_nlink = 1;
            st->st_size = static_cast<off_t>(a.size);
            break;
    }
    st->st_blksize = 4096;
    st->st_blocks = static_cast<blkcnt_t>((a.size + 511) / 512);
    st->st_mtim.tv_sec = a.mtime;
    st->st_atim.tv_sec = a.mtime;
    st->st_ctim.tv_sec = a.mtime;
}

int toOpenFlags(int posixFlags, bool creating) {
    int f = 0;
    switch (posixFlags & O_ACCMODE) {
        case O_RDONLY: f |= vemount::kOpenRead; break;
        case O_WRONLY: f |= vemount::kOpenWrite; break;
        default: f |= vemount::kOpenRead | vemount::kOpenWrite; break;
    }
    if (posixFlags & O_TRUNC) f |= vemount::kOpenTrunc;
    if (creating && (posixFlags & O_EXCL)) f |= vemount::kOpenExcl;
    return f;
}

#define GUARD(expr)                      \
    try {                                \
        expr;                            \
    } catch (...) {                      \
        return -EIO;                     \
    }

// ── FUSE operations (thin translation onto MountFs) ─────────────────────────────────────────────────

int opGetattr(const char* path, struct stat* st, struct fuse_file_info*) {
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

int opMkdir(const char* path, mode_t) { GUARD(return current()->fs->mkdir(path)); }
int opUnlink(const char* path) { GUARD(return current()->fs->unlink(path)); }
int opRmdir(const char* path) { GUARD(return current()->fs->rmdir(path)); }
int opSymlink(const char* target, const char* link) { GUARD(return current()->fs->symlink(target, link)); }
int opRename(const char* from, const char* to, unsigned int flags) {
    GUARD(return current()->fs->rename(from, to, flags));
}
int opChmod(const char*, mode_t, struct fuse_file_info*) { return 0; }  // permission bits are not stored
int opChown(const char*, uid_t, gid_t, struct fuse_file_info*) { return 0; }

int opTruncate(const char* path, off_t size, struct fuse_file_info* fi) {
    if (size < 0) return -EINVAL;
    Mount* m = current();
    if (fi) {
        GUARD(return m->fs->ftruncate(fi->fh, static_cast<uint64_t>(size)));
    }
    GUARD(return m->fs->truncate(path, static_cast<uint64_t>(size)));
}

int opOpen(const char* path, struct fuse_file_info* fi) {
    uint64_t fh = 0;
    int rc = 0;
    GUARD(rc = current()->fs->open(path, toOpenFlags(fi->flags, false), fh));
    if (rc != 0) return rc;
    fi->fh = fh;
    return 0;
}

int opCreate(const char* path, mode_t, struct fuse_file_info* fi) {
    uint64_t fh = 0;
    int rc = 0;
    GUARD(rc = current()->fs->create(path, toOpenFlags(fi->flags, true), fh));
    if (rc != 0) return rc;
    fi->fh = fh;
    return 0;
}

int opRead(const char*, char* buf, size_t size, off_t off, struct fuse_file_info* fi) {
    if (off < 0) return -EINVAL;
    GUARD(return current()->fs->read(fi->fh, reinterpret_cast<uint8_t*>(buf), size, static_cast<uint64_t>(off)));
}

int opWrite(const char*, const char* buf, size_t size, off_t off, struct fuse_file_info* fi) {
    if (off < 0) return -EINVAL;
    GUARD(return current()->fs->write(fi->fh, reinterpret_cast<const uint8_t*>(buf), size, static_cast<uint64_t>(off)));
}

int opFlush(const char*, struct fuse_file_info* fi) { GUARD(return current()->fs->flush(fi->fh)); }
int opFsync(const char*, int, struct fuse_file_info* fi) { GUARD(return current()->fs->flush(fi->fh)); }
int opRelease(const char*, struct fuse_file_info* fi) {
    try { current()->fs->release(fi->fh); } catch (...) {}
    return 0;
}

int opStatfs(const char*, struct statvfs* sv) {
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

int opUtimens(const char* path, const struct timespec tv[2], struct fuse_file_info*) {
    if (tv[1].tv_nsec == UTIME_OMIT) return 0;
    const int64_t secs = tv[1].tv_nsec == UTIME_NOW ? static_cast<int64_t>(std::time(nullptr))
                                                     : static_cast<int64_t>(tv[1].tv_sec);
    GUARD(return current()->fs->setMtime(path, secs));
}

int opFallocate(const char* path, int mode, off_t offset, off_t length, struct fuse_file_info* fi) {
    if (mode != 0) return -EOPNOTSUPP;  // punch-hole / collapse-range etc. are not supported
    if (offset < 0 || length < 0) return -EINVAL;
    Mount* m = current();
    vemount::Attr a;
    int rc = 0;
    GUARD(rc = m->fs->getattr(path, a));
    if (rc != 0) return rc;
    const uint64_t want = static_cast<uint64_t>(offset) + static_cast<uint64_t>(length);
    if (want <= a.size) return 0;
    if (fi) {
        GUARD(return m->fs->ftruncate(fi->fh, want));
    }
    GUARD(return m->fs->truncate(path, want));
}

int opReaddir(const char* path, void* buf, fuse_fill_dir_t filler, off_t, struct fuse_file_info*,
              enum fuse_readdir_flags flags) {
    Mount* m = current();
    std::vector<vemount::DirItem> items;
    int rc = 0;
    GUARD(rc = m->fs->readdir(path, items));
    if (rc != 0) return rc;
    const enum fuse_fill_dir_flags fill = (flags & FUSE_READDIR_PLUS) ? FUSE_FILL_DIR_PLUS : static_cast<enum fuse_fill_dir_flags>(0);
    struct stat dirSt;
    fillStat(m, vemount::Attr{vemount::NodeType::Dir, 0, static_cast<int64_t>(std::time(nullptr))}, &dirSt);
    filler(buf, ".", &dirSt, 0, fill);
    filler(buf, "..", &dirSt, 0, fill);
    for (const auto& item : items) {
        if (item.name.empty() || item.name.size() > 255) continue;
        struct stat st;
        fillStat(m, item.attr, &st);
        if (filler(buf, item.name.c_str(), &st, 0, fill) != 0) break;
    }
    return 0;
}

void* opInit(struct fuse_conn_info* conn, struct fuse_config* cfg) {
    cfg->use_ino = 0;
    cfg->kernel_cache = 0;
    cfg->nullpath_ok = 0;
    // Directory listings already carry full attributes, so let the kernel use readdirplus; and take
    // O_TRUNC atomically in open() (that is what lets a folder-vault write start as a clean stream).
    conn->want |= (conn->capable & FUSE_CAP_READDIRPLUS);
    conn->want |= (conn->capable & FUSE_CAP_ATOMIC_O_TRUNC);
    return gApi.fnContext()->private_data;
}

void fillOps(struct fuse_operations& ops) {
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
    ops.fallocate = opFallocate;
}

// ── helpers: mount point, fusermount3 ───────────────────────────────────────────────────────────────

bool isMountPoint(const std::string& path) {
    struct stat st, parent;
    if (stat(path.c_str(), &st) != 0) return errno == ENOTCONN;  // a dead FUSE mount is still a mount
    std::string par = path;
    while (par.size() > 1 && par.back() == '/') par.pop_back();
    const size_t slash = par.rfind('/');
    par = slash == std::string::npos ? "." : (slash == 0 ? "/" : par.substr(0, slash));
    if (stat(par.c_str(), &parent) != 0) return false;
    return st.st_dev != parent.st_dev;
}

// Runs `fusermount3 <args>`; returns its exit status (or -1 if it could not run / timed out) and stderr.
int runFusermount(const std::vector<std::string>& args, int timeoutMs, std::string* err) {
    int pipefd[2];
    if (pipe(pipefd) != 0) return -1;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addopen(&fa, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&fa, pipefd[0]);
    std::vector<char*> argv;
    static const char* exe = "fusermount3";
    argv.push_back(const_cast<char*>(exe));
    for (const auto& a : args) argv.push_back(const_cast<char*>(a.c_str()));
    argv.push_back(nullptr);
    pid_t pid = 0;
    const int rc = posix_spawnp(&pid, exe, &fa, nullptr, argv.data(), environ);
    posix_spawn_file_actions_destroy(&fa);
    close(pipefd[1]);
    if (rc != 0) {
        close(pipefd[0]);
        return -1;
    }
    std::string captured;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    int status = 0;
    bool exited = false;
    while (std::chrono::steady_clock::now() < deadline) {
        struct pollfd pfd{pipefd[0], POLLIN, 0};
        if (poll(&pfd, 1, 50) > 0 && (pfd.revents & POLLIN)) {
            char b[256];
            const ssize_t n = read(pipefd[0], b, sizeof(b));
            if (n > 0) captured.append(b, static_cast<size_t>(n));
        }
        if (waitpid(pid, &status, WNOHANG) == pid) { exited = true; break; }
    }
    if (!exited) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
    }
    char b[256];
    ssize_t n;
    while ((n = read(pipefd[0], b, sizeof(b))) > 0) captured.append(b, static_cast<size_t>(n));
    close(pipefd[0]);
    if (err) *err = captured;
    return exited && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

std::string sanitizeName(const char* name) {
    std::string out = name && *name ? name : "VaultExplorer";
    for (char& c : out) {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ' ||
                        c == '_' || c == '-' || c == '.';
        if (!ok) c = '_';
    }
    if (out.size() > 64) out.resize(64);
    return out;
}

void fireCallback(int64_t id, int32_t event) {
    void (*cb)(int64_t, int32_t) = nullptr;
    {
        std::lock_guard<std::mutex> g(gCbMu);
        cb = gCallback;
    }
    if (cb) cb(id, event);
}

// Validates (and if needed prepares) the directory a mount will cover. Returns "" or a reason.
std::string prepareMountPoint(const std::string& mp) {
    if (mp.empty() || mp[0] != '/') return "mount point must be an absolute path";
    struct stat st;
    if (lstat(mp.c_str(), &st) != 0) {
        if (errno == ENOTCONN) {
            // A previous run died without cleaning up: detach the dead mount, then reuse the directory.
            runFusermount({"-u", "-z", "--", mp}, 5000, nullptr);
            if (lstat(mp.c_str(), &st) != 0) return "mount point is a dead FUSE mount that could not be cleared";
        } else if (errno == ENOENT) {
            // Create the missing directory (and parents), owner-only.
            std::string cur;
            for (size_t i = 1; i <= mp.size(); ++i) {
                if (i == mp.size() || mp[i] == '/') {
                    cur = mp.substr(0, i);
                    if (!cur.empty() && mkdir(cur.c_str(), 0700) != 0 && errno != EEXIST) {
                        return "cannot create mount point: " + std::string(std::strerror(errno));
                    }
                }
            }
            if (lstat(mp.c_str(), &st) != 0) return "cannot create mount point";
        } else {
            return "cannot access mount point: " + std::string(std::strerror(errno));
        }
    }
    if (S_ISLNK(st.st_mode)) return "mount point must not be a symbolic link";
    if (!S_ISDIR(st.st_mode)) return "mount point is not a directory";
    if (st.st_uid != getuid()) return "mount point is not owned by the current user";
    if (isMountPoint(mp)) return "something is already mounted there";
    DIR* d = opendir(mp.c_str());
    if (!d) return "cannot read mount point: " + std::string(std::strerror(errno));
    bool empty = true;
    while (struct dirent* e = readdir(d)) {
        if (std::strcmp(e->d_name, ".") != 0 && std::strcmp(e->d_name, "..") != 0) { empty = false; break; }
    }
    closedir(d);
    if (!empty) return "mount point is not empty";
    return "";
}

// Tears one mount down. force=false refuses (VE_ERR_BUSY) while files are open.
int32_t unmountOne(const std::shared_ptr<Mount>& m, bool force) {
    if (m->reaped.load()) return VE_OK;
    m->unmountRequested.store(true);
    bool detached = m->loopEnded.load();

    if (!detached) {
        std::string err;
        int rc = runFusermount({"-u", "--", m->mountPoint}, 10000, &err);
        if (rc != 0 && isMountPoint(m->mountPoint)) {
            if (!force) {
                m->unmountRequested.store(false);
                const bool busy = err.find("busy") != std::string::npos || err.find("Busy") != std::string::npos;
                setLastError(busy ? "the vault is in use (files are open)" : "fusermount3 failed: " + err);
                return busy ? VE_ERR_BUSY : VE_ERR_FAILED;
            }
            // Forced: stop the loop, wake it with a harmless request, and let libfuse lazily detach.
            gApi.fnExit(m->fuse);
            struct stat st;
            const std::string probe = m->mountPoint + kProbePath;
            stat(probe.c_str(), &st);
        }
    }
    // Wait for the loop to finish (it ends when the kernel closes the connection / sees the exit flag).
    for (int i = 0; i < 200 && !m->loopEnded.load(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    if (!m->loopEnded.load()) {
        gApi.fnExit(m->fuse);
        struct stat st;
        const std::string probe = m->mountPoint + kProbePath;
        stat(probe.c_str(), &st);
        for (int i = 0; i < 40 && !m->loopEnded.load(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    if (m->loop.joinable()) {
        if (m->loopEnded.load()) m->loop.join();
        else m->loop.detach();  // stuck inside a blocked engine call; do not hang the caller
    }
    // Commit what is pending while the slot is still open, then release libfuse's objects.
    try { m->fs->closeAll(); } catch (...) {}
    gApi.fnUnmount(m->fuse);
    gApi.fnDestroy(m->fuse);
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
    std::call_once(gApiOnce, loadApi);
    std::string reason;
    if (!gApi.lib) reason = gApiError;
    else if (!inPath("fusermount3")) reason = "fusermount3 not found (install the 'fuse3' package)";
    else if (access("/dev/fuse", R_OK | W_OK) != 0) reason = "/dev/fuse is not accessible (is the fuse kernel module available?)";
    copyOut(reason, reason_buf, reason_cap);
    return reason.empty() ? 1 : 0;
}

extern "C" VE_API int32_t ve_mount(int32_t vol, const char* mountPointUtf8, const ve_mount_options* opts,
                                   int64_t* outId) {
    if (outId) *outId = 0;
    if (!mountPointUtf8 || !outId) return VE_ERR_INVALID_ARG;
    char reason[256];
    if (!ve_mount_supported(reason, sizeof(reason))) {
        setLastError(reason);
        return VE_ERR_UNSUPPORTED;
    }
    bool fv = false, ci = false, ro = false;
    if (!ve_internal_vol_traits(vol, &fv, &ci, &ro)) return VE_ERR_NOT_UNLOCKED;
    {
        std::lock_guard<std::mutex> g(gMu);
        for (auto& kv : gMounts) {
            if (kv.second->vol == vol && kv.second->mountPoint == mountPointUtf8) {
                setLastError("this vault is already mounted there");
                return VE_ERR_INVALID_ARG;
            }
        }
    }
    const std::string prep = prepareMountPoint(mountPointUtf8);
    if (!prep.empty()) {
        setLastError(prep);
        return VE_ERR_INVALID_ARG;
    }

    vemount::FsOptions fo;
    fo.readOnly = (opts && opts->read_only) || ro;
    if (opts && opts->sub_path && opts->sub_path[0] && std::strcmp(opts->sub_path, "/") != 0) fo.root = opts->sub_path;
    if (opts && opts->max_buffer_mb > 0) fo.maxBufferBytes = static_cast<uint64_t>(opts->max_buffer_mb) << 20;

    auto m = std::make_shared<Mount>();
    m->id = gNextId.fetch_add(1);
    m->vol = vol;
    m->mountPoint = mountPointUtf8;
    while (m->mountPoint.size() > 1 && m->mountPoint.back() == '/') m->mountPoint.pop_back();
    m->uid = getuid();
    m->gid = getgid();
    m->fs = std::make_unique<vemount::MountFs>(vol, fo);

    std::string optStr = "fsname=VaultExplorer:" + sanitizeName(opts ? opts->volume_name : nullptr) +
                         ",subtype=vaultexplorer,auto_unmount,attr_timeout=2,entry_timeout=2,negative_timeout=1";
    if (fo.readOnly) optStr += ",ro";
    if (opts && opts->allow_other) optStr += ",allow_other";

    struct fuse_args args = FUSE_ARGS_INIT(0, nullptr);
    gApi.fnOptAddArg(&args, "vaultexplorer");
    gApi.fnOptAddArg(&args, "-o");
    gApi.fnOptAddArg(&args, optStr.c_str());
    struct fuse_operations ops;
    fillOps(ops);
    m->fuse = gApi.fnNew(&args, &ops, sizeof(ops), m.get());
    gApi.fnOptFreeArgs(&args);
    if (!m->fuse) {
        setLastError("fuse_new failed (unsupported mount options?)");
        return VE_ERR_MOUNT_FAILED;
    }
    if (gApi.fnMount(m->fuse, m->mountPoint.c_str()) != 0) {
        gApi.fnDestroy(m->fuse);
        m->fuse = nullptr;
        setLastError("mounting failed (FUSE refused the mount; for allow_other, enable user_allow_other in /etc/fuse.conf)");
        return VE_ERR_MOUNT_FAILED;
    }
    {
        std::lock_guard<std::mutex> g(gMu);
        gMounts[m->id] = m;
    }
    Mount* raw = m.get();
    m->loop = std::thread([raw]() {
        gApi.fnLoop(raw->fuse);
        raw->loopEnded.store(true);
        if (!raw->unmountRequested.load()) fireCallback(raw->id, 1);  // ejected from outside
    });

    // Probe: mounted-but-not-serving looks mounted. Wait until the kernel has really asked us something.
    struct stat st;
    const std::string probe = m->mountPoint + kProbePath;
    for (int i = 0; i < 100 && !m->probeSeen.load() && !m->loopEnded.load(); ++i) {
        stat(probe.c_str(), &st);
        if (!m->probeSeen.load()) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    if (!m->probeSeen.load()) {
        setLastError("the mount did not start serving requests");
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
        // Locking is an explicit, security-relevant action: try the polite way, then do not let open files
        // keep the keys alive.
        if (unmountOne(m, false) == VE_ERR_BUSY) unmountOne(m, true);
    }
}

#elif defined(_WIN32) && defined(VE_HAVE_WINFSP)
// The Windows glue (WinFsp) lives in ve_mount_winfsp.cpp and provides the same ABI.

#else  // ── no OS-mount support in this build ────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_mount_supported(char* reason_buf, size_t reason_cap) {
#if defined(_WIN32)
    copyOut("this build has no WinFsp support (WinFsp headers were missing at build time)", reason_buf, reason_cap);
#else
    copyOut("this build has no FUSE support (libfuse3 development headers were missing at build time)",
            reason_buf, reason_cap);
#endif
    return 0;
}
extern "C" VE_API int32_t ve_mount(int32_t, const char*, const ve_mount_options*, int64_t* out_id) {
    if (out_id) *out_id = 0;
    char reason[256];
    ve_mount_supported(reason, sizeof(reason));
    setLastError(reason);
    return VE_ERR_UNSUPPORTED;
}
extern "C" VE_API int32_t ve_unmount(int64_t, int32_t) { return VE_OK; }
extern "C" VE_API int32_t ve_list_mounts(ve_buffer* out) {
    if (out) { out->data = nullptr; out->len = 0; }
    return VE_OK;
}
extern "C" VE_API void ve_set_mount_callback(void (*)(int64_t, int32_t)) {}
void ve_internal_unmount_volume(int32_t) {}

#endif
