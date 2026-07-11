#pragma once

#include <cstdint>

// Creates a new VeraCrypt-format container at file descriptor [fd]:
// generates a salt and master key from /dev/urandom, builds and encrypts
// the volume header (primary + backup copy), zero-fills the data area,
// then formats the requested filesystem (fat/exfat/ntfs/ext2/ext3/ext4) on
// top of it. Behind VeraCryptEngine's createContainerNative JNI call (see
// VeraCryptEngine.kt).
//
// Always takes ownership of [fd]: it is closed before this function
// returns, regardless of outcome (synced first on success). Matches the fd
// ownership convention already used by prepareSession/prepareUsbSession in
// session_prepare.h.
//
// cipherId/hashId: 255 = auto, which defaults to AES + SHA-512.
bool createContainer(int fd, const char* password, int pim, int64_t sizeBytes,
                     const char* fileSystem, int cipherId, int hashId);