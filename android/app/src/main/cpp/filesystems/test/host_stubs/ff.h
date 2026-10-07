// Host-test stand-in for FatFs's ff.h: only the names ext_backend.cpp and
// session/volume_state.h need to compile (BYTE/UINT/LBA_t, FF_VOLUMES, and
// FATFS/FIL as opaque members of VolumeState). Not a FatFs implementation.
#pragma once
#include <cstdint>
#define FF_VOLUMES 8
typedef unsigned char BYTE;
typedef unsigned int UINT;
typedef uint32_t DWORD;
typedef uint64_t LBA_t;
typedef struct { int dummy; } FATFS;
typedef struct { int dummy; } FIL;
