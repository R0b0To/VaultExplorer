#pragma once
// Initialisation of the reserved VeraCrypt header areas (the two 128 KiB header
// groups at the start and end of a container). See vc_geometry.h for the layout.
//
// Real VeraCrypt fills ALL of both groups with random data before the real
// headers go in, so an absent hidden-volume header is indistinguishable from a
// present one (and from the rest of the encrypted-looking header area). A fresh
// zero-extended file that only receives the normal 512-byte headers instead
// shows an all-zero hidden-header slot exactly when there is no hidden volume.
//
// Written as templates over a byte sink and a random source so the same code
// serves file containers (pwrite on an fd) and USB devices (physicalWrite), and
// can be unit-tested on the host (containers/test/vc_header_areas_test.cpp).
#include <algorithm>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <vector>
#include <unistd.h>
#include "vc_geometry.h"

namespace vcgeom {

// pwrite() the whole buffer, retrying on EINTR and short writes.
inline bool pwriteFully(int fd, uint64_t offset, const unsigned char* data, size_t length) {
    size_t done = 0;
    while (done < length) {
        const ssize_t n = ::pwrite(fd, data + done, length - done, static_cast<off_t>(offset + done));
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (n == 0) return false;
        done += static_cast<size_t>(n);
    }
    return true;
}

// Writes `length` random bytes at `offset` in 64 KiB pieces.
//   sink(uint64_t offset, const unsigned char* data, size_t n) -> bool
//   rnd(void* out, size_t n) -> bool
template <typename SinkFn, typename RandomFn>
bool writeRandomRange(uint64_t offset, uint64_t length, SinkFn&& sink, RandomFn&& rnd) {
    constexpr uint64_t kChunk = 64 * 1024;
    std::vector<unsigned char> buf(static_cast<size_t>(std::min<uint64_t>(length, kChunk)));
    for (uint64_t done = 0; done < length;) {
        const size_t n = static_cast<size_t>(std::min<uint64_t>(length - done, buf.size()));
        if (!rnd(buf.data(), n)) return false;
        if (!sink(offset + done, buf.data(), n)) return false;
        done += n;
    }
    return true;
}

// Fills both header groups of the container that starts at `base` and is
// `containerSize` bytes long: [base, base+A) and [base+size-A, base+size).
// Call it BEFORE writing the real headers. The last piece ends at the final
// byte of the container, so on a file that has not been extended yet this also
// establishes the full length.
template <typename SinkFn, typename RandomFn>
bool randomizeHeaderGroups(uint64_t base, uint64_t containerSize, SinkFn&& sink, RandomFn&& rnd) {
    if (containerSize < 2 * TC_VOLUME_HEADER_GROUP_SIZE) return false;
    return writeRandomRange(base, TC_VOLUME_HEADER_GROUP_SIZE, sink, rnd) &&
           writeRandomRange(base + containerSize - TC_VOLUME_HEADER_GROUP_SIZE,
                            TC_VOLUME_HEADER_GROUP_SIZE, sink, rnd);
}

}  // namespace vcgeom
