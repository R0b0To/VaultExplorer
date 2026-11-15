#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

// Block-level cryptography for CryFS.
enum class CryfsCipherId : uint8_t {
    kAes256Gcm = 0,   // "aes-256-gcm" - CryFS default, authenticated
    kAes256Cfb = 1,   // "aes-256-cfb" - legacy default, unauthenticated
    kAes128Gcm = 2,   // "aes-128-gcm"
    kAes128Cfb = 3,   // "aes-128-cfb"
    kXChaCha20Poly1305 = 4, // "xchacha20-poly1305" - CryFS 1.0+ default
    // 16 + n: the other ciphers official C++ CryFS 1.x offers (twofish-*, serpent-*, cast-256-*, mars-*, each in
    // -gcm and -cfb flavour); n indexes cryfs_legacy::spec() (crypto/cryfs_legacy_ciphers.h).
    kLegacyBase = 16,
    kUnknown = 255,
};

CryfsCipherId cryfsCipherIdFromName(const char* name);

std::vector<uint8_t> cryfsBlockEncrypt(CryfsCipherId cipher,
                                        const uint8_t* key, size_t keyLen,
                                        const uint8_t* plaintext, size_t plaintextLen);

bool cryfsBlockDecrypt(CryfsCipherId cipher,
                        const uint8_t* key, size_t keyLen,
                        const uint8_t* ciphertext, size_t ciphertextLen,
                        std::vector<uint8_t>& out);

long cryfsBlockCleartextSize(CryfsCipherId cipher, size_t ciphertextLen);

// Key length in bytes the cipher needs, or 0 for kUnknown.
int cryfsCipherKeyBytes(CryfsCipherId cipher);
// Bytes a block grows by when encrypted (IV/nonce + tag), or -1 for kUnknown.
long cryfsCipherOverheadBytes(CryfsCipherId cipher);
