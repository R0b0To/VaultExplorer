#pragma once

// Operating-system CSPRNG, as one small portable function.
//
// Every place that needs random bytes straight from the OS (container salts,
// the ext2/3/4 UUID, single-file-crypto IVs, the base stream userentropy::
// fillRandom() mixes user entropy into) used to open /dev/urandom itself.
// That is fine on Android and Linux but does not exist on Windows, so the
// read now lives here:
//
//   * Windows  -> BCryptGenRandom, implemented in ffi/ve_win_platform.cpp (link bcrypt)
//   * others   -> /dev/urandom, read to completion, retrying on EINTR / short
//                 reads (the exact behavior the call sites had before)
//
// Returns true only if all `len` bytes were produced. On false the buffer
// contents are unspecified and must not be used as key material.

#include <cstddef>
#include <cstdint>

#if !defined(_WIN32)
#  include <cerrno>
#  include <fcntl.h>
#  include <unistd.h>
#endif

#if defined(_WIN32)
// Implemented with BCryptGenRandom in ffi/ve_win_platform.cpp -- kept out of this header so
// no engine translation unit has to include <windows.h> (it collides with the ntfs-3g headers).
bool osRandomBytes(void* buf, size_t len);
#else
inline bool osRandomBytes(void* buf, size_t len) {
    if (len == 0) return true;
    if (buf == nullptr) return false;
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    uint8_t* p = static_cast<uint8_t*>(buf);
    size_t done = 0;
    bool ok = true;
    while (done < len) {
        ssize_t n = read(fd, p + done, len - done);
        if (n < 0) {
            if (errno == EINTR) continue;
            ok = false;
            break;
        }
        if (n == 0) {  // EOF on urandom should be impossible; treat as failure
            ok = false;
            break;
        }
        done += static_cast<size_t>(n);
    }
    close(fd);
    return ok;
}
#endif  // !_WIN32
