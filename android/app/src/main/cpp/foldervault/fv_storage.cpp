#include "fv_storage.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/time.h>
#include <unistd.h>

namespace fv {

// ------------------------------------------------------------------ FdFile --

FdFile::FdFile(int fd) : fd_(fd) {
    if (fd_ >= 0) {
        off_t cur = ::lseek(fd_, 0, SEEK_CUR);
        seekable_ = cur >= 0;
        pos_ = cur >= 0 ? cur : 0;
    }
}
FdFile::~FdFile() { close(); }
FdFile::FdFile(FdFile&& o) noexcept : fd_(o.fd_), seekable_(o.seekable_), pos_(o.pos_) { o.fd_ = -1; }
FdFile& FdFile::operator=(FdFile&& o) noexcept {
    if (this != &o) { close(); fd_ = o.fd_; seekable_ = o.seekable_; pos_ = o.pos_; o.fd_ = -1; }
    return *this;
}
void FdFile::close() { if (fd_ >= 0) { ::close(fd_); fd_ = -1; } }

int64_t FdFile::size() const {
    if (fd_ < 0) return -1;
    struct stat st;
    if (::fstat(fd_, &st) != 0 || !S_ISREG(st.st_mode)) return -1;
    return (int64_t)st.st_size;
}

int64_t FdFile::readAt(uint8_t* buf, size_t n, int64_t off) {
    if (fd_ < 0) return -1;
    size_t got = 0;
    if (seekable_) {
        while (got < n) {
            ssize_t r = ::pread(fd_, buf + got, n - got, (off_t)(off + (int64_t)got));
            if (r < 0) { if (errno == EINTR) continue; return -1; }
            if (r == 0) break;
            got += (size_t)r;
        }
        return (int64_t)got;
    }
    if (off < pos_) return kNeedsReopen;
    uint8_t scratch[16 * 1024];
    while (pos_ < off) {   // discard up to the wanted offset
        size_t want = (size_t)std::min<int64_t>((int64_t)sizeof(scratch), off - pos_);
        ssize_t r = ::read(fd_, scratch, want);
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        if (r == 0) return 0;
        pos_ += r;
    }
    while (got < n) {
        ssize_t r = ::read(fd_, buf + got, n - got);
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        if (r == 0) break;
        got += (size_t)r;
        pos_ += r;
    }
    return (int64_t)got;
}

bool FdFile::writeAll(const uint8_t* buf, size_t n) {
    size_t done = 0;
    while (done < n) {
        ssize_t r = ::write(fd_, buf + done, n - done);
        if (r < 0) { if (errno == EINTR) continue; return false; }
        done += (size_t)r;
    }
    return true;
}

bool FdFile::sync() { return fd_ >= 0 && ::fsync(fd_) == 0; }

// ------------------------------------------------------------ PosixStorage --

PosixStorage::PosixStorage(std::string rootDir) : root_(std::move(rootDir)) {
    while (root_.size() > 1 && root_.back() == '/') root_.pop_back();
}

bool PosixStorage::abs(const std::string& rel, std::string& out) const {
    out = root_;
    size_t i = 0;
    while (i < rel.size()) {
        size_t j = rel.find('/', i);
        if (j == std::string::npos) j = rel.size();
        std::string seg = rel.substr(i, j - i);
        if (!seg.empty()) {
            if (seg == "." || seg == ".." || seg.find('\0') != std::string::npos) return false;
            out.push_back('/');
            out += seg;
        }
        i = j + 1;
    }
    return true;
}

static int64_t mtimeMsOf(const struct stat& st) {
#if defined(__APPLE__)
    return (int64_t)st.st_mtimespec.tv_sec * 1000 + st.st_mtimespec.tv_nsec / 1000000;
#else
    return (int64_t)st.st_mtim.tv_sec * 1000 + st.st_mtim.tv_nsec / 1000000;
#endif
}

bool PosixStorage::list(const std::string& dir, std::vector<DirEntry>& out) {
    std::string p;
    if (!abs(dir, p)) return false;
    DIR* d = ::opendir(p.c_str());
    if (!d) return false;
    out.clear();
    while (struct dirent* e = ::readdir(d)) {
        if (!std::strcmp(e->d_name, ".") || !std::strcmp(e->d_name, "..")) continue;
        struct stat st;
        if (::fstatat(::dirfd(d), e->d_name, &st, 0) != 0) continue;
        DirEntry de;
        de.name = e->d_name;
        de.isDir = S_ISDIR(st.st_mode);
        de.size = de.isDir ? 0 : (int64_t)st.st_size;
        de.mtimeMs = mtimeMsOf(st);
        out.push_back(std::move(de));
    }
    ::closedir(d);
    return true;
}

bool PosixStorage::stat(const std::string& path, DirEntry& out) {
    std::string p;
    if (!abs(path, p)) return false;
    struct stat st;
    if (::stat(p.c_str(), &st) != 0) return false;
    out.name = nameOf(path);
    out.isDir = S_ISDIR(st.st_mode);
    out.size = out.isDir ? 0 : (int64_t)st.st_size;
    out.mtimeMs = mtimeMsOf(st);
    return true;
}

bool PosixStorage::mkdir(const std::string& path) {
    std::string p;
    if (!abs(path, p)) return false;
    if (::mkdir(p.c_str(), 0777) == 0) return true;
    if (errno != EEXIST) return false;
    struct stat st;
    return ::stat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

bool PosixStorage::createFile(const std::string& path) {
    std::string p;
    if (!abs(path, p)) return false;
    int fd = ::open(p.c_str(), O_WRONLY | O_CREAT | O_CLOEXEC, 0666);
    if (fd < 0) return false;
    ::close(fd);
    return true;
}

bool PosixStorage::rename(const std::string& from, const std::string& to) {
    std::string a, b;
    if (!abs(from, a) || !abs(to, b)) return false;
    return ::rename(a.c_str(), b.c_str()) == 0;
}

static bool removeTree(const std::string& p) {
    struct stat st;
    if (::lstat(p.c_str(), &st) != 0) return errno == ENOENT;
    if (!S_ISDIR(st.st_mode)) return ::unlink(p.c_str()) == 0;
    DIR* d = ::opendir(p.c_str());
    if (!d) return false;
    bool ok = true;
    while (struct dirent* e = ::readdir(d)) {
        if (!std::strcmp(e->d_name, ".") || !std::strcmp(e->d_name, "..")) continue;
        if (!removeTree(p + "/" + e->d_name)) ok = false;
    }
    ::closedir(d);
    return ::rmdir(p.c_str()) == 0 && ok;
}

bool PosixStorage::remove(const std::string& path) {
    std::string p;
    if (!abs(path, p) || path.empty()) return false;   // never delete the root
    return removeTree(p);
}

bool PosixStorage::setMtime(const std::string& path, int64_t epochSec) {
    std::string p;
    if (!abs(path, p)) return false;
    struct timespec ts[2];
    ts[0].tv_sec = (time_t)epochSec; ts[0].tv_nsec = 0;
    ts[1] = ts[0];
    return ::utimensat(AT_FDCWD, p.c_str(), ts, 0) == 0;
}

bool PosixStorage::readWhole(const std::string& path, Bytes& out) {
    std::string p;
    if (!abs(path, p)) return false;
    int fd = ::open(p.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    FdFile f(fd);
    out.clear();
    uint8_t buf[64 * 1024];
    int64_t off = 0;
    for (;;) {
        int64_t r = f.readAt(buf, sizeof(buf), off);
        if (r < 0) return false;
        if (r == 0) break;
        out.insert(out.end(), buf, buf + r);
        off += r;
    }
    return true;
}

bool PosixStorage::writeWhole(const std::string& path, const uint8_t* data, size_t len) {
    std::string p;
    if (!abs(path, p)) return false;
    int fd = ::open(p.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (fd < 0) return false;
    FdFile f(fd);
    return f.writeAll(data, len) && f.sync();
}

bool PosixStorage::writeBlock(const std::string& path, const uint8_t* data, size_t len) {
    std::string p;
    if (!abs(path, p)) return false;
    int fd = ::open(p.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (fd < 0) return false;
    FdFile f(fd);
    return f.writeAll(data, len);
}

bool PosixStorage::writeWholeAtomic(const std::string& path, const uint8_t* data, size_t len) {
    std::string p;
    if (!abs(path, p)) return false;
    std::string tmp = p + ".fvtmp";
    int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (fd < 0) return writeWhole(path, data, len);   // directory not writable for new names: best effort
    bool ok;
    {
        FdFile f(fd);
        ok = f.writeAll(data, len) && f.sync();
    }
    if (ok && ::rename(tmp.c_str(), p.c_str()) == 0) return true;
    ::unlink(tmp.c_str());
    return false;
}

FdFile PosixStorage::openRead(const std::string& path, const std::string& /*hint*/) {
    std::string p;
    if (!abs(path, p)) return FdFile();
    return FdFile(::open(p.c_str(), O_RDONLY | O_CLOEXEC));
}

FdFile PosixStorage::openWrite(const std::string& path, bool truncate) {
    std::string p;
    if (!abs(path, p)) return FdFile();
    return FdFile(::open(p.c_str(), O_WRONLY | (truncate ? O_TRUNC : 0) | O_CLOEXEC));
}

bool PosixStorage::spaceInfo(int64_t& total, int64_t& free) {
    struct statvfs sv;
    if (::statvfs(root_.c_str(), &sv) != 0) return false;
    total = (int64_t)sv.f_blocks * (int64_t)sv.f_frsize;
    free = (int64_t)sv.f_bavail * (int64_t)sv.f_frsize;
    return true;
}

}  // namespace fv
