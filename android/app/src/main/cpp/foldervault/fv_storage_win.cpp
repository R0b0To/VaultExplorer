// Windows twin of fv_storage.cpp: FdFile, PosixStorage (a plain directory tree) and the fv_os.h helpers, on the
// Win32 API instead of POSIX. Only built on Windows (see CMakeLists.txt); everything else uses fv_storage.cpp.
//
// NB: do not include <sys/stat.h> here -- on MinGW it #defines stat to _stat64, which would rename Storage::stat.
//
// Differences from the POSIX implementation that matter:
//  * Paths are UTF-8 at the interface and UTF-16 at the OS. Every path handed to Windows is in the extended
//    \\?\ form: no MAX_PATH limit, no DOS device names (a plain "NUL" or "CON" stays an ordinary name) and no
//    stripping of trailing dots / spaces.
//  * Path segments are validated for Windows too ('\\', ':' (alternate data streams) and the wildcard / reserved
//    characters are refused), so a hostile name can no more escape the vault root here than on POSIX.
//  * Symbolic links: only real links (IO_REPARSE_TAG_SYMLINK / MOUNT_POINT) count as links. Other reparse points
//    (OneDrive / cloud placeholders, dedup) are ordinary files and directories.
//  * Files are opened with FILE_SHARE_READ|WRITE|DELETE so renaming or deleting an open file works as on POSIX,
//    and rename / delete retry briefly on sharing violations (virus scanners and indexers hold files open).
//  * Descriptors are CRT descriptors wrapped around Win32 handles (_open_osfhandle), so FdFile keeps its int fd().
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "fv_storage.h"

#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <sys/types.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <cwchar>

#include "fv_os.h"

namespace fv {

namespace {

constexpr DWORD kShare = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
constexpr uint64_t kEpochDiff100ns = 116444736000000000ULL;   // 1601-01-01 -> 1970-01-01

bool toWide(const std::string& s, std::wstring& out) {
    out.clear();
    if (s.empty()) return true;
    const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), (int)s.size(), nullptr, 0);
    if (n <= 0) return false;   // not valid UTF-8
    out.resize((size_t)n);
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), (int)s.size(), &out[0], n) == n;
}

std::string toUtf8(const wchar_t* w, size_t len) {
    if (len == 0) return std::string();
    const int n = WideCharToMultiByte(CP_UTF8, 0, w, (int)len, nullptr, 0, nullptr, nullptr);
    if (n <= 0) return std::string();
    std::string s((size_t)n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, (int)len, &s[0], n, nullptr, nullptr);
    return s;
}

// Absolute path in the \\?\ form (see the header comment). Normalizes "." / ".." and relative paths first, so only
// ever call it on a whole root / host path -- never on a name that must stay byte-exact.
std::wstring extendedPath(std::wstring w) {
    std::replace(w.begin(), w.end(), L'/', L'\\');
    if (w.compare(0, 4, L"\\\\?\\") == 0 || w.compare(0, 4, L"\\\\.\\") == 0) return w;
    const DWORD need = GetFullPathNameW(w.c_str(), 0, nullptr, nullptr);
    if (need == 0) return w;
    std::wstring full(need, L'\0');
    const DWORD got = GetFullPathNameW(w.c_str(), need, &full[0], nullptr);
    if (got == 0 || got >= need) return w;
    full.resize(got);
    if (full.compare(0, 2, L"\\\\") == 0) return L"\\\\?\\UNC\\" + full.substr(2);   // \\server\share\...
    return L"\\\\?\\" + full;
}

bool hostPath(const char* utf8, std::wstring& out) {
    std::wstring w;
    if (!utf8 || !toWide(utf8, w) || w.empty()) return false;
    out = extendedPath(std::move(w));
    return true;
}

int64_t fileTimeMs(const FILETIME& ft) {
    const uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return t < kEpochDiff100ns ? 0 : (int64_t)((t - kEpochDiff100ns) / 10000ULL);
}

FILETIME secToFileTime(int64_t sec) {
    const uint64_t t = (uint64_t)(sec < 0 ? 0 : sec) * 10000000ULL + kEpochDiff100ns;
    FILETIME ft;
    ft.dwLowDateTime = (DWORD)(t & 0xFFFFFFFFULL);
    ft.dwHighDateTime = (DWORD)(t >> 32);
    return ft;
}

