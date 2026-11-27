// Host-side test, no Android toolchain required:
//   g++ -std=c++17 fd_write_buffer_test.cpp -o fd_write_buffer_test && ./fd_write_buffer_test
//
// Covers the contract disk_write/CTRL_SYNC depend on: sectors FatFs was told
// were written must still reach the fd after a *failed* flush. The buffer
// used to clear a stream before pwrite ran, so one failed flush (EIO from the
// SD card / FUSE layer, a revoked fd, ...) silently discarded up to 1 MB of
// already-acknowledged FAT/directory/data writes while every later flush
// reported success.
#include "../fd_write_buffer.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <string>
#include <vector>
#include <atomic>

namespace {

struct TempFile {
    std::string path;
    int fd = -1;
    TempFile() {
        char tmpl[] = "/tmp/fdwb_testXXXXXX";
        fd = mkstemp(tmpl);
        assert(fd >= 0);
        path = tmpl;
    }
    ~TempFile() {
        if (fd >= 0) close(fd);
        unlink(path.c_str());
    }
    // A second descriptor on the same file that rejects writes (EBADF),
    // standing in for a transient write failure.
    int openReadOnly() const {
        int ro = open(path.c_str(), O_RDONLY);
        assert(ro >= 0);
        return ro;
    }
    std::vector<unsigned char> readAt(uint64_t off, size_t len) const {
        std::vector<unsigned char> out(len, 0);
        ssize_t n = pread64(fd, out.data(), len, static_cast<off64_t>(off));
        assert(n == static_cast<ssize_t>(len));
        return out;
    }
};

std::vector<unsigned char> bytesOf(unsigned char fill, size_t n) {
    return std::vector<unsigned char>(n, fill);
}

// Data stream (> 2 KB writes): a failed flush keeps the bytes; a later
// successful flush persists them.
void testDataStreamSurvivesFailedFlush() {
    TempFile f;
    FdWriteBuffer buf;
    auto data = bytesOf(0xA5, 4096);
    assert(buf.write(f.fd, 8192, data.data(), data.size()));

    int ro = f.openReadOnly();
    assert(!buf.flush(ro));          // write failed
    close(ro);

    assert(buf.flush(f.fd));         // retry on a healthy fd
    assert(f.readAt(8192, 4096) == data);
}

// Metadata stream (<= 2 KB writes: FAT/directory sectors): same guarantee.
void testMetaStreamSurvivesFailedFlush() {
    TempFile f;
    FdWriteBuffer buf;
    auto fat = bytesOf(0x3C, 512);
    assert(buf.write(f.fd, 1024, fat.data(), fat.size()));

    int ro = f.openReadOnly();
    assert(!buf.flush(ro));
    close(ro);

    assert(buf.flush(f.fd));
    assert(f.readAt(1024, 512) == fat);
}

// A read overlapping buffered bytes must not lose them if the flush it
// triggers fails.
void testFlushIfOverlapsFailureKeepsData() {
    TempFile f;
    FdWriteBuffer buf;
    auto data = bytesOf(0x77, 1024);
    assert(buf.write(f.fd, 4096, data.data(), data.size()));

    int ro = f.openReadOnly();
    assert(!buf.flushIfOverlaps(ro, 4096, 512));
    close(ro);

    assert(buf.flushIfOverlaps(f.fd, 4096, 512));
    assert(f.readAt(4096, 1024) == data);
}

// A failed flush inside write() (non-contiguous data write) must report the
// failure without discarding the earlier, still-pending stream.
void testNonContiguousWriteFailureKeepsPendingStream() {
    TempFile f;
    FdWriteBuffer buf;
    auto first = bytesOf(0x11, 4096);
    assert(buf.write(f.fd, 0, first.data(), first.size()));

    // Non-contiguous follow-up forces a flush of `first`; use a read-only fd
    // so that flush fails.
    int ro = f.openReadOnly();
    auto second = bytesOf(0x22, 4096);
    assert(!buf.write(ro, 65536, second.data(), second.size()));
    close(ro);

    assert(buf.flush(f.fd));
    assert(f.readAt(0, 4096) == first);
}

// Sanity: the normal coalescing path still persists everything on flush.
void testHappyPathCoalescesAndPersists() {
    TempFile f;
    FdWriteBuffer buf;
    for (int i = 0; i < 8; i++) {
        auto chunk = bytesOf(static_cast<unsigned char>(0x40 + i), 4096);
        assert(buf.write(f.fd, static_cast<uint64_t>(i) * 4096, chunk.data(), chunk.size()));
    }
    assert(buf.flush(f.fd));
    for (int i = 0; i < 8; i++) {
        assert(f.readAt(static_cast<uint64_t>(i) * 4096, 4096) ==
               bytesOf(static_cast<unsigned char>(0x40 + i), 4096));
    }
    // Nothing left pending: a second flush is a no-op success.
    assert(buf.flush(f.fd));
}

// reset() still discards pending bytes (used when a session is torn down).
void testResetDiscardsPending() {
    TempFile f;
    FdWriteBuffer buf;
    auto data = bytesOf(0x99, 4096);
    assert(buf.write(f.fd, 0, data.data(), data.size()));
    buf.reset();
    assert(buf.flush(f.fd));
    assert(lseek(f.fd, 0, SEEK_END) == 0);  // nothing was written
}

// ---- failure logging -------------------------------------------------------
// A failed pwrite used to return a bare `false`. It must now leave one log
// line with the errno and the fd's access mode (the diagnostic that tells
// "fd was opened read-only" from "disk full"), without ever naming a file,
// and must not flood the log when the fd stays broken.
std::vector<std::string> g_logLines;
void captureSink(int level, const char* tag, const char* message) {
    if (level != ENGINE_LOG_LEVEL_WARN) return;
    if (std::string(tag) != "VaultExplorer_C++") return;
    if (!std::strstr(message, "pwrite64 failed")) return;
    g_logLines.emplace_back(message);
}

// Must run before every other test: the failure counter is process-wide.
void testFailedWriteLogsErrnoAndAccessMode() {
    engineLogSetSink(captureSink);
    TempFile f;
    int ro = f.openReadOnly();
    auto data = bytesOf(0x5A, 4096);
    assert(!FdWriteBuffer::directWrite(ro, 8192, data.data(), data.size()));
    assert(g_logLines.size() == 1);
    const std::string& line = g_logLines[0];
    assert(line.find("errno=9") != std::string::npos);         // EBADF on an O_RDONLY fd
    assert(line.find("fdAccess=RDONLY") != std::string::npos);
    assert(line.find("off=8192") != std::string::npos);
    assert(line.find("len=4096") != std::string::npos);
    assert(line.find(f.path) == std::string::npos);            // never a path

    // 19 more failures: only #2..#5 and the powers of two (8, 16) are logged.
    for (int i = 0; i < 19; i++) {
        assert(!FdWriteBuffer::directWrite(ro, 0, data.data(), data.size()));
    }
    assert(g_logLines.size() == 7);

    // A write that succeeds logs nothing.
    assert(FdWriteBuffer::directWrite(f.fd, 0, data.data(), data.size()));
    assert(g_logLines.size() == 7);
    close(ro);
    engineLogSetSink(nullptr);
}

}  // namespace

int main() {
    testFailedWriteLogsErrnoAndAccessMode();
    testDataStreamSurvivesFailedFlush();
    testMetaStreamSurvivesFailedFlush();
    testFlushIfOverlapsFailureKeepsData();
    testNonContiguousWriteFailureKeepsPendingStream();
    testHappyPathCoalescesAndPersists();
    testResetDiscardsPending();
    std::printf("fd_write_buffer_test: all passed\n");
    return 0;
}
