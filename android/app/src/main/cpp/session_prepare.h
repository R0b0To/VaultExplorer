#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>

#include "container_header.h"
#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"

// VeraCrypt / LUKS session establishment.
//
// This is the layer behind VeraCryptEngine's Tier-1 (session-establishment)
// JNI calls — deriveKeyMaterialNative, unlockAndListNative,
// unlockUsbAndListNative (see VeraCryptEngine.kt) — covering header/keyslot
// cipher-and-hash auto-detection, keyfile mixing, and turning a recovered
// master key into a live VolumeState session. LUKS's own keyslot/AF-stripe
// master-key recovery stays in luks_header.h/.cpp; this module is the layer
// above it (and above VeraCrypt's own header decrypt) that both formats
// funnel through on the way to an unlocked volume.
//
// Ownership contract for every keyfileFds parameter below, matching the
// contract already documented on the Kotlin/JNI boundary: each fd is
// closed exactly once — on success or failure — before the function
// returns. Callers must not touch or close them afterward.

// Tries every requested (hash, cipher) combination against the VeraCrypt
// header at [headerSector] — or just the pair pinned by cipherIdParam/
// hashIdParam when either isn't 255 — and returns the recovered 192-byte
// key material, decrypted header body, matched IDs, and parsed header
// fields on success. Touches neither keyfiles nor VolumeState. Used
// directly by deriveKeyMaterialNative (quick-unlock key export) and
// internally by prepareSession/prepareUsbSession below.
bool deriveAndValidateHeader(
    const unsigned char headerSector[VC_FULL_HEADER_SIZE],
    const unsigned char* password, size_t passwordLen, int pim,
    int cipherIdParam, int hashIdParam,
    unsigned char outKeyMaterial[192],
    unsigned char outDecryptedHeader[VC_HEADER_BODY_SIZE],
    CascadeId& outMatchedCipher,
    HashId& outMatchedHash,
    ParsedHeaderFields& outFields,
    int volId = -1);

// Derives the 192-byte VeraCrypt header key for [hash] at PIM [clampedPim]
// (Argon2id emits the full 192 bytes directly; PBKDF2-family hashes derive
// it via iterationsForHash()). Used both during unlock
// (deriveAndValidateHeader, one hash at a time while auto-detecting) and
// during container creation (which already knows its hash/cipher and skips
// the auto-detect loop entirely).
// abortFlag: forwarded to pbkdf2Hmac — see its doc comment in cipher_shim.h.
// Container creation has no concurrent workers to abort against, so it
// omits this and gets the default nullptr.
bool deriveHeaderKey(HashId hash,
                     const unsigned char* password, size_t passwordLen,
                     const unsigned char* salt, int clampedPim,
                     unsigned char* out, size_t outLen,
                     const std::atomic<bool>* abortFlag = nullptr);

// Establishes a session for volume [volId] backed by open file descriptor
// [fd] — a VeraCrypt container file or a LUKS1/LUKS2 image; format is
// auto-detected from the magic bytes. Takes ownership of [fd] and every fd
// in [keyfileFds] regardless of outcome. If [forceDerive] is false and a
// session is already active for [volId], returns true immediately without
// deriving anything (still closes [fd]) — used by lazy session checks,
// distinct from an explicit unlock request.
bool prepareSession(int fd, const unsigned char* password, size_t passwordLen,
                    int pim, int volId, bool forceDerive, int cipherId, int hashId,
                    const unsigned char* preservedKey = nullptr, size_t preservedKeyLen = 0,
                    const int* keyfileFds = nullptr, int keyfileCount = 0);

// USB-backed counterpart to prepareSession: scans the device's MBR/GPT
// partition table (plus an unpartitioned whole-disk fallback) for a
// VeraCrypt or LUKS header, trying [partitionOffsetHint] first when given.
bool prepareUsbSession(const unsigned char* password, size_t passwordLen, int pim, int volId,
                       int cipherId, int hashId, const unsigned char* preservedKey = nullptr,
                       size_t preservedKeyLen = 0, int64_t partitionOffsetHint = -1,
                       const int* keyfileFds = nullptr, int keyfileCount = 0);

// ── Per-volume unlock cancellation ──────────────────────────────────────
//
// A cooperative cancel flag polled from inside the (potentially
// long-running) auto-detect loops in deriveAndValidateHeader/
// prepareLuksSession. Owned by this module since it's meaningless outside
// an in-progress prepareSession/prepareUsbSession call; the JNI layer only
// sets/clears it (requestCancelUnlockNative / the start of each unlock
// call) and reads it back to decide whether to throw
// UnlockCancelledException.
void clearUnlockCancellation(int volId);
void requestUnlockCancellation(int volId);
bool isUnlockCancelled(int volId);