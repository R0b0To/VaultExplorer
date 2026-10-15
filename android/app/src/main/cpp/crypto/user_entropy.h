#pragma once

// User-collected entropy ("random pool enrichment", like VeraCrypt desktop's
// mouse-movement step) for key/salt generation.
//
// The creation wizards collect touch movement in Dart and hand it to the
// native create entry points. Those entry points install it for the duration
// of the call with userentropy::Scope; every place that draws a salt / master
// key / LUKS keyslot material then calls userentropy::fillRandom() instead of
// reading /dev/urandom directly.
//
// How the entropy is used
// -----------------------
//   output = /dev/urandom bytes  XOR  keystream(user entropy)
//
// The keystream is a deterministic function of the user input only, and the
// /dev/urandom bytes are independent of it, so the result is exactly as
// uniform as /dev/urandom alone: mixing can ADD entropy (it protects against
// a weak or compromised OS RNG, which is the whole point of VeraCrypt's pool)
// but can never REMOVE any, even if the user input is low quality or
// attacker-controlled. If /dev/urandom cannot be read, fillRandom() fails
// instead of falling back to user entropy alone.
//
// Keystream construction (identical to util/UserEntropy.kt on the JVM side):
//
//   seed    = SHA-512( "VaultExplorer/user-entropy/v1" || u32be(len) || input )
//   block_i = SHA-512( seed || u64be(i) )           i = 0, 1, 2, ...
//   stream  = block_0 || block_1 || ...             consumed sequentially,
//                                                   never reused or rewound
//
// so a 4 KB pool is compressed into the 512-bit seed rather than only the
// first few bytes being used, and the salt and the master key of one volume
// (and the outer and hidden volume of one container) never share keystream.
//
// Scope is per THREAD (thread_local): the JNI entry points that create
// volumes run the whole operation on the calling thread, and a thread-local
// install means no global state can leak into an unrelated concurrent call.
// Scopes nest (the previous state is restored on destruction). Only the
// 64-byte seed is kept, never the raw input, and it is wiped on destruction.

#include <cstddef>
#include <cstdint>

namespace userentropy {

constexpr size_t kSeedSize  = 64;  // SHA-512 output
constexpr size_t kBlockSize = 64;

// Installs user entropy for the calling thread until destruction. A null /
// empty input installs nothing (fillRandom() then behaves exactly like a
// plain /dev/urandom read).
class Scope {
public:
    Scope(const uint8_t* data, size_t len);
    ~Scope();
    Scope(const Scope&) = delete;
    Scope& operator=(const Scope&) = delete;

private:
    struct Saved;
    Saved* saved_;  // previous thread state, restored by the destructor
};

// True when a Scope carrying user entropy is active on the calling thread.
bool active();

// Fills [buf, buf+len) with cryptographically random bytes (uint8_t is
// `unsigned char`, so the container code's `unsigned char` buffers can be
// passed directly): /dev/urandom,
// XORed with the user-entropy keystream when a Scope is active. Returns false
// if /dev/urandom could not be read in full (buf contents are then
// unspecified and must not be used). len == 0 succeeds trivially.
bool fillRandom(uint8_t* buf, size_t len);

// XORs the next len bytes of the active Scope's keystream into buf (the second
// half of fillRandom(), split out so tests can check the mixing without a
// random source). No-op returning true when no Scope is active. Returns false
// only if SHA-512 fails, in which case buf is left untouched.
bool applyKeystream(uint8_t* buf, size_t len);

// Pure building blocks, exposed for the known-answer tests.
bool deriveSeed(const uint8_t* data, size_t len, uint8_t outSeed[kSeedSize]);
bool keystreamBlock(const uint8_t seed[kSeedSize], uint64_t counter, uint8_t outBlock[kBlockSize]);

}  // namespace userentropy
