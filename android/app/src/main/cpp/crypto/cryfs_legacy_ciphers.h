#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

// The extra ciphers official C++ CryFS 1.x offers besides AES and XChaCha20-Poly1305:
//   twofish-{128,256}-{gcm,cfb}, serpent-{128,256}-{gcm,cfb}, cast-256-{gcm,cfb}, mars-{128,256,448}-{gcm,cfb}
// All have a 128-bit block, so the modes are exactly the ones used for AES:
//   GCM: IV(16) || ciphertext || tag(16)   -- 16-byte IV (not the usual 12), no associated data
//   CFB: IV(16) || ciphertext              -- full-block (CFB-128) feedback, unauthenticated
// Only the *encrypt* direction of the block cipher is needed for either mode, so that is all that is here.
namespace cryfs_legacy {

enum class Algo : uint8_t { Twofish, Serpent, Cast256, Mars };
enum class Mode : uint8_t { Gcm, Cfb };

struct Spec {
    const char* name;
    Algo algo;
    Mode mode;
    size_t keyLen;
};

constexpr size_t kSpecCount = 16;
const Spec& spec(size_t index);                 // index < kSpecCount
int findSpecIndex(const char* name);            // -1 if [name] is not one of the ciphers above

class Block128 {
public:
    virtual ~Block128() = default;
    // [in] and [out] may be the same buffer.
    virtual void encrypt(const uint8_t in[16], uint8_t out[16]) const = 0;
};

// nullptr if [keyLen] is not valid for the algorithm.
std::unique_ptr<Block128> makeBlockCipher(Algo algo, const uint8_t* key, size_t keyLen);

// out = ciphertext (n bytes) || tag (16 bytes)
void gcmSeal(const Block128& bc, const uint8_t iv[16], const uint8_t* plain, size_t n, uint8_t* out);
// false (and [out] untouched) if the tag does not verify.
bool gcmOpen(const Block128& bc, const uint8_t iv[16], const uint8_t* cipher, size_t n, const uint8_t tag[16], uint8_t* out);
void cfbCrypt(const Block128& bc, bool encrypt, const uint8_t iv[16], const uint8_t* in, size_t n, uint8_t* out);

}  // namespace cryfs_legacy
