#pragma once

#include <cstddef>
#include <cstdint>

// XChaCha20-Poly1305 AEAD (draft-irtf-cfrg-xchacha-03 construction over
// RFC 8439 ChaCha20-Poly1305, via mbedtls_chachapoly for the inner
// 12-byte-nonce primitive). Shared between crypto/cryfs_block_cipher.cpp
// (CryFS block store, no AAD) and the gocryptfs JNI bridge (AAD = big-endian
// blockNo || 16-byte fileID, matching gocryptfs's contentenc.concatAD()).
//
// Wire/argument layout matches gocryptfs and CryFS conventions: a 24-byte
// nonce, then ciphertext of the same length as the plaintext, then a
// 16-byte Poly1305 tag -- i.e. callers own nonce placement, this only does
// the AEAD core over (nonce, aad, plaintext) -> (ciphertext, tag).

// Derives the XChaCha20 subkey via HChaCha20(key, nonce24[0:16]). Exposed
// separately because both callers derive it the same way; kept here so
// there's a single implementation to keep in sync with the RFC.
void hchacha20(const uint8_t key[32], const uint8_t nonce16[16], uint8_t outSubkey[32]);

// Encrypts `plaintextLen` bytes and writes `plaintextLen` ciphertext bytes
// followed by a 16-byte tag into `outCiphertextAndTag` (caller-allocated,
// must be at least plaintextLen + 16 bytes). `aad`/`aadLen` may be
// nullptr/0. Returns false on setup failure.
bool xchacha20Poly1305Seal(const uint8_t key[32], const uint8_t nonce24[24],
                            const uint8_t* aad, size_t aadLen,
                            const uint8_t* plaintext, size_t plaintextLen,
                            uint8_t* outCiphertextAndTag);

// Verifies and decrypts `bodyLen` bytes of ciphertext plus a trailing
// 16-byte tag, writing `bodyLen` plaintext bytes to `outPlaintext`
// (caller-allocated). Returns false if authentication fails or setup
// fails; `outPlaintext` must not be trusted in that case.
bool xchacha20Poly1305Open(const uint8_t key[32], const uint8_t nonce24[24],
                            const uint8_t* aad, size_t aadLen,
                            const uint8_t* ciphertext, size_t bodyLen,
                            const uint8_t tag[16],
                            uint8_t* outPlaintext);
