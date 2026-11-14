#pragma once

#include <cstddef>
#include <cstdint>

bool scrypt_crypto(const uint8_t* passphrase, size_t passphraseLen,
                   const uint8_t* salt, size_t saltLen,
                   uint32_t N, uint32_t r, uint32_t p,
                   uint8_t* out, size_t outLen);

// Same output as scrypt_crypto, but keeps at most [vBudgetBytes] of the 128*r*N-byte V array (time-memory
// trade-off), so parameters needing more RAM than the budget still work, just slower. Used for CryFS, whose
// official default settings need 512 MiB - 1 GiB.
bool scrypt_crypto_lowmem(const uint8_t* passphrase, size_t passphraseLen,
                          const uint8_t* salt, size_t saltLen,
                          uint32_t N, uint32_t r, uint32_t p,
                          uint8_t* out, size_t outLen, size_t vBudgetBytes);