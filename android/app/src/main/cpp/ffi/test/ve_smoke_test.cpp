// End-to-end smoke test for the desktop C ABI (ffi/ve_engine.h).
//
// Drives ONLY the public ve_* functions -- exactly what a dart:ffi host would --
// against a real VeraCrypt container created in a temp directory:
//
//   create -> probe -> unlock -> mkdir/write/read/list/size/rename/copy/delete
//   -> lock -> re-unlock (persistence) -> wrong password -> cancel path
//
// plus hidden volumes, password change, the container tools (expand, grow the file system, hidden volume in an
// existing volume), folder vaults, crypto primitives, digests and the single-file tool.
//
// Usage: ve_smoke_test [filesystem ...]     (default: fat)
//        e.g. ve_smoke_test fat exfat ntfs ext4
//        ve_smoke_test tools | crypto | fv | chpw | device     (one section only)
// Exit code 0 = every check passed.

#include "ve_crypto_vectors.inc"
#include "ve_engine.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#if defined(_WIN32)
#  include <io.h>
#  include <windows.h>
#else
#  include <fcntl.h>
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

        // native symlinks (ext2/3/4 and NTFS only): a relative link, listed apart from the ordinary listing
        if (std::strcmp(fs, "ext4") == 0 || std::strcmp(fs, "ntfs") == 0) {
            CHECK_RC(ve_create_symlink(kVol, "/docs/lnk", "copy.txt"), VE_OK);
            ve_buffer lb{};
            CHECK_RC(ve_list_symlinks(kVol, "/docs", &lb), VE_OK);
            bool saw = false;
            if (lb.data && lb.len > 4) saw = std::string((const char*)lb.data + 4, lb.len - 4).find("|lnk") != std::string::npos;
            ve_buffer_free(&lb);
            CHECK(saw);
            CHECK(!listContains(listDir(kVol, "/docs"), "lnk"));  // links stay out of ordinary listings
            ve_buffer tb{};
            CHECK_RC(ve_read_symlink(kVol, "/docs/lnk", &tb), VE_OK);
            CHECK(tb.len == 8 && std::memcmp(tb.data, "copy.txt", 8) == 0);
            ve_buffer_free(&tb);
            CHECK_RC(ve_delete_file(kVol, "/docs/lnk"), VE_OK);
        } else {
            CHECK(ve_create_symlink(kVol, "/docs/lnk", "copy.txt") != VE_OK);  // FAT / exFAT cannot
        }

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
    CHECK(ve_get_file_size(0, "outer.txt") < 0);  // the hidden volume is a different filesystem (missing -> -1)
    const std::string hiddenData = "lives in the hidden volume";
    CHECK_RC(ve_write_file_chunk(0, "secret.txt", 0, (const uint8_t*)hiddenData.data(), hiddenData.size()), VE_OK);
    ve_lock(0);

    CHECK_RC(unlock(path, kOuter, 0), VE_OK);
    CHECK(readAll(0, "outer.txt") == outerData);
    CHECK(ve_get_file_size(0, "secret.txt") < 0);  // not visible from the outer volume (missing -> -1)
    ve_lock(0);
    CHECK_RC(unlock(path, "neither", 0), VE_ERR_FAILED);

    std::remove(path.c_str());
}

// ---- crypto primitives vs. independent reference implementations ---------------------------------
static std::vector<uint8_t> unhex(const char* h) {
    std::vector<uint8_t> out;
    for (size_t i = 0; h[i] && h[i + 1]; i += 2) {
        auto nib = [](char c) { return c <= '9' ? c - '0' : (c | 0x20) - 'a' + 10; };
        out.push_back(static_cast<uint8_t>(nib(h[i]) * 16 + nib(h[i + 1])));
    }
    return out;
}
static std::vector<uint8_t> vecOf(const char* name) {
    for (const auto& v : kVectors) if (std::strcmp(v.name, name) == 0) return unhex(v.hex);
    std::fprintf(stderr, "  FAIL missing vector %s\n", name);
    ++g_failures;
    return {};
}
static std::vector<uint8_t> bytes(const std::string& s) { return std::vector<uint8_t>(s.begin(), s.end()); }
static std::vector<uint8_t> seq(int from, int n) {
    std::vector<uint8_t> v(n);
    for (int i = 0; i < n; ++i) v[i] = static_cast<uint8_t>(from + i);
    return v;
}
static std::vector<uint8_t> takeBuffer(ve_buffer& b) {
    std::vector<uint8_t> out(b.data, b.data + b.len);
    ve_buffer_free(&b);
    return out;
}

static void runCrypto() {
    std::printf("== crypto primitives ==\n");
    const std::string utf8pw = "p\xC3\xA4ssw\xC3\xB6rd \xF0\x9F\x94\x92";
    const auto pwBytes = bytes(utf8pw);
    const auto key32 = seq(0, 32), key16 = seq(0, 16), iv12 = seq(100, 12), iv16 = seq(200, 16), nonce24 = seq(50, 24);
    const std::string aadS = "header-bytes";
    std::string ptS;
    for (int i = 0; i < 3; ++i) ptS += "The quick brown fox jumps over the lazy dog";
    const auto pt = bytes(ptS), aad = bytes(aadS);

    // PBKDF2 (SHA-1 / SHA-256 / SHA-512), incl. a non-ASCII UTF-8 password and an embedded-NUL salt
    {
        std::vector<uint8_t> o(20);
        CHECK_RC(ve_pbkdf2(VE_HASH_SHA1, (const uint8_t*)"password", 8, (const uint8_t*)"salt", 4, 2, o.data(), o.size()), VE_OK);
        CHECK(o == vecOf("pbkdf2_sha1"));
        o.assign(40, 0);
        CHECK_RC(ve_pbkdf2(VE_HASH_SHA256, pwBytes.data(), pwBytes.size(), (const uint8_t*)"saltSALTsalt", 12, 1000, o.data(), o.size()), VE_OK);
        CHECK(o == vecOf("pbkdf2_sha256"));
        o.assign(64, 0);
        const uint8_t salt[] = {0, 1, 2, 3, 's', 'a', 'l', 't'};
        CHECK_RC(ve_pbkdf2(VE_HASH_SHA512, pwBytes.data(), pwBytes.size(), salt, sizeof(salt), 1000, o.data(), o.size()), VE_OK);
        CHECK(o == vecOf("pbkdf2_sha512"));
        CHECK_RC(ve_pbkdf2(9, pwBytes.data(), 1, salt, 4, 1, o.data(), o.size()), VE_ERR_INVALID_ARG);   // bad hash id
        CHECK_RC(ve_pbkdf2(VE_HASH_SHA256, pwBytes.data(), 1, salt, 0, 1, o.data(), o.size()), VE_ERR_INVALID_ARG);  // empty salt
    }
    // HMAC (RFC 4231 style vectors; the SHA-512 one uses a key longer than the block size)
    {
        uint8_t o[64];
        size_t n = 0;
        const auto data = bytes("what do ya want for nothing?");
        CHECK_RC(ve_hmac(VE_HASH_SHA1, (const uint8_t*)"Jefe", 4, data.data(), data.size(), o, sizeof(o), &n), VE_OK);
        CHECK(std::vector<uint8_t>(o, o + n) == vecOf("hmac_sha1"));
        CHECK_RC(ve_hmac(VE_HASH_SHA256, (const uint8_t*)"Jefe", 4, data.data(), data.size(), o, sizeof(o), &n), VE_OK);
        CHECK(std::vector<uint8_t>(o, o + n) == vecOf("hmac_sha256"));
        std::string longKey(100, 'k'), longData;
        for (int i = 0; i < 50; ++i) longData += "data";
        CHECK_RC(ve_hmac(VE_HASH_SHA512, (const uint8_t*)longKey.data(), longKey.size(), (const uint8_t*)longData.data(), longData.size(), o, sizeof(o), &n), VE_OK);
        CHECK(std::vector<uint8_t>(o, o + n) == vecOf("hmac_sha512"));
        CHECK_RC(ve_hmac(VE_HASH_SHA512, (const uint8_t*)"k", 1, data.data(), data.size(), o, 32, &n), VE_ERR_INVALID_ARG);  // out_cap too small
    }
    // scrypt (RFC 7914 vector 2: N=1024 r=8 p=16) and Argon2id
    {
        std::vector<uint8_t> o(64);
        CHECK_RC(ve_scrypt((const uint8_t*)"password", 8, (const uint8_t*)"NaCl", 4, 1024, 8, 16, o.data(), o.size()), VE_OK);
        CHECK(o == vecOf("scrypt"));
        o.assign(32, 0);
        CHECK_RC(ve_argon2id((const uint8_t*)"password", 8, (const uint8_t*)"somesalt", 8, 1024, 2, 2, o.data(), o.size()), VE_OK);
        CHECK(o == vecOf("argon2id"));
    }
    // AES-GCM: 128/256-bit keys, AAD, a 16-byte IV, empty plaintext, tamper detection
    {
        ve_buffer b{};
        CHECK_RC(ve_aes_gcm_seal(key16.data(), 16, iv12.data(), 12, aad.data(), aad.size(), pt.data(), pt.size(), &b), VE_OK);
        CHECK(takeBuffer(b) == vecOf("gcm16"));
        CHECK_RC(ve_aes_gcm_seal(key32.data(), 32, iv12.data(), 12, aad.data(), aad.size(), pt.data(), pt.size(), &b), VE_OK);
        const auto sealed = takeBuffer(b);
        CHECK(sealed == vecOf("gcm32"));
        CHECK_RC(ve_aes_gcm_seal(key32.data(), 32, iv16.data(), 16, nullptr, 0, pt.data(), pt.size(), &b), VE_OK);
        CHECK(takeBuffer(b) == vecOf("gcm32_iv16"));
        CHECK_RC(ve_aes_gcm_seal(key32.data(), 32, iv12.data(), 12, nullptr, 0, nullptr, 0, &b), VE_OK);
        CHECK(takeBuffer(b) == vecOf("gcm_empty"));

        CHECK_RC(ve_aes_gcm_open(key32.data(), 32, iv12.data(), 12, aad.data(), aad.size(), sealed.data(), sealed.size(), &b), VE_OK);
        CHECK(takeBuffer(b) == pt);
        auto bad = sealed;
        bad[3] ^= 1;
        CHECK_RC(ve_aes_gcm_open(key32.data(), 32, iv12.data(), 12, aad.data(), aad.size(), bad.data(), bad.size(), &b), VE_ERR_FAILED);
        CHECK(b.data == nullptr && b.len == 0);
        CHECK_RC(ve_aes_gcm_open(key32.data(), 32, iv12.data(), 12, nullptr, 0, sealed.data(), sealed.size(), &b), VE_ERR_FAILED);  // wrong AAD
        const auto empty = vecOf("gcm_empty");
        CHECK_RC(ve_aes_gcm_open(key32.data(), 32, iv12.data(), 12, nullptr, 0, empty.data(), empty.size(), &b), VE_OK);
        CHECK(takeBuffer(b).empty());
        CHECK_RC(ve_aes_gcm_seal(key32.data(), 24, iv12.data(), 12, nullptr, 0, pt.data(), pt.size(), &b), VE_ERR_INVALID_ARG);  // 192-bit key unsupported
    }
    // AES-CBC decrypt (PKCS#7)
    {
        ve_buffer b{};
        const auto c128 = vecOf("cbc128"), c256 = vecOf("cbc256");
        CHECK_RC(ve_aes_cbc_decrypt(key16.data(), 16, iv16.data(), 16, c128.data(), c128.size(), &b), VE_OK);
        CHECK(takeBuffer(b) == pt);
        CHECK_RC(ve_aes_cbc_decrypt(key32.data(), 32, iv16.data(), 16, c256.data(), c256.size(), &b), VE_OK);
        CHECK(takeBuffer(b) == bytes("exactly16bytes!!"));
        CHECK_RC(ve_aes_cbc_decrypt(key16.data(), 16, iv16.data(), 16, c128.data(), c128.size() - 1, &b), VE_ERR_INVALID_ARG);  // not block-aligned
        CHECK_RC(ve_aes_cbc_decrypt(key32.data(), 32, iv16.data(), 16, c128.data(), c128.size(), &b), VE_ERR_FAILED);  // wrong key: padding check fails
    }
    // XChaCha20-Poly1305 open
    {
        ve_buffer b{};
        const auto sealed = vecOf("xchacha");
        CHECK_RC(ve_xchacha20poly1305_open(key32.data(), 32, nonce24.data(), 24, aad.data(), aad.size(), sealed.data(), sealed.size(), &b), VE_OK);
        CHECK(takeBuffer(b) == pt);
        auto bad = sealed;
        bad.back() ^= 1;
        CHECK_RC(ve_xchacha20poly1305_open(key32.data(), 32, nonce24.data(), 24, aad.data(), aad.size(), bad.data(), bad.size(), &b), VE_ERR_FAILED);
        CHECK_RC(ve_xchacha20poly1305_open(key32.data(), 31, nonce24.data(), 24, nullptr, 0, sealed.data(), sealed.size(), &b), VE_ERR_INVALID_ARG);
    }
}

