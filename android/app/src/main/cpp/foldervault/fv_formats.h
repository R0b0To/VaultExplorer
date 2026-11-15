// Format knowledge every host needs and none should copy: which file marks each vault format, how to tell a
// config file is genuine, what a "create" call defaults to. Kept next to the engines so an Android handler, a
// desktop front-end and the tests all read the same answer.
#pragma once

#include <string>

#include "fv_vault.h"

namespace fv {

// "gocryptfs" | "cryptomator" | "cryfs" -- the names the host UI layers use.
const char* formatWireName(VaultFormat format);
// Also accepts the legacy "directory_vault" (= Cryptomator). False for anything else.
bool formatFromWireName(const std::string& name, VaultFormat& out);

// The file in the vault folder's root that marks the format and that header backup saves and restores:
// "gocryptfs.conf" | "masterkey.cryptomator" | "cryfs.config".
const char* configFileName(VaultFormat format);

// True if [configFileName] exists as a regular file in the root of [storage]. A cheap probe, not a validation.
bool looksLikeVault(VaultFormat format, Storage& storage);

// Structural check of a config file's bytes, without a password: used before a backup is restored over a vault's
// config. On false, [reason] is a message fit for the user. CryFS's config is encrypted, so only its outer
// envelope (header, KDF parameter block, the fixed minimum size) can be judged.
bool validateConfigFile(VaultFormat format, const Bytes& content, std::string& reason);

// "aes-256-gcm" | "xchacha20-poly1305" | "aes-siv" (case-sensitive). Anything else, including empty, gives the
// default (AES-256-GCM): callers that predate the cipher choice keep working.
GocryptfsCipher gocryptfsCipherFromName(const std::string& name);

// Fills in defaults and clamps what a caller passed so a malformed request cannot produce a vault that cannot work:
// a cipher other than the two offered at creation time (xchacha20-poly1305, aes-256-gcm) falls back to
// xchacha20-poly1305; a block size outside [kCryfsMinBlockSize, kCryfsMaxBlockSize] (or <= 0) to the default.
// Hosts call this on user-supplied arguments. createCryfs deliberately does not: it must stay able to create
// vaults with the legacy ciphers (the tests do), which are not offered to users.
constexpr int kCryfsMinBlockSize = 4 * 1024;
constexpr int kCryfsMaxBlockSize = 64 * 1024 * 1024;
void normalizeCryfsCreateOptions(CryfsCreateOptions& options);

}  // namespace fv
