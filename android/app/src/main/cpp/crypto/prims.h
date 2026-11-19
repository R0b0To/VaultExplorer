// One-shot cryptographic primitives behind the Dart layer's platform-channel crypto methods
// (hmac, pbkdf2, aesGcm*, aesCbcDecrypt): HMAC, PBKDF2-HMAC, AES-GCM and AES-CBC on in-memory
// buffers.
//
// Platform-neutral C++ on the mbedtls both builds already link -- no JNI, Android or Flutter
// types -- so a desktop front-end calls exactly the code Android does, and the app's TOTP codes,
// authenticator-backup imports and Bitwarden check behave identically on every platform.
//
// Contracts follow the handlers they stand in for (DerivedKeyHandlers.kt):
//   * hash names on the wire are exactly "sha1", "sha256", "sha512";
//   * an empty HMAC key or an empty PBKDF2 salt is rejected, never silently accepted;
//   * AES-GCM takes 128- or 256-bit keys (no AES-192, as in the existing native path), any
//     non-empty IV, appends / expects a 16-byte tag;
//   * AES-CBC is PKCS#7-padded (what JCA calls PKCS5Padding for AES): encrypt takes any length,
//     decrypt rejects an empty input, a length that is not a multiple of 16 and any bad padding.
// Every function returns false on failure and leaves `out` empty; temporaries holding key
// material or plaintext are wiped.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace prims {

using Bytes = std::vector<uint8_t>;

enum class Hash { Sha1, Sha256, Sha512 };

// The exact lower-case wire names; anything else is rejected rather than defaulted.
bool parseHash(std::string_view wireName, Hash& out);

// HMAC of `data` under `key` (non-empty).
bool hmac(Hash h, const uint8_t* key, size_t keyLen, const uint8_t* data, size_t dataLen, Bytes& out);

// PBKDF2-HMAC: `outLen` bytes from password `pw` (may be empty) and a non-empty `salt`;
// iterations >= 1.
bool pbkdf2(Hash h, const uint8_t* pw, size_t pwLen, const uint8_t* salt, size_t saltLen, uint32_t iterations,
            size_t outLen, Bytes& out);

// AES-GCM; `out` = ciphertext || 16-byte tag. `aad` may be null / empty.
bool aesGcmSeal(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* aad, size_t aadLen,
                const uint8_t* pt, size_t ptLen, Bytes& out);
// `ctAndTag` = ciphertext || tag; false for a wrong key / IV / AAD or any tampering.
bool aesGcmOpen(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* aad, size_t aadLen,
                const uint8_t* ctAndTag, size_t ctLen, Bytes& out);

// AES-CBC + PKCS#7; key 16 / 24 / 32 bytes, IV exactly 16.
bool aesCbcEncrypt(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* pt, size_t ptLen,
                   Bytes& out);
bool aesCbcDecrypt(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* ct, size_t ctLen,
                   Bytes& out);

}  // namespace prims
