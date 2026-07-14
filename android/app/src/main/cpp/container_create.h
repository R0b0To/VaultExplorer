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
//
// keyfileFds/keyfileCount: same detach/ownership contract as elsewhere —
// every fd is closed exactly once (success or failure), either by
// applyKeyfilesToPassword() or by this function directly if it never gets
// that far. Keyfiles are mixed ADDITIVELY into the password (same as
// VeraCrypt's unlock-side behavior in prepareSession), including allowing
// an empty typed password when keyfiles alone are supplied — matching
// real VeraCrypt, which also allows a keyfile-only volume.
bool createContainer(int fd, const char* password, int pim, int64_t sizeBytes,
                     const char* fileSystem, int cipherId, int hashId,
                     const int* keyfileFds = nullptr, int keyfileCount = 0);

// Creates a new LUKS1 or LUKS2 container at [fd]: generates a random
// master key, writes a fresh header + single occupied keyslot (see
// luksCreateHeader() in crypto/luks_header.h for the on-disk format
// details and the LUKS1-is-AES-only restriction), zero-fills the data
// area, then formats an ext2/ext3/ext4 filesystem on top — LUKS containers
// are restricted to the ext family since that's the realistic pairing for
// a container the user intends to also mount on Linux.
//
// [luksVersion]: 1 or 2.
//
// cipherId/hashId: unlike VeraCrypt's 255-means-auto convention, these
// must both be concrete (non-255) here — container creation always knows
// exactly which algorithm it's using, there is no auto-detect at creation
// time. cipherId is restricted to the single-layer ciphers LUKS can
// express — AES(0)/Serpent(1)/Twofish(2)/Camellia(8)/Kuznyechik(9) — and
// that set is the same for luksVersion==1 and luksVersion==2: both
// luks1CreateHeader() and luks1Unlock() encrypt/decrypt the keyslot AF
// area with whatever cipher the container declares rather than assuming
// AES (see luksCreateHeader()'s doc comment), so LUKS1 is no longer
// restricted to AES-only. hashId is restricted to SHA-512(0)/SHA-256(1)/
// Argon2id(5) — Argon2id is only valid for luksVersion==2, since LUKS1 has
// no Argon2 support in the real spec.
//
// keyfileFds/keyfileCount: matches real `cryptsetup --key-file` semantics
// (also documented on prepareLuksSession in session_prepare.cpp) — when
// present, the first keyfile's raw bytes REPLACE the typed password
// entirely rather than mixing with it, and only the first keyfile is
// used.
//
// Always takes ownership of [fd] (closed before returning, regardless of
// outcome) and of every fd in [keyfileFds], matching the ownership
// convention used throughout this codebase.
bool createLuksContainer(int fd, const char* password, int pim, int64_t sizeBytes,
                         const char* fileSystem, int luksVersion, int cipherId, int hashId,
                         const int* keyfileFds = nullptr, int keyfileCount = 0);

// Creates a VeraCrypt container with an embedded hidden volume.
// The outer volume is created and formatted first, then a hidden volume
// header is written at VC_HIDDEN_HEADER_OFFSET (65536) with its own
// independently generated master key and salt. The hidden data area
// occupies the tail end of the container's data region. The hidden
// filesystem is formatted independently.
//
// cipherId/hashId apply to BOTH the outer and hidden volumes (matching
// real VeraCrypt, which always uses the same cipher/hash for both).
//
// Always takes ownership of [fd] and all keyfile fds.
bool createContainerWithHidden(int fd,
                               const char* outerPassword, const char* hiddenPassword,
                               int outerPim, int hiddenPim,
                               int64_t sizeBytes,
                               const char* outerFileSystem, const char* hiddenFileSystem,
                               int64_t hiddenSizeBytes,
                               int outerCipherId, int outerHashId,
                               int hiddenCipherId, int hiddenHashId,
                               const int* outerKeyfileFds = nullptr, int outerKeyfileCount = 0,
                               const int* hiddenKeyfileFds = nullptr, int hiddenKeyfileCount = 0);

// Re-encrypts a VeraCrypt container's header (primary + backup) with a
// new password and PIM. Decrypts the existing header using
// deriveAndValidateHeader() to recover the master key, then re-derives
// a fresh header key from the new password with a new random salt and
// re-encrypts the same header body.
//
// cipherId/hashId: 255 = auto-detect (tries all combinations against
// the existing header). When a match is found, the re-encrypted header
// uses the same cipher.
//
// Always takes ownership of [fd] and all keyfile fds.
bool changeContainerPassword(int fd,
                              const char* oldPassword, const char* newPassword,
                              int oldPim, int newPim,
                              int cipherId, int hashId,
                              const int* oldKeyfileFds = nullptr, int oldKeyfileCount = 0,
                              const int* newKeyfileFds = nullptr, int newKeyfileCount = 0);