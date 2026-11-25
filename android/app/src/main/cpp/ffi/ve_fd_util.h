// Small helpers the C ABI translation units share (ve_tools.cpp, ve_repair.cpp, ve_composite.cpp): closing
// descriptors the call owns, checking a credential's pointer/length pairs, and a NUL-terminated password copy that
// is wiped when it goes out of scope. Header-only, like platform/file_identity.h.
#pragma once

#include <cstdint>
#include <string>

#if defined(_WIN32)
#  include <io.h>
#else
#  include <unistd.h>
#endif

#include <mbedtls/platform_util.h>

namespace veffi {

// Descriptors handed to a ve_* call belong to it from the moment it is entered; a call that refuses its arguments
// closes them itself so the caller never has anything left to track.
inline void closeFd(int32_t fd) {
    if (fd < 0) return;
#if defined(_WIN32)
    _close(fd);
#else
    close(fd);
#endif
}

inline void closeAll(const int32_t* fds, int32_t count) {
    if (!fds) return;
    for (int32_t i = 0; i < count; ++i) closeFd(fds[i]);
}

// A password given as (bytes, length) plus a keyfile descriptor list: every length is sane and no non-empty list is
// a null pointer.
inline bool credentialOk(const uint8_t* password, int32_t passwordLen, const int32_t* keyfileFds, int32_t keyfileCount) {
    return passwordLen >= 0 && (passwordLen == 0 || password != nullptr) && keyfileCount >= 0 &&
           (keyfileCount == 0 || keyfileFds != nullptr);
}

// A NUL-terminated copy of a password that is wiped when it goes out of scope (the engine takes C strings).
class SecretString {
public:
    SecretString(const uint8_t* bytes, int32_t len)
        : text_(bytes != nullptr ? reinterpret_cast<const char*>(bytes) : "",
                bytes != nullptr ? static_cast<size_t>(len) : 0) {}
    ~SecretString() {
        if (!text_.empty()) mbedtls_platform_zeroize(&text_[0], text_.size());
    }
    SecretString(const SecretString&) = delete;
    SecretString& operator=(const SecretString&) = delete;
    const char* c_str() const { return text_.c_str(); }
    // True when the bytes held a NUL, which a C string cannot carry (the password would be cut short at it).
    bool hasEmbeddedNul() const { return text_.find('\0') != std::string::npos; }

private:
    std::string text_;
};

}  // namespace veffi