static std::string toHex(const uint8_t* d, size_t n) {
    static const char* k = "0123456789abcdef";
    std::string s;
    for (size_t i = 0; i < n; ++i) { s += k[d[i] >> 4]; s += k[d[i] & 15]; }
    return s;
}

static void runHashes() {
    std::printf("== streaming digests ==\n");
    // known one-shot vectors
    struct One { int alg; const char* in; const char* hex; } ones[] = {
        {VE_HASH_MD5, "", "d41d8cd98f00b204e9800998ecf8427e"},
        {VE_HASH_MD5, "abc", "900150983cd24fb0d6963f7d28e17f72"},
        {VE_HASH_SHA1, "abc", "a9993e364706816aba3e25717850c26c9cd0d89d"},
        {VE_HASH_SHA256, "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
    };
    for (const auto& o : ones) {
        uint8_t out[64];
        size_t n = 0;
        CHECK_RC(ve_hash_bytes(o.alg, (const uint8_t*)o.in, std::strlen(o.in), out, sizeof(out), &n), VE_OK);
        CHECK(toHex(out, n) == o.hex);
    }
    // one session, four algorithms, chunked at awkward sizes, vs hashlib
    std::vector<uint8_t> data(1024000);
    for (size_t i = 0; i < data.size(); ++i) data[i] = (uint8_t)(i & 255);
    const uint32_t mask = (1u << VE_HASH_MD5) | (1u << VE_HASH_SHA1) | (1u << VE_HASH_SHA256) | (1u << VE_HASH_SHA512);
    int64_t h = ve_hash_begin(mask);
    CHECK(h != 0);
    const size_t steps[] = {1, 7, 4096, 65537, 3, 999983};
    size_t off = 0, si = 0;
    while (off < data.size()) {
        const size_t n = std::min(steps[si++ % 6], data.size() - off);
        CHECK_RC(ve_hash_update(h, data.data() + off, n), VE_OK);
        off += n;
    }
    const struct { int alg; const char* name; } algs[] = {{VE_HASH_MD5, "digest_md5"}, {VE_HASH_SHA1, "digest_sha1"}, {VE_HASH_SHA256, "digest_sha256"}, {VE_HASH_SHA512, "digest_sha512"}};
    for (const auto& a : algs) {
        uint8_t out[64];
        size_t n = 0;
        CHECK_RC(ve_hash_finish(h, a.alg, out, sizeof(out), &n), VE_OK);
        CHECK(out != nullptr && std::vector<uint8_t>(out, out + n) == vecOf(a.name));
        CHECK_RC(ve_hash_finish(h, a.alg, out, sizeof(out), &n), VE_ERR_INVALID_ARG);  // a digest can be taken only once
    }
    ve_hash_free(h);
    uint8_t scratch[64];
    size_t sn = 0;
    CHECK_RC(ve_hash_update(h, data.data(), 1), VE_ERR_INVALID_ARG);                         // freed handle is rejected
    CHECK_RC(ve_hash_finish(h, VE_HASH_MD5, scratch, sizeof(scratch), &sn), VE_ERR_INVALID_ARG);
    CHECK_RC(ve_hash_update(0x1234, data.data(), 1), VE_ERR_INVALID_ARG);                    // forged handle too
    CHECK(ve_hash_begin(0) == 0);
    CHECK_RC(ve_hash_bytes(9, data.data(), 1, scratch, sizeof(scratch), &sn), VE_ERR_INVALID_ARG);
    // MD5 is digest-only: it must not be usable as a PBKDF2/HMAC hash
    CHECK_RC(ve_pbkdf2(VE_HASH_MD5, (const uint8_t*)"p", 1, (const uint8_t*)"s", 1, 1, scratch, 16), VE_ERR_INVALID_ARG);
    CHECK_RC(ve_hmac(VE_HASH_MD5, (const uint8_t*)"k", 1, (const uint8_t*)"d", 1, scratch, sizeof(scratch), &sn), VE_ERR_INVALID_ARG);
}

static int32_t changePw(const std::string& path, int format, const char* oldPw, const char* newPw) {
    int fd = ve_open_file(path.c_str(), 1);
    if (fd < 0) return -1000;
    ve_change_password_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.fd = fd;
    p.container_format = format;
    p.old_password = (const uint8_t*)oldPw;
    p.old_password_len = (int32_t)std::strlen(oldPw);
    p.new_password = (const uint8_t*)newPw;
    p.new_password_len = (int32_t)std::strlen(newPw);
    p.cipher_id = p.hash_id = 255;
    return ve_change_password(&p);
}

static void runChangePassword(int format, const char* fs, int64_t size) {
    std::printf("== change password (%s, %s) ==\n", format == 0 ? "VeraCrypt" : (format == 1 ? "LUKS1" : "LUKS2"), fs);
    const std::string path = tempPath("ve_smoke_chpw.hc");
    std::remove(path.c_str());
    const char* kOld = "old pass";
    const char* kNew = "new pass \xC3\xA9";
    int fd = ve_create_file(path.c_str());
    CHECK(fd >= 0);
    ve_create_params cp;
    std::memset(&cp, 0, sizeof(cp));
    cp.struct_size = sizeof(cp);
    cp.fd = fd;
    cp.password = (const uint8_t*)kOld;
    cp.password_len = (int32_t)std::strlen(kOld);
    cp.size_bytes = size;
    cp.file_system = fs;
    cp.container_format = format;
    // Creation takes concrete ids: LUKS has no "auto" (255) the way VeraCrypt unlock does; the app's
    // create dialog defaults both to 0 (AES / first hash).
    cp.cipher_id = cp.hash_id = format == 0 ? 255 : 0;
    cp.quick_format = 1;
    CHECK_RC(ve_create_container(&cp), VE_OK);

    CHECK_RC(unlock(path, kOld, 0), VE_OK);
    const std::string data = "survives a password change";
    CHECK_RC(ve_write_file_chunk(0, "keep.txt", 0, (const uint8_t*)data.data(), data.size()), VE_OK);
    ve_lock(0);

    CHECK_RC(changePw(path, format, "wrong old password", kNew), format == 0 ? VE_ERR_FAILED : VE_ERR_AUTH_FAILED);
    CHECK_RC(unlock(path, kOld, 0), VE_OK);  // a failed change must leave the old password working
    ve_lock(0);
    CHECK_RC(changePw(path, format, kOld, kNew), VE_OK);
    CHECK_RC(unlock(path, kOld, 0), VE_ERR_FAILED);
    CHECK_RC(unlock(path, kNew, 0), VE_OK);
    CHECK(readAll(0, "keep.txt") == data);
    ve_lock(0);
    CHECK_RC(changePw(path, format, kNew, ""), VE_ERR_INVALID_ARG);  // an empty new password is refused
    std::remove(path.c_str());
}

static bool writeHostFile(const std::string& path, const std::vector<uint8_t>& data) {
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) return false;
    const bool ok = data.empty() || std::fwrite(data.data(), 1, data.size(), f) == data.size();
    std::fclose(f);
    return ok;
}
static std::vector<uint8_t> readHostFile(const std::string& path) {
    std::vector<uint8_t> out;
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return out;
    uint8_t buf[65536];
    size_t n;
    while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0) out.insert(out.end(), buf, buf + n);
    std::fclose(f);
    return out;
}

static int32_t singleFile(bool encrypt, int cipher, const std::string& src, const std::string& dst, const char* pw,
                          const std::vector<std::string>& keyfiles = {}, int opId = 0) {
    std::vector<int32_t> kf;
    for (const auto& k : keyfiles) kf.push_back(ve_open_file(k.c_str(), 0));
    ve_single_file_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.src_fd = ve_open_file(src.c_str(), 0);
    p.dest_fd = ve_create_file(dst.c_str());
    p.encrypt = encrypt;
    p.cipher_index = cipher;
    p.password = (const uint8_t*)pw;
    p.password_len = (int32_t)std::strlen(pw);
    p.keyfile_fds = kf.empty() ? nullptr : kf.data();
    p.keyfile_count = (int32_t)kf.size();
    p.op_id = opId;
    return ve_single_file_crypt(&p);
}

static void runSingleFile() {
    std::printf("== single-file encryption ==\n");
    const std::string plain = tempPath("ve_sf_plain.bin"), enc = tempPath("ve_sf_enc.vxenc"), dec = tempPath("ve_sf_dec.bin");
    const std::string keyfile = tempPath("ve_sf_key.bin");
    std::vector<uint8_t> data(300 * 1024 + 77);
    for (size_t i = 0; i < data.size(); ++i) data[i] = (uint8_t)((i * 2654435761u) >> 13);
    CHECK(writeHostFile(plain, data));
    CHECK(writeHostFile(keyfile, seq(11, 200)));

    for (int cipher : {0, 1, 2, 3}) {
        CHECK_RC(singleFile(true, cipher, plain, enc, "tool pass \xC3\xA9"), VE_OK);
        const auto ciphertext = readHostFile(enc);
        CHECK(ciphertext.size() > data.size());                          // header + tag overhead
        CHECK(!ciphertext.empty() && std::search(ciphertext.begin(), ciphertext.end(), data.begin(), data.begin() + 64) == ciphertext.end());  // no plaintext leak
        CHECK_RC(singleFile(false, 0, enc, dec, "tool pass \xC3\xA9"), VE_OK);
        CHECK(readHostFile(dec) == data);
        CHECK_RC(singleFile(false, 0, enc, dec, "wrong"), VE_ERR_FAILED);
    }
    // keyfile as a second factor
    CHECK_RC(singleFile(true, 0, plain, enc, "pw", {keyfile}), VE_OK);
    CHECK_RC(singleFile(false, 0, enc, dec, "pw"), VE_ERR_FAILED);                 // password alone is not enough
    CHECK_RC(singleFile(false, 0, enc, dec, "pw", {keyfile}), VE_OK);
    CHECK(readHostFile(dec) == data);
    // progress events + cancellation
    {
        ve_event ev;
        while (ve_poll_event(&ev)) {}  // drain
        ve_op_register(7, VE_OP_COPY);
        CHECK_RC(singleFile(true, 0, plain, enc, "pw", {}, 7), VE_OK);
        bool sawProgress = false;
        uint64_t lastDone = 0, lastTotal = 0;
        while (ve_poll_event(&ev)) {
            if (ev.kind == VE_EVENT_SPLITJOIN_PROGRESS && ev.op_id == 7) { sawProgress = true; lastDone = ev.n0; lastTotal = ev.n1; }
        }
        CHECK(sawProgress && lastDone <= lastTotal && lastTotal >= data.size());
        ve_op_unregister(7);

        ve_op_register(9, VE_OP_COPY);
        ve_op_cancel(9);
        CHECK_RC(singleFile(true, 0, plain, enc, "pw", {}, 9), VE_ERR_CANCELLED);
        ve_op_unregister(9);
    }
    // truncated / foreign input is rejected, not crashed on
    CHECK(writeHostFile(enc, std::vector<uint8_t>(10, 0xAB)));
    CHECK_RC(singleFile(false, 0, enc, dec, "pw"), VE_ERR_FAILED);
    CHECK(writeHostFile(enc, {}));
    CHECK_RC(singleFile(false, 0, enc, dec, "pw"), VE_ERR_FAILED);
    for (const auto& f : {plain, enc, dec, keyfile}) std::remove(f.c_str());
}


// ---- folder vaults (gocryptfs / Cryptomator / CryFS): create, unlock into a slot, then drive the
// generic slot-addressed file calls against it, including a copy to and from a real container. ----
static void sh(const std::string& cmd) {
    if (std::system(cmd.c_str()) != 0) { /* best-effort setup/cleanup */ }
}

