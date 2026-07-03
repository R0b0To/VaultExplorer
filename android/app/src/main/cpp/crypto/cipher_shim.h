// crypto/cipher_shim.h
//
// Uniform adapter over VeraCrypt's vendored reference primitives.
// This is the ONLY header that should ever need to change if upstream
// renames a function or changes a signature — everything else in this
// codebase (cascade.cpp, vaultexplorer.cpp) talks to these types only.
//
// IMPORTANT: the function bodies in cipher_shim.cpp currently contain
// TODO markers instead of real calls into Twofish.c/Serpent.c/etc. — I
// have not verified the exact upstream signatures (VeraCrypt's C sources
// use old reference-implementation-era naming that has shifted slightly
// across versions). Fill these in against the ACTUAL vendored headers
// once FetchContent has pulled them — do not guess signatures here.
#pragma once
#include <cstdint>
#include <cstddef>

// ── Cipher identity ──────────────────────────────────────────────────────

enum class CipherId : uint8_t {
    kAes = 0,
    kSerpent = 1,
    kTwofish = 2,
};

// Every cipher below is a 128-bit-block, 256-bit-key block cipher — this is
// what VeraCrypt requires for XTS mode. (No 64-bit-block legacy ciphers are
// supported here, matching your AES-only baseline.)
static constexpr size_t kBlockCipherKeyBytes = 32;   // 256-bit
static constexpr size_t kBlockSizeBytes      = 16;   // 128-bit

// Opaque per-cipher key-schedule storage. Sized generously (Serpent's
// schedule is the largest of the three); cipher_shim.cpp reinterprets this
// as the real upstream context type.
struct BlockCipherContext {
    CipherId id;
    alignas(16) unsigned char scheduleStorage[4608]; // fits TwofishInstance (4256 bytes) and Serpent (560 bytes)
};

// Sets up [ctx] for encryption AND decryption with [key] (32 bytes).
// Returns false on failure (should not normally happen for a fixed 256-bit
// key — kept as a return value only for parity with mbedTLS's API shape).
bool blockCipherSetKey(BlockCipherContext& ctx, CipherId id,
                        const unsigned char key[kBlockCipherKeyBytes]);

// Single 16-byte block, ECB-level primitive. XTS tweaking/chaining lives in
// cascade.cpp, NOT here — this function must do nothing but transform one
// block with the already-scheduled key.
void blockCipherEncryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]);
void blockCipherDecryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]);

// ── Hash identity (for PBKDF2-HMAC) ──────────────────────────────────────

enum class HashId : uint8_t {
    kSha512 = 0,   // already supported via mbedTLS — kept here for uniformity
    kSha256 = 1,   // already supported via mbedTLS
    kWhirlpool = 2,
    kStreebog = 3,
    kBlake2s256 = 4,
};

static constexpr size_t kMaxHashOutputBytes = 64; // SHA-512/Whirlpool/Streebog = 64B, others less

// Runs PBKDF2-HMAC-[hash] and writes exactly [outLen] bytes to [out].
// For kSha512/kSha256 this should delegate to the existing mbedTLS
// mbedtls_pkcs5_pbkdf2_hmac() path already used in vaultexplorer.cpp — do
// NOT reimplement HMAC/PBKDF2 by hand for the vendored hashes either;
// wrap them in a minimal HMAC construction using their raw digest fn,
// mirroring mbedtls_md's approach, OR (preferred, less error-prone) use
// mbedtls's generic MD interface with a custom md_info_t if the vendored
// primitive can be adapted to mbedTLS's callback shape.
bool pbkdf2Hmac(HashId hash,
                 const unsigned char* password, size_t passwordLen,
                 const unsigned char* salt, size_t saltLen,
                 unsigned int iterations,
                 unsigned char* out, size_t outLen);

int iterationsForHash(HashId hash, int clampedPim);