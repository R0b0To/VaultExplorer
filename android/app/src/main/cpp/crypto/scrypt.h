#pragma once

#include <cstddef>
#include <cstdint>

bool scrypt_crypto(const uint8_t* passphrase, size_t passphraseLen,
                   const uint8_t* salt, size_t saltLen,
                   uint32_t N, uint32_t r, uint32_t p,
                   uint8_t* out, size_t outLen);