static void runFolderVaults() {
    std::printf("== folder vaults ==\n");
    int32_t supported = ve_fv_supported();
    std::printf("  supported: %d\n", supported);
    if (!supported) {
        ve_buffer msg{};
        CHECK_RC(ve_fv_unlock(0, VE_FV_GOCRYPTFS, "/nonexistent", (const uint8_t*)"x", 1, nullptr, 0, 0, 1, "", "", &msg, nullptr),
                 VE_ERR_FAILED);
        ve_buffer_free(&msg);
        return;
    }
#if !defined(_WIN32)
    static const char* kNames[] = {"gocryptfs", "cryptomator", "cryfs"};
    const char* kPassword = "correct horse battery staple";
    const char* kNewPassword = "another passphrase";
    const std::string stateDir = tempPath("ve_fv_state");
    const std::string tmpDir = tempPath("");
    const int kFvVol = 3;  // not 0, so it cannot be mistaken for the container slot used below
    const int kBlockVol = 1;

    // A real container for the mixed copy tests (slot 1).
    const std::string hc = tempPath("ve_fv_block.hc");
    std::remove(hc.c_str());
    {
        int fd = ve_create_file(hc.c_str());
        CHECK(fd >= 0);
        ve_create_params cp;
        std::memset(&cp, 0, sizeof(cp));
        cp.struct_size = sizeof(cp);
        cp.fd = fd;
        cp.password = reinterpret_cast<const uint8_t*>(kPassword);
        cp.password_len = static_cast<int32_t>(std::strlen(kPassword));
        cp.size_bytes = 8ll << 20;
        cp.file_system = "fat";
        cp.container_format = 0;
        cp.cipher_id = 255;
        cp.hash_id = 255;
        cp.quick_format = 1;
        CHECK_RC(ve_create_container(&cp), VE_OK);
    }
    CHECK_RC(unlock(hc, kPassword, kBlockVol), VE_OK);

    std::string big(300 * 1000 + 17, '\0');  // spans several cipher blocks / chunks
    for (size_t i = 0; i < big.size(); ++i) big[i] = (char)((i * 131 + (i >> 8)) & 0xFF);
    const std::string payload = "hello from a folder vault\n";

    for (int fmt = 0; fmt < 3; ++fmt) {
        std::printf("  -- %s --\n", kNames[fmt]);
        const std::string root = tempPath((std::string("ve_fv_") + kNames[fmt]).c_str());
        const std::string rmCmd = "rm -rf '" + root + "' '" + stateDir + "'";
        sh(rmCmd);
        sh("mkdir -p '" + root + "' '" + stateDir + "'");

        int32_t probed = 99;
        CHECK_RC(ve_fv_probe(root.c_str(), &probed), VE_OK);
        CHECK(probed == -1);  // empty directory

        ve_buffer msg{};
        CHECK_RC(ve_fv_create(fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                              0, 0, 0, 0, 0, nullptr, nullptr, 0, stateDir.c_str(), tmpDir.c_str(), &msg),
                 VE_OK);
        if (msg.data) std::printf("    create message: %.*s\n", (int)msg.len, (const char*)msg.data);
        ve_buffer_free(&msg);
        CHECK_RC(ve_fv_probe(root.c_str(), &probed), VE_OK);
        CHECK(probed == fmt);

        // wrong password -> AUTH_FAILED; right one opens it
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)"definitely wrong", 16, nullptr, 0, 0, 1,
                              stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                 VE_ERR_AUTH_FAILED);
        ve_buffer_free(&msg);
        ve_buffer derived{};
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                              nullptr, 0, 0, 1, stateDir.c_str(), tmpDir.c_str(), &msg, &derived),
                 VE_OK);
        ve_buffer_free(&msg);
        ve_buffer_free(&derived);
        CHECK(ve_get_container_format(kFvVol) ==
              (fmt == 0 ? VE_FORMAT_GOCRYPTFS : fmt == 1 ? VE_FORMAT_CRYPTOMATOR : VE_FORMAT_CRYFS));
        // an occupied slot refuses a second unlock
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                              nullptr, 0, 0, 1, stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                 VE_ERR_FAILED);
        ve_buffer_free(&msg);

        // generic slot-addressed calls
        CHECK_RC(ve_create_directory(kFvVol, "/docs"), VE_OK);
        CHECK_RC(ve_write_file_chunk(kFvVol, "/docs/hello.txt", 0, (const uint8_t*)payload.data(), payload.size()), VE_OK);
        CHECK_RC(ve_fv_finish_write(kFvVol, "/docs/hello.txt"), VE_OK);  // chunked writes become valid here
        CHECK(ve_get_file_size(kFvVol, "/docs/hello.txt") == (int64_t)payload.size());
        CHECK(readAll(kFvVol, "/docs/hello.txt") == payload);
        CHECK(ve_get_file_size(kFvVol, "/docs/missing") < 0);
        for (size_t off = 0; off < big.size(); off += 64 * 1024) {
            const size_t n = std::min<size_t>(64 * 1024, big.size() - off);
            CHECK_RC(ve_write_file_chunk(kFvVol, "/docs/big.bin", (int64_t)off, (const uint8_t*)big.data() + off, n), VE_OK);
        }
        CHECK_RC(ve_fv_finish_write(kFvVol, "/docs/big.bin"), VE_OK);
        CHECK(ve_get_file_size(kFvVol, "/docs/big.bin") == (int64_t)big.size());
        CHECK(readAll(kFvVol, "/docs/big.bin") == big);
        CHECK(ve_get_folder_size(kFvVol, "/docs") == (int64_t)(big.size() + payload.size()));

        const auto root1 = listDir(kFvVol, "/");
        const auto docs = listDir(kFvVol, "/docs");
        CHECK(listContains(root1, "docs"));
        CHECK(listContains(docs, "hello.txt") && listContains(docs, "big.bin"));

        if (fmt == 1) {
            // Cryptomator stores names NFC-normalised. A decomposed name ("e" + U+0301) written by one host must be
            // the same file as the composed one (U+00E9) on every other, so the engine needs a Unicode normaliser
            // (ffi/ve_nfc.cpp; Android asks java.text.Normalizer).
            const std::string nfdPath = "/docs/e\xCC\x81.txt";
            const std::string nfcPath = "/docs/\xC3\xA9.txt";
            CHECK_RC(ve_write_file_chunk(kFvVol, nfdPath.c_str(), 0, (const uint8_t*)payload.data(), payload.size()), VE_OK);
            CHECK_RC(ve_fv_finish_write(kFvVol, nfdPath.c_str()), VE_OK);
            CHECK(readAll(kFvVol, nfcPath.c_str()) == payload);
            const auto nfcDocs = listDir(kFvVol, "/docs");
            CHECK(listContains(nfcDocs, "\xC3\xA9.txt") && !listContains(nfcDocs, "e\xCC\x81.txt"));
            CHECK_RC(ve_delete_file(kFvVol, nfcPath.c_str()), VE_OK);
        }

        CHECK_RC(ve_rename_file(kFvVol, "/docs/hello.txt", "/docs/renamed.txt"), VE_OK);
        CHECK(readAll(kFvVol, "/docs/renamed.txt") == payload);
        CHECK_RC(ve_set_last_modified(kFvVol, "/docs/renamed.txt", 1700000000), VE_OK);

        // copy inside the vault, with op tracking
        ve_op_register(77, VE_OP_COPY);
        CHECK_RC(ve_copy_file(kFvVol, "/docs/big.bin", kFvVol, "/docs/big_copy.bin", 77), VE_OK);
        ve_op_unregister(77);
        CHECK(readAll(kFvVol, "/docs/big_copy.bin") == big);
        // empty file via copy
        CHECK_RC(ve_write_file_chunk(kFvVol, "/docs/empty.txt", 0, (const uint8_t*)"", 0), VE_OK);
        CHECK_RC(ve_fv_finish_write(kFvVol, "/docs/empty.txt"), VE_OK);
        CHECK_RC(ve_copy_file(kFvVol, "/docs/empty.txt", kFvVol, "/docs/empty_copy.txt", 0), VE_OK);
        CHECK(ve_get_file_size(kFvVol, "/docs/empty_copy.txt") == 0);

        // vault -> container and container -> vault (mixed copy)
        CHECK_RC(ve_create_directory(kBlockVol, "/fromvault"), VE_OK);
        CHECK_RC(ve_copy_file(kFvVol, "/docs/big.bin", kBlockVol, "/fromvault/big.bin", 0), VE_OK);
        CHECK(readAll(kBlockVol, "/fromvault/big.bin") == big);
        CHECK_RC(ve_copy_file(kBlockVol, "/fromvault/big.bin", kFvVol, "/docs/from_container.bin", 0), VE_OK);
        CHECK(readAll(kFvVol, "/docs/from_container.bin") == big);
        CHECK_RC(ve_delete_file(kBlockVol, "/fromvault/big.bin"), VE_OK);
        CHECK_RC(ve_delete_file(kBlockVol, "/fromvault"), VE_OK);

        // streaming read
        int64_t h = ve_open_stream(kFvVol, "/docs/big.bin");
        CHECK(h != 0);
        if (h) {
            std::vector<uint8_t> chunk(4096);
            const int64_t off = 100000;
            int32_t n = ve_read_stream(kFvVol, h, off, chunk.data(), (int32_t)chunk.size());
            CHECK(n == (int32_t)chunk.size());
            CHECK(n > 0 && std::memcmp(chunk.data(), big.data() + off, (size_t)n) == 0);
            CHECK(ve_read_stream(kFvVol, h, (int64_t)big.size(), chunk.data(), 16) == 0);  // EOF
            ve_close_stream(kFvVol, h);
            CHECK(ve_read_stream(kFvVol, h, 0, chunk.data(), 16) < 0);  // closed handle
        }
        CHECK(ve_open_stream(kFvVol, "/docs/nope") == 0);

        // export to the host and import back
        const std::string hostOut = tempPath("ve_fv_export.bin");
        CHECK_RC(ve_export_file(kFvVol, "/docs/big.bin", hostOut.c_str(), 0), VE_OK);
        CHECK_RC(ve_import_file(kFvVol, "/docs/imported.bin", hostOut.c_str(), 0), VE_OK);
        CHECK(readAll(kFvVol, "/docs/imported.bin") == big);
        std::remove(hostOut.c_str());

        // info / space / label / symlink + hidden-count queries
        ve_vault_info info;
        std::memset(&info, 0, sizeof(info));
        info.struct_size = sizeof(info);
        CHECK_RC(ve_get_vault_info(kFvVol, &info), VE_OK);
        CHECK(info.read_only == 0 && info.container_format == ve_get_container_format(kFvVol));
        uint64_t total = 0, freeB = 0;
        CHECK_RC(ve_get_space_info(kFvVol, &total, &freeB), VE_OK);
        ve_buffer items{};
        CHECK_RC(ve_fv_info(kFvVol, &items), VE_OK);
        CHECK(items.len > 4);
        ve_buffer_free(&items);
        ve_buffer links{};
        CHECK_RC(ve_list_symlinks(kFvVol, "/docs", &links), VE_OK);  // nothing linked yet
        CHECK(links.len == 4);  // just the u32 count (0)
        ve_buffer_free(&links);
        if (fmt == VE_FV_CRYPTOMATOR) {
            // Cryptomator vaults support relative, in-vault symlinks (file and folder targets)
            CHECK_RC(ve_create_symlink(kFvVol, "/docs/link.txt", "renamed.txt"), VE_OK);
            CHECK_RC(ve_create_directory(kFvVol, "/docs/sub"), VE_OK);
            CHECK_RC(ve_create_symlink(kFvVol, "/docs/sublink", "sub"), VE_OK);
            const auto sl = [&] {
                ve_buffer b{};
                std::vector<std::string> out;
                if (ve_list_symlinks(kFvVol, "/docs", &b) == VE_OK && b.len >= 4) {
                    uint32_t cnt = 0;
                    std::memcpy(&cnt, b.data, 4);
                    size_t off = 4;
                    for (uint32_t i = 0; i < cnt && off + 4 <= b.len; ++i) {
                        uint32_t len = 0;
                        std::memcpy(&len, b.data + off, 4);
                        off += 4;
                        out.emplace_back((const char*)b.data + off, len);
                        off += len;
                    }
                }
                ve_buffer_free(&b);
                return out;
            }();
            CHECK(sl.size() == 2);
            bool sawFile = false, sawDir = false;
            for (const auto& e : sl) {
                if (e.rfind("L|", 0) == 0 && e.size() >= 3 && e.find("|link.txt") != std::string::npos) sawFile = true;
                if (e.rfind("LD|0|", 0) == 0 && e.find("|sublink") != std::string::npos) sawDir = true;
            }
            CHECK(sawFile && sawDir);
            ve_buffer tgt{};
            CHECK_RC(ve_read_symlink(kFvVol, "/docs/link.txt", &tgt), VE_OK);
            CHECK(tgt.len == 11 && std::memcmp(tgt.data, "renamed.txt", 11) == 0);
            ve_buffer_free(&tgt);
            CHECK(ve_read_symlink(kFvVol, "/docs/renamed.txt", &tgt) != VE_OK);  // a regular file is not a link
            ve_buffer_free(&tgt);
            CHECK(readAll(kFvVol, "/docs/link.txt") == payload);  // reads resolve inside the vault
            CHECK_RC(ve_delete_file(kFvVol, "/docs/link.txt"), VE_OK);  // deleting unlinks the link only
            CHECK_RC(ve_delete_file(kFvVol, "/docs/sublink"), VE_OK);
            CHECK(readAll(kFvVol, "/docs/renamed.txt") == payload);
        } else {
            if (fmt == VE_FV_CRYFS) {
                // CryFS stores symlink nodes, but does not resolve them for file reads.
                CHECK_RC(ve_create_symlink(kFvVol, "/docs/link.txt", "renamed.txt"), VE_OK);
                ve_buffer cryfsLinks{};
                CHECK_RC(ve_list_symlinks(kFvVol, "/docs", &cryfsLinks), VE_OK);
                uint32_t linkCount = 0;
                if (cryfsLinks.data && cryfsLinks.len >= sizeof(linkCount))
                    std::memcpy(&linkCount, cryfsLinks.data, sizeof(linkCount));
                CHECK(linkCount == 1);
                ve_buffer_free(&cryfsLinks);
                ve_buffer target{};
                CHECK_RC(ve_read_symlink(kFvVol, "/docs/link.txt", &target), VE_OK);
                CHECK(target.len == 11 && std::memcmp(target.data, "renamed.txt", 11) == 0);
                ve_buffer_free(&target);
                CHECK_RC(ve_delete_file(kFvVol, "/docs/link.txt"), VE_OK);
            } else {
                CHECK(ve_create_symlink(kFvVol, "/docs/link.txt", "renamed.txt") != VE_OK);  // gocryptfs does not expose symlinks
            }
        }
        // Cryptomator key-file probe: a current (format 8) vault
        if (fmt == VE_FV_CRYPTOMATOR) {
            int32_t code = 99;
            CHECK_RC(ve_fv_probe_cryptomator(root.c_str(), &code), VE_OK);
            CHECK(code == 8);
        }
        CHECK_RC(ve_fv_batch(kFvVol, 0, 1), VE_OK);
        CHECK_RC(ve_fv_batch(kFvVol, 0, 0), VE_OK);
        CHECK_RC(ve_fv_info(kBlockVol, &items), VE_ERR_NOT_UNLOCKED);  // a container slot is not a folder vault

        CHECK_RC(ve_delete_file(kFvVol, "/docs/big_copy.bin"), VE_OK);
        CHECK(ve_get_file_size(kFvVol, "/docs/big_copy.bin") < 0);

        // lock wipes the slot; the data persists on disk
        ve_buffer junk{};
        ve_lock(kFvVol);
        CHECK_RC(ve_list_directory(kFvVol, "/", &junk), VE_ERR_NOT_UNLOCKED);
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                              nullptr, 0, 0, 1, stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                 VE_OK);
        ve_buffer_free(&msg);
        CHECK(readAll(kFvVol, "/docs/big.bin") == big);
        ve_lock(kFvVol);

        // read-only mount rejects writes
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                              nullptr, 0, 1, 1, stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                 VE_OK);
        ve_buffer_free(&msg);
        CHECK_RC(ve_write_file_chunk(kFvVol, "/docs/nope.txt", 0, (const uint8_t*)"x", 1), VE_ERR_READ_ONLY);
        CHECK(readAll(kFvVol, "/docs/renamed.txt") == payload);
        ve_lock(kFvVol);

        // Check & Repair and the config-file helpers through the ABI
        {
            struct FvCheck {
                int32_t rc = -1;
                uint32_t outcome = 99;
                std::string message;
                uint32_t scanned = 0, deep = 0, issues = 0;
            };
            auto runCheck = [&](const char* pw, int32_t session, bool repair) {
                FvCheck r;
                ve_buffer rec{};
                const uint8_t* p = (const uint8_t*)pw;
                const int32_t n = pw ? (int32_t)std::strlen(pw) : 0;
                r.rc = repair ? ve_fv_repair(fmt, root.c_str(), p, n, session, stateDir.c_str(), tmpDir.c_str(), 0, &rec)
                              : ve_fv_check(fmt, root.c_str(), p, n, session, stateDir.c_str(), tmpDir.c_str(), 0, &rec);
                size_t pos = 0;
                auto u32 = [&]() {
                    uint32_t v = 0;
                    for (int i = 0; i < 4 && pos < rec.len; ++i) v |= (uint32_t)rec.data[pos++] << (8 * i);
                    return v;
                };
                if (r.rc == VE_OK && rec.data) {
                    r.outcome = u32();
                    const uint32_t len = u32();
                    if (pos + len <= rec.len) r.message.assign((const char*)rec.data + pos, len);
                    pos += len;
                    if (r.outcome == 0 && !repair) {
                        r.scanned = u32();
                        r.deep = u32();
                        r.issues = u32();
                    }
                }
                ve_buffer_free(&rec);
                return r;
            };

            FvCheck c = runCheck(nullptr, -1, false);  // structure only: no credentials
            CHECK(c.rc == VE_OK && c.outcome == 0 && c.deep == 0);
            c = runCheck("definitely wrong", -1, false);
            CHECK(c.rc == VE_OK && c.outcome == 1);  // wrong password
            c = runCheck(kPassword, -1, false);        // deep scan with the password
            CHECK(c.rc == VE_OK && c.outcome == 0 && c.deep == 1 && c.scanned >= 1);
            c = runCheck(nullptr, kFvVol, false);      // a session that is not open
            CHECK(c.rc == VE_OK && c.outcome == 2 && !c.message.empty());
            c = runCheck(nullptr, -1, true);
            if (fmt == VE_FV_CRYFS) {
                CHECK(c.rc == VE_OK && c.outcome == 2);  // CryFS repair is not implemented
                CHECK(c.message.find("Automatic repair is currently supported") != std::string::npos);
            } else {
                CHECK(c.rc == VE_OK && c.outcome == 1);  // a repair is refused without credentials
            }

            // the unlocked slot as the credential
            CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                                  nullptr, 0, 1, 1, stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                     VE_OK);
            ve_buffer_free(&msg);
            c = runCheck(nullptr, kFvVol, false);
            CHECK(c.rc == VE_OK && c.outcome == 0 && c.deep == 1);
            ve_lock(kFvVol);

            // config file name, and validation of the real file and of garbage
            ve_buffer name{};
            CHECK_RC(ve_fv_config_file_name(fmt, &name), VE_OK);
            const std::string cfgName(name.data ? (const char*)name.data : "", name.len);
            ve_buffer_free(&name);
            CHECK(cfgName == (fmt == 0 ? "gocryptfs.conf" : fmt == 1 ? "masterkey.cryptomator" : "cryfs.config"));
            std::ifstream cfg(root + "/" + cfgName, std::ios::binary);
            const std::string cfgBytes((std::istreambuf_iterator<char>(cfg)), std::istreambuf_iterator<char>());
            CHECK(!cfgBytes.empty());
            ve_buffer why{};
            CHECK_RC(ve_fv_validate_config(fmt, (const uint8_t*)cfgBytes.data(), (int32_t)cfgBytes.size(), &why), VE_OK);
            ve_buffer_free(&why);
            CHECK_RC(ve_fv_validate_config(fmt, (const uint8_t*)"not a config", 12, &why), VE_ERR_FAILED);
            CHECK(why.len > 0);
            ve_buffer_free(&why);
            CHECK_RC(ve_fv_config_file_name(7, &name), VE_ERR_INVALID_ARG);
        }

        // password change
        CHECK_RC(ve_fv_change_password(fmt, root.c_str(), (const uint8_t*)"nope nope", 9,
                                       (const uint8_t*)kNewPassword, (int32_t)std::strlen(kNewPassword), &msg),
                 VE_ERR_AUTH_FAILED);
        ve_buffer_free(&msg);
        CHECK_RC(ve_fv_change_password(fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                                       (const uint8_t*)kNewPassword, (int32_t)std::strlen(kNewPassword), &msg),
                 VE_OK);
        ve_buffer_free(&msg);
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kPassword, (int32_t)std::strlen(kPassword),
                              nullptr, 0, 0, 1, stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                 VE_ERR_AUTH_FAILED);
        ve_buffer_free(&msg);
        CHECK_RC(ve_fv_unlock(kFvVol, fmt, root.c_str(), (const uint8_t*)kNewPassword, (int32_t)std::strlen(kNewPassword),
                              nullptr, 0, 0, 1, stateDir.c_str(), tmpDir.c_str(), &msg, nullptr),
                 VE_OK);
        ve_buffer_free(&msg);
        CHECK(readAll(kFvVol, "/docs/big.bin") == big);
        ve_lock(kFvVol);

        sh(rmCmd);
    }
    ve_lock(kBlockVol);
    std::remove(hc.c_str());
