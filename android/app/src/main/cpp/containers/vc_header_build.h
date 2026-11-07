#pragma once
// Shared building blocks for WRITING VeraCrypt volume headers: container
// creation, USB creation, composite creation, password change and the
// "restore header from embedded backup" repair. Header-only so it can be
// unit-tested on the host (containers/test/vc_header_build_test.cpp).
//
// Two things every writer used to get wrong, now done in exactly one place:
//
//  1. The fixed preamble. Upstream stamps header format version 5
//     (VOLUME_HEADER_VERSION) and minimum program version 0x010b
//     (TC_VOLUME_MIN_REQUIRED_PROGRAM_VERSION) into every header it writes
//     (Common/Volumes.h, Volume/VolumeHeader.cpp). This app used to write
//     format version 2 (4 sites) and required-program-version 6 (1 site).
//
//  2. Backup headers. VeraCrypt never writes the same 512 bytes twice: each
//     header copy -- primary and backup -- gets its own random salt, its own
//     header key (the KDF is re-run for the new salt) and is encrypted
//     separately (Core/VolumeCreator.cpp "Backup header", Core/CoreBase.cpp
//     ChangePassword -> Volume::ReEncryptHeader). Writing the very same sector
//     twice is a fingerprint of the container on its own, and for hidden
//     volumes the hidden slot at 64 KiB and its backup at V-64 KiB would be
//     byte-identical exactly when a hidden volume exists -- defeating the
//     plausible deniability the feature is for.
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>
#include "mbedtls/platform_util.h"
#include "crypto/cascade.h"
#include "crypto/cipher_shim.h"
#include "crypto/user_entropy.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"

// Defined in session/session_prepare.cpp, where it is declared with a default
// for cancelCheck. Repeated here WITHOUT the default so this header stays light
// (a later declaration may add the default; repeating it would be an error).
bool deriveHeaderKey(HashId hash,
                     const unsigned char* password, size_t passwordLen,
                     const unsigned char* salt, int clampedPim,
                     unsigned char* out, size_t outLen,
                     std::function<bool()> cancelCheck);

// "VERA" + header format version + minimum program version, at the start of
// the decrypted 448-byte header body.
inline void vcStampHeaderPreamble(unsigned char* body) {
    body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
    body[VC_HDR_OFF_VERSION]              = static_cast<unsigned char>(VC_HEADER_FORMAT_VERSION >> 8);
    body[VC_HDR_OFF_VERSION + 1]          = static_cast<unsigned char>(VC_HEADER_FORMAT_VERSION & 0xFF);
    body[VC_HDR_OFF_REQUIRED_VERSION]     = static_cast<unsigned char>(VC_MIN_PROGRAM_VERSION >> 8);
    body[VC_HDR_OFF_REQUIRED_VERSION + 1] = static_cast<unsigned char>(VC_MIN_PROGRAM_VERSION & 0xFF);
}

// XTS-encrypts a decrypted header body (VC_HEADER_BODY_SIZE bytes) in place as
// data unit 0 with [headerKey] (primary keys, then tweak keys), applying the
// cascade layers in encryption order -- the inverse of tryDecryptHeader().
inline bool vcEncryptHeaderBody(CascadeId cipher, const unsigned char* headerKey, unsigned char* body) {
    const CascadeSpec spec = cascadeSpecFor(cipher);
    CascadeContext ctx;
    if (!cascadeSetKeys(ctx, cipher, headerKey, spec.layerCount * 64)) return false;
    for (int layer = spec.layerCount - 1; layer >= 0; layer--) {
        const XtsLayerKey& lk = ctx.layers[layer];
        unsigned char T[16] = {0};
        blockCipherEncryptBlock(lk.tweakKey, T, T);
        for (int blk = 0; blk < 28; blk++) {
            unsigned char* bp = body + blk * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = bp[j] ^ T[j];
            blockCipherEncryptBlock(lk.dataKeyEnc, tmp, tmp);
            for (int j = 0; j < 16; j++) bp[j] = tmp[j] ^ T[j];
            xtsMultiplyTweak(T);
        }
    }
    return true;
}

// Builds a complete VC_FULL_HEADER_SIZE header sector for the already-final
// plaintext [plainBody] (same master keys, same fields) under a FRESH random
// salt: header key = KDF(password, pim, new salt), then encrypted. Use it for
// every second copy of a header (the backup slots, a header restored from its
// backup). [password] is the effective password (keyfiles already mixed in).
inline bool vcBuildFreshlySaltedHeaderSector(const unsigned char* plainBody,
                                             CascadeId cipher, HashId hash,
                                             const unsigned char* password, size_t passwordLen,
                                             int clampedPim, unsigned char* outSector) {
    unsigned char salt[VC_SALT_SIZE];
    unsigned char headerKey[192] = {0};
    unsigned char enc[VC_HEADER_BODY_SIZE];
    bool ok = userentropy::fillRandom(salt, VC_SALT_SIZE) &&
              deriveHeaderKey(hash, password, passwordLen, salt, clampedPim,
                              headerKey, sizeof(headerKey), nullptr);
    if (ok) {
        std::memcpy(enc, plainBody, VC_HEADER_BODY_SIZE);
        ok = vcEncryptHeaderBody(cipher, headerKey, enc);
    }
    if (ok) {
        std::memcpy(outSector, salt, VC_SALT_SIZE);
        std::memcpy(outSector + VC_SALT_SIZE, enc, VC_HEADER_BODY_SIZE);
    }
    mbedtls_platform_zeroize(headerKey, sizeof(headerKey));
    mbedtls_platform_zeroize(enc, sizeof(enc));
    return ok;
}
