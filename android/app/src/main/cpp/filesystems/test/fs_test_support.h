// Shared scaffolding for the host-side filesystem backend tests
// (ext_backend_test.cpp, ntfs_backend_test.cpp): a tiny CHECK framework, test
// runner, deterministic test data, and host-file helpers. Header-only; each test
// binary is a single translation unit, so the globals below are not shared state.
#pragma once

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static int g_failures = 0;
static int g_checks = 0;
static int g_skips = 0;

#define CHECK(cond)                                                                   \
    do {                                                                              \
        ++g_checks;                                                                   \
        if (!(cond)) {                                                                \
            ++g_failures;                                                             \
            std::printf("    FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);           \
        }                                                                             \
    } while (0)
#define CHECK_EQ(a, b)                                                                \
    do {                                                                              \
        ++g_checks;                                                                   \
        const auto va_ = (a);                                                         \
        const auto vb_ = (b);                                                         \
        if (!(va_ == vb_)) {                                                          \
            ++g_failures;                                                             \
            std::printf("    FAIL %s:%d: %s == %s\n", __FILE__, __LINE__, #a, #b);    \
        }                                                                             \
    } while (0)

using Bytes = std::vector<uint8_t>;

static std::string g_tmp;  // per-run scratch directory, removed by runTests()

static bool commandExists(const char* name) {
    const std::string cmd = std::string("command -v ") + name + " >/dev/null 2>&1";
    return std::system(cmd.c_str()) == 0;
}

static Bytes pseudoRandom(size_t n, uint64_t seed) {
    Bytes out(n);
    uint64_t x = seed * 0x9E3779B97F4A7C15ull + 1;
    for (size_t i = 0; i < n; ++i) {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;  // xorshift64
        out[i] = static_cast<uint8_t>(x >> 24);
    }
    return out;
}

static bool writeHostFile(const std::string& path, const Bytes& data) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) return false;
    const bool ok = fwrite(data.data(), 1, data.size(), f) == data.size();
    fclose(f);
    return ok;
}
static Bytes readHostFile(const std::string& path) {
    Bytes out;
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return out;
    uint8_t buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) out.insert(out.end(), buf, buf + n);
    fclose(f);
    return out;
}
static uint64_t hashHostFile(const std::string& path) {  // FNV-1a
    uint64_t h = 1469598103934665603ull;
    for (uint8_t b : readHostFile(path)) { h ^= b; h *= 1099511628211ull; }
    return h;
}

struct TestCase { const char* name; void (*fn)(); };
#define T(fn) {#fn, fn}

// Runs every test, calling [afterEach] between them (close volumes, etc.),
// prints a summary and returns the process exit code.
static int runTests(const char* suite, const TestCase* tests, size_t count, void (*afterEach)()) {
    std::printf("== %s ==\n", suite);
    int failedTests = 0;
    for (size_t i = 0; i < count; ++i) {
        const int before = g_failures;
        std::printf("[ RUN  ] %s\n", tests[i].name);
        tests[i].fn();
        if (afterEach) afterEach();
        const bool ok = g_failures == before;
        if (!ok) ++failedTests;
        std::printf("[ %s ] %s\n", ok ? "  OK" : "FAIL", tests[i].name);
    }
    if (!g_tmp.empty()) {
        const std::string cleanup = "rm -rf '" + g_tmp + "'";
        std::system(cleanup.c_str());
    }
    std::printf("\n%zu tests, %d checks, %d failed checks (%d failed tests), %d skipped checks\n",
                count, g_checks, g_failures, failedTests, g_skips);
    return g_failures == 0 ? 0 : 1;
}

static bool makeScratchDir(const char* prefix) {
    std::string tmpl = std::string("/tmp/") + prefix + ".XXXXXX";
    std::vector<char> buf(tmpl.begin(), tmpl.end());
    buf.push_back('\0');
    if (!mkdtemp(buf.data())) { std::perror("mkdtemp"); return false; }
    g_tmp = buf.data();
    return true;
}