#endif
}

// ---- container tools: expand, grow the file system, hidden volume in an existing volume (Phase 1c) ----------
// Drives ve_expand_* / ve_grow_*_fs / ve_hidden_*: the engine side of the Expand-volume and Add-hidden-volume
// tools, over real containers. BitLocker cannot be created here, so for it only the refusal paths are covered
// (the engine's own bl_expand / bl_disk_expand tests cover the layout work).

static int64_t hostFileSize(const std::string& path) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return -1;
#if defined(_WIN32)
    _fseeki64(f, 0, SEEK_END);
    const int64_t n = _ftelli64(f);
#else
    fseeko(f, 0, SEEK_END);
    const int64_t n = static_cast<int64_t>(ftello(f));
#endif
    std::fclose(f);
    return n;
}

// True when the descriptor number no longer refers to an open file (POSIX only; elsewhere assumed closed).
static bool fdIsClosed(int fd) {
#if defined(_WIN32)
    (void)fd;
    return true;
#else
    return fcntl(fd, F_GETFD) == -1;
#endif
}

static bool makeContainer(const std::string& path, const char* password, int64_t size, const char* fs, int format,
                          const std::vector<std::string>& keyfiles = {}) {
    std::remove(path.c_str());
    std::vector<int32_t> kf;
    for (const auto& k : keyfiles) {
        const int f = ve_open_file(k.c_str(), 0);
        if (f < 0) return false;
        kf.push_back(f);
    }
    const int fd = ve_create_file(path.c_str());
    if (fd < 0) return false;
    ve_create_params cp;
    std::memset(&cp, 0, sizeof(cp));
    cp.struct_size = sizeof(cp);
    cp.fd = fd;
    cp.password = reinterpret_cast<const uint8_t*>(password);
    cp.password_len = static_cast<int32_t>(std::strlen(password));
    cp.size_bytes = size;
    cp.file_system = fs;
    cp.container_format = format;
    cp.cipher_id = cp.hash_id = format == 0 ? 255 : 0;  // LUKS creation takes concrete ids
    cp.keyfile_fds = kf.empty() ? nullptr : kf.data();
    cp.keyfile_count = static_cast<int32_t>(kf.size());
    cp.quick_format = 1;
    return ve_create_container(&cp) == VE_OK;
}

static int32_t unlockWithKeyfiles(const std::string& path, const char* password, int volId,
                                  const std::vector<std::string>& keyfiles) {
    std::vector<int32_t> kf;
    for (const auto& k : keyfiles) {
        const int f = ve_open_file(k.c_str(), 0);
        if (f < 0) return -1000;
        kf.push_back(f);
    }
    const int fd = ve_open_file(path.c_str(), 1);
    if (fd < 0) return -1000;
    ve_unlock_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.fd = fd;
    p.password = reinterpret_cast<const uint8_t*>(password);
    p.password_len = static_cast<int32_t>(std::strlen(password));
    p.vol_id = volId;
    p.cipher_id = p.hash_id = 255;
    p.keyfile_fds = kf.empty() ? nullptr : kf.data();
    p.keyfile_count = static_cast<int32_t>(kf.size());
    return ve_unlock(&p);
}

struct ToolResult {
    int32_t rc = -1000;       // the call's own return code
    int32_t outcome = -1;     // result_out[0]
    int32_t fsStep = -2;      // result_out[1]: -1 not run, else FsGrowStatus
    int32_t fsKind = -1;      // result_out[2]
};

static ToolResult toolResultOf(int32_t rc, const int32_t* out) {
    ToolResult r;
    r.rc = rc;
    r.outcome = out[0];
    r.fsStep = out[1];
    r.fsKind = out[2];
    return r;
}

// Opens the keyfiles first, then the container (as the worker isolate does), and runs one tool call.
template <typename Call>
static ToolResult runTool(const std::string& path, const std::vector<std::string>& keyfiles, Call call) {
    std::vector<int32_t> kf;
    for (const auto& k : keyfiles) {
        const int f = ve_open_file(k.c_str(), 0);
        if (f < 0) {
            for (int32_t x : kf) ve_close_fd(x);
            return ToolResult{};
        }
        kf.push_back(f);
    }
    const int fd = ve_open_file(path.c_str(), 1);
    if (fd < 0) {
        for (int32_t x : kf) ve_close_fd(x);
        return ToolResult{};
    }
    int32_t out[3] = {-9, -9, -9};
    const int32_t rc = call(fd, kf.empty() ? nullptr : kf.data(), static_cast<int32_t>(kf.size()), out);
    return toolResultOf(rc, out);
}

static ToolResult expandVc(const std::string& path, const char* pw, int64_t newSize, bool initFree, bool growFs,
                           const std::vector<std::string>& keyfiles = {}) {
    return runTool(path, keyfiles, [&](int fd, const int32_t* kf, int32_t kfCount, int32_t* out) {
        return ve_expand_veracrypt(fd, (const uint8_t*)pw, (int32_t)std::strlen(pw), 0, 255, 255, kf, kfCount, newSize,
                                   initFree ? 1 : 0, growFs ? 1 : 0, out);
    });
}

static ToolResult growVc(const std::string& path, const char* pw, const std::vector<std::string>& keyfiles = {}) {
    return runTool(path, keyfiles, [&](int fd, const int32_t* kf, int32_t kfCount, int32_t* out) {
        return ve_grow_veracrypt_fs(fd, (const uint8_t*)pw, (int32_t)std::strlen(pw), 0, 255, 255, kf, kfCount, out);
    });
}

