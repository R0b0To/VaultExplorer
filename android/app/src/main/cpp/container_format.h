#pragma once

#include <cstdint>

// Stable cross-layer format identifiers.  These intentionally describe an
// on-disk container family rather than the crypto implementation selected to
// unlock it.  Keep values aligned with Kotlin's ContainerFormat.fromNative().
enum class ContainerFormat : uint8_t {
    kVeraCrypt = 0,
    kLuks1 = 1,
    kLuks2 = 2,
};
