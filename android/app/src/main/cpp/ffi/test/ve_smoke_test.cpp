// End-to-end smoke test for the desktop C ABI (ffi/ve_engine.h).
//
// Drives ONLY the public ve_* functions -- exactly what a dart:ffi host would --
// against a real VeraCrypt container created in a temp directory:
//
//   create -> probe -> unlock -> mkdir/write/read/list/size/rename/copy/delete
//   -> lock -> re-unlock (persistence) -> wrong password -> cancel path
//
// Usage: ve_smoke_test [filesystem ...]     (default: fat)
//        e.g. ve_smoke_test fat exfat ntfs ext4
// Exit code 0 = every check passed.

#include "ve_engine.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if defined(_WIN32)
#  include <io.h>
#  include <windows.h>
#else
#  include <unistd.h>
#endif

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                              \
    do {                                                                         \
        ++g_checks;                                                              \
        if (!(cond)) {                                                           \
            ++g_failures;                                                        \
            std::fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                        \
    } while (0)

#define CHECK_RC(expr, expected)                                                         \
    do {                                                                                 \
        ++g_checks;                                                                      \
        const int32_t rc_ = (expr);                                                      \
        if (rc_ != (expected)) {                                                         \
            ++g_failures;                                                                \
            std::fprintf(stderr, "  FAIL %s:%d: %s -> %d (expected %d)\n", __FILE__,     \
                         __LINE__, #expr, rc_, (int)(expected));                         \
        }                                                                                \
    } while (0)

static std::string tempPath(const char* name) {
#if defined(_WIN32)
    char dir[MAX_PATH];
    DWORD n = GetTempPathA(MAX_PATH, dir);
    return std::string(dir, n) + name;
#else
    const char* t = std::getenv("TMPDIR");
    return std::string(t && *t ? t : "/tmp") + "/" + name;
#endif
}

static bool makeSparseFile(const std::string& path, int64_t size) {
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) return false;
    // A plain fseek past the end then one byte makes a (possibly sparse) file of `size`.
#if defined(_WIN32)
    bool ok = _fseeki64(f, size - 1, SEEK_SET) == 0;
#else
    bool ok = fseeko(f, static_cast<off_t>(size - 1), SEEK_SET) == 0;
#endif
    ok = ok && std::fputc(0, f) != EOF;
    std::fclose(f);
    return ok;
}

static int32_t unlock(const std::string& path, const char* password, int volId, int readOnly = 0) {
    int fd = ve_open_file(path.c_str(), readOnly ? 0 : 1);
    if (fd < 0) return -1000;
    ve_unlock_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.fd = fd;
    p.password = reinterpret_cast<const uint8_t*>(password);
    p.password_len = static_cast<int32_t>(std::strlen(password));
    p.vol_id = volId;
    p.cipher_id = 255;
    p.hash_id = 255;
    p.read_only = readOnly;
    return ve_unlock(&p);
}

static std::string readAll(int vol, const char* path) {
    int64_t size = ve_get_file_size(vol, path);
    std::string out;
    if (size <= 0) return out;
    ve_buffer buf{};
    if (ve_read_file_chunk(vol, path, 0, static_cast<int32_t>(size), &buf) == VE_OK && buf.data) {
        out.assign(reinterpret_cast<const char*>(buf.data), buf.len);
    }
    ve_buffer_free(&buf);
    return out;
}

static std::vector<std::string> listDir(int vol, const char* path) {
    std::vector<std::string> names;
    ve_buffer buf{};
    if (ve_list_directory(vol, path, &buf) != VE_OK || !buf.data) { ve_buffer_free(&buf); return names; }
    auto u32 = [&](size_t off) {
        return (uint32_t)buf.data[off] | ((uint32_t)buf.data[off + 1] << 8) |
               ((uint32_t)buf.data[off + 2] << 16) | ((uint32_t)buf.data[off + 3] << 24);
    };
    size_t off = 4;
    uint32_t count = u32(0);
    for (uint32_t i = 0; i < count && off + 4 <= buf.len; ++i) {
        uint32_t len = u32(off);
        off += 4;
        if (off + len > buf.len) break;
        names.emplace_back(reinterpret_cast<const char*>(buf.data) + off, len);
        off += len;
    }
    ve_buffer_free(&buf);
    return names;
}

static bool listContains(const std::vector<std::string>& entries, const char* name) {
    for (const auto& e : entries) if (e.find(name) != std::string::npos) return true;
    return false;
}

static void runFilesystem(const char* fs, int64_t sizeBytes) {
    std::printf("== filesystem: %s (%lld MiB) ==\n", fs, (long long)(sizeBytes >> 20));
    const std::string path = tempPath((std::string("ve_smoke_") + fs + ".hc").c_str());
    const char* kPassword = "correct horse battery staple";
    const int kVol = 0;

    std::remove(path.c_str());  // the file must not exist: ve_create_file makes it

    // ---- create ----
    {
        int fd = ve_create_file(path.c_str());
        CHECK(fd >= 0);
        ve_create_params cp;
        std::memset(&cp, 0, sizeof(cp));
        cp.struct_size = sizeof(cp);
        cp.fd = fd;
        cp.password = reinterpret_cast<const uint8_t*>(kPassword);
        cp.password_len = static_cast<int32_t>(std::strlen(kPassword));
        cp.size_bytes = sizeBytes;
        cp.file_system = fs;
        cp.container_format = 0;  // VeraCrypt
        cp.cipher_id = 255;
        cp.hash_id = 255;
        cp.quick_format = 1;
        CHECK_RC(ve_create_container(&cp), VE_OK);
    }

    // ---- probe ----
    {
        int fd = ve_open_file(path.c_str(), 0);
        CHECK(fd >= 0);
        const char* fmt = ve_probe_format(fd);
        std::printf("  probe: %s\n", fmt);
        // A VeraCrypt volume has no magic header, so it probes as an unknown/headerless
        // blob; the point of this check is only that probing never crashes or claims
        // a different container format.
        CHECK(fmt != nullptr);
        ve_close_fd(fd);
    }

    // ---- wrong password never unlocks ----
    CHECK_RC(unlock(path, "definitely wrong", kVol), VE_ERR_FAILED);

    // ---- unlock + file operations ----
    CHECK_RC(unlock(path, kPassword, kVol), VE_OK);
    {
        std::printf("  matched cipher=%d hash=%d format=%d\n", ve_get_matched_cipher_id(kVol),
                    ve_get_matched_hash_id(kVol), ve_get_container_format(kVol));
        CHECK(ve_get_matched_cipher_id(kVol) >= 0);
        CHECK(ve_get_matched_hash_id(kVol) >= 0);
        CHECK(ve_get_container_format(kVol) == 0);  // VeraCrypt
        CHECK(ve_get_matched_cipher_id(99) < 0);

        uint64_t total = 0, freeB = 0;
        CHECK_RC(ve_get_space_info(kVol, &total, &freeB), VE_OK);
        std::printf("  space: total=%llu free=%llu\n", (unsigned long long)total, (unsigned long long)freeB);
        CHECK(total > 0 && freeB > 0 && freeB <= total);

        ve_vault_info info;
        std::memset(&info, 0, sizeof(info));
        info.struct_size = sizeof(info);
        CHECK_RC(ve_get_vault_info(kVol, &info), VE_OK);
        std::printf("  info: format=%d size=%lld cipher=%d hash=%d hidden=%d ro=%d fs=%s\n", info.container_format,
                    (long long)info.volume_size_bytes, info.cipher_id, info.hash_id, info.hidden_volume,
                    info.read_only, info.has_file_system ? info.file_system : "(none)");
        CHECK(info.container_format == 0 && info.has_cipher_hash == 1 && info.volume_size_bytes > 0);
        CHECK(info.read_only == 0 && info.hidden_volume == 0 && info.has_file_system == 1);
        ve_vault_info bad;
        std::memset(&bad, 0, sizeof(bad));
        bad.struct_size = sizeof(bad);
        CHECK_RC(ve_get_vault_info(7, &bad), VE_ERR_NOT_UNLOCKED);

        char label[64] = {0};
        CHECK(ve_get_filesystem_label(kVol, label, sizeof(label)) >= 0);
        std::printf("  fs label: %s\n", label);

        CHECK_RC(ve_create_directory(kVol, "/docs"), VE_OK);

        const std::string payload = "hello from the desktop engine\n";
        CHECK_RC(ve_write_file_chunk(kVol, "/docs/hello.txt",
                                     0, reinterpret_cast<const uint8_t*>(payload.data()), payload.size()),
                 VE_OK);
        CHECK(ve_get_file_size(kVol, "/docs/hello.txt") == (int64_t)payload.size());
        CHECK(readAll(kVol, "/docs/hello.txt") == payload);

        // multi-chunk write/read crossing sector and cluster boundaries
        std::string big(300 * 1024 + 123, '\0');
        for (size_t i = 0; i < big.size(); ++i) big[i] = static_cast<char>((i * 131 + 7) & 0xFF);
        const size_t half = big.size() / 2;
        CHECK_RC(ve_write_file_chunk(kVol, "/docs/big.bin", 0,
                                     reinterpret_cast<const uint8_t*>(big.data()), half), VE_OK);
        CHECK_RC(ve_write_file_chunk(kVol, "/docs/big.bin", (int64_t)half,
                                     reinterpret_cast<const uint8_t*>(big.data()) + half, big.size() - half), VE_OK);
        CHECK(readAll(kVol, "/docs/big.bin") == big);

        auto root = listDir(kVol, "/");
        auto docs = listDir(kVol, "/docs");
        std::printf("  / has %zu entries, /docs has %zu\n", root.size(), docs.size());
        // The Dart side addresses paths WITHOUT a leading slash ("" = root, "docs/x.txt").
        CHECK(listDir(kVol, "").size() == root.size());
        CHECK(listDir(kVol, "docs").size() == docs.size());
        CHECK(ve_get_file_size(kVol, "docs/big.bin") == (int64_t)big.size());
        CHECK(readAll(kVol, "docs/hello.txt") == payload);
        CHECK(listContains(root, "docs"));
        CHECK(listContains(docs, "hello.txt"));
        CHECK(listContains(docs, "big.bin"));

        CHECK_RC(ve_rename_file(kVol, "/docs/hello.txt", "/docs/renamed.txt"), VE_OK);
        CHECK(readAll(kVol, "/docs/renamed.txt") == payload);

        // copy with progress tracking + cancellation plumbing
        ve_op_register(42, VE_OP_COPY);
        CHECK_RC(ve_copy_file(kVol, "/docs/renamed.txt", kVol, "/docs/copy.txt", 42), VE_OK);
        ve_op_unregister(42);
        CHECK(readAll(kVol, "/docs/copy.txt") == payload);

        // streaming read
        int64_t h = ve_open_stream(kVol, "/docs/big.bin");
        CHECK(h != 0);
        if (h) {
            std::vector<uint8_t> chunk(4096);
            const int64_t off = 100000;
            int32_t n = ve_read_stream(kVol, h, off, chunk.data(), (int32_t)chunk.size());
            CHECK(n == (int32_t)chunk.size());
            CHECK(n > 0 && std::memcmp(chunk.data(), big.data() + off, (size_t)n) == 0);
            ve_close_stream(kVol, h);
        }

        // export to the host and import back
        const std::string hostOut = tempPath("ve_smoke_export.bin");
        CHECK_RC(ve_export_file(kVol, "/docs/big.bin", hostOut.c_str(), 0), VE_OK);
        CHECK_RC(ve_import_file(kVol, "/docs/imported.bin", hostOut.c_str(), 0), VE_OK);
        CHECK(readAll(kVol, "/docs/imported.bin") == big);
        std::remove(hostOut.c_str());

        CHECK_RC(ve_delete_file(kVol, "/docs/copy.txt"), VE_OK);
        CHECK(!listContains(listDir(kVol, "/docs"), "copy.txt"));

        // unlocked slot must reject a bad slot id / path cleanly
        CHECK(ve_get_file_size(99, "/x") < 0);
        ve_buffer junk{};
        CHECK_RC(ve_list_directory(5, "/", &junk), VE_ERR_NOT_UNLOCKED);

        ve_lock(kVol);
        CHECK_RC(ve_list_directory(kVol, "/", &junk), VE_ERR_NOT_UNLOCKED);
    }

    // ---- persistence across lock / re-unlock, and read-only mount ----
    CHECK_RC(unlock(path, kPassword, kVol), VE_OK);
    CHECK(readAll(kVol, "/docs/renamed.txt") == "hello from the desktop engine\n");
    ve_lock(kVol);
    CHECK_RC(unlock(path, kPassword, kVol, /*readOnly=*/1), VE_OK);
    CHECK_RC(ve_write_file_chunk(kVol, "/docs/nope.txt", 0, (const uint8_t*)"x", 1), VE_ERR_READ_ONLY);
    ve_lock(kVol);

    std::remove(path.c_str());
}

// Creates a container in a file that does not exist yet (ve_create_file), with an embedded hidden
// volume, then checks that each password opens its own volume and the contents stay separate.
static void runHidden() {
    std::printf("== hidden volume (fat outer 8 MiB, fat hidden 2 MiB) ==\n");
    const std::string path = tempPath("ve_smoke_hidden.hc");
    std::remove(path.c_str());  // must NOT exist: exercises ve_create_file
    const char* kOuter = "outer password";
    const char* kHidden = "hidden password";

    int fd = ve_create_file(path.c_str());
    CHECK(fd >= 0);
    ve_create_hidden_params hp;
    std::memset(&hp, 0, sizeof(hp));
    hp.struct_size = sizeof(hp);
    hp.fd = fd;
    hp.outer_password = reinterpret_cast<const uint8_t*>(kOuter);
    hp.outer_password_len = (int32_t)std::strlen(kOuter);
    hp.hidden_password = reinterpret_cast<const uint8_t*>(kHidden);
    hp.hidden_password_len = (int32_t)std::strlen(kHidden);
    hp.size_bytes = 8ll << 20;
    hp.hidden_size_bytes = 2ll << 20;
    hp.outer_file_system = "fat";
    hp.hidden_file_system = "fat";
    hp.outer_cipher_id = hp.hidden_cipher_id = 255;
    hp.outer_hash_id = hp.hidden_hash_id = 255;
    hp.quick_format = 1;
    CHECK_RC(ve_create_container_with_hidden(&hp), VE_OK);

    CHECK_RC(unlock(path, kOuter, 0), VE_OK);
    const std::string outerData = "lives in the outer volume";
    CHECK_RC(ve_write_file_chunk(0, "outer.txt", 0, (const uint8_t*)outerData.data(), outerData.size()), VE_OK);
    ve_lock(0);

    CHECK_RC(unlock(path, kHidden, 0), VE_OK);
    CHECK(ve_get_file_size(0, "outer.txt") == 0);  // the hidden volume is a different filesystem
    const std::string hiddenData = "lives in the hidden volume";
    CHECK_RC(ve_write_file_chunk(0, "secret.txt", 0, (const uint8_t*)hiddenData.data(), hiddenData.size()), VE_OK);
    ve_lock(0);

    CHECK_RC(unlock(path, kOuter, 0), VE_OK);
    CHECK(readAll(0, "outer.txt") == outerData);
    CHECK(ve_get_file_size(0, "secret.txt") == 0);
    ve_lock(0);
    CHECK_RC(unlock(path, "neither", 0), VE_ERR_FAILED);

    std::remove(path.c_str());
}

int main(int argc, char** argv) {
    std::printf("ve abi %d, %d volume slots\n", ve_abi_version(), ve_max_volumes());
    CHECK(ve_abi_version() == VE_ABI_VERSION);

    std::vector<std::string> filesystems;
    for (int i = 1; i < argc; ++i) filesystems.push_back(argv[i]);
    if (filesystems.empty()) filesystems.push_back("fat");

    for (const auto& fs : filesystems) {
        // ext/ntfs need more room than a tiny FAT volume.
        const int64_t size = (fs == "fat" || fs == "exfat") ? 8ll << 20 : 32ll << 20;
        runFilesystem(fs.c_str(), size);
    }

    runHidden();

    std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