static ToolResult expandLuks(const std::string& path, const char* pw, int64_t newSize, bool initFree, bool growFs) {
    return runTool(path, {}, [&](int fd, const int32_t*, int32_t, int32_t* out) {
        return ve_expand_luks(fd, (const uint8_t*)pw, (int32_t)std::strlen(pw), nullptr, 0, newSize, initFree ? 1 : 0,
                              growFs ? 1 : 0, out);
    });
}

static ToolResult growLuks(const std::string& path, const char* pw) {
    return runTool(path, {}, [&](int fd, const int32_t*, int32_t, int32_t* out) {
        return ve_grow_luks_fs(fd, (const uint8_t*)pw, (int32_t)std::strlen(pw), nullptr, 0, out);
    });
}

static uint64_t spaceTotal(int vol) {
    uint64_t total = 0, freeB = 0;
    return ve_get_space_info(vol, &total, &freeB) == VE_OK ? total : 0;
}

// ExpandOutcome / FsGrowStatus values (ve_engine.h).
enum { kOutOk = 0, kOutWrongPassword = 1, kOutNotExpandable = 2, kOutNotLarger = 3, kOutIoError = 4,
       kOutInUse = 8, kOutNotBitLocker = 9 };
enum { kFsGrown = 0, kFsAlreadyFills = 1, kFsUnsupported = 2, kFsNotRun = -1 };

// [thorough] also runs the refusal paths (in use, wrong password, not larger); each wrong password costs a full
// auto-detect key derivation, so the other file systems only repeat the success path.
static void runExpandVeraCrypt(const char* fs, int expectedKind, bool canGrow, bool thorough) {
    std::printf("== expand VeraCrypt (%s, 32 MiB -> 40 -> 48 MiB) ==\n", fs);
    const std::string path = tempPath("ve_smoke_expand.hc");
    const char* kPw = "expand me";
    const int64_t kMiB = 1ll << 20;
    CHECK(makeContainer(path, kPw, 32 * kMiB, fs, 0));

    CHECK_RC(unlock(path, kPw, 0), VE_OK);
    const std::string keep = "written before the expansion";
    CHECK_RC(ve_write_file_chunk(0, "keep.txt", 0, (const uint8_t*)keep.data(), keep.size()), VE_OK);
    const uint64_t total0 = spaceTotal(0);

    // An unlocked container is never touched.
    if (thorough) {
        const ToolResult r = expandVc(path, kPw, 40 * kMiB, false, true);
        CHECK(r.rc == VE_OK && r.outcome == kOutInUse);
        CHECK(hostFileSize(path) == 32 * kMiB);
        const ToolResult g = growVc(path, kPw);
        CHECK(g.rc == VE_OK && g.outcome == kOutInUse);
    }
    ve_lock(0);

    // Refusals leave the file exactly as it was.
    if (thorough) {
        const ToolResult wrong = expandVc(path, "wrong password", 40 * kMiB, false, true);
        CHECK(wrong.rc == VE_OK && wrong.outcome == kOutWrongPassword && wrong.fsStep == kFsNotRun);
        const ToolResult same = expandVc(path, kPw, 32 * kMiB, false, true);
        CHECK(same.rc == VE_OK && same.outcome == kOutNotLarger);
        const ToolResult smaller = expandVc(path, kPw, 16 * kMiB, false, true);
        CHECK(smaller.rc == VE_OK && smaller.outcome == kOutNotLarger);
        CHECK(hostFileSize(path) == 32 * kMiB);
        CHECK_RC(unlock(path, kPw, 0), VE_OK);  // still opens
        ve_lock(0);
    }

    // Expand and grow the file system in one go (new free space is encrypted zeroes).
    {
        const ToolResult r = expandVc(path, kPw, 40 * kMiB, true, true);
        CHECK(r.rc == VE_OK && r.outcome == kOutOk);
        CHECK(r.fsStep == (canGrow ? kFsGrown : kFsUnsupported));
        CHECK(r.fsKind == expectedKind || (expectedKind == 3 && (r.fsKind == 1 || r.fsKind == 2 || r.fsKind == 3)));
        CHECK(hostFileSize(path) == 40 * kMiB);
        CHECK_RC(unlock(path, kPw, 0), VE_OK);
        CHECK(readAll(0, "keep.txt") == keep);
        if (canGrow) CHECK(spaceTotal(0) > total0);
        const std::string after = "written after";
        CHECK_RC(ve_write_file_chunk(0, "after.txt", 0, (const uint8_t*)after.data(), after.size()), VE_OK);
        CHECK(readAll(0, "after.txt") == after);
        ve_lock(0);
    }

    // Expand only; then grow the file system as a separate step (what "Grow file system only" does).
    if (canGrow) {
        CHECK_RC(unlock(path, kPw, 0), VE_OK);
        const uint64_t before = spaceTotal(0);
        ve_lock(0);
        const ToolResult e = expandVc(path, kPw, 48 * kMiB, false, false);
        CHECK(e.rc == VE_OK && e.outcome == kOutOk && e.fsStep == kFsNotRun);
        CHECK(hostFileSize(path) == 48 * kMiB);
        CHECK_RC(unlock(path, kPw, 0), VE_OK);
        CHECK(spaceTotal(0) == before);  // the file system still ends where it did
        ve_lock(0);

        const ToolResult g = growVc(path, kPw);
        CHECK(g.rc == VE_OK && g.outcome == kOutOk && g.fsStep == kFsGrown && g.fsKind == expectedKind);
        CHECK_RC(unlock(path, kPw, 0), VE_OK);
        CHECK(spaceTotal(0) > before);
        CHECK(readAll(0, "keep.txt") == keep);
        ve_lock(0);

        const ToolResult again = growVc(path, kPw);
        CHECK(again.rc == VE_OK && again.outcome == kOutOk && again.fsStep == kFsAlreadyFills);
        if (thorough) {
            const ToolResult wrong = growVc(path, "wrong password");
            CHECK(wrong.rc == VE_OK && wrong.outcome == kOutWrongPassword);
        }
    }
    std::remove(path.c_str());
}

// Keyfiles are mixed into the password: the call must accept them, refuse their absence, and close every fd.
static void runExpandKeyfile() {
    std::printf("== expand VeraCrypt with a keyfile ==\n");
    const std::string path = tempPath("ve_smoke_expand_kf.hc");
    const std::string keyfile = tempPath("ve_smoke_expand.key");
    const char* kPw = "with keyfile";
    const int64_t kMiB = 1ll << 20;
    CHECK(writeHostFile(keyfile, seq(3, 300)));
    CHECK(makeContainer(path, kPw, 8 * kMiB, "fat", 0, {keyfile}));

    const ToolResult noKeyfile = expandVc(path, kPw, 12 * kMiB, false, false);
    CHECK(noKeyfile.rc == VE_OK && noKeyfile.outcome == kOutWrongPassword);
    CHECK(hostFileSize(path) == 8 * kMiB);

    const ToolResult ok = expandVc(path, kPw, 12 * kMiB, false, false, {keyfile});
    CHECK(ok.rc == VE_OK && ok.outcome == kOutOk);
    CHECK(hostFileSize(path) == 12 * kMiB);
    CHECK_RC(unlockWithKeyfiles(path, kPw, 0, {keyfile}), VE_OK);
    ve_lock(0);
    CHECK_RC(unlock(path, kPw, 0), VE_ERR_FAILED);  // the keyfile is still required

    const ToolResult grow = growVc(path, kPw, {keyfile});
    CHECK(grow.rc == VE_OK && grow.outcome == kOutOk && grow.fsStep == kFsUnsupported);  // FAT cannot grow in place
    std::remove(path.c_str());
    std::remove(keyfile.c_str());
}

static void runExpandLuks(int format, const char* fs, int expectedKind) {
    std::printf("== expand LUKS%d (%s, 32 MiB -> 40 MiB) ==\n", format, fs);
    const std::string path = tempPath("ve_smoke_expand_luks.img");
    const char* kPw = "luks expand";
    const int64_t kMiB = 1ll << 20;
    CHECK(makeContainer(path, kPw, 32 * kMiB, fs, format));

    CHECK_RC(unlock(path, kPw, 0), VE_OK);
    const std::string keep = "luks data before";
    CHECK_RC(ve_write_file_chunk(0, "keep.txt", 0, (const uint8_t*)keep.data(), keep.size()), VE_OK);
    const uint64_t total0 = spaceTotal(0);
    {
        const ToolResult busy = expandLuks(path, kPw, 40 * kMiB, false, true);
        CHECK(busy.rc == VE_OK && busy.outcome == kOutInUse);
    }
    ve_lock(0);

    {
        const ToolResult wrong = expandLuks(path, "wrong password", 40 * kMiB, false, true);
        CHECK(wrong.rc == VE_OK && wrong.outcome == kOutWrongPassword);
        const ToolResult smaller = expandLuks(path, kPw, 16 * kMiB, false, true);
        CHECK(smaller.rc == VE_OK && smaller.outcome == kOutNotLarger);
        CHECK(hostFileSize(path) == 32 * kMiB);
    }
    {
        const ToolResult r = expandLuks(path, kPw, 40 * kMiB, true, true);
        CHECK(r.rc == VE_OK && r.outcome == kOutOk && r.fsStep == kFsGrown && r.fsKind == expectedKind);
        CHECK(hostFileSize(path) == 40 * kMiB);
        CHECK_RC(unlock(path, kPw, 0), VE_OK);
        CHECK(readAll(0, "keep.txt") == keep);
        CHECK(spaceTotal(0) > total0);
        ve_lock(0);
        const ToolResult again = growLuks(path, kPw);
        CHECK(again.rc == VE_OK && again.outcome == kOutOk && again.fsStep == kFsAlreadyFills);
    }
    // A VeraCrypt container is not LUKS (outcome 6) and a LUKS container is not VeraCrypt (wrong password).
    {
        const std::string vc = tempPath("ve_smoke_expand_notluks.hc");
        CHECK(makeContainer(vc, kPw, 8 * kMiB, "fat", 0));
        const ToolResult notLuks = expandLuks(vc, kPw, 12 * kMiB, false, false);
        CHECK(notLuks.rc == VE_OK && notLuks.outcome == 6);
        CHECK(hostFileSize(vc) == 8 * kMiB);
        const ToolResult luksAsVc = expandVc(path, kPw, 48 * kMiB, false, false);
        CHECK(luksAsVc.rc == VE_OK && luksAsVc.outcome == kOutWrongPassword);
        std::remove(vc.c_str());
    }
    std::remove(path.c_str());
}

