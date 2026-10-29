// Companion to ffi/compat/ff.h: upstream diskio.h pulls in ff.h through a sibling-relative
// `#include "ff.h"`, which would bypass the ff.h shim, so the same _WIN32 hiding is applied here.
#pragma once

#if defined(_WIN32)
#  pragma push_macro("_WIN32")
#  undef _WIN32
#  include_next "diskio.h"
#  pragma pop_macro("_WIN32")
#else
#  include_next "diskio.h"
#endif
