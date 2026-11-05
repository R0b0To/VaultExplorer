// Cryptographic building blocks for the folder-vault engines.
//
// Everything here is a thin, allocation-aware wrapper around mbedTLS (and,
// optionally, BoringSSL/OpenSSL for the bulk AEAD path -- see FV_AEAD_EVP).
// The heavier algorithms the app already had in native code (scrypt, EME,
// AES-SIV, XChaCha20-Poly1305, the CryFS block cipher) are reused as-is from
// ../crypto/ instead of being duplicated.
#pragma once

#include <functional>
#include <memory>
#include <mutex>
#include <vector>

#include "fv_common.h"

namespace fv::crypto {

// ---- randomness ---------------------------------------------------------

// Fast CSPRNG for per-chunk nonces and block ids (getrandom/arc4random).
void randomFast(uint8_t* out, size_t n);

// Randomness for key material, salts and ivs of *creation* flows. On
// Android this honours the user-entropy Scope installed by the create JNI
// entry points (see crypto/user_entropy.h); elsewhere it equals randomFast.
// Throws Error(Io) if the OS RNG cannot be read.
void randomKey(uint8_t* out, size_t n);
Bytes randomKeyBytes(size_t n);

// ---- hashing / MAC / KDF ------------------------------------------------

enum class Md { Sha1, Sha256, Sha384, Sha512 };

Bytes hash(Md md, const uint8_t* data, size_t n);
Bytes hmac(Md md, const uint8_t* key, size_t keyLen, const uint8_t* data, size_t n);

// Incremental HMAC-SHA256 (Cryptomator CTR/HMAC chunks and headers).
class HmacSha256 {
public:
    HmacSha256(const uint8_t* key, size_t keyLen);
    ~HmacSha256();
    HmacSha256(const HmacSha256&) = delete;
    HmacSha256& operator=(const HmacSha256&) = delete;
    void update(const uint8_t* data, size_t n);
    void finish(uint8_t out[32]);
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

// HKDF-SHA256 with an all-zero salt (what gocryptfs uses), RFC 5869.
Secret hkdfSha256(const uint8_t* secret, size_t secretLen, const std::string& info, size_t outLen);

// scrypt (wraps crypto/scrypt.cpp). Throws Error(Unsupported) if the
// parameters exceed the native layer's safety caps.
Secret scrypt(const uint8_t* pass, size_t passLen, const uint8_t* salt, size_t saltLen,
              uint32_t N, uint32_t r, uint32_t p, size_t outLen);

// ---- block / stream primitives -------------------------------------------

// RFC 3394 AES key wrap (Cryptomator masterkey file). Unwrap returns false
// on integrity failure (wrong KEK).
Bytes aesKeyWrap(const uint8_t* kek, size_t kekLen, const uint8_t* key, size_t keyLen);
bool aesKeyUnwrap(const uint8_t* kek, size_t kekLen, const uint8_t* wrapped, size_t wrappedLen, Secret& out);

// AES-CTR (big-endian 128-bit counter). In-place capable.
void aesCtr(const uint8_t* key, size_t keyLen, const uint8_t iv[16], const uint8_t* in, uint8_t* out, size_t n);

// ---- AEAD ---------------------------------------------------------------

enum class AeadKind { AesGcm, XChaCha20Poly1305 };

// A reusable AEAD key. seal/open are thread-safe: internally a small pool of
// per-thread cipher contexts is used (mbedTLS/EVP contexts are not
// re-entrant). Wire layout handled by callers: nonce || ct || 16-byte tag.
class AeadKey {
public:
    static constexpr size_t kTagLen = 16;
    AeadKey(AeadKind kind, const uint8_t* key, size_t keyLen);
    ~AeadKey();
    AeadKey(const AeadKey&) = delete;
    AeadKey& operator=(const AeadKey&) = delete;

    AeadKind kind() const { return kind_; }
    // Nonce length is chosen per call for AES-GCM (12 for Cryptomator, 16 for
    // gocryptfs); XChaCha20 is always 24.
    // out must have room for ptLen + 16 bytes (ciphertext || tag).
    bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen,
              const uint8_t* pt, size_t ptLen, uint8_t* out) const;
    // ctAndTag is ciphertext || tag (ctLen includes the tag); out gets ctLen-16 bytes.
    bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen,
              const uint8_t* ctAndTag, size_t ctLen, uint8_t* out) const;

    struct Ctx {  // backend-specific, defined in fv_crypto.cpp
        virtual ~Ctx() = default;
        virtual bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen,
                          const uint8_t* pt, size_t ptLen, uint8_t* out) = 0;
        virtual bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen,
                          const uint8_t* ctAndTag, size_t ctLen, uint8_t* out) = 0;
    };
private:
    std::unique_ptr<Ctx> acquire() const;
    void release(std::unique_ptr<Ctx> c) const;
    AeadKind kind_;
    Secret key_;
    mutable std::mutex mu_;
    mutable std::vector<std::unique_ptr<Ctx>> pool_;
};

// Runs fn(startIdx, endIdx) over [0,total) split across hardware threads
// when total is large enough to be worth it. Returns false if any slice
// returned false. Slices are contiguous so each thread touches its own
// region of the output buffer.
bool parallelRanges(size_t total, size_t minParallel, const std::function<bool(size_t, size_t)>& fn);

}  // namespace fv::crypto