static void runHiddenInExisting() {
    std::printf("== hidden volume in an existing volume (fat outer 16 MiB) ==\n");
    const std::string path = tempPath("ve_smoke_hidden_direct.hc");
    const char* kOuter = "outer password";
    const char* kHidden = "hidden password";
    const int64_t kMiB = 1ll << 20;
    CHECK(makeContainer(path, kOuter, 16 * kMiB, "fat", 0));

    CHECK_RC(unlock(path, kOuter, 0), VE_OK);
    const std::string outerData = "outer data that must survive";
    CHECK_RC(ve_write_file_chunk(0, "outer.txt", 0, (const uint8_t*)outerData.data(), outerData.size()), VE_OK);
    ve_lock(0);

    auto analyze = [&](const char* pw, int64_t out[4]) {
        const int fd = ve_open_file(path.c_str(), 0);
        if (fd < 0) return (int32_t)-1000;
        return ve_hidden_analyze(fd, (const uint8_t*)pw, (int32_t)std::strlen(pw), 0, 255, 255, nullptr, 0, out);
    };
    auto create = [&](const char* outerPw, const char* hiddenPw, int64_t size, const char* fs, int32_t* outcome) {
        const int fd = ve_open_file(path.c_str(), 1);
        if (fd < 0) return (int32_t)-1000;
        ve_hidden_in_existing_params p;
        std::memset(&p, 0, sizeof(p));
        p.struct_size = sizeof(p);
        p.fd = fd;
        p.outer_password = (const uint8_t*)outerPw;
        p.outer_password_len = (int32_t)std::strlen(outerPw);
        p.outer_cipher_id = p.outer_hash_id = 255;
        p.hidden_password = (const uint8_t*)hiddenPw;
        p.hidden_password_len = (int32_t)std::strlen(hiddenPw);
        p.hidden_file_system = fs;
        p.hidden_size_bytes = size;
        p.hidden_cipher_id = p.hidden_hash_id = 0;
        p.quick_format = 1;
        return ve_hidden_create_in_existing(&p, outcome);
    };

    int64_t info[4] = {-1, -1, -1, -1};
    CHECK_RC(analyze(kOuter, info), VE_OK);
    std::printf("  analysis: outcome=%lld fsKind=%lld cluster=%lld max=%lld\n", (long long)info[0], (long long)info[1],
                (long long)info[2], (long long)info[3]);
    CHECK(info[0] == 0 && info[1] >= 1 && info[1] <= 3 && info[2] > 0);
    const int64_t maxHidden = info[3];
    CHECK(maxHidden >= 2 * kMiB && maxHidden < 16 * kMiB);
    int64_t wrong[4] = {-1, -1, -1, -1};
    CHECK_RC(analyze("not the password", wrong), VE_OK);
    CHECK(wrong[0] == 1 && wrong[3] == 0);

    int32_t outcome = -1;
    CHECK_RC(create(kOuter, kHidden, maxHidden + (1 << 20), "FAT", &outcome), VE_OK);
    CHECK(outcome == 3);  // no room
    CHECK_RC(create(kOuter, kOuter, 2 * kMiB, "FAT", &outcome), VE_OK);
    CHECK(outcome == 6);  // the same password could never be told apart
    CHECK_RC(create("not the password", kHidden, 2 * kMiB, "FAT", &outcome), VE_OK);
    CHECK(outcome == 1);
    // None of the refusals touched the container.
    CHECK_RC(unlock(path, kOuter, 0), VE_OK);
    CHECK(readAll(0, "outer.txt") == outerData);
    ve_lock(0);
    CHECK_RC(unlock(path, kHidden, 0), VE_ERR_FAILED);

    CHECK_RC(create(kOuter, kHidden, 2 * kMiB, "FAT", &outcome), VE_OK);
    CHECK(outcome == 0);

    CHECK_RC(unlock(path, kHidden, 0), VE_OK);  // the hidden volume opens with its own password...
    CHECK(ve_get_file_size(0, "outer.txt") < 0);
    const std::string hiddenData = "lives in the new hidden volume";
    CHECK_RC(ve_write_file_chunk(0, "secret.txt", 0, (const uint8_t*)hiddenData.data(), hiddenData.size()), VE_OK);
    ve_lock(0);
    CHECK_RC(unlock(path, kOuter, 0), VE_OK);  // ...and the outer volume is exactly as it was
    CHECK(readAll(0, "outer.txt") == outerData);
    CHECK(ve_get_file_size(0, "secret.txt") < 0);
    ve_lock(0);
    CHECK_RC(unlock(path, kHidden, 0), VE_OK);
    CHECK(readAll(0, "secret.txt") == hiddenData);
    ve_lock(0);

    // A volume that already holds a hidden volume is not a plain standard volume any more... but its outer header
    // is unchanged, so the tool must not let a second one be stacked on top of the first.
    {
        const std::string keyfile = tempPath("ve_smoke_hidden_direct.key");
        CHECK(writeHostFile(keyfile, seq(9, 200)));
        const std::string kfPath = tempPath("ve_smoke_hidden_direct_kf.hc");
        CHECK(makeContainer(kfPath, kOuter, 16 * kMiB, "fat", 0, {keyfile}));
        const int fd = ve_open_file(kfPath.c_str(), 0);
        const int kfd = ve_open_file(keyfile.c_str(), 0);
        int64_t kfInfo[4] = {-1, -1, -1, -1};
        const int32_t kfds[1] = {kfd};
        CHECK_RC(ve_hidden_analyze(fd, (const uint8_t*)kOuter, (int32_t)std::strlen(kOuter), 0, 255, 255, kfds, 1, kfInfo),
                 VE_OK);
        CHECK(kfInfo[0] == 0 && kfInfo[3] > 0);  // keyfile-protected outer volume: the keyfile fd was accepted and closed
        CHECK(fdIsClosed(fd) && fdIsClosed(kfd));
        std::remove(kfPath.c_str());
        std::remove(keyfile.c_str());
    }
    std::remove(path.c_str());
}

