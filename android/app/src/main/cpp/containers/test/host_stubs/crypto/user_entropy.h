#pragma once
// Host-test stand-in for crypto/user_entropy.h: declaration only; each test
// supplies its own userentropy::fillRandom (deterministic, with a failure switch).
#include <cstddef>
#include <cstdint>
namespace userentropy {
bool fillRandom(uint8_t* buf, size_t len);
}
