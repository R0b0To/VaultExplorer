// crypto/keyfile_mixing.h
//
// Faithful reimplementation of upstream VeraCrypt's keyfile "pool mixing"
// algorithm (Common/Keyfiles.c: KeyFileProcess / KeyFilesApply, in the
// vendored reference sources attached to this project). This is NOT a KDF
// — it's a deterministic, order-dependent whitening step applied to the
// raw password BEFORE that (possibly-extended, possibly-binary) password
// is handed to PBKDF2. Any deviation here (pool size selection, per-keyfile
// CRC state reset, additive-not-XOR mixing, the final combine-into-password
// step) silently produces a different derived key than real VeraCrypt (or
// this app's desktop counterpart) would produce for the same
// password+keyfiles — i.e. a container that looks like "wrong password"
// even though the password is correct. Do not simplify this.
#pragma once
#include <cstddef>
#include <cstdint>

// Mirror the vendored Keyfiles.h constants of the same names exactly.
static constexpr size_t KEYFILE_POOL_LEGACY_SIZE = 64;
static constexpr size_t KEYFILE_POOL_SIZE        = 128;
static constexpr size_t KEYFILE_MAX_READ_LEN     = 1024 * 1024;

// VeraCrypt's historical (TrueCrypt-era) maximum password length; used
// only to select which keyfile pool size applies (Keyfiles.c:
// "password->Length <= MAX_LEGACY_PASSWORD ? ... : ...").
static constexpr size_t MAX_LEGACY_PASSWORD = 64;

// Current VeraCrypt maximum password length. The mixed password buffer
// this app builds is capped here; anything the keyfile pool would write
// past this index is simply not applied (matches upstream: password->Text
// is a fixed-size buffer of this length).
static constexpr size_t MAX_PASSWORD_LEN = 128;

// Mixes the readable contents of keyfileFds[0..keyfileCount) into
// [password]/[passwordLen] IN PLACE, exactly matching KeyFilesApply()'s
// keyfile-pool step followed by its "mix pool into password" step.
//
//  - [password] must point at a buffer of at least MAX_PASSWORD_LEN bytes.
//  - [passwordLen] is both the CURRENT password length in [password] and
//    an out-param: it may grow (never shrink) if the keyfile pool is
//    larger than the original password, exactly as upstream does
//    ("if (password->Length < keyPoolSize) password->Length = keyPoolSize;").
//  - After this call [password] is arbitrary binary data. It can
//    legitimately contain embedded 0x00 bytes and MUST NOT be treated as a
//    C string from here on — always carry it around with [passwordLen]
//    explicitly, never strlen().
//  - Every fd in [keyfileFds] is read once and then CLOSED by this
//    function, matching this codebase's existing single-use-fd convention
//    for descriptors crossing the JNI boundary (see e.g.
//    createContainerNative's `close(fd)`). Callers should hand over fds
//    obtained via e.g. ParcelFileDescriptor.detachFd() on the Kotlin side.
//  - Returns false if keyfileCount > 0 and ANY keyfile could not be read
//    (bad fd, permission error, or a genuinely empty file — upstream
//    treats a 0-byte keyfile as ERR_HANDLE_EOF, a hard error, and so do
//    we). On false, [password]/[passwordLen] are left untouched and the
//    caller should treat the whole unlock attempt as failed rather than
//    silently proceeding without the keyfile's contribution.
bool applyKeyfilesToPassword(const int* keyfileFds, int keyfileCount,
                              unsigned char* password, size_t* passwordLen);
