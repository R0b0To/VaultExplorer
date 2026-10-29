// Windows-only platform pieces for the desktop engine (compiled only when WIN32).
//
//   * pread / pwrite (+ the *64 spellings the engine also uses) over CRT descriptors,
//     declared in ffi/compat/ve_win_compat.h
//   * the OS random source behind crypto/os_random.h (BCryptGenRandom)
//
// This is the only translation unit that includes <windows.h>.

#if !defined(_WIN32)
#  error "ve_win_platform.cpp is Windows-only"
#endif

#ifndef WIN32_LEAN_AND_MEAN
#  define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#  define NOMINMAX
#endif
#include <windows.h>
#include <bcrypt.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <vector>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

namespace {

// Positional I/O via an explicit OVERLAPPED offset, so concurrent callers on one descriptor
// never depend on a shared file position. Loops until `count` bytes or EOF/error.
ssize_t positionalIo(int fd, void* buf, size_t count, int64_t offset, bool write) {
    HANDLE h = reinterpret_cast<HANDLE>(_get_osfhandle(fd));
    if (h == INVALID_HANDLE_VALUE) { errno = EBADF; return -1; }
    if (offset < 0) { errno = EINVAL; return -1; }
    uint8_t* p = static_cast<uint8_t*>(buf);
    size_t total = 0;
    while (total < count) {
        const DWORD chunk = (count - total) > 0x40000000u ? 0x40000000u
                                                          : static_cast<DWORD>(count - total);
        OVERLAPPED ov;
        ZeroMemory(&ov, sizeof(ov));
        const uint64_t pos = static_cast<uint64_t>(offset) + total;
        ov.Offset = static_cast<DWORD>(pos & 0xFFFFFFFFu);
        ov.OffsetHigh = static_cast<DWORD>(pos >> 32);
        DWORD done = 0;
        const BOOL ok = write ? WriteFile(h, p + total, chunk, &done, &ov)
                              : ReadFile(h, p + total, chunk, &done, &ov);
        if (!ok) {
            const DWORD err = GetLastError();
            if (!write && err == ERROR_HANDLE_EOF) break;  // read at/after EOF -> short read
            errno = EIO;
            return total > 0 ? static_cast<ssize_t>(total) : -1;
        }
        if (done == 0) break;
        total += done;
    }
    return static_cast<ssize_t>(total);
}

}  // namespace

ssize_t pread(int fd, void* buf, size_t count, off_t offset) {
    return positionalIo(fd, buf, count, static_cast<int64_t>(offset), false);
}
ssize_t pwrite(int fd, const void* buf, size_t count, off_t offset) {
    return positionalIo(fd, const_cast<void*>(buf), count, static_cast<int64_t>(offset), true);
}
ssize_t pread64(int fd, void* buf, size_t count, int64_t offset) {
    return positionalIo(fd, buf, count, offset, false);
}
ssize_t pwrite64(int fd, const void* buf, size_t count, int64_t offset) {
    return positionalIo(fd, const_cast<void*>(buf), count, offset, true);
}
int fsync(int fd) { return _commit(fd); }
int fdatasync(int fd) { return _commit(fd); }

// crypto/os_random.h declares this (non-inline) on Windows so that header never needs windows.h.
bool osRandomBytes(void* buf, size_t len) {
    if (len == 0) return true;
    if (buf == nullptr) return false;
    uint8_t* p = static_cast<uint8_t*>(buf);
    while (len > 0) {  // BCryptGenRandom takes a ULONG length: chunk so >4 GiB cannot truncate
        const ULONG chunk = len > 0x40000000u ? 0x40000000u : static_cast<ULONG>(len);
        if (BCryptGenRandom(nullptr, p, chunk, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) return false;
        p += chunk;
        len -= chunk;
    }
    return true;
}

// Opens a host file from a UTF-8 path (declared in ffi/ve_engine.cpp). Returns a CRT descriptor or -1.
// _O_BINARY is essential: the C runtime's default text mode would translate CR/LF and treat 0x1A
// as EOF, silently corrupting a container.
int ve_win_open_utf8(const char* path, int writable, int create) {
    const int wlen = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, nullptr, 0);
    if (wlen <= 0) return -1;
    std::vector<wchar_t> wpath(static_cast<size_t>(wlen));
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wpath.data(), wlen) <= 0) return -1;
    if (create) {
        return _wopen(wpath.data(), _O_RDWR | _O_CREAT | _O_TRUNC | _O_BINARY | _O_NOINHERIT,
                      _S_IREAD | _S_IWRITE);
    }
    return _wopen(wpath.data(), (writable ? _O_RDWR : _O_RDONLY) | _O_BINARY | _O_NOINHERIT);
}
