#include "fv_crypto.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <future>
#include <thread>

#include "mbedtls/aes.h"
#include "mbedtls/gcm.h"
#include "mbedtls/md.h"
#include "mbedtls/platform_util.h"

#include "crypto/scrypt.h"
#include "crypto/xchacha20poly1305.h"

#if defined(FV_AEAD_EVP)
#include <openssl/aead.h>   // BoringSSL
#include <openssl/evp.h>
#endif

#if defined(FV_USE_USERENTROPY)
#include "crypto/user_entropy.h"
#endif

#if defined(__linux__) || defined(__ANDROID__)
#include <fcntl.h>
#include <sys/random.h>
#include <unistd.h>
#endif
#if defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>
#endif

namespace fv::crypto {

// ------------------------------------------------------------ randomness --

// OS entropy source. The formats request nonces for a whole batch of chunks
// at once, so this is one call per batch, never one per chunk.
static bool osRandom(uint8_t* out, size_t n) {
#if defined(__ANDROID__)
    arc4random_buf(out, n);
    return true;
#elif defined(__linux__)
    size_t off = 0;
    while (off < n) {
        ssize_t r = getrandom(out + off, n - off, 0);
        if (r < 0) {
            if (errno == EINTR) continue;
            int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
            if (fd < 0) return false;
            while (off < n) {
                ssize_t k = read(fd, out + off, n - off);
                if (k <= 0) { close(fd); return false; }
                off += (size_t)k;
            }
            close(fd);
            return true;
        }
        off += (size_t)r;
    }
    return true;
#elif defined(_WIN32)
    return BCryptGenRandom(nullptr, out, (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
#else
    arc4random_buf(out, n);
    return true;
#endif
}

void randomFast(uint8_t* out, size_t n) {
    if (n == 0) return;
    if (!osRandom(out, n)) throw Error(Err::Io, "OS random source unavailable");
}

void randomKey(uint8_t* out, size_t n) {
    if (n == 0) return;
#if defined(FV_USE_USERENTROPY)
    if (!userentropy::fillRandom(out, n)) throw Error(Err::Io, "OS random source unavailable");
#else
    randomFast(out, n);
#endif
}

Bytes randomKeyBytes(size_t n) {
    Bytes b(n);
    randomKey(b.data(), n);
    return b;
}

// ------------------------------------------------------------- hash / mac --

static mbedtls_md_type_t mdType(Md md) {
    switch (md) {
        case Md::Sha1: return MBEDTLS_MD_SHA1;
        case Md::Sha256: return MBEDTLS_MD_SHA256;
        case Md::Sha384: return MBEDTLS_MD_SHA384;
        case Md::Sha512: return MBEDTLS_MD_SHA512;
    }
    return MBEDTLS_MD_NONE;
}

Bytes hash(Md md, const uint8_t* data, size_t n) {
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(mdType(md));
    Bytes out(mbedtls_md_get_size(info));
    if (mbedtls_md(info, data, n, out.data()) != 0) throw Error(Err::Io, "hash failed");
    return out;
}

Bytes hmac(Md md, const uint8_t* key, size_t keyLen, const uint8_t* data, size_t n) {
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(mdType(md));
    Bytes out(mbedtls_md_get_size(info));
    if (mbedtls_md_hmac(info, key, keyLen, data, n, out.data()) != 0) throw Error(Err::Io, "hmac failed");
    return out;
}

struct HmacSha256::Impl {
    mbedtls_md_context_t ctx;
    Impl() { mbedtls_md_init(&ctx); }
    ~Impl() { mbedtls_md_free(&ctx); }
};

HmacSha256::HmacSha256(const uint8_t* key, size_t keyLen) : impl_(new Impl) {
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (mbedtls_md_setup(&impl_->ctx, info, 1) != 0 ||
        mbedtls_md_hmac_starts(&impl_->ctx, key, keyLen) != 0)
        throw Error(Err::Io, "hmac init failed");
}
HmacSha256::~HmacSha256() = default;
void HmacSha256::update(const uint8_t* d, size_t n) {
    if (n && mbedtls_md_hmac_update(&impl_->ctx, d, n) != 0) throw Error(Err::Io, "hmac update failed");
}
void HmacSha256::finish(uint8_t out[32]) {
    if (mbedtls_md_hmac_finish(&impl_->ctx, out) != 0) throw Error(Err::Io, "hmac finish failed");
}

Secret hkdfSha256(const uint8_t* secret, size_t secretLen, const std::string& info, size_t outLen) {
    constexpr size_t H = 32;
    if (outLen == 0 || outLen > 255 * H) throw Error(Err::Unsupported, "HKDF output length out of range");
    uint8_t zeroSalt[H] = {0};
    Bytes prk = hmac(Md::Sha256, zeroSalt, H, secret, secretLen);
    size_t blocks = (outLen + H - 1) / H;
    Secret okm(blocks * H);
    Bytes t;
    for (size_t i = 1; i <= blocks; i++) {
        Bytes msg;
        msg.insert(msg.end(), t.begin(), t.end());
        msg.insert(msg.end(), info.begin(), info.end());
        msg.push_back((uint8_t)i);
        t = hmac(Md::Sha256, prk.data(), prk.size(), msg.data(), msg.size());
        std::memcpy(okm.data() + (i - 1) * H, t.data(), H);
        secureZero(msg.data(), msg.size());
    }
    secureZero(prk.data(), prk.size());
    secureZero(t.data(), t.size());
    Secret out(okm.data(), outLen);
    return out;
}

Secret scrypt(const uint8_t* pass, size_t passLen, const uint8_t* salt, size_t saltLen,
              uint32_t N, uint32_t r, uint32_t p, size_t outLen) {
    Secret out(outLen);
    if (!scrypt_crypto(pass, passLen, salt, saltLen, N, r, p, out.data(), outLen))
        throw Error(Err::Unsupported, "scrypt parameters are invalid or exceed the supported limits");
    return out;
}

// -------------------------------------------------------- key wrap / CTR --

static const uint8_t kRfc3394Iv[8] = {0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6};

struct AesEcb {
    mbedtls_aes_context ctx;
    AesEcb(const uint8_t* key, size_t keyLen, bool enc) {
        mbedtls_aes_init(&ctx);
        int rc = enc ? mbedtls_aes_setkey_enc(&ctx, key, keyLen * 8) : mbedtls_aes_setkey_dec(&ctx, key, keyLen * 8);
        if (rc != 0) { mbedtls_aes_free(&ctx); throw Error(Err::Unsupported, "bad AES key length"); }
    }
    ~AesEcb() { mbedtls_aes_free(&ctx); }
    void block(bool enc, const uint8_t in[16], uint8_t out[16]) {
        mbedtls_aes_crypt_ecb(&ctx, enc ? MBEDTLS_AES_ENCRYPT : MBEDTLS_AES_DECRYPT, in, out);
    }
};

static void xorCounter(uint8_t a[8], uint64_t t) {
    for (int k = 0; k < 8; k++) a[k] ^= (uint8_t)(t >> (8 * (7 - k)));
}

Bytes aesKeyWrap(const uint8_t* kek, size_t kekLen, const uint8_t* key, size_t keyLen) {
    if (keyLen % 8 != 0 || keyLen < 16) throw Error(Err::Unsupported, "key to wrap must be a multiple of 8 bytes, >= 16");
    size_t n = keyLen / 8;
    AesEcb aes(kek, kekLen, true);
    uint8_t a[8];
    std::memcpy(a, kRfc3394Iv, 8);
    Bytes r(key, key + keyLen);
    for (int j = 0; j < 6; j++) {
        for (size_t i = 1; i <= n; i++) {
            uint8_t in[16], out[16];
            std::memcpy(in, a, 8);
            std::memcpy(in + 8, &r[(i - 1) * 8], 8);
            aes.block(true, in, out);
            std::memcpy(a, out, 8);
            xorCounter(a, (uint64_t)n * j + i);
            std::memcpy(&r[(i - 1) * 8], out + 8, 8);
        }
    }
    Bytes res(8 + keyLen);
    std::memcpy(res.data(), a, 8);
    std::memcpy(res.data() + 8, r.data(), keyLen);
    secureZero(r.data(), r.size());
    return res;
}

bool aesKeyUnwrap(const uint8_t* kek, size_t kekLen, const uint8_t* wrapped, size_t wrappedLen, Secret& out) {
    if (wrappedLen % 8 != 0 || wrappedLen < 24) return false;
    size_t n = wrappedLen / 8 - 1;
    AesEcb aes(kek, kekLen, false);
    uint8_t a[8];
    std::memcpy(a, wrapped, 8);
    Secret r(wrapped + 8, n * 8);
    for (int j = 5; j >= 0; j--) {
        for (size_t i = n; i >= 1; i--) {
            uint8_t in[16], o[16];
            uint8_t ax[8];
            std::memcpy(ax, a, 8);
            xorCounter(ax, (uint64_t)n * j + i);
            std::memcpy(in, ax, 8);
            std::memcpy(in + 8, r.data() + (i - 1) * 8, 8);
            aes.block(false, in, o);
            std::memcpy(a, o, 8);
            std::memcpy(r.data() + (i - 1) * 8, o + 8, 8);
        }
    }
    int diff = 0;
    for (int i = 0; i < 8; i++) diff |= a[i] ^ kRfc3394Iv[i];
    if (diff != 0) return false;
    out = std::move(r);
    return true;
}

void aesCtr(const uint8_t* key, size_t keyLen, const uint8_t iv[16], const uint8_t* in, uint8_t* out, size_t n) {
    mbedtls_aes_context ctx;
    mbedtls_aes_init(&ctx);
    if (mbedtls_aes_setkey_enc(&ctx, key, keyLen * 8) != 0) { mbedtls_aes_free(&ctx); throw Error(Err::Unsupported, "bad AES key length"); }
    uint8_t counter[16], stream[16] = {0};
    std::memcpy(counter, iv, 16);
    size_t off = 0;
    int rc = mbedtls_aes_crypt_ctr(&ctx, n, &off, counter, stream, in, out);
    mbedtls_aes_free(&ctx);
    secureZero(stream, 16);
    if (rc != 0) throw Error(Err::Io, "AES-CTR failed");
}

// ------------------------------------------------------------------ AEAD --

namespace {

#if defined(FV_AEAD_EVP)
// BoringSSL/OpenSSL EVP backend: noticeably faster than mbedTLS' GCM on
// devices without the ARMv8 PMULL path wired in, and what the app shipped
// with before this code moved here.
struct GcmCtx : AeadKey::Ctx {
    EVP_CIPHER_CTX* ctx;
    const EVP_CIPHER* cipher;
    Secret key;
    GcmCtx(const uint8_t* k, size_t kl) : key(k, kl) {
        cipher = kl == 16 ? EVP_aes_128_gcm() : EVP_aes_256_gcm();
        ctx = EVP_CIPHER_CTX_new();
        if (!ctx || (kl != 16 && kl != 32)) throw Error(Err::Unsupported, "bad AES-GCM key length");
    }
    ~GcmCtx() override { if (ctx) EVP_CIPHER_CTX_free(ctx); }
    bool seal(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* pt, size_t pl, uint8_t* out) override {
        int len = 0;
        bool ok = EVP_EncryptInit_ex(ctx, cipher, nullptr, nullptr, nullptr) == 1 &&
                  EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, (int)nl, nullptr) == 1 &&
                  EVP_EncryptInit_ex(ctx, nullptr, nullptr, key.data(), nonce) == 1;
        if (ok && al > 0) ok = EVP_EncryptUpdate(ctx, nullptr, &len, aad, (int)al) == 1;
        size_t w = 0;
        if (ok && pl > 0) { ok = EVP_EncryptUpdate(ctx, out, &len, pt, (int)pl) == 1; w = (size_t)len; }
        if (ok) { ok = EVP_EncryptFinal_ex(ctx, out + w, &len) == 1; w += (size_t)len; }
        if (ok) ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, 16, out + w) == 1;
        return ok;
    }
    bool open(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* ct, size_t cl, uint8_t* out) override {
        if (cl < 16) return false;
        size_t pl = cl - 16;
        int len = 0;
        bool ok = EVP_DecryptInit_ex(ctx, cipher, nullptr, nullptr, nullptr) == 1 &&
                  EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, (int)nl, nullptr) == 1 &&
                  EVP_DecryptInit_ex(ctx, nullptr, nullptr, key.data(), nonce) == 1;
        if (ok && al > 0) ok = EVP_DecryptUpdate(ctx, nullptr, &len, aad, (int)al) == 1;
        size_t w = 0;
        if (ok && pl > 0) { ok = EVP_DecryptUpdate(ctx, out, &len, ct, (int)pl) == 1; w = (size_t)len; }
        if (ok) ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, 16, const_cast<uint8_t*>(ct + pl)) == 1;
        if (ok) ok = EVP_DecryptFinal_ex(ctx, out + w, &len) == 1;
        return ok;
    }
};

