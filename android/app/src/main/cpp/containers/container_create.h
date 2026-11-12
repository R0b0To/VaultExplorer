#pragma once

#include <cstdint>
#include "usb_create_diagnostics.h"
#include "fs_grow.h"

// Creates a new VeraCrypt-format container at file descriptor [fd]:
// generates a salt and master key from /dev/urandom, builds and encrypts
// the volume header (primary + backup copy), zero-fills the data area,
// then formats the requested filesystem (fat/exfat/ntfs/ext2/ext3/ext4) on
// top of it. Behind NativeEngine's createContainerNative JNI call (see
// NativeEngine.kt).
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
                     const int* keyfileFds = nullptr, int keyfileCount = 0,
                     bool quickFormat = false);

// Creates a new LUKS1 or LUKS2 container at [fd]: generates a random
// master key, writes a fresh header + single occupied keyslot (see
// luksCreateHeader() in crypto/luks_header.h for the on-disk format
// details and the LUKS1-is-AES-only restriction), zero-fills the data
// area, then formats the requested filesystem (fat/exfat/ntfs/ext2/ext3/ext4)
// on top of it.
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
                         const int* keyfileFds = nullptr, int keyfileCount = 0,
                         bool quickFormat = false);

// Creates a new VeraCrypt-format USB container directly on the raw block
// device identified by [volId] (via UsbBlockBridge, see usb/UsbMassStorageDevice.kt),
// starting at [startSector] (typically 2048, i.e. right after the MBR
// written separately by writeMbrPartitionTable). Same header/zero-fill/
// format sequence as createContainer, adapted for a USB block target
// instead of a file descriptor.
//
// Returns a UsbCreateResult identifying exactly which phase failed (see
// usb_create_diagnostics.h) instead of a bare bool -- this used to return
// bool; the internal Kotlin<->JNI contract already reflects the new
// richer result (see NativeEngine.createUsbContainerNative's doc comment),
// this is the corresponding native-side change.
//
// [operationId]: opaque short string included in every LOGI line this
// function emits, so Kotlin and native logs for one createUsbContainer()
// call can be correlated in a bug report. Never used for anything other
// than logging.
UsbCreateResult createUsbContainer(int volId, uint64_t startSector, const char* password, int pim, int64_t sizeBytes,
                        const char* fileSystem, int cipherId, int hashId,
                        const int* keyfileFds = nullptr, int keyfileCount = 0, bool quickFormat = false,
                        const char* operationId = "",
                        uint32_t sectorSize = 512);   // the drive's logical sector size (512..4096): header field + file system sector size

UsbCreateResult createUsbLuksContainer(int volId, uint64_t startSector, const char* password, int pim, int64_t sizeBytes,
                            const char* fileSystem, int luksVersion, int cipherId, int hashId,
                            const int* keyfileFds = nullptr, int keyfileCount = 0, bool quickFormat = false,
                            const char* operationId = "");

UsbCreateResult createUsbContainerWithHidden(
    int volId, uint64_t startSector,
    const char* outerPassword, const char* hiddenPassword,
    int outerPim, int hiddenPim, int64_t sizeBytes,
    const char* outerFileSystem, const char* hiddenFileSystem,
    int64_t hiddenSizeBytes,
    int outerCipherId, int outerHashId,
    int hiddenCipherId, int hiddenHashId,
    const int* outerKeyfileFds = nullptr, int outerKeyfileCount = 0,
    const int* hiddenKeyfileFds = nullptr, int hiddenKeyfileCount = 0,
    bool quickFormat = false, const char* operationId = "",
    uint32_t sectorSize = 512);
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
                               const int* hiddenKeyfileFds = nullptr, int hiddenKeyfileCount = 0,
                               bool quickFormat = false);

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
                              const int* newKeyfileFds = nullptr, int newKeyfileCount = 0,
                              int newHashId = 255);   // 255 = keep the PRF the header was found with

// Rewraps a LUKS1/LUKS2 container's master key (whichever version [fd]
// already is, auto-detected) under a new password: unlocks with
// [oldPassword]/[oldKeyfileFds] exactly like unlocking normally would,
// then re-derives and re-encrypts that same active keyslot with a fresh
// salt under [newPassword]/[newKeyfileFds] — see luksChangeKeyslotPassword()
// in crypto/luks_header.h for exactly what does and doesn't change on
// disk. No PIM parameter: LUKS has no PIM concept (that's VeraCrypt-only),
// and cipher/hash are read directly from the container's own header/JSON
// metadata rather than passed in, unlike changeContainerPassword() above.
//
// oldKeyfileFds/newKeyfileFds: matches real `cryptsetup --key-file`
// semantics (see createLuksContainer's doc comment) — when present, the
// first keyfile's raw bytes REPLACE the corresponding typed password
// entirely rather than mixing with it.
//
// Returns 0 on success, 1 if the old password/keyfile didn't verify
// against any active keyslot, 2 on any other failure (I/O error, corrupt
// or unsupported header, etc.) — mirrors LuksChangePasswordResult so the
// JNI bridge can translate straight through without re-deriving the
// distinction itself.
//
// Always takes ownership of [fd] and all keyfile fds.
int changeLuksContainerPassword(int fd,
                                const char* oldPassword, const char* newPassword,
                                const int* oldKeyfileFds = nullptr, int oldKeyfileCount = 0,
                                const int* newKeyfileFds = nullptr, int newKeyfileCount = 0);