// Bad arguments: the call refuses, and still closes every descriptor it was given.
static void runToolsInvalidArgs() {
    std::printf("== container tools: invalid arguments and BitLocker refusals ==\n");
    const std::string path = tempPath("ve_smoke_tools_args.hc");
    const char* kPw = "args";
    const int64_t kMiB = 1ll << 20;
    CHECK(makeContainer(path, kPw, 8 * kMiB, "fat", 0));
    int32_t out[3] = {0, 0, 0};
    int64_t out4[4] = {0, 0, 0, 0};

    {
        const int fd = ve_open_file(path.c_str(), 1);
        CHECK_RC(ve_expand_veracrypt(fd, nullptr, 5, 0, 255, 255, nullptr, 0, 12 * kMiB, 0, 0, out), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 1);
        CHECK_RC(ve_expand_veracrypt(fd, (const uint8_t*)kPw, 4, 0, 255, 255, nullptr, 0, 12 * kMiB, 0, 0, nullptr),
                 VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 1);
        CHECK_RC(ve_expand_luks(fd, (const uint8_t*)kPw, 4, nullptr, 3, 12 * kMiB, 0, 0, out), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 0);
        CHECK_RC(ve_hidden_analyze(fd, (const uint8_t*)kPw, -1, 0, 255, 255, nullptr, 0, out4), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    // The repair / header-backup calls hand the descriptor to the engine in the same way (ABI 11): a call refused
    // before it reaches the engine still closes it.
    {
        const int fd = ve_open_file(path.c_str(), 0);
        CHECK_RC(ve_repair_diagnose_file(fd, -1, nullptr, nullptr), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 0);
        CHECK_RC(ve_header_export(fd, -1, nullptr), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 1);
        CHECK_RC(ve_repair_restore_veracrypt(fd, nullptr, 3, 0, 255, 255, -1, out), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 1);
        CHECK_RC(ve_header_restore(fd, 0, nullptr, -1, nullptr, 0, 0, 255, 255, -1, nullptr, 0, out), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
    }
    {
        // a keyfile that cannot be read: the call reports it through the result, and the container is closed too
        const int fd = ve_open_file(path.c_str(), 1);
        const int badKeyfile = ve_open_file(path.c_str(), 0);
        ve_close_fd(badKeyfile);  // an already-closed descriptor cannot be read
        const int32_t kfds[1] = {badKeyfile};
        const uint8_t payload[4] = {1, 2, 3, 4};
        out[0] = -1;
        CHECK_RC(ve_header_restore(fd, 0, payload, 4, nullptr, 0, 0, 255, 255, -1, kfds, 1, out), VE_OK);
        CHECK(out[0] != 0);
        CHECK(fdIsClosed(fd));
    }
    {
        const int fd = ve_open_file(path.c_str(), 1);
        ve_hidden_in_existing_params p;
        std::memset(&p, 0, sizeof(p));
        p.struct_size = sizeof(p);
        p.fd = fd;
        p.outer_password = (const uint8_t*)kPw;
        p.outer_password_len = 4;
        p.hidden_password = (const uint8_t*)"h";
        p.hidden_password_len = 1;
        p.hidden_file_system = "FAT";
        p.hidden_size_bytes = 0;  // no size
        int32_t outcome = -1;
        CHECK_RC(ve_hidden_create_in_existing(&p, &outcome), VE_ERR_INVALID_ARG);
        CHECK(fdIsClosed(fd));
        CHECK_RC(ve_hidden_create_in_existing(nullptr, &outcome), VE_ERR_INVALID_ARG);
        p.struct_size = 8;  // an old / foreign layout is refused without reading past it
        CHECK_RC(ve_hidden_create_in_existing(&p, &outcome), VE_ERR_INVALID_ARG);
    }

    // BitLocker: a file that is not a BitLocker volume is reported as such and left alone.
    {
        const ToolResult r = runTool(path, {}, [&](int fd, const int32_t*, int32_t, int32_t* o) {
            return ve_expand_bitlocker(fd, (const uint8_t*)kPw, 4, 12 * kMiB, 0, 1, o);
        });
        CHECK(r.rc == VE_OK && r.outcome == kOutNotBitLocker && r.fsStep == kFsNotRun);
        const ToolResult g = runTool(path, {}, [&](int fd, const int32_t*, int32_t, int32_t* o) {
            return ve_grow_bitlocker_fs(fd, (const uint8_t*)kPw, 4, o);
        });
        CHECK(g.rc == VE_OK && g.outcome == kOutNotBitLocker);
        CHECK(hostFileSize(path) == 8 * kMiB);
    }
    std::remove(path.c_str());
}

static void runVolumeTools() {
    runExpandVeraCrypt("ext4", 8, true, true);
    runExpandVeraCrypt("ntfs", 5, true, false);
    runExpandVeraCrypt("fat", 3, false, false);
    runExpandKeyfile();
    runExpandLuks(2, "ext4", 8);
    runExpandLuks(1, "ntfs", 5);
    runHiddenInExisting();
    runToolsInvalidArgs();
}

// ---------------------------------------------------------------------------------------------------------------------
// Composite containers (ABI 13): one VeraCrypt volume spread over several ordinary files.
// ---------------------------------------------------------------------------------------------------------------------

// Deterministic pseudo-random content (so every carrier's first 4 KiB differs, which is what orders them), with an
// optional magic number on the front so the profiler sees a PNG / JPEG.
static std::vector<uint8_t> carrierBytes(size_t size, uint64_t seed, const std::vector<uint8_t>& magic = {}) {
    std::vector<uint8_t> v(size);
    uint64_t s = seed * 0x9E3779B97F4A7C15ull + 1;
    for (size_t i = 0; i < size; ++i) {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        v[i] = static_cast<uint8_t>(s >> 24);
    }
    std::copy(magic.begin(), magic.end(), v.begin());
    return v;
}

struct ProfileItem {
    uint32_t fileIndex = 0, inputIndex = 0, tier = 0;
    uint64_t fileSize = 0, payloadOffset = 0, allocatable = 0;
    std::string format, path;
};
struct ProfileRec {
    int32_t rc = -1000;
    uint64_t total = 0;
    std::vector<ProfileItem> items;
    const ProfileItem* find(const std::string& path) const {
        for (const auto& i : items) if (i.path == path) return &i;
        return nullptr;
    }
};

static std::vector<const char*> cstrs(const std::vector<std::string>& v) {
    std::vector<const char*> out;
    for (const auto& s : v) out.push_back(s.c_str());
    return out;
}

static ProfileRec compositeProfile(const std::vector<std::string>& paths, int pct) {
    ProfileRec rec;
    ve_buffer out{};
    const auto ptrs = cstrs(paths);
    rec.rc = ve_composite_profile(ptrs.data(), static_cast<int32_t>(ptrs.size()), pct, &out);
    if (rec.rc != VE_OK || !out.data) { ve_buffer_free(&out); return rec; }
    size_t off = 0;
    auto u32 = [&]() { uint32_t v = 0; for (int i = 0; i < 4; ++i) v |= static_cast<uint32_t>(out.data[off + i]) << (8 * i); off += 4; return v; };
    auto u64 = [&]() { uint64_t v = 0; for (int i = 0; i < 8; ++i) v |= static_cast<uint64_t>(out.data[off + i]) << (8 * i); off += 8; return v; };
    auto str = [&]() { const uint32_t n = u32(); std::string s(reinterpret_cast<const char*>(out.data) + off, n); off += n; return s; };
    rec.total = u64();
    const uint32_t count = u32();
    for (uint32_t i = 0; i < count; ++i) {
        ProfileItem it;
        it.fileIndex = u32();
        it.inputIndex = u32();
        it.tier = u32();
        it.fileSize = u64();
        it.payloadOffset = u64();
        it.allocatable = u64();
        it.format = str();
        it.path = str();
        rec.items.push_back(it);
    }
    CHECK(off == out.len);  // the record is exactly what the header documents, nothing left over
    ve_buffer_free(&out);
    return rec;
}

struct CompositeOutcome {
    int32_t rc = -1000;
    std::string error;
    std::vector<int> keyfileFds;  // what the call was handed: every one must be closed on return
    bool keyfilesClosed() const {
        for (int fd : keyfileFds) if (!fdIsClosed(fd)) return false;
        return true;
    }
};

static std::string takeText(ve_buffer& b) {
    std::string s = b.data ? std::string(reinterpret_cast<const char*>(b.data), b.len) : std::string();
    ve_buffer_free(&b);
    return s;
}

static bool openKeyfiles(const std::vector<std::string>& keyfiles, std::vector<int>& fds) {
    for (const auto& k : keyfiles) {
        const int f = ve_open_file(k.c_str(), 0);
        if (f < 0) return false;
        fds.push_back(f);
    }
    return true;
}

static CompositeOutcome compositeCreate(const std::vector<std::string>& paths, int64_t requested, int pct,
                                        const char* password, const std::vector<std::string>& keyfiles = {},
                                        int volId = 2) {
    CompositeOutcome r;
    if (!openKeyfiles(keyfiles, r.keyfileFds)) return r;
    const auto ptrs = cstrs(paths);
    ve_composite_create_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.vol_id = volId;
    p.carrier_paths = ptrs.data();
    p.carrier_count = static_cast<int32_t>(ptrs.size());
    p.requested_bytes = requested;
    p.safety_margin_pct = pct;
    p.password = reinterpret_cast<const uint8_t*>(password);
    p.password_len = static_cast<int32_t>(std::strlen(password));
    p.file_system = "fat";
    p.cipher_id = p.hash_id = 255;
    p.keyfile_fds = r.keyfileFds.empty() ? nullptr : reinterpret_cast<const int32_t*>(r.keyfileFds.data());
    p.keyfile_count = static_cast<int32_t>(r.keyfileFds.size());
    p.quick_format = 1;
    ve_buffer err{};
    r.rc = ve_composite_create(&p, &err);
    r.error = takeText(err);
    return r;
}

static CompositeOutcome compositeUnlock(const std::vector<std::string>& paths, const char* password,
                                        const std::vector<std::string>& keyfiles = {}, int volId = 3,
                                        bool readOnly = false) {
    CompositeOutcome r;
    if (!openKeyfiles(keyfiles, r.keyfileFds)) return r;
    const auto ptrs = cstrs(paths);
    ve_composite_unlock_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.vol_id = volId;
    p.carrier_paths = ptrs.data();
    p.carrier_count = static_cast<int32_t>(ptrs.size());
    p.password = reinterpret_cast<const uint8_t*>(password);
    p.password_len = static_cast<int32_t>(std::strlen(password));
    p.cipher_id = p.hash_id = 255;
    p.keyfile_fds = r.keyfileFds.empty() ? nullptr : reinterpret_cast<const int32_t*>(r.keyfileFds.data());
    p.keyfile_count = static_cast<int32_t>(r.keyfileFds.size());
    p.read_only = readOnly ? 1 : 0;
    ve_buffer err{};
    r.rc = ve_composite_unlock(&p, &err);
    r.error = takeText(err);
    return r;
}

static bool slotIsEmpty(int vol) {
    uint64_t total = 0, freeB = 0;
    return ve_get_space_info(vol, &total, &freeB) != VE_OK;
}

static void runComposite() {
    std::printf("== composite containers ==\n");
    const char* kPw = "composite vault pass";
    const std::string a = tempPath("ve_smoke_comp_a.bin");
    const std::string b = tempPath("ve_smoke_comp_b.png");
    const std::string c = tempPath("ve_smoke_comp_c.jpg");
    const std::string plain = tempPath("ve_smoke_comp_plain.bin");
    const std::string zipLike = tempPath("ve_smoke_comp_x.zip");
    const std::vector<uint8_t> origA = carrierBytes(6u << 20, 1);
    const std::vector<uint8_t> origB = carrierBytes(8u << 20, 2, {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A});
    const std::vector<uint8_t> origC = carrierBytes(6u << 20, 3, {0xFF, 0xD8, 0xFF, 0xE0});
    const std::vector<uint8_t> origPlain = carrierBytes(1u << 20, 4);
    CHECK(writeHostFile(a, origA) && writeHostFile(b, origB) && writeHostFile(c, origC));
    CHECK(writeHostFile(plain, origPlain));
    CHECK(writeHostFile(zipLike, carrierBytes(64u << 10, 5, {'P', 'K', 3, 4})));

    // ---- profile: sizes the carriers, never writes ----
    const std::vector<std::string> order1 = {b, a, c};
    const ProfileRec prof = compositeProfile(order1, 50);
    CHECK_RC(prof.rc, VE_OK);
    CHECK(prof.items.size() == 3);
    {
        uint64_t sum = 0;
        std::vector<bool> seenInput(3, false);
        for (const auto& it : prof.items) {
            sum += it.allocatable;
            if (it.inputIndex < 3) seenInput[it.inputIndex] = true;
            CHECK(it.payloadOffset == it.fileSize);  // generic / PNG / JPEG: appended after the content
            CHECK(it.allocatable % 512 == 0);
        }
        CHECK(sum == prof.total);
        CHECK(seenInput[0] && seenInput[1] && seenInput[2]);  // inputIndex = the position in the caller's list
        CHECK(prof.total == (3u + 4u + 3u) * (1ull << 20));   // 50 % of 6 + 8 + 6 MiB
        const ProfileItem* ia = prof.find(a);
        const ProfileItem* ib = prof.find(b);
        const ProfileItem* ic = prof.find(c);
        CHECK(ia && ib && ic);
        if (ia && ib && ic) {
            CHECK(ia->format == "generic" && ia->tier == 2);
            CHECK(ib->format == "png" && ib->tier == 0);
            CHECK(ic->format == "jpeg" && ic->tier == 1);
            CHECK(ib->inputIndex == 0 && ia->inputIndex == 1 && ic->inputIndex == 2);
        }
    }
    CHECK(readHostFile(a) == origA && readHostFile(b) == origB && readHostFile(c) == origC);  // untouched
    {
        const ProfileRec zip = compositeProfile({zipLike}, 50);  // archives are refused as carriers
        CHECK_RC(zip.rc, VE_OK);
        CHECK(zip.items.size() == 1 && zip.items[0].format == "archive_unsupported" && zip.total == 0);
    }
    {
        ve_buffer out{};
        const char* one[] = {a.c_str()};
        const char* withEmpty[] = {a.c_str(), ""};
        CHECK_RC(ve_composite_profile(nullptr, 1, 10, &out), VE_ERR_INVALID_ARG);
        CHECK_RC(ve_composite_profile(one, 0, 10, &out), VE_ERR_INVALID_ARG);
        CHECK_RC(ve_composite_profile(withEmpty, 2, 10, &out), VE_ERR_INVALID_ARG);
        CHECK_RC(ve_composite_profile(one, 1, 10, nullptr), VE_ERR_INVALID_ARG);
    }

    // ---- create: refusals leave every carrier untouched ----
    {
        CompositeOutcome r = compositeCreate(order1, static_cast<int64_t>(prof.total) + 512, 50, kPw);
        CHECK_RC(r.rc, VE_ERR_FAILED);
        CHECK(r.error == "CARRIER_CAPACITY_CHANGED");
        r = compositeCreate(order1, 0, 50, std::string(129, 'x').c_str());
        CHECK_RC(r.rc, VE_ERR_FAILED);
        CHECK(r.error == "PASSWORD_TOO_LONG");
        CHECK(readHostFile(a) == origA && readHostFile(b) == origB && readHostFile(c) == origC);

        // too small to hold a volume, with a keyfile handed over: refused, nothing written, keyfile closed
        const std::string tiny1 = tempPath("ve_smoke_comp_tiny1.bin");
        const std::string tiny2 = tempPath("ve_smoke_comp_tiny2.bin");
        const std::string kf = tempPath("ve_smoke_comp_tiny.key");
        const std::vector<uint8_t> t1 = carrierBytes(100u << 10, 6), t2 = carrierBytes(100u << 10, 7);
        CHECK(writeHostFile(tiny1, t1) && writeHostFile(tiny2, t2) && writeHostFile(kf, carrierBytes(64, 8)));
        r = compositeCreate({tiny1, tiny2}, 0, 50, kPw, {kf});
        CHECK_RC(r.rc, VE_ERR_FAILED);
        CHECK(r.error == "SIZE_TOO_SMALL");
        CHECK(r.keyfilesClosed());
        CHECK(readHostFile(tiny1) == t1 && readHostFile(tiny2) == t2);
        std::remove(tiny1.c_str());
        std::remove(tiny2.c_str());
        std::remove(kf.c_str());
    }

    // ---- create: the real thing ----
    {
        const CompositeOutcome r = compositeCreate(order1, static_cast<int64_t>(prof.total), 50, kPw);
        CHECK_RC(r.rc, VE_OK);
        CHECK(r.error.empty());
        CHECK(slotIsEmpty(2));  // the formatting slot is left empty, not unlocked
        for (const auto& [path, orig] : {std::pair<std::string, const std::vector<uint8_t>*>{a, &origA},
                                         {b, &origB}, {c, &origC}}) {
            const std::vector<uint8_t> now = readHostFile(path);
            CHECK(now.size() > orig->size());  // grew by its share
            CHECK(std::equal(orig->begin(), orig->end(), now.begin()));  // the host content is exactly as it was
        }
    }

    // ---- unlock: failures ----
    CHECK(slotIsEmpty(3));
    {
        CompositeOutcome r = compositeUnlock(order1, "definitely wrong");
        CHECK_RC(r.rc, VE_ERR_FAILED);
        CHECK(r.error == "INCORRECT_PASSWORD_OR_INVALID_CONTAINER");
        CHECK(slotIsEmpty(3));

        // a file that never carried a share: nothing to find, so no key derivation either
        const std::string kf = tempPath("ve_smoke_comp_nf.key");
        CHECK(writeHostFile(kf, carrierBytes(64, 9)));
        r = compositeUnlock({plain}, kPw, {kf});
        CHECK_RC(r.rc, VE_ERR_FAILED);
        CHECK(r.error == "NO_EXTENTS_DETECTED");
        CHECK(r.keyfilesClosed());
        CHECK(readHostFile(plain) == origPlain);
        std::remove(kf.c_str());

        // a carrier missing from the set
        r = compositeUnlock({a, b}, kPw);
        std::printf("  missing carrier: rc=%d %s\n", r.rc, r.error.c_str());
        CHECK_RC(r.rc, VE_ERR_FAILED);
        CHECK(!r.error.empty());
        CHECK(slotIsEmpty(3));
    }

    // ---- unlock in a different order each time: files written in one session are there in the next ----
    const std::string hello = "hello from a composite vault";
    const std::vector<uint8_t> big = carrierBytes(1u << 20, 10);
    {
        const CompositeOutcome r = compositeUnlock({c, b, a}, kPw);
        CHECK_RC(r.rc, VE_OK);
        CHECK(ve_get_container_format(3) == 0);
        CHECK(ve_get_matched_cipher_id(3) >= 0 && ve_get_matched_hash_id(3) >= 0);
        uint64_t total = 0, freeB = 0;
        CHECK_RC(ve_get_space_info(3, &total, &freeB), VE_OK);
        CHECK(total > 0 && freeB > 0);
        CHECK_RC(ve_create_directory(3, "/docs"), VE_OK);
        CHECK_RC(ve_write_file_chunk(3, "/docs/hello.txt", 0, reinterpret_cast<const uint8_t*>(hello.data()), hello.size()), VE_OK);
        CHECK_RC(ve_write_file_chunk(3, "/docs/big.bin", 0, big.data(), big.size()), VE_OK);
        CHECK(readAll(3, "/docs/hello.txt") == hello);
        ve_lock(3);
        CHECK(slotIsEmpty(3));
    }
    {
        const CompositeOutcome r = compositeUnlock({a, c, b}, kPw);
        CHECK_RC(r.rc, VE_OK);
        CHECK(listContains(listDir(3, "/"), "docs"));
        CHECK(readAll(3, "/docs/hello.txt") == hello);
        CHECK(readAll(3, "/docs/big.bin") == std::string(big.begin(), big.end()));
        ve_lock(3);
    }

    // ---- read-only unlock: readable, not writable, carriers untouched ----
    {
        const std::vector<uint8_t> beforeA = readHostFile(a), beforeB = readHostFile(b), beforeC = readHostFile(c);
        const CompositeOutcome r = compositeUnlock({b, a, c}, kPw, {}, 3, /*readOnly=*/true);
        CHECK_RC(r.rc, VE_OK);
        CHECK(readAll(3, "/docs/hello.txt") == hello);
        CHECK_RC(ve_write_file_chunk(3, "/docs/nope.txt", 0, reinterpret_cast<const uint8_t*>("x"), 1), VE_ERR_READ_ONLY);
        ve_lock(3);
        CHECK(readHostFile(a) == beforeA && readHostFile(b) == beforeB && readHostFile(c) == beforeC);
    }

    // ---- keyfile-only credential: create and unlock, every keyfile descriptor closed ----
    {
        const std::string e = tempPath("ve_smoke_comp_e.bin");
        const std::string f = tempPath("ve_smoke_comp_f.bin");
        const std::string key = tempPath("ve_smoke_comp_k.key");
        CHECK(writeHostFile(e, carrierBytes(4u << 20, 11)) && writeHostFile(f, carrierBytes(4u << 20, 12)));
        CHECK(writeHostFile(key, carrierBytes(64, 13)));
        CompositeOutcome r = compositeCreate({e, f}, 0, 50, "", {key});
        CHECK_RC(r.rc, VE_OK);
        CHECK(r.keyfilesClosed());
        r = compositeUnlock({f, e}, "", {key});
        CHECK_RC(r.rc, VE_OK);
        CHECK(r.keyfilesClosed());
        CHECK_RC(ve_write_file_chunk(3, "k.txt", 0, reinterpret_cast<const uint8_t*>("k"), 1), VE_OK);
        ve_lock(3);
        std::remove(e.c_str());
        std::remove(f.c_str());
        std::remove(key.c_str());
    }

    // ---- invalid arguments: refused, every descriptor handed over is closed ----
    {
        const std::string key = tempPath("ve_smoke_comp_inv.key");
        CHECK(writeHostFile(key, carrierBytes(64, 14)));
        const char* one[] = {a.c_str()};
        const char* withEmpty[] = {a.c_str(), ""};
        auto handedKeyfile = [&](std::vector<int>& fds) { return openKeyfiles({key}, fds); };

        {
            std::vector<int> fds;
            CHECK(handedKeyfile(fds));
            ve_composite_unlock_params p;
            std::memset(&p, 0, sizeof(p));
            p.struct_size = sizeof(p);
            p.vol_id = 999;  // no such slot
            p.carrier_paths = one;
            p.carrier_count = 1;
            p.keyfile_fds = reinterpret_cast<const int32_t*>(fds.data());
            p.keyfile_count = 1;
            CHECK_RC(ve_composite_unlock(&p, nullptr), VE_ERR_INVALID_ARG);
            CHECK(fdIsClosed(fds[0]));
        }
        {
            std::vector<int> fds;
            CHECK(handedKeyfile(fds));
            ve_composite_unlock_params p;
            std::memset(&p, 0, sizeof(p));
            p.struct_size = sizeof(p);
            p.vol_id = 3;
            p.carrier_paths = withEmpty;  // an empty path
            p.carrier_count = 2;
            p.keyfile_fds = reinterpret_cast<const int32_t*>(fds.data());
            p.keyfile_count = 1;
            CHECK_RC(ve_composite_unlock(&p, nullptr), VE_ERR_INVALID_ARG);
            CHECK(fdIsClosed(fds[0]));
            p.struct_size = 4;  // a struct from an older / broken caller
            std::vector<int> fds2;
            CHECK(handedKeyfile(fds2));
            p.keyfile_fds = reinterpret_cast<const int32_t*>(fds2.data());
            CHECK_RC(ve_composite_unlock(&p, nullptr), VE_ERR_INVALID_ARG);
            CHECK(fdIsClosed(fds2[0]));
        }
        {
            std::vector<int> fds;
            CHECK(handedKeyfile(fds));
            ve_composite_create_params p;
            std::memset(&p, 0, sizeof(p));
            p.struct_size = sizeof(p);
            p.vol_id = 2;
            p.carrier_paths = one;
            p.carrier_count = 1;
            p.file_system = nullptr;  // required
            p.keyfile_fds = reinterpret_cast<const int32_t*>(fds.data());
            p.keyfile_count = 1;
            CHECK_RC(ve_composite_create(&p, nullptr), VE_ERR_INVALID_ARG);
            CHECK(fdIsClosed(fds[0]));
        }
        {
            // a password with a NUL in it would be cut short by the C string the engine takes
            const uint8_t nulPw[4] = {'a', 0, 'b', 'c'};
            ve_composite_create_params p;
            std::memset(&p, 0, sizeof(p));
            p.struct_size = sizeof(p);
            p.vol_id = 2;
            p.carrier_paths = one;
            p.carrier_count = 1;
            p.file_system = "fat";
            p.password = nulPw;
            p.password_len = 4;
            CHECK_RC(ve_composite_create(&p, nullptr), VE_ERR_INVALID_ARG);
            p.password = reinterpret_cast<const uint8_t*>("");  // no password and no keyfile: nothing to authenticate with
            p.password_len = 0;
            CHECK_RC(ve_composite_create(&p, nullptr), VE_ERR_INVALID_ARG);
            CHECK_RC(ve_composite_create(nullptr, nullptr), VE_ERR_INVALID_ARG);
            CHECK_RC(ve_composite_unlock(nullptr, nullptr), VE_ERR_INVALID_ARG);
        }
        CHECK(readHostFile(a).size() > origA.size());  // (a carries its share from the create above; nothing here changed it)
        std::remove(key.c_str());
    }

    for (const auto& path : {a, b, c, plain, zipLike}) std::remove(path.c_str());
}

// ---- raw block devices (ve_unlock_device) -------------------------------------------------------------
// A "device" may be a regular file (a raw disk image), which is how this runs without root or a loop device: the
// engine's device path is the same one a /dev/sdX or \\.\PhysicalDriveN takes (sector reads/writes through the
// attached-device hooks, partition scan, LUKS/VeraCrypt probing); only the OS open differs.

static bool makeContainerFile(const std::string& path, int64_t size, int format, const char* fs, const char* password) {
    std::remove(path.c_str());
    const int fd = ve_create_file(path.c_str());
    if (fd < 0) return false;
    ve_create_params cp;
    std::memset(&cp, 0, sizeof(cp));
    cp.struct_size = sizeof(cp);
    cp.fd = fd;
    cp.password = reinterpret_cast<const uint8_t*>(password);
    cp.password_len = static_cast<int32_t>(std::strlen(password));
    cp.size_bytes = size;
    cp.file_system = fs;
    cp.container_format = format;
    cp.cipher_id = cp.hash_id = format == 0 ? 255 : 0;  // LUKS creation takes concrete ids (no "auto")
    cp.quick_format = 1;
    return ve_create_container(&cp) == VE_OK;
}

static int32_t unlockDevice(const std::string& path, const char* password, int volId, int readOnly = 0,
                            int32_t* osError = nullptr) {
    ve_unlock_device_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.device_path = path.c_str();
    p.vol_id = volId;
    p.password = reinterpret_cast<const uint8_t*>(password);
    p.password_len = static_cast<int32_t>(std::strlen(password));
    p.cipher_id = 255;
    p.hash_id = 255;
    p.read_only = readOnly;
    p.partition_offset_hint = -1;
    p.os_error_out = osError;
    return ve_unlock_device(&p);
}

static std::vector<unsigned char> slurp(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::vector<unsigned char>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

static bool spit(const std::string& path, const std::vector<unsigned char>& bytes) {
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    f.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return static_cast<bool>(f);
}

// Writes a file through the engine, reads it back, and reports whether it matched.
static bool roundTrip(int vol, const char* name, const std::string& content) {
    if (ve_write_file_chunk(vol, name, 0, reinterpret_cast<const uint8_t*>(content.data()), content.size()) != VE_OK) return false;
    return readAll(vol, name) == content;
}

static void runRawDevices() {
    std::printf("== raw block devices (ve_unlock_device) ==\n");
    const char* kPw = "correct horse battery staple";
    const std::string kMsg = "written through the raw device layer";

    // The device list is JSON, and does not crash where the platform has nothing to list.
    {
        ve_buffer buf{};
        CHECK_RC(ve_list_block_devices(&buf), VE_OK);
        CHECK(buf.data != nullptr && buf.len >= 2 && buf.data[0] == '[' && buf.data[buf.len - 1] == ']');
        ve_buffer_free(&buf);
    }

    // 1. A whole device that is one VeraCrypt volume (VeraCrypt "encrypt the whole drive": header at sector 0).
    {
        const std::string img = tempPath("ve_dev_vc.img");
        CHECK(makeContainerFile(img, 8ll << 20, 0, "fat", kPw));
        CHECK_RC(unlockDevice(img, "definitely wrong", 0), VE_ERR_FAILED);
        CHECK_RC(unlockDevice(img, kPw, 0), VE_OK);
        CHECK(ve_get_container_format(0) == 0);
        CHECK(roundTrip(0, "/hello.txt", kMsg));
        // The same device cannot be opened into a second slot while the first holds it.
        CHECK_RC(unlockDevice(img, kPw, 1), VE_ERR_DEVICE_OPEN);
        ve_lock(0);
        // Writes went to the image: the plain file unlock sees them.
        CHECK_RC(unlock(img, kPw, 0), VE_OK);
        CHECK(readAll(0, "/hello.txt") == kMsg);
        ve_lock(0);
        // Read-only: opens, reads, refuses writes.
        CHECK_RC(unlockDevice(img, kPw, 0, /*readOnly=*/1), VE_OK);
        CHECK(readAll(0, "/hello.txt") == kMsg);
        CHECK(ve_write_file_chunk(0, "/nope.txt", 0, reinterpret_cast<const uint8_t*>("x"), 1) != VE_OK);
        ve_lock(0);
        std::remove(img.c_str());
    }

    // 2. A raw LUKS2 volume with no partition table (a partition node such as /dev/sdb1 looks exactly like this).
    {
        const std::string img = tempPath("ve_dev_luks.img");
        CHECK(makeContainerFile(img, 16ll << 20, 2, "ext4", kPw));
        CHECK_RC(unlockDevice(img, "definitely wrong", 0), VE_ERR_FAILED);
        CHECK_RC(unlockDevice(img, kPw, 0), VE_OK);
        CHECK(ve_get_container_format(0) == 2);
        CHECK(roundTrip(0, "/luks.txt", kMsg));
        ve_lock(0);
        CHECK_RC(unlock(img, kPw, 0), VE_OK);
        CHECK(readAll(0, "/luks.txt") == kMsg);
        ve_lock(0);
        std::remove(img.c_str());
    }

    // 3. A disk with an MBR partition table and the VeraCrypt volume in partition 1 (1 MiB in).
    {
        const std::string inner = tempPath("ve_dev_part_inner.hc");
        const std::string disk = tempPath("ve_dev_part.img");
        CHECK(makeContainerFile(inner, 8ll << 20, 0, "fat", kPw));
        std::vector<unsigned char> volume = slurp(inner);
        CHECK(volume.size() == (8u << 20));
        const size_t kStart = 1u << 20;  // sector 2048
        std::vector<unsigned char> image(kStart + volume.size() + (1u << 20), 0);
        std::copy(volume.begin(), volume.end(), image.begin() + kStart);
        unsigned char* e = image.data() + 446;
        e[4] = 0x0C;
        const uint32_t startLba = static_cast<uint32_t>(kStart / 512), count = static_cast<uint32_t>(volume.size() / 512);
        for (int i = 0; i < 4; ++i) { e[8 + i] = (startLba >> (8 * i)) & 0xFF; e[12 + i] = (count >> (8 * i)) & 0xFF; }
        image[510] = 0x55;
        image[511] = 0xAA;
        CHECK(spit(disk, image));

        CHECK_RC(unlockDevice(disk, "definitely wrong", 0), VE_ERR_FAILED);
        CHECK_RC(unlockDevice(disk, kPw, 0), VE_OK);
        CHECK(roundTrip(0, "/part.txt", kMsg));
        ve_lock(0);
        // The change landed inside the partition, at its offset, and nowhere else.
        const std::vector<unsigned char> after = slurp(disk);
        CHECK(after.size() == image.size());
        CHECK(std::equal(after.begin(), after.begin() + kStart, image.begin()));
        CHECK(std::equal(after.begin() + kStart + volume.size(), after.end(), image.begin() + kStart + volume.size()));
        std::vector<unsigned char> extracted(after.begin() + kStart, after.begin() + kStart + volume.size());
        CHECK(spit(inner, extracted));
        CHECK_RC(unlock(inner, kPw, 0), VE_OK);
        CHECK(readAll(0, "/part.txt") == kMsg);
        ve_lock(0);
        std::remove(inner.c_str());
        std::remove(disk.c_str());
    }

    // 4. Open errors are told apart from a wrong password.
    {
        int32_t os = 0;
        CHECK_RC(unlockDevice(tempPath("ve_dev_does_not_exist.img"), kPw, 0, 0, &os), VE_ERR_DEVICE_NOT_FOUND);
        CHECK(os != 0);
        CHECK_RC(unlockDevice(tempPath(""), kPw, 0), VE_ERR_DEVICE_OPEN);  // a directory is not a disk
        CHECK_RC(unlockDevice("", kPw, 0), VE_ERR_INVALID_ARG);
        CHECK_RC(unlockDevice(tempPath("x.img"), kPw, 9999), VE_ERR_INVALID_ARG);
    }
}

int main(int argc, char** argv) {
    std::printf("ve abi %d, %d volume slots\n", ve_abi_version(), ve_max_volumes());
    CHECK(ve_abi_version() == VE_ABI_VERSION);

    if (argc == 2 && std::strcmp(argv[1], "crypto") == 0) {  // fast path: primitives + digests only
        runCrypto();
        runHashes();
        runSingleFile();
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    if (argc == 2 && std::strcmp(argv[1], "fv") == 0) {  // fast path: folder vaults only
        runFolderVaults();
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    if (argc == 2 && std::strcmp(argv[1], "tools") == 0) {  // fast path: expand / grow / hidden-in-existing only
        runVolumeTools();
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    if (argc == 2 && std::strcmp(argv[1], "composite") == 0) {  // fast path: composite containers only
        runComposite();
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    if (argc == 2 && std::strcmp(argv[1], "device") == 0) {  // fast path: raw block devices only
        runRawDevices();
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    if (argc == 2 && std::strcmp(argv[1], "chpw") == 0) {  // fast path: password change only
        runChangePassword(0, "fat", 8ll << 20);
        runChangePassword(1, "ext4", 16ll << 20);
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    // `--fs-only fat ext4 ...`: just the per-filesystem sections (the full run takes a few minutes).
    const bool fsOnly = argc >= 3 && std::strcmp(argv[1], "--fs-only") == 0;

    std::vector<std::string> filesystems;
    for (int i = fsOnly ? 2 : 1; i < argc; ++i) filesystems.push_back(argv[i]);
    if (filesystems.empty()) filesystems.push_back("fat");

    for (const auto& fs : filesystems) {
        // ext/ntfs need more room than a tiny FAT volume.
        const int64_t size = (fs == "fat" || fs == "exfat") ? 8ll << 20 : 32ll << 20;
        runFilesystem(fs.c_str(), size);
    }
    if (fsOnly) {
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    runHidden();
    runVolumeTools();
    runComposite();
    runChangePassword(0, "fat", 8ll << 20);
    runChangePassword(1, "ext4", 16ll << 20);
    runRawDevices();
    runFolderVaults();
    runCrypto();
    runHashes();
    runSingleFile();

    std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
