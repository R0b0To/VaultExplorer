// crypto/cascade.h
//
// Generalizes VolumeState's single AES-XTS context into a cascade of up to
// 3 independently-keyed XTS layers, matching VeraCrypt's supported cipher
// combinations:
//   AES · Serpent · Twofish                              (1-layer, 3 options)
//   AES-Twofish · Serpent-AES · Twofish-Serpent           (2-layer, 3 options)
//   AES-Twofish-Serpent · Serpent-Twofish-AES             (3-layer, 2 options)
//
// Cascade ORDER matters and is cipher-specific: VeraCrypt encrypts through
// the layers in the order the name lists them, and decrypts in REVERSE
// order. E.g. "AES-Twofish" encrypts AES-then-Twofish and decrypts
// Twofish-then-AES.
#pragma once
#include "cipher_shim.h"
#include <cstdint>
#include <array>

static constexpr int kMaxCascadeLayers = 3;

// One of the 8 combinations VeraCrypt (and this app) supports beyond plain
// AES. Order in the array is encrypt order; decrypt runs it in reverse.
struct CascadeSpec {
    int layerCount;
    std::array<CipherId, kMaxCascadeLayers> layers;
};

enum class CascadeId : uint8_t {
    kAes,
    kSerpent,
    kTwofish,
    kAesTwofish,
    kSerpentAes,
    kTwofishSerpent,
    kAesTwofishSerpent,
    kSerpentTwofishAes,
};

CascadeSpec cascadeSpecFor(CascadeId id);

// Per-layer XTS key pair (data key + tweak key, both 256-bit, matching your
// existing AES-XTS convention of a 64-byte combined key material slot).
struct XtsLayerKey {
    BlockCipherContext dataKeyEnc;
    BlockCipherContext dataKeyDec;
    BlockCipherContext tweakKey;   // XTS tweak-key schedule is a second,
                                    // independently-keyed block cipher of
                                    // the SAME algorithm as the data key.
};

// Full cascade context — this is what replaces the bare
// `mbedtls_aes_xts_context dataCtxDec/dataCtxEnc` pair inside VolumeState.
struct CascadeContext {
    CascadeId id;
    int layerCount;
    std::array<XtsLayerKey, kMaxCascadeLayers> layers; // in ENCRYPT order

    bool initialized = false;
};

// Derives all layer keys from the raw header key-material bytes.
// [keyMaterial] must point at layerCount * 64 bytes — i.e. for a 3-layer
// cascade this reads header body offsets 192, 256, and 320 (64 bytes each),
// exactly the three slot positions your existing VC_KEY_OFFSET_MASTER
// comment already identifies but doesn't yet use for layers 2/3.
bool cascadeSetKeys(CascadeContext& ctx, CascadeId id,
                     const unsigned char* keyMaterial, size_t keyMaterialLen);

// Encrypts/decrypts exactly one 512-byte sector through every layer of the
// cascade, in the correct order, with the correct XTS tweak per layer.
// [sectorNumber] is whatever tweak convention the caller has already
// resolved (absolute physical vs. relative — same ambiguity your existing
// disk_read/disk_write already handle via `relTweak`).
void cascadeEncryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]);
void cascadeDecryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]);