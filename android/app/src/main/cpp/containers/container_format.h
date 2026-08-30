#pragma once

#include <cstdint>

// Stable cross-layer format identifiers.  These intentionally describe an
// on-disk container family rather than the crypto implementation selected to
// unlock it.  Keep values aligned with Kotlin's ContainerFormat.fromNative().
enum class ContainerFormat : uint8_t {
    kVeraCrypt = 0,
    kLuks1 = 1,
    kLuks2 = 2,
    kBitLocker = 3,
    // No encryption layer at all -- the container's virtual disk (or a
    // partition within it) carries a directly-recognizable FAT/exFAT/NTFS/
    // ext filesystem. Currently only reachable via a VHD/VHDX whole-disk
    // image (see session_prepare.cpp's plain-VHD/VHDX fallback); disk_read/
    // disk_write, ntfsPread/ntfsPwrite, and the ext2 io_manager all treat
    // this as "pass the bytes through, don't run them through a cascade".
    kPlain = 4,
};