struct XChaChaCtx : AeadKey::Ctx {
    EVP_AEAD_CTX ctx;
    bool valid;
    XChaChaCtx(const uint8_t* k, size_t kl) {
        valid = kl == 32 && EVP_AEAD_CTX_init(&ctx, EVP_aead_xchacha20_poly1305(), k, kl, 16, nullptr) == 1;
        if (!valid) throw Error(Err::Unsupported, "bad XChaCha20 key");
    }
    ~XChaChaCtx() override { if (valid) EVP_AEAD_CTX_cleanup(&ctx); }
    bool seal(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* pt, size_t pl, uint8_t* out) override {
        size_t w = 0;
        return EVP_AEAD_CTX_seal(&ctx, out, &w, pl + 16, nonce, nl, pt, pl, aad, al) == 1;
    }
    bool open(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* ct, size_t cl, uint8_t* out) override {
        if (cl < 16) return false;
        size_t w = 0;
        // max_out_len must be the REAL capacity of [out] (cl - tag): on an authentication
        // failure BoringSSL zero-fills max_out_len bytes of it.
        return EVP_AEAD_CTX_open(&ctx, out, &w, cl - 16, nonce, nl, ct, cl, aad, al) == 1;
    }
};
#else
struct GcmCtx : AeadKey::Ctx {
    mbedtls_gcm_context ctx;
    GcmCtx(const uint8_t* k, size_t kl) {
        mbedtls_gcm_init(&ctx);
        if ((kl != 16 && kl != 32) || mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, k, (unsigned)kl * 8) != 0) {
            mbedtls_gcm_free(&ctx);
            throw Error(Err::Unsupported, "bad AES-GCM key length");
        }
    }
    ~GcmCtx() override { mbedtls_gcm_free(&ctx); }
    bool seal(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* pt, size_t pl, uint8_t* out) override {
        return mbedtls_gcm_crypt_and_tag(&ctx, MBEDTLS_GCM_ENCRYPT, pl, nonce, nl, aad, al, pt, out, 16, out + pl) == 0;
    }
    bool open(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* ct, size_t cl, uint8_t* out) override {
        if (cl < 16) return false;
        size_t pl = cl - 16;
        return mbedtls_gcm_auth_decrypt(&ctx, pl, nonce, nl, aad, al, ct + pl, 16, ct, out) == 0;
    }
};

