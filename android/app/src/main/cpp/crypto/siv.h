#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

bool siv_encrypt(const uint8_t* encKey, size_t encKeyLen,
                 const uint8_t* macKey, size_t macKeyLen,
                 const uint8_t* plaintext, size_t plaintextLen,
                 const std::vector<std::vector<uint8_t>>& adList,
                 uint8_t* out, size_t outLen);

bool siv_decrypt(const uint8_t* encKey, size_t encKeyLen,
                 const uint8_t* macKey, size_t macKeyLen,
                 const uint8_t* ciphertext, size_t ciphertextLen,
                 const std::vector<std::vector<uint8_t>>& adList,
                 uint8_t* out, size_t outLen);