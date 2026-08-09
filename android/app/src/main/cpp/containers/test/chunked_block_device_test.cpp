// Host-side test, no Android toolchain required:
// g++ -std=c++17 chunked_block_device_test.cpp ../chunked_block_device.cpp -o chunked_block_device_test
#include "../chunked_block_device.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <limits>
#include <vector>

struct Call {
    uint64_t chunk;
    uint64_t offset;
    size_t length;

    bool operator==(const Call& other) const {
        return chunk == other.chunk && offset == other.offset && length == other.length;
    }
};

int main() {
    constexpr uint32_t chunkSize = 16;
    std::vector<Call> reads;
    std::vector<Call> writes;

    ChunkedBlockDevice device(
        48, chunkSize,
        [&reads](uint64_t chunk, uint64_t offset, unsigned char* out, size_t length) {
            reads.push_back({chunk, offset, length});
            std::memset(out, static_cast<int>(chunk), length);
            return true;
        },
        [&writes](uint64_t chunk, uint64_t offset, const unsigned char*, size_t length) {
            writes.push_back({chunk, offset, length});
            return true;
        });

    // A range across two boundaries must be split exactly at each chunk.
    unsigned char output[22]{};
    assert(device.pread(10, output, sizeof(output)));
    assert((reads == std::vector<Call>{{0, 10, 6}, {1, 0, 16}}));
    assert(output[0] == 0 && output[5] == 0 && output[6] == 1 && output[21] == 1);

    const unsigned char input[22]{};
    assert(device.pwrite(10, input, sizeof(input)));
    assert((writes == std::vector<Call>{{0, 10, 6}, {1, 0, 16}}));

    // A callback error must stop the request and be propagated to native I/O.
    ChunkedBlockDevice failing(32, chunkSize,
        [](uint64_t, uint64_t, unsigned char*, size_t) { return false; },
        [](uint64_t, uint64_t, const unsigned char*, size_t) { return false; });
    assert(!failing.pread(0, output, 1));
    assert(!failing.pwrite(0, input, 1));

    // Bounds checks must reject overflow and EOF-spanning requests without callbacks.
    assert(!device.pread(47, output, 2));
    assert(!device.pwrite(std::numeric_limits<uint64_t>::max(), input, 1));
    assert(!device.pread(0, nullptr, 1));
    assert(device.pread(48, nullptr, 0));

    std::puts("chunked_block_device_test: all assertions passed");
    return 0;
}