// ---- Volume expansion (VeraCrypt Volume Expander; containers/vc_expand.h) --------------------
enum class ExpandOutcome : int {
    kOk = 0, kWrongPassword = 1, kNotExpandable = 2, kNotLarger = 3, kIoError = 4, kBadKeyfile = 5,
};
// Result of the file-system step that can follow an expand (see growFileSystem below).
struct FsGrowReport {
    bool attempted = false;                      // false: not asked for, or the container step failed first
    FsGrowStatus status = FsGrowStatus::kFailed;
    char fsLabel[16] = {0};                      // "NTFS", "ext4", "exFAT", ... (empty if not recognised)
};
// Grows a standard VeraCrypt file container to [newSizeBytes] (rounded down to 4096): extends the file,
// initialises the new space under the volume key (or, [initFreeSpace] false, just wipes the old embedded
// backup header), rewrites the volume header with the new size and moves the embedded backup header to
// the new end. With [growFileSystem] (and [fsReport]) it then grows the file system inside into the added
// space where that is possible in place -- NTFS and ext2/3/4; see filesystems/fs_ops.h fsGrowToFit -- and
// reports what happened in [fsReport]; the container expansion itself stands either way. Always takes
// ownership of [fd] and the keyfile fds.
ExpandOutcome expandVeraCryptContainer(int fd, const char* password, int pim, int cipherId, int hashId,
                                       const int* keyfileFds, int keyfileCount,
                                       int64_t newSizeBytes, bool initFreeSpace,
                                       bool growFileSystem = false, FsGrowReport* fsReport = nullptr);
// Only the file-system step, for a standard volume that was expanded earlier (or by another program) and whose
// file system still ends where it did. Same ownership of [fd] and keyfile fds. kNotExpandable: not a plain
// full-size standard volume. kOk means the step ran; its result is in [fsReport].
ExpandOutcome growVeraCryptFileSystem(int fd, const char* password, int pim, int cipherId, int hashId,
                                      const int* keyfileFds, int keyfileCount, FsGrowReport* fsReport);

// ---- Hidden volume inside an EXISTING volume (VeraCrypt "direct mode") -------------------------------
enum class HiddenHostOutcome : int {
    kOk = 0, kWrongPassword = 1, kUnsupportedFs = 2, kNoSpace = 3, kIoError = 4, kBadKeyfile = 5, kInvalid = 6,
};
struct HiddenHostAnalysis {
    int fsKind = 0;                 // VcFsKind: 1 FAT12, 2 FAT16, 3 FAT32, 4 exFAT, 5 NTFS
    uint64_t clusterSize = 0;
    uint64_t maxHiddenBytes = 0;    // upstream's maximum hidden volume size for this outer volume (0 = no room)
};
// Opens the standard volume (read-only), reads its FAT/exFAT/NTFS cluster map and reports how large a hidden
// volume could be placed at its end. Takes ownership of [fd] and the keyfile fds.
HiddenHostOutcome analyzeHiddenVolumeHost(int fd, const char* password, int pim, int cipherId, int hashId,
                                          const int* keyfileFds, int keyfileCount, HiddenHostAnalysis* out);
// Creates a hidden volume of [hiddenSizeBytes] at the end of the existing standard volume: hidden header (and
// backup) under its own salt/keys, optional wipe, file system. The outer volume's own header and files are not
// touched. Takes ownership of [fd] and of both keyfile fd sets.
HiddenHostOutcome createHiddenVolumeInExisting(int fd,
                                               const char* outerPassword, int outerPim, int outerCipherId, int outerHashId,
                                               const int* outerKeyfileFds, int outerKeyfileCount,
                                               const char* hiddenPassword, int hiddenPim,
                                               const char* hiddenFileSystem, int64_t hiddenSizeBytes,
                                               int hiddenCipherId, int hiddenHashId,
                                               const int* hiddenKeyfileFds, int hiddenKeyfileCount,
                                               bool quickFormat);
