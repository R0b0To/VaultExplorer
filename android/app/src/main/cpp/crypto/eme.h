#pragma once

#include <cstddef>
#include <cstdint>

bool eme_transform(const uint8_t* key, size_t keyLen,
                   const uint8_t tweak[16],
                   const uint8_t* in, uint8_t* out, size_t len,
                   bool encrypt);