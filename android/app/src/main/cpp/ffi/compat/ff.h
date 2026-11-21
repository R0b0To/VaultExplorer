// Shim for FatFs's ff.h on Windows (MinGW) -- a plain pass-through everywhere else.
//
// Upstream ff.h has a "Windows VC++ (for development only)" branch keyed on _WIN32 that
// #includes <windows.h>. Pulling windows.h into the engine breaks every translation unit that
// also sees the ntfs-3g headers (BOOL typedef, DELETE / FILE_ATTRIBUTE_* macros vs. layout.h
// enums, wincrypt's X509_NAME vs. BoringSSL, ...). While upstream's ff.h is parsed we therefore
// hide _WIN32 so it takes its portable C99 branch (<stdint.h>-based types).
#pragma once

#if defined(_WIN32)
#  pragma push_macro("_WIN32")
#  undef _WIN32
#  include_next "ff.h"
#  pragma pop_macro("_WIN32")
#else
#  include_next "ff.h"
#endif