struct XChaChaCtx : AeadKey::Ctx {
    uint8_t key[32];
    XChaChaCtx(const uint8_t* k, size_t kl) {
        if (kl != 32) throw Error(Err::Unsupported, "bad XChaCha20 key");
        std::memcpy(key, k, 32);
    }
    ~XChaChaCtx() override { secureZero(key, 32); }
    bool seal(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* pt, size_t pl, uint8_t* out) override {
        if (nl != 24) return false;
        return xchacha20Poly1305Seal(key, nonce, aad, al, pt, pl, out);
    }
    bool open(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al, const uint8_t* ct, size_t cl, uint8_t* out) override {
        if (nl != 24 || cl < 16) return false;
        size_t bl = cl - 16;
        return xchacha20Poly1305Open(key, nonce, aad, al, ct, bl, ct + bl, out);
    }
};
#endif

}  // namespace

AeadKey::AeadKey(AeadKind kind, const uint8_t* key, size_t keyLen) : kind_(kind), key_(key, keyLen) {
    // Fail fast on a bad key instead of at the first chunk.
    release(acquire());
}
AeadKey::~AeadKey() = default;

std::unique_ptr<AeadKey::Ctx> AeadKey::acquire() const {
    {
        std::lock_guard<std::mutex> g(mu_);
        if (!pool_.empty()) {
            auto c = std::move(pool_.back());
            pool_.pop_back();
            return c;
        }
    }
    if (kind_ == AeadKind::AesGcm) return std::make_unique<GcmCtx>(key_.data(), key_.size());
    return std::make_unique<XChaChaCtx>(key_.data(), key_.size());
}

