// Crypto primitives for the desktop C ABI (see "crypto primitives" in ve_engine.h).
//
// Each function here is the JNI-free twin of a NativeEngine.*Native function in
// jni/crypto_bridge.cpp, built on the same helpers (BoringSSL EVP/HMAC, the bundled scrypt and
// Argon2, xchacha20poly1305), so a hash or ciphertext produced on desktop is byte-identical to one
// produced on Android -- which matters for anything that leaves the device (settings backups,
// authenticator exports). Where the Android side does the work in Kotlin (HMAC, AES-CBC) the same
// standard algorithm is used.
#include "ve_engine.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <mutex>
#include <unordered_set>
#include <vector>

#include <mbedtls/platform_util.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>

#include "crypto/cipher_shim.h"
#include "crypto/scrypt.h"
#include "crypto/xchacha20poly1305.h"

namespace {

const EVP_MD* mdFor(int32_t hash) {
    switch (hash) {
        case VE_HASH_MD5: return EVP_md5();   // digests only (checksum tool, cache keys); not valid for ve_pbkdf2/ve_hmac callers' intent
        case VE_HASH_SHA1: return EVP_sha1();
        case VE_HASH_SHA256: return EVP_sha256();
        case VE_HASH_SHA512: return EVP_sha512();
        default: return nullptr;
    }
}

// Hands `bytes` to the caller in a malloc'd ve_buffer (freed + wiped with ve_buffer_free).
bool emit(const uint8_t* bytes, size_t len, ve_buffer* out) {
    out->data = nullptr;
    out->len = 0;
    if (len == 0) return true;
    auto* mem = static_cast<uint8_t*>(std::malloc(len));
    if (!mem) return false;
    std::memcpy(mem, bytes, len);
    out->data = mem;
    out->len = len;
    return true;
}

constexpr size_t kTag = 16;

}  // namespace

#define VE_TRY try {
#define VE_CATCH(retval) } catch (...) { return (retval); }

