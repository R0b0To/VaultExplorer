#pragma once

// dm-crypt / LUKS sector cipher (data area AND keyslot area).
//
// Implements the cipher notations real LUKS1/LUKS2 volumes use, so that a
// volume created by upstream cryptsetup decrypts bit-for-bit identically:
//
//   chaining : xts            (key = K1 || K2, 512..4096-byte data units)
//              cbc            (one independent CBC chain per sector)
//   IV       : plain          (32-bit little-endian sector number)
//              plain64        (64-bit little-endian sector number)
//              essiv:sha256   (AES/<cipher>_k'(sector), k' = SHA-256(volume key))
//
// "Sector number" is always counted in 512-byte units, exactly like dm-crypt:
// for a 4096-byte logical sector the IV advances by 8 per sector (this is also
// what LUKS2 `iv_tweak` is expressed in).
//
// Supported block ciphers: aes (128- or 256-bit key per XTS half / CBC key),
// serpent, twofish, camellia, kuznyechik (256-bit only). Anything else
// (ecb, lrw, benbi, tcw, hctr2, adiantum, AEAD/integrity ...) is rejected by
// luksParseCipherSpec() so callers can report "unsupported" instead of
// silently deriving a wrong key.

#include <cstddef>
#include <cstdint>
#include <string>
#include "cipher_shim.h"
#include "cascade.h"

enum class LuksChain : uint8_t { kXts = 0, kCbc = 1 };
enum class LuksIvMode : uint8_t { kPlain = 0, kPlain64 = 1, kEssivSha256 = 2 };

struct LuksCipherSpec {
    CipherId   cipher = CipherId::kAes;
    LuksChain  chain = LuksChain::kXts;
    LuksIvMode iv = LuksIvMode::kPlain64;
    uint32_t   keyBytes = 0;   // total volume-key bytes (XTS: both halves)
};

// [cipherName] e.g. "aes", [cipherMode] e.g. "xts-plain64" or "cbc-essiv:sha256".
// Returns false for any combination this implementation cannot decrypt
// correctly (including key sizes the cipher cannot take).
bool luksParseCipherSpec(const std::string& cipherName, const std::string& cipherMode,
                         uint32_t keyBytes, LuksCipherSpec& out);

// Convenience for LUKS2 notation "cipher-mode[-iv]" (e.g. "aes-xts-plain64",
// "aes-cbc-essiv:sha256"): splits at the first '-'.
bool luksParseCipherString(const std::string& encryption, uint32_t keyBytes, LuksCipherSpec& out);

struct LuksCipherContext {
    LuksCipherSpec spec;
    XtsLayerKey    xts;          // chain == kXts
    BlockCipherContext cbcEnc;   // chain == kCbc
    BlockCipherContext cbcDec;
    BlockCipherContext essiv;    // iv == kEssivSha256
    bool initialized = false;
};

// Key must be exactly spec.keyBytes long.
bool luksCipherInit(LuksCipherContext& ctx, const LuksCipherSpec& spec,
                    const uint8_t* key, size_t keyLen);

// Encrypts/decrypts [len] bytes (a multiple of [sectorSize]) sector by sector.
// [iv512Start] is the IV/tweak counter of the first sector, in 512-byte units.
// [sectorSize] is a power of two in [512, 4096]. in == out is allowed.
// Thread-safe for concurrent calls on a const context.
bool luksCipherCrypt(const LuksCipherContext& ctx, bool encrypt, uint64_t iv512Start,
                     uint32_t sectorSize, const uint8_t* in, uint8_t* out, size_t len);

void luksCipherWipe(LuksCipherContext& ctx);
