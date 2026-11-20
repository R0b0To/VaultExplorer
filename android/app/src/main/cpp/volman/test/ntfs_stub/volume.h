// Test-only stand-in for ntfs-3g's <volume.h>, for volman_block_test.
//
// The real header drags in ntfs-3g's <support.h>, which defines function-like macros
//     #define min(a,b) ((a) <= (b) ? (a) : (b))      (and the same for max)
// so any later std::min(x, y) in a translation unit that includes session/volume_state.h fails
// to compile ("expected unqualified-id"). That bit vm_block_volume.cpp once, because the plain
// host stub (filesystems/test/host_stubs/volume.h) has no such macros. This wrapper keeps the
// stub and adds the macros, so the same mistake fails here, on any machine, not only in the
// Android build. Write (std::min)(a, b) in code that sees volume_state.h.
#pragma once

#include "../../../filesystems/test/host_stubs/volume.h"

#ifndef min
#define min(a, b) ((a) <= (b) ? (a) : (b))
#endif
#ifndef max
#define max(a, b) ((a) >= (b) ? (a) : (b))
#endif
