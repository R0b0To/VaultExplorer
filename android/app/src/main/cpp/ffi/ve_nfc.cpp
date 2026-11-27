// Unicode NFC for the desktop engine.
//
// Cryptomator stores every file name NFC-normalised, so the same name typed or imported in a decomposed form
// ("e" + U+0301) and in a composed one (U+00E9) must be one file. The folder-vault core (foldervault/fv_common.h)
// cannot carry the Unicode tables and leaves non-ASCII names untouched until the host installs a normaliser:
// on Android that is java.text.Normalizer (jni/foldervault_bridge.cpp), here it is utf8proc.
//
// Installed when the library loads, before any vault can be opened. Pure-ASCII names never reach it
// (fv::nfc() returns them as they are).

#include <utf8proc.h>

#include <cstdlib>
#include <string>

#include "foldervault/fv_common.h"

namespace {

std::string nfcViaUtf8proc(const std::string& utf8) {
    utf8proc_uint8_t* out = nullptr;
    const utf8proc_ssize_t n = utf8proc_map(
        reinterpret_cast<const utf8proc_uint8_t*>(utf8.data()), static_cast<utf8proc_ssize_t>(utf8.size()), &out,
        static_cast<utf8proc_option_t>(UTF8PROC_STABLE | UTF8PROC_COMPOSE));
    if (n < 0 || !out) {  // not valid UTF-8 (or out of memory): leave the name as it is, as with no normaliser
        std::free(out);
        return utf8;
    }
    std::string result(reinterpret_cast<const char*>(out), static_cast<size_t>(n));
    std::free(out);
    return result;
}

[[maybe_unused]] const bool g_nfcInstalled = (fv::setNfcNormalizer(&nfcViaUtf8proc), true);

}  // namespace