void AeadKey::release(std::unique_ptr<Ctx> c) const {
    std::lock_guard<std::mutex> g(mu_);
    if (pool_.size() < 16) pool_.push_back(std::move(c));
}

bool AeadKey::seal(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al,
                   const uint8_t* pt, size_t pl, uint8_t* out) const {
    auto c = acquire();
    bool ok = c->seal(nonce, nl, aad, al, pt, pl, out);
    release(std::move(c));
    return ok;
}

bool AeadKey::open(const uint8_t* nonce, size_t nl, const uint8_t* aad, size_t al,
                   const uint8_t* ct, size_t cl, uint8_t* out) const {
    auto c = acquire();
    bool ok = c->open(nonce, nl, aad, al, ct, cl, out);
    release(std::move(c));
    return ok;
}

// ------------------------------------------------------------- parallel --

bool parallelRanges(size_t total, size_t minParallel, const std::function<bool(size_t, size_t)>& fn) {
    if (total == 0) return true;
    unsigned hw = std::thread::hardware_concurrency();
    if (hw == 0) hw = 4;
    if (hw > total) hw = (unsigned)total;
    if (hw <= 1 || total < minParallel) return fn(0, total);
    std::vector<std::future<bool>> futs;
    size_t per = total / hw;
    for (unsigned t = 0; t < hw; t++) {
        size_t s = t * per;
        size_t e = (t == hw - 1) ? total : s + per;
        futs.push_back(std::async(std::launch::async, [&fn, s, e] { return fn(s, e); }));
    }
    bool ok = true;
    for (auto& f : futs) { if (!f.get()) ok = false; }
    return ok;
}

}  // namespace fv::crypto