extern "C" VE_API int32_t ve_pbkdf2(int32_t hash, const uint8_t* password, size_t password_len,
                                    const uint8_t* salt, size_t salt_len, uint32_t iterations,
                                    uint8_t* out, size_t out_len) {
    const EVP_MD* md = hash == VE_HASH_MD5 ? nullptr : mdFor(hash);  // MD5 is digest-only
    if (!md || !password || !salt || salt_len == 0 || iterations == 0 || !out || out_len == 0) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    const int ok = PKCS5_PBKDF2_HMAC(reinterpret_cast<const char*>(password), password_len, salt, salt_len,
                                     iterations, md, out_len, out);
    if (ok != 1) {
        mbedtls_platform_zeroize(out, out_len);
        return VE_ERR_FAILED;
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_hmac(int32_t hash, const uint8_t* key, size_t key_len,
                                  const uint8_t* data, size_t data_len,
                                  uint8_t* out, size_t out_cap, size_t* out_len) {
    const EVP_MD* md = hash == VE_HASH_MD5 ? nullptr : mdFor(hash);  // MD5 is digest-only
    if (!md || !key || key_len == 0 || (data_len > 0 && !data) || !out || !out_len) return VE_ERR_INVALID_ARG;
    VE_TRY
    const size_t digest = EVP_MD_size(md);
    if (out_cap < digest) return VE_ERR_INVALID_ARG;
    unsigned int written = 0;
    static const uint8_t kEmpty[1] = {0};
    if (!HMAC(md, key, key_len, data ? data : kEmpty, data_len, out, &written)) return VE_ERR_FAILED;
    *out_len = written;
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_scrypt(const uint8_t* password, size_t password_len,
                                    const uint8_t* salt, size_t salt_len,
                                    uint32_t n, uint32_t r, uint32_t p, uint8_t* out, size_t out_len) {
    if (!password || !salt || !out || out_len == 0) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (!scrypt_crypto(password, password_len, salt, salt_len, n, r, p, out, out_len)) {
        mbedtls_platform_zeroize(out, out_len);
        return VE_ERR_FAILED;
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_argon2id(const uint8_t* password, size_t password_len,
                                      const uint8_t* salt, size_t salt_len,
                                      uint32_t memory_kib, uint32_t iterations, uint32_t parallelism,
                                      uint8_t* out, size_t out_len) {
    if (!password || !salt || !out || out_len == 0) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (!argon2idDeriveKey(password, password_len, salt, salt_len, memory_kib, iterations, parallelism,
                           out, out_len, nullptr)) {
        mbedtls_platform_zeroize(out, out_len);
        return VE_ERR_FAILED;
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── AES-GCM ──────────────────────────────────────────────────────────────

namespace {

const EVP_CIPHER* gcmFor(size_t keyLen) {
    if (keyLen == 16) return EVP_aes_128_gcm();
    if (keyLen == 32) return EVP_aes_256_gcm();
    return nullptr;
}

struct CipherCtx {
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    ~CipherCtx() { if (ctx) EVP_CIPHER_CTX_free(ctx); }
};

}  // namespace

extern "C" VE_API int32_t ve_aes_gcm_seal(const uint8_t* key, size_t key_len, const uint8_t* iv, size_t iv_len,
                                          const uint8_t* aad, size_t aad_len,
                                          const uint8_t* plaintext, size_t plaintext_len, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    const EVP_CIPHER* cipher = gcmFor(key_len);
    if (!cipher || !key || !iv || iv_len == 0 || (plaintext_len > 0 && !plaintext) || (aad_len > 0 && !aad)) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    CipherCtx c;
    if (!c.ctx) return VE_ERR_FAILED;
    std::vector<uint8_t> buf(plaintext_len + kTag);
    int len = 0;
    size_t total = 0;
    bool ok = EVP_EncryptInit_ex(c.ctx, cipher, nullptr, nullptr, nullptr) == 1 &&
              EVP_CIPHER_CTX_ctrl(c.ctx, EVP_CTRL_AEAD_SET_IVLEN, static_cast<int>(iv_len), nullptr) == 1 &&
              EVP_EncryptInit_ex(c.ctx, nullptr, nullptr, key, iv) == 1;
    if (ok && aad_len > 0) ok = EVP_EncryptUpdate(c.ctx, nullptr, &len, aad, static_cast<int>(aad_len)) == 1;
    if (ok && plaintext_len > 0) {
        ok = EVP_EncryptUpdate(c.ctx, buf.data(), &len, plaintext, static_cast<int>(plaintext_len)) == 1;
        total = static_cast<size_t>(len);
    }
    if (ok) {
        ok = EVP_EncryptFinal_ex(c.ctx, buf.data() + total, &len) == 1;
        total += static_cast<size_t>(len);
    }
    if (ok) {
        ok = EVP_CIPHER_CTX_ctrl(c.ctx, EVP_CTRL_AEAD_GET_TAG, kTag, buf.data() + total) == 1;
        total += kTag;
    }
    const bool emitted = ok && emit(buf.data(), total, out);
    mbedtls_platform_zeroize(buf.data(), buf.size());
    return emitted ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_aes_gcm_open(const uint8_t* key, size_t key_len, const uint8_t* iv, size_t iv_len,
                                          const uint8_t* aad, size_t aad_len,
                                          const uint8_t* ciphertext_and_tag, size_t len, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    const EVP_CIPHER* cipher = gcmFor(key_len);
    if (!cipher || !key || !iv || iv_len == 0 || !ciphertext_and_tag || len < kTag || (aad_len > 0 && !aad)) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    CipherCtx c;
    if (!c.ctx) return VE_ERR_FAILED;
    const size_t body = len - kTag;
    std::vector<uint8_t> buf(body + 16);  // +block slack for EVP_DecryptFinal
    int outl = 0;
    size_t total = 0;
    bool ok = EVP_DecryptInit_ex(c.ctx, cipher, nullptr, nullptr, nullptr) == 1 &&
              EVP_CIPHER_CTX_ctrl(c.ctx, EVP_CTRL_AEAD_SET_IVLEN, static_cast<int>(iv_len), nullptr) == 1 &&
              EVP_DecryptInit_ex(c.ctx, nullptr, nullptr, key, iv) == 1;
    if (ok && aad_len > 0) ok = EVP_DecryptUpdate(c.ctx, nullptr, &outl, aad, static_cast<int>(aad_len)) == 1;
    if (ok && body > 0) {
        ok = EVP_DecryptUpdate(c.ctx, buf.data(), &outl, ciphertext_and_tag, static_cast<int>(body)) == 1;
        total = static_cast<size_t>(outl);
    }
    if (ok) {
        ok = EVP_CIPHER_CTX_ctrl(c.ctx, EVP_CTRL_AEAD_SET_TAG, kTag,
                                 const_cast<uint8_t*>(ciphertext_and_tag + body)) == 1;
    }
    if (ok) {
        ok = EVP_DecryptFinal_ex(c.ctx, buf.data() + total, &outl) == 1;  // authenticates
        total += static_cast<size_t>(outl);
    }
    const bool emitted = ok && emit(buf.data(), total, out);
    mbedtls_platform_zeroize(buf.data(), buf.size());
    return emitted ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_aes_cbc_decrypt(const uint8_t* key, size_t key_len, const uint8_t* iv, size_t iv_len,
                                             const uint8_t* ciphertext, size_t len, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    const EVP_CIPHER* cipher = key_len == 16 ? EVP_aes_128_cbc()
                              : key_len == 24 ? EVP_aes_192_cbc()
                              : key_len == 32 ? EVP_aes_256_cbc() : nullptr;
    if (!cipher || !key || !iv || iv_len != 16 || !ciphertext || len == 0 || len % 16 != 0) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    CipherCtx c;
    if (!c.ctx) return VE_ERR_FAILED;
    std::vector<uint8_t> buf(len + 16);
    int outl = 0;
    size_t total = 0;
    bool ok = EVP_DecryptInit_ex(c.ctx, cipher, nullptr, key, iv) == 1 &&  // PKCS#7 padding is the default
              EVP_DecryptUpdate(c.ctx, buf.data(), &outl, ciphertext, static_cast<int>(len)) == 1;
    if (ok) {
        total = static_cast<size_t>(outl);
        ok = EVP_DecryptFinal_ex(c.ctx, buf.data() + total, &outl) == 1;  // checks + strips the padding
        total += static_cast<size_t>(outl);
    }
    const bool emitted = ok && emit(buf.data(), total, out);
    mbedtls_platform_zeroize(buf.data(), buf.size());
    return emitted ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_xchacha20poly1305_open(const uint8_t* key, size_t key_len,
                                                    const uint8_t* nonce, size_t nonce_len,
                                                    const uint8_t* aad, size_t aad_len,
                                                    const uint8_t* ciphertext_and_tag, size_t len, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!key || key_len != 32 || !nonce || nonce_len != 24 || !ciphertext_and_tag || len < kTag ||
        (aad_len > 0 && !aad)) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    const size_t body = len - kTag;
    std::vector<uint8_t> buf(body ? body : 1);
    const bool ok = xchacha20Poly1305Open(key, nonce, aad, aad_len, ciphertext_and_tag, body,
                                          ciphertext_and_tag + body, buf.data());
    const bool emitted = ok && emit(buf.data(), body, out);
    mbedtls_platform_zeroize(buf.data(), buf.size());
    return emitted ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}


// ── streaming digests ────────────────────────────────────────────────────

namespace {

constexpr int kMaxAlg = 5;  // ids 1..4 used (index = id)

struct HashSession {
    EVP_MD_CTX* ctx[kMaxAlg] = {};
    bool finished[kMaxAlg] = {};
    ~HashSession() {
        for (auto* c : ctx) if (c) EVP_MD_CTX_free(c);
    }
};

std::mutex g_hashMu;
std::unordered_set<HashSession*> g_hashSessions;  // live handles only: a stale/forged handle is rejected

HashSession* lookup(int64_t handle) {
    auto* s = reinterpret_cast<HashSession*>(static_cast<intptr_t>(handle));
    return g_hashSessions.count(s) ? s : nullptr;
}

}  // namespace

extern "C" VE_API int64_t ve_hash_begin(uint32_t mask) {
    VE_TRY
    auto session = std::make_unique<HashSession>();
    bool any = false;
    for (int id = 1; id < kMaxAlg; ++id) {
        if (!(mask & (1u << id))) continue;
        const EVP_MD* md = mdFor(id);
        session->ctx[id] = EVP_MD_CTX_new();
        if (!md || !session->ctx[id] || EVP_DigestInit_ex(session->ctx[id], md, nullptr) != 1) return 0;
        any = true;
    }
    if (!any) return 0;
    HashSession* raw = session.release();
    std::lock_guard<std::mutex> lock(g_hashMu);
    g_hashSessions.insert(raw);
    return static_cast<int64_t>(reinterpret_cast<intptr_t>(raw));
    VE_CATCH(0)
}

extern "C" VE_API int32_t ve_hash_update(int64_t handle, const uint8_t* data, size_t len) {
    if (len > 0 && !data) return VE_ERR_INVALID_ARG;
    VE_TRY
    // Updates on one session are serialized by the caller (one reader feeds it); only the registry
    // is locked, so a session being fed does not block others.
    HashSession* s;
    {
        std::lock_guard<std::mutex> lock(g_hashMu);
        s = lookup(handle);
    }
    if (!s) return VE_ERR_INVALID_ARG;
    for (int id = 1; id < kMaxAlg; ++id) {
        if (s->ctx[id] && !s->finished[id] && len > 0 && EVP_DigestUpdate(s->ctx[id], data, len) != 1) return VE_ERR_FAILED;
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_hash_finish(int64_t handle, int32_t algorithm, uint8_t* out, size_t cap, size_t* out_len) {
    if (algorithm < 1 || algorithm >= kMaxAlg || !out || !out_len) return VE_ERR_INVALID_ARG;
    VE_TRY
    HashSession* s;
    {
        std::lock_guard<std::mutex> lock(g_hashMu);
        s = lookup(handle);
    }
    if (!s || !s->ctx[algorithm] || s->finished[algorithm]) return VE_ERR_INVALID_ARG;
    unsigned int n = 0;
    uint8_t md[EVP_MAX_MD_SIZE];
    if (EVP_DigestFinal_ex(s->ctx[algorithm], md, &n) != 1) return VE_ERR_FAILED;
    s->finished[algorithm] = true;
    if (cap < n) return VE_ERR_INVALID_ARG;
    std::memcpy(out, md, n);
    *out_len = n;
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API void ve_hash_free(int64_t handle) {
    HashSession* s;
    {
        std::lock_guard<std::mutex> lock(g_hashMu);
        s = lookup(handle);
        if (s) g_hashSessions.erase(s);
    }
    delete s;
}

extern "C" VE_API int32_t ve_hash_bytes(int32_t algorithm, const uint8_t* data, size_t len,
                                        uint8_t* out, size_t cap, size_t* out_len) {
    const EVP_MD* md = (algorithm >= 1 && algorithm < kMaxAlg) ? mdFor(algorithm) : nullptr;
    if (!md || (len > 0 && !data) || !out || !out_len) return VE_ERR_INVALID_ARG;
    VE_TRY
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned int n = 0;
    static const uint8_t kEmpty[1] = {0};
    if (EVP_Digest(data ? data : kEmpty, len, digest, &n, md, nullptr) != 1) return VE_ERR_FAILED;
    if (cap < n) return VE_ERR_INVALID_ARG;
    std::memcpy(out, digest, n);
    *out_len = n;
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}