// Retries an operation that failed only because something else briefly holds the file (scanner, indexer).
template <class F>
bool retryBusy(F op) {
    for (int attempt = 0; attempt < 6; ++attempt) {
        if (op()) return true;
        const DWORD e = GetLastError();
        if (e != ERROR_SHARING_VIOLATION && e != ERROR_ACCESS_DENIED && e != ERROR_LOCK_VIOLATION) return false;
        Sleep(15u * (unsigned)(attempt + 1));
    }
    return false;
}

bool isDirAttr(DWORD a) { return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY) != 0; }
bool isLinkTag(DWORD tag) { return tag == IO_REPARSE_TAG_SYMLINK || tag == IO_REPARSE_TAG_MOUNT_POINT; }

// Reparse tag of the object at [w] itself (not followed); 0 if it is not a reparse point.
DWORD reparseTagOf(const std::wstring& w) {
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileExW(w.c_str(), FindExInfoBasic, &fd, FindExSearchNameMatch, nullptr, 0);
    if (h == INVALID_HANDLE_VALUE) return 0;
    FindClose(h);
    return (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? fd.dwReserved0 : 0;
}

// Attributes of the object at [w], following links (POSIX stat()).
bool statFollow(const std::wstring& w, BY_HANDLE_FILE_INFORMATION& info) {
    HANDLE h = CreateFileW(w.c_str(), FILE_READ_ATTRIBUTES, kShare, nullptr, OPEN_EXISTING,
                           FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    const bool ok = GetFileInformationByHandle(h, &info) != 0;
    CloseHandle(h);
    return ok;
}

FdFile wrapHandle(HANDLE h, int oflags) {
    if (h == INVALID_HANDLE_VALUE) return FdFile();
    const int fd = _open_osfhandle((intptr_t)h, oflags);
    if (fd < 0) {
        CloseHandle(h);
        return FdFile();
    }
    return FdFile(fd);
}

FdFile openForWrite(const std::wstring& w, DWORD disposition) {
    HANDLE h = CreateFileW(w.c_str(), GENERIC_WRITE, kShare, nullptr, disposition, FILE_ATTRIBUTE_NORMAL, nullptr);
    return wrapHandle(h, 0);
}

bool removeTreeW(const std::wstring& p) {
    const DWORD a = GetFileAttributesW(p.c_str());
    if (a == INVALID_FILE_ATTRIBUTES) {
        const DWORD e = GetLastError();
        return e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND;
    }
    if (a & FILE_ATTRIBUTE_READONLY) SetFileAttributesW(p.c_str(), a & ~(DWORD)FILE_ATTRIBUTE_READONLY);
    if (!isDirAttr(a)) return retryBusy([&] { return DeleteFileW(p.c_str()) != 0; });
    // A directory link is removed itself, never followed.
    if ((a & FILE_ATTRIBUTE_REPARSE_POINT) && isLinkTag(reparseTagOf(p)))
        return retryBusy([&] { return RemoveDirectoryW(p.c_str()) != 0; });
    bool ok = true;
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileExW((p + L"\\*").c_str(), FindExInfoBasic, &fd, FindExSearchNameMatch, nullptr,
                                FIND_FIRST_EX_LARGE_FETCH);
    if (h == INVALID_HANDLE_VALUE) return false;
    do {
        if (!std::wcscmp(fd.cFileName, L".") || !std::wcscmp(fd.cFileName, L"..")) continue;
        if (!removeTreeW(p + L"\\" + fd.cFileName)) ok = false;
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    return retryBusy([&] { return RemoveDirectoryW(p.c_str()) != 0; }) && ok;
}

// A physical name coming from a (possibly hostile) vault. Beyond the POSIX rules ('.', '..', NUL) Windows treats
// '\\' as a separator, ':' as an alternate-data-stream / drive marker and '*' '?' as wildcards.
bool validSegment(const std::string& seg) {
    if (seg == "." || seg == "..") return false;
    for (unsigned char c : seg) {
        if (c < 0x20) return false;   // includes NUL
        switch (c) {
            case '\\': case ':': case '*': case '?': case '"': case '<': case '>': case '|': return false;
            default: break;
        }
    }
    return true;
}

}  // namespace

// ------------------------------------------------------------------ FdFile --

FdFile::FdFile(int fd) : fd_(fd) {
    if (fd_ >= 0) {
        const int64_t cur = _lseeki64(fd_, 0, SEEK_CUR);
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
void FdFile::close() { if (fd_ >= 0) { _close(fd_); fd_ = -1; } }

int64_t FdFile::size() const {
    if (fd_ < 0) return -1;
    HANDLE h = (HANDLE)_get_osfhandle(fd_);
    if (h == INVALID_HANDLE_VALUE || GetFileType(h) != FILE_TYPE_DISK) return -1;
    LARGE_INTEGER li;
    return GetFileSizeEx(h, &li) ? (int64_t)li.QuadPart : -1;
}

int64_t FdFile::readAt(uint8_t* buf, size_t n, int64_t off) {
    if (fd_ < 0) return -1;
    size_t got = 0;
    if (seekable_) {
        while (got < n) {
            const int64_t r = osPread(fd_, buf + got, n - got, off + (int64_t)got);
            if (r < 0) return -1;
            if (r == 0) break;
            got += (size_t)r;
        }
        return (int64_t)got;
    }
    if (off < pos_) return kNeedsReopen;
    uint8_t scratch[16 * 1024];
    while (pos_ < off) {   // discard up to the wanted offset
        const unsigned want = (unsigned)std::min<int64_t>((int64_t)sizeof(scratch), off - pos_);
        const int r = _read(fd_, scratch, want);
        if (r < 0) return -1;
        if (r == 0) return 0;
        pos_ += r;
    }
    while (got < n) {
        const unsigned want = (unsigned)std::min<size_t>(n - got, 1u << 30);
        const int r = _read(fd_, buf + got, want);
        if (r < 0) return -1;
        if (r == 0) break;
        got += (size_t)r;
        pos_ += r;
    }
    return (int64_t)got;
}

bool FdFile::writeAll(const uint8_t* buf, size_t n) {
    size_t done = 0;
    while (done < n) {
        const unsigned want = (unsigned)std::min<size_t>(n - done, 1u << 30);
        const int r = _write(fd_, buf + done, want);
        if (r <= 0) return false;
        done += (size_t)r;
    }
    return true;
}

bool FdFile::sync() { return fd_ >= 0 && _commit(fd_) == 0; }

// ------------------------------------------------------------ PosixStorage --

PosixStorage::PosixStorage(std::string rootDir) : root_(std::move(rootDir)) {
    // Trailing separators go, but "C:\" must keep its backslash ("C:" alone means "the current directory of C:").
    while (root_.size() > 1 && (root_.back() == '/' || root_.back() == '\\') &&
           !(root_.size() == 3 && root_[1] == ':')) {
        root_.pop_back();
    }
    std::wstring w;
    if (toWide(root_, w) && !w.empty()) rootW_ = extendedPath(std::move(w));
}

bool PosixStorage::abs(const std::string&, std::string&) const { return false; }   // POSIX-only; see absW()

bool PosixStorage::absW(const std::string& rel, std::wstring& out) const {
    if (rootW_.empty()) return false;
    out = rootW_;
    size_t i = 0;
    while (i < rel.size()) {
        size_t j = rel.find('/', i);
        if (j == std::string::npos) j = rel.size();
        const std::string seg = rel.substr(i, j - i);
        if (!seg.empty()) {
            std::wstring ws;
            if (!validSegment(seg) || !toWide(seg, ws)) return false;
            if (out.back() != L'\\') out.push_back(L'\\');
            out += ws;
        }
        i = j + 1;
    }
    return true;
}

bool PosixStorage::list(const std::string& dir, std::vector<DirEntry>& out) {
    std::wstring w;
    if (!absW(dir, w)) return false;
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileExW((w + (w.back() == L'\\' ? L"*" : L"\\*")).c_str(), FindExInfoBasic, &fd,
                                FindExSearchNameMatch, nullptr, FIND_FIRST_EX_LARGE_FETCH);
    if (h == INVALID_HANDLE_VALUE) return false;   // missing, or not a directory
    out.clear();
    do {
        if (!std::wcscmp(fd.cFileName, L".") || !std::wcscmp(fd.cFileName, L"..")) continue;
        DirEntry de;
        de.name = toUtf8(fd.cFileName, std::wcslen(fd.cFileName));
        if (de.name.empty()) continue;
        DWORD attrs = fd.dwFileAttributes;
        uint64_t size = ((uint64_t)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
        FILETIME mtime = fd.ftLastWriteTime;
        if ((attrs & FILE_ATTRIBUTE_REPARSE_POINT) && isLinkTag(fd.dwReserved0)) {
            // describe the target, as on POSIX, but remember it is a link; a dangling one is not listed
            de.isSymlink = true;
            BY_HANDLE_FILE_INFORMATION info;
            if (!statFollow(w + L"\\" + fd.cFileName, info)) continue;
            attrs = info.dwFileAttributes;
            size = ((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
            mtime = info.ftLastWriteTime;
        }
        de.isDir = isDirAttr(attrs);
        de.size = de.isDir ? 0 : (int64_t)size;
        de.mtimeMs = fileTimeMs(mtime);
        out.push_back(std::move(de));
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    return true;
}

bool PosixStorage::stat(const std::string& path, DirEntry& out) {
    std::wstring w;
    if (!absW(path, w)) return false;
    BY_HANDLE_FILE_INFORMATION info;
    if (!statFollow(w, info)) return false;
    out.name = nameOf(path);
    out.isSymlink = false;
    if (!path.empty()) {   // (the root itself may legitimately be reached through a link)
        const DWORD a = GetFileAttributesW(w.c_str());   // does not follow links
        out.isSymlink = a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_REPARSE_POINT) && isLinkTag(reparseTagOf(w));
    }
    out.isDir = isDirAttr(info.dwFileAttributes);
    out.size = out.isDir ? 0 : (int64_t)(((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow);
    out.mtimeMs = fileTimeMs(info.ftLastWriteTime);
    return true;
}

bool PosixStorage::mkdir(const std::string& path) {
    std::wstring w;
    if (!absW(path, w)) return false;
    if (CreateDirectoryW(w.c_str(), nullptr)) return true;
    if (GetLastError() != ERROR_ALREADY_EXISTS) return false;
    return isDirAttr(GetFileAttributesW(w.c_str()));
}

bool PosixStorage::existsNoFollow(const std::string& path) {
    std::wstring w;
    if (!absW(path, w)) return false;
    if (path.empty()) {   // (the root itself may legitimately be reached through a link)
        BY_HANDLE_FILE_INFORMATION info;
        return statFollow(w, info);
    }
    return GetFileAttributesW(w.c_str()) != INVALID_FILE_ATTRIBUTES;   // a link is reported itself, even dangling
}

bool PosixStorage::createFile(const std::string& path) {
    std::wstring w;
    if (!absW(path, w)) return false;
    HANDLE h = CreateFileW(w.c_str(), GENERIC_WRITE, kShare, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    CloseHandle(h);
    return true;
}

bool PosixStorage::rename(const std::string& from, const std::string& to) {
    std::wstring a, b;
    if (!absW(from, a) || !absW(to, b)) return false;
    return retryBusy([&] { return MoveFileExW(a.c_str(), b.c_str(), MOVEFILE_REPLACE_EXISTING) != 0; });
}

bool PosixStorage::remove(const std::string& path) {
    std::wstring w;
    if (!absW(path, w) || path.empty()) return false;   // never delete the root
    return removeTreeW(w);
}

bool PosixStorage::setMtime(const std::string& path, int64_t epochSec) {
    std::wstring w;
    if (!absW(path, w)) return false;
    HANDLE h = CreateFileW(w.c_str(), FILE_WRITE_ATTRIBUTES, kShare, nullptr, OPEN_EXISTING,
                           FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    const FILETIME ft = secToFileTime(epochSec);
    const bool ok = SetFileTime(h, nullptr, &ft, &ft) != 0;
    CloseHandle(h);
    return ok;
}

bool PosixStorage::readWhole(const std::string& path, Bytes& out) {
    FdFile f = openRead(path, std::string());
    if (!f.valid()) return false;
    out.clear();
    uint8_t buf[64 * 1024];
    int64_t off = 0;
    for (;;) {
        const int64_t r = f.readAt(buf, sizeof(buf), off);
        if (r < 0) return false;
        if (r == 0) break;
        out.insert(out.end(), buf, buf + r);
        off += r;
    }
    return true;
}

bool PosixStorage::writeWhole(const std::string& path, const uint8_t* data, size_t len) {
    std::wstring w;
    if (!absW(path, w)) return false;
    FdFile f = openForWrite(w, CREATE_ALWAYS);
    return f.valid() && f.writeAll(data, len) && f.sync();
}

bool PosixStorage::writeBlock(const std::string& path, const uint8_t* data, size_t len) {
    std::wstring w;
    if (!absW(path, w)) return false;
    FdFile f = openForWrite(w, CREATE_ALWAYS);
    return f.valid() && f.writeAll(data, len);
}

bool PosixStorage::writeWholeAtomic(const std::string& path, const uint8_t* data, size_t len) {
    std::wstring w;
    if (!absW(path, w)) return false;
    const std::wstring tmp = w + L".fvtmp";
    FdFile f = openForWrite(tmp, CREATE_ALWAYS);
    if (!f.valid()) return writeWhole(path, data, len);   // directory not writable for new names: best effort
    const bool ok = f.writeAll(data, len) && f.sync();
    f.close();
    if (ok && retryBusy([&] { return MoveFileExW(tmp.c_str(), w.c_str(), MOVEFILE_REPLACE_EXISTING) != 0; })) return true;
    DeleteFileW(tmp.c_str());
    return false;
}

FdFile PosixStorage::openRead(const std::string& path, const std::string& /*hint*/) {
    std::wstring w;
    if (!absW(path, w)) return FdFile();
    HANDLE h = CreateFileW(w.c_str(), GENERIC_READ, kShare, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    return wrapHandle(h, _O_RDONLY);
}

FdFile PosixStorage::openWrite(const std::string& path, bool truncate) {
    std::wstring w;
    if (!absW(path, w)) return FdFile();
    return openForWrite(w, truncate ? TRUNCATE_EXISTING : OPEN_EXISTING);
}

bool PosixStorage::spaceInfo(int64_t& total, int64_t& free) {
    if (rootW_.empty()) return false;
    const std::wstring dir = rootW_.back() == L'\\' ? rootW_ : rootW_ + L"\\";
    ULARGE_INTEGER avail, tot, totFree;
    if (!GetDiskFreeSpaceExW(dir.c_str(), &avail, &tot, &totFree)) return false;
    total = (int64_t)tot.QuadPart;
    free = (int64_t)avail.QuadPart;
    return true;
}

// ------------------------------------------------------------------ fv_os.h --

int osOpen(const char* utf8Path, int flags, int mode) {
    std::wstring w;
    if (!hostPath(utf8Path, w)) { errno = EINVAL; return -1; }
    (void)mode;   // only meaningful with O_CREAT; the CRT wants _S_IREAD|_S_IWRITE (0x100|0x80) there
    return _wopen(w.c_str(), flags | _O_BINARY | _O_NOINHERIT, 0x0100 | 0x0080);
}

std::FILE* osFopen(const char* utf8Path, const char* mode) {
    std::wstring w;
    if (!hostPath(utf8Path, w) || !mode) { errno = EINVAL; return nullptr; }
    std::wstring m;
    for (const char* p = mode; *p; ++p) m.push_back((wchar_t)(unsigned char)*p);   // fopen modes are ASCII
    return _wfopen(w.c_str(), m.c_str());
}

int osUnlink(const char* utf8Path) {
    std::wstring w;
    if (!hostPath(utf8Path, w)) { errno = EINVAL; return -1; }
    return retryBusy([&] { return DeleteFileW(w.c_str()) != 0; }) ? 0 : -1;
}

int osRename(const char* utf8From, const char* utf8To) {
    std::wstring a, b;
    if (!hostPath(utf8From, a) || !hostPath(utf8To, b)) { errno = EINVAL; return -1; }
    return retryBusy([&] { return MoveFileExW(a.c_str(), b.c_str(), MOVEFILE_REPLACE_EXISTING) != 0; }) ? 0 : -1;
}

bool osMkdirs(const std::string& utf8Path) {
    std::wstring w;
    if (utf8Path.empty() || !toWide(utf8Path, w) || w.empty()) return false;
    const std::wstring full = extendedPath(std::move(w));   // \\?\C:\a\b   or   \\?\UNC\server\share\a
    size_t rootLen = 7;                                       // "\\?\C:\"
    if (full.compare(0, 8, L"\\\\?\\UNC\\") == 0) {
        size_t p = full.find(L'\\', 8);                                   // end of the server name
        p = p == std::wstring::npos ? p : full.find(L'\\', p + 1);        // end of the share name
        rootLen = p == std::wstring::npos ? full.size() : p + 1;
    }
    for (size_t i = rootLen; i <= full.size();) {
        size_t j = full.find(L'\\', i);
        if (j == std::wstring::npos) j = full.size();
        if (j > i) {
            const std::wstring cur = full.substr(0, j);
            if (!CreateDirectoryW(cur.c_str(), nullptr) && !isDirAttr(GetFileAttributesW(cur.c_str()))) return false;
        }
        i = j + 1;
    }
    return true;
}

namespace {
int64_t positionalIo(int fd, void* buf, size_t n, int64_t off, bool write) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) { errno = EBADF; return -1; }
    size_t total = 0;
    while (total < n) {
        const DWORD chunk = (DWORD)std::min<size_t>(n - total, 1u << 30);
        const int64_t at = off + (int64_t)total;
        OVERLAPPED ov;
        std::memset(&ov, 0, sizeof ov);
        ov.Offset = (DWORD)(at & 0xFFFFFFFFLL);
        ov.OffsetHigh = (DWORD)(at >> 32);
        DWORD done = 0;
        const BOOL ok = write ? WriteFile(h, (const char*)buf + total, chunk, &done, &ov)
                              : ReadFile(h, (char*)buf + total, chunk, &done, &ov);
        if (!ok) {
            if (!write && GetLastError() == ERROR_HANDLE_EOF) break;   // at / past the end: short read
            errno = EIO;
            return total > 0 ? (int64_t)total : -1;
        }
        if (done == 0) break;
        total += done;
    }
    return (int64_t)total;
}
}  // namespace

int64_t osPread(int fd, void* buf, size_t n, int64_t offset) { return positionalIo(fd, buf, n, offset, false); }
int64_t osPwrite(int fd, const void* buf, size_t n, int64_t offset) {
    return positionalIo(fd, const_cast<void*>(buf), n, offset, true);
}
int osFsync(int fd) { return _commit(fd); }
int osFileno(std::FILE* f) { return _fileno(f); }

int osMakeScratch(const std::string& utf8Dir) {
    std::wstring dir;
    if (utf8Dir.empty()) {
        wchar_t tmp[MAX_PATH + 1];
        const DWORD n = GetTempPathW(MAX_PATH, tmp);
        if (n == 0 || n > MAX_PATH) return -1;
        dir.assign(tmp, n);
    } else if (!toWide(utf8Dir, dir)) {
        return -1;
    }
    dir = extendedPath(std::move(dir));
    if (dir.back() != L'\\') dir.push_back(L'\\');
    static std::atomic<unsigned> counter{0};
    for (int attempt = 0; attempt < 32; ++attempt) {
        wchar_t name[64];
        std::swprintf(name, 64, L"cryfs_write_%08lx%08x%04x", (unsigned long)GetCurrentProcessId(),
                      (unsigned)GetTickCount64(), (counter.fetch_add(1) + attempt) & 0xFFFF);
        const std::wstring path = dir + name;
        HANDLE h = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, kShare, nullptr, CREATE_NEW,
                               FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
        if (h == INVALID_HANDLE_VALUE) {
            if (GetLastError() == ERROR_FILE_EXISTS || GetLastError() == ERROR_ALREADY_EXISTS) continue;
            return -1;
        }
        const int fd = _open_osfhandle((intptr_t)h, 0);
        if (fd < 0) CloseHandle(h);
        return fd;
    }
    return -1;
}

}  // namespace fv
