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

#include "ve_crypto_vectors.inc"
#include "ve_engine.h"

#include <algorithm>
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
            CHECK(ve_create_symlink(kFvVol, "/docs/link.txt", "renamed.txt") != VE_OK);  // not supported by these formats
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
    runChangePassword(0, "fat", 8ll << 20);
    runChangePassword(1, "ext4", 16ll << 20);
    runFolderVaults();
    runCrypto();
    runHashes();
    runSingleFile();

    std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
