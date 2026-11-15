// Check & Repair for folder vaults (gocryptfs, Cryptomator, CryFS).
//
// Platform-neutral like the rest of foldervault/: everything the tool does to a vault goes through fv::Storage
// (paths relative to the vault root), so the same code runs over PosixStorage on a desktop and over the SAF /
// mirror storage on Android. No JNI, no Android, no Flutter.
//
//  * check  -- read-only. Structure only (no credentials), or a deep scan that also decrypts every file name and
//              authenticates every file header and chunk (password or an unlocked Vault as credentials).
//  * repair -- gocryptfs and Cryptomator only (CryFS has no repair). Needs credentials. Never deletes data that
//              could still be recovered: entries that cannot be placed back into the tree are moved into a
//              /LOST+FOUND folder inside the vault, under a fresh name that the vault can read.
//
// Credentials: a password (UTF-8 bytes, the caller keeps ownership and wipes it) or an unlocked fv::Vault of the
// same vault. With a Vault its keys are used instead of deriving them again (no scrypt run) and its caches are
// invalidated after a repair; the keys are read through Vault::exportKeys() and never leave this process.
#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "fv_vault.h"

namespace fv::check {

// The numeric values are part of the host contract (the Android UI receives them as ints).
enum class Severity { Info = 0, Warning = 1, Critical = 2 };

struct Issue {
    Severity severity = Severity::Info;
    std::string path;      // cleartext path inside the vault, '/'-separated with a leading '/'; "/" = the root
    std::string message;
};

// How a call ended. For anything but Ok, CheckResult/RepairResult::message says why.
enum class Outcome { Ok, InvalidVault, WrongPassword };

struct CheckReport {
    VaultFormat format = VaultFormat::Gocryptfs;
    int filesScanned = 0;       // files looked at (Cryptomator without credentials: backing folders found)
    bool deepScan = false;      // names and file contents were authenticated, not just the layout
    std::vector<Issue> issues;
    // No warning and no critical issue (Info entries do not count).
    bool healthy() const {
        for (const Issue& i : issues) if (i.severity != Severity::Info) return false;
        return true;
    }
};

struct CheckResult {
    Outcome outcome = Outcome::InvalidVault;
    std::string message;
    CheckReport report;         // meaningful when outcome == Ok
};

struct RepairReport {
    VaultFormat format = VaultFormat::Gocryptfs;
    int fixed = 0;              // broken metadata put right in place (diriv, dir.c9r, config, header, ...)
    int recovered = 0;          // entries moved into /LOST+FOUND
    int removed = 0;            // empty or meaningless leftovers deleted
    std::vector<Issue> remaining;   // what a fresh check still finds after the repair
    bool healthy() const {
        for (const Issue& i : remaining) if (i.severity != Severity::Info) return false;
        return true;
    }
};

struct RepairResult {
    Outcome outcome = Outcome::InvalidVault;
    std::string message;
    RepairReport report;        // meaningful when outcome == Ok
};

struct Credentials {
    // Raw UTF-8 password. nullptr: a check runs structure-only; a repair is refused (WrongPassword).
    const uint8_t* password = nullptr;
    size_t passwordLen = 0;
    // An unlocked Vault of this vault (same format). Takes precedence over [password].
    Vault* session = nullptr;
};

struct Hooks {
    // Step-by-step progress for a live log panel, UTF-8. Called on the calling thread only.
    std::function<void(const std::string&)> log;
};

// [env] is only read for CryFS (cryfsLocalStateDir, tempDir).
CheckResult checkVault(VaultFormat format, Storage& storage, const Credentials& creds, const HostEnv& env,
                       const Hooks& hooks = {});
RepairResult repairVault(VaultFormat format, Storage& storage, const Credentials& creds, const HostEnv& env,
                         const Hooks& hooks = {});

// "gocryptfs" | "cryptomator" | "cryfs" -- the names the host and the Dart layer use.
const char* formatWire(VaultFormat format);

}  // namespace fv::check
