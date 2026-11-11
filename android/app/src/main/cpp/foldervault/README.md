# foldervault -- gocryptfs, Cryptomator and CryFS in portable C++

The folder-vault engines of VaultExplorer. Platform-neutral C++20: **no JNI, no
Android, no Flutter**. On Android it is reached through `../jni/foldervault_bridge.cpp`;
on a desktop it links as-is (`test/fvcli.cpp` is a complete command-line
front-end and the harness behind the interop tests).

```
fv_vault.h        public API: fv::Vault (the VaultBackend method set), open/create/change-password
fv_storage.h      fv::Storage -- where the *encrypted* files live; PosixStorage = a plain directory
fv_common.h       Error/Secret/path helpers/codecs, the NFC + logging hooks
fv_crypto.*       RNG, hashes/HMAC/HKDF, AES key wrap/CTR, pooled AEAD (AES-GCM, XChaCha20), scrypt wrapper
fv_json.*         tiny JSON reader/writer (configs only)
fv_engine.*       chunked file engine shared by gocryptfs + Cryptomator (random-access reads, streaming writes, import/export)
fv_gocryptfs*     config, EME names, long names, AES-256-GCM / XChaCha20-Poly1305 / AES-SIV content, tree, session
fv_cryptomator*   masterkey + JWT, SIV names, .c9s shortening, SIV_GCM / SIV_CTRMAC content, tree, session
fv_cryfs*         config, block store + local integrity state, blob data tree, dir blobs, session
fv_pool.h         small worker pool (CryFS fan-out)
test/             fv_tests.cpp (unit/scenario/stress), fvcli.cpp, interop/ (real gocryptfs / Cryptomator / CryFS)
```

scrypt, EME, AES-SIV, XChaCha20-Poly1305 and the CryFS block cipher are the
existing `../crypto/` sources (shared with the rest of the engine), not copies.

## Using it

```cpp
auto storage = std::make_shared<fv::PosixStorage>("/path/to/vault");
fv::HostEnv env;  env.cryfsLocalStateDir = "~/.local/share/vaultexplorer/cryfs";   // CryFS only
auto r = fv::openGocryptfs(storage, pw, pwLen, /*readOnly*/ false, env);
if (r.status == fv::OpenStatus::Ok) {
    r.vault->listDirectory("", entries);
    r.vault->importStream("docs/a.txt", source, nullptr);
}
```

`create*` writes only the vault skeleton; unlock it with `open*` afterwards (that
two-step shape lets a host choose the *session* storage after it knows what is on
disk -- see `fv::StorageFactory`).

Build: the only third-party dependency is mbedTLS 3.x (BoringSSL/OpenSSL-style EVP is an optional
faster AEAD backend, `-DFV_AEAD_EVP=1`, which is what the Android build uses). The CMake targets
are `foldervault_core` (static library), `foldervault_test` and `fvcli` in `../CMakeLists.txt`.

## The storage contract

Everything the engines do to the disk goes through `fv::Storage` (paths relative to the
vault root, '/'-separated, `""` = root; implementations must be thread-safe). Two
implementations exist: `PosixStorage` and, on Android only, `JniStorage`, which forwards
each call to Kotlin's `FolderVaultStorage` (SAF documents, the local mirror and its
push/pull hooks -- `markWritePending`, `publishWrite`, `ensureContentReady`, ...). A
desktop front-end that wants another backend (cloud, SFTP) implements the same ~20 methods.

Hosts must also install, once: `fv::setNfcNormalizer` (Cryptomator file names are NFC
normalised before encryption; the core carries no Unicode tables -- Android installs
`java.text.Normalizer`, a desktop should install ICU/utf8proc; without it only
non-ASCII names that arrive in decomposed form are affected) and, optionally,
`fv::setLogger`.

## Testing

```
cmake --build <build> --target foldervault_test fvcli   # host build, no Android toolchain
ctest -R foldervault_test                               # 2455 checks, about a minute
FVCLI=<build>/fvcli CRYPTOMATOR_CLI=<cryptomator-cli> test/interop/run_all.sh   # real implementations over FUSE
test/interop/oracle/fetch_oracle.sh                     # once: the official cryptofs jars (needs a JDK 21)
FVCLI=<build>/fvcli test/interop/run_all.sh             # ...then also runs the cryptomator_{symlink,backup,migrate} cross-checks
```

`foldervault_test` has known-answer vectors from an independent implementation (Python
`cryptography`: HKDF, RFC 3394 key wrap, AES-GCM with 12/16-byte nonces, the AES-SIV
block layout, Cryptomator name encryption), a scenario run per format (random-access
reads across chunk boundaries, streamed + incremental writes, renames/moves/replaces,
Unicode and over-long names, deletes, mtimes, extraction), tamper detection, CryFS
rollback protection and legacy block names, password change, and multi-threaded stress.
It is clean under ASan/UBSan/LSan and TSan. The `interop/` scripts check the other
direction against the official software: gocryptfs 2.4 (all three ciphers + plaintext
names, `gocryptfs -fsck`), Cryptomator CLI 0.6.2 (format 8) and CryFS 0.11.4 (XChaCha20 and
AES-GCM, shallow and deep block trees). The `cryptomator_{symlink,backup,migrate}_interop.sh` scripts
drive the official `cryptofs` library directly (no FUSE) through `interop/oracle/Official.java` and
check both directions: symlinks (plain, shortened, unicode, 10k-character targets, move/delete/mtime),
key-file backup names, and the format 7 -> 8 migration against official's own `Version8Migrator`.
For gocryptfs there is a much wider differential test, described in the next section.

## gocryptfs: conformance with the official implementation

The gocryptfs engine is held to what the official implementation
(<https://github.com/rfjakob/gocryptfs>) does -- not merely to what it writes -- so a vault can be
shared with gocryptfs on a desktop and kept in sync by a file-sync tool.

**How it is checked**

* `foldervault_test`: every rule is transcribed from the official source (`internal/configfile`
  `Validate()` and scrypt checks, `nametransform`, `contentenc`, `fusefrontend`). The official example
  filesystems (`tests/example_filesystems`, MIT) are vendored in `test/vectors/gocryptfs/`: the vaults
  gocryptfs still mounts (v0.7 ... v2.2, with and without HKDF / Raw64 / long names, AES-GCM, AES-SIV,
  XChaCha20-Poly1305, plaintext names, `-deterministic-names`) must open, be readable and writable here, and
  accept a password change; the ones it refuses (v0.4 - v0.6) must be refused. Master keys and the padded
  long-name hash are known answers derived independently of this code.
* `test/interop/gocryptfs_official_compat.py`: a differential test against the real binary over FUSE, with
  gocryptfs' own view of the vault (names, sizes, SHA-256 of every file) as the oracle. **A**: vaults made by
  `gocryptfs -init` in nine flavours (GCM, `-aessiv`, `-xchacha`, `-plaintextnames`, `-deterministic-names`
  alone and with each cipher, `-longnamemax 62`, `-longnamemax 100 -deterministic-names`) are populated by
  gocryptfs, read here, modified here (every long-name transition: short/long x file/folder x
  rename/move/delete), and read back by gocryptfs; `gocryptfs -fsck` must pass. **B**: the same for vaults
  created here with every creation option, plus a comparison of the written `gocryptfs.conf` (flags, their
  order, `LongNameMax`, scrypt parameters) with what `gocryptfs -init` writes, and a password change.
  **C**: the example filesystems. **D**: the synchronisation scenario of issue #228 (two devices create the same
  folder offline; the ciphertext is merged). **E**: damaged ciphertext -- conflict copies, non-canonical
  base64, bad `.name` files, all-zero / short / missing diriv -- where both implementations must list exactly the
  same entries. It passes against gocryptfs master and against 2.4.0, apart from non-canonical base64 names, which
  2.4.0 still accepted.
* The tests themselves were mutation-checked: 39 deliberate re-introductions of the old behaviour, 37 caught;
  the two survivors are equivalent (an all-zero header is also refused by the version check, and a sidecar
  over 344 bytes can never decrypt to a legal name).

**What is supported**

| | |
|---|---|
| Content | AES-256-GCM, XChaCha20-Poly1305, AES-SIV |
| Names | encrypted (EME, Raw64 or padded base64, random per-folder `gocryptfs.diriv` **or** `-deterministic-names`), plaintext |
| Long names | `gocryptfs.longname.*` with the default 255 or `-longnamemax` 62..255 |
| Older vaults | without `HKDF` (gocryptfs 0.7 - 1.2: master key used as-is, 96-bit key-wrap nonce, AES-SIV key = SHA-512) and without `Raw64` (<= 1.6: padded base64 for names and long-name hashes) |
| Create | cipher, plaintext names, `-deterministic-names`, `-longnamemax`, `-scryptn` (`GocryptfsCreateOptions`) |
| Not supported | **FIDO2**-protected vaults (refused with an explanation, not "wrong password"); `-reverse` (nothing on disk to open); v0.4 - v0.6 (gocryptfs refuses them too) |

**Matches gocryptfs**

* `gocryptfs.conf` is validated like `ConfFile.Validate()`: the known-flag list (`LongNameMax`, `FIDO2` included), the
  cipher / plaintext / `LongNameMax` consistency rules, scrypt `N >= 1024` (power of two), `R >= 8`, `P >= 1`, a
  salt of at least 32 bytes. `HKDF`, `EMENames`, `Raw64` and `LongNames` are *not* required, as in gocryptfs.
* Names: `IsValidName` (1..255 bytes, no `/` or NUL, not `.`/`..`; newlines and U+FFFD are fine) and strict base64
  -- a name that merely *decodes* to the same bytes is not one of gocryptfs' names.
* Listing: `gocryptfs.conf` is hidden in the root only (with plaintext names it, and only it, is reserved and cannot
  be created over); `gocryptfs.diriv` and `.name` sidecars are special only with encrypted names; with plaintext
  names `data.name`, `gocryptfs.diriv` and the like are ordinary files.
* A `gocryptfs.diriv` is exactly 16 bytes and not all zero. Listing a folder re-reads it every time; lookups use a
  cache that expires after 60 s (gocryptfs' `dircache`), and a refresh of a folder drops it. A folder that has no
  diriv is reported, **never** given a made-up one. Sidecars are 1..344 bytes. A file header must not be all-zero and
  must not carry an all-zero file id.
* Order and rollback: `mkdir` writes the sidecar, the folder, then the diriv, `create` the sidecar then the file,
  `rename` the new sidecar then the rename -- each step undone if a later one fails, so no half-made folder or orphan
  sidecar is left. Making an entry over something this app does not show (a symlink) fails with "exists", as in
  gocryptfs, instead of writing through it.
* A password change re-wraps the key the way the vault's own flags say, so older vaults stay unlockable by gocryptfs.

**Deliberate differences**

* gocryptfs symlinks are not shown or followed (unlike Cryptomator's, which are supported -- see below). They stay in
  the ciphertext untouched and are removed with their folder.
* A name that is not well-formed UTF-8 cannot be a Java/Dart string, so such an entry is not shown. gocryptfs
  allows any bytes.
* `gocryptfs.conf.bak` in the root is hidden: it is the backup Check & Repair keeps, not a gocryptfs file.
* No `-badname` mode, extended attributes, hard links or special files.

**Synchronised ciphertext.** Create the vault with `-deterministic-names` (here:
`GocryptfsCreateOptions::deterministicNames`, "Filenames: Deterministic" in the create dialog): there are no
`gocryptfs.diriv` files, so a folder that two devices create offline is the *same* folder on both and a sync tool merges
their contents. With random dirivs the two `gocryptfs.diriv` files conflict, one wins, and every name written under the
other is unreadable -- in gocryptfs and here alike (test phase D shows both). Changes made behind the app's back are
picked up by pull-to-refresh (listing, lookups and open read handles below the folder), not live.

**Fixed along the way** (each found by the differential test or while reading the official code)

* `deleteFile` of a cleartext path that does not exist could delete a *physical* file of that name -- in an
  encrypted vault `gocryptfs.conf` or `gocryptfs.diriv`.
* Names containing `\n`, `\r` or U+FFFD, and empty names, were hidden / accepted contrary to gocryptfs; names over
  255 bytes could be created although gocryptfs cannot read them.
* Plaintext-names vaults: `*.name`, `gocryptfs.diriv`, `gocryptfs.longname.*` and the config name were mishandled in
  listings (one entry was shown under the wrong name), and a file named `gocryptfs.conf` could be written over the
  config.
* A refresh left open read handles below the folder stale; an existing folder without a diriv was silently given a
  new random one (which would orphan the names written under the real one once it arrived); a failed `mkdir`
  could leave a folder without its diriv.

## Where this differs from the Kotlin it replaced

Deliberate, each one verified against the real client where one exists:

* **CryFS block files are named in UPPERCASE hex**, as the official CryFS does. The old code
  wrote lowercase, which only worked because Android's emulated storage is
  case-insensitive; on a case-sensitive filesystem (a desktop, an ext4 SD card, a vault synced
  from Android) CryFS could not see those blocks. New blocks are uppercase; lowercase
  files of existing vaults are still read, overwritten in place and deleted. The integrity
  state keys stay lowercase so existing installs keep their recorded versions.
* **Cryptomator `dirid.c9r` holds the directory's own id.** The old code stored the parent's
  id there. Checked by creating directories only through the real Cryptomator and decoding
  what it wrote. Backups already written by the old code are left as they are.
* **A failed or cancelled write no longer leaves a truncated encrypted file** under the final name.
* **`renameFile` onto an existing file replaces it** (POSIX semantics) for all three formats;
  CryFS used to create a duplicate entry. Moving a folder into itself is refused.
* **Cryptomator deletes a directory's sub-directories' backing folders too** (they live
  elsewhere under `d/`, so deleting only the node orphaned them), and resolves a name with one
  encrypt + stat instead of decrypting the whole directory (a scan remains as fallback for
  non-ASCII names).
* **CryFS**: new blocks no longer fsync the integrity log (overwrites still do; the official CryFS
  does not either), leaf blocks are deleted without being decrypted, large reads decrypt in
  parallel, scratch files for incremental writes are unlinked immediately.
* gocryptfs: the scrypt `P` comes from the config; the all-zero "hole" shortcut also applies on the bulk path.
* `crypto/siv.cpp`: one `memcpy(…, nullptr, 0)` guarded (found by UBSan; the old Kotlin hit it too).

* **Cryptomator symlinks** (`isSymlink`, `listSymlinks`, `readSymlink`, `createSymlink`): a link is a node
  folder holding `symlink.c9r` (target, UTF-8, encrypted like file content), found with official's precedence
  (`dir.c9r`, then `symlink.c9r`, then `contents.c9r`). Links are **never part of `listDirectory`** (they are neither
  files nor folders, so sync/export/scanners cannot accidentally recurse through one). The interactive browser
  merges them as shortcut entries. Relative targets are resolved inside the same vault for reads, writes and
  directory traversal, with a 40-link hop limit (so cycles fail closed); absolute targets are refused. Delete and
  rename operate on the link node itself, while mtime follows the target. We are stricter than
  official in one place: a target is limited to 32767 *bytes* (official checks 32767 characters when creating but
  refuses more than 32767 bytes when reading, so it can create a link it cannot read back), and an empty,
  NUL-containing or malformed-UTF-8 target is refused.
* **Cryptomator `hiddenEntryCount`**: number of entries that exist on disk but are not listed (sync-conflict copies
  such as `name (1).c9r`, names that no longer authenticate, half-synced nodes). Dot-files, the internal
  `dir.c9r`/`dirid.c9r` and foreign files are not counted, like official ignores them. Counted during the normal
  listing pass, so asking for it is free. These entries are still not shown or resolved -- that is future work.
* **Cryptomator key-file backups on open** (`HostEnv::backupKeyFilesOnOpen`, default on, read-write opens only):
  `vault.cryptomator` and `masterkey.cryptomator` are copied to `<file>.<8 hex>.bkup` exactly as official does;
  an existing backup is verified, never overwritten, and a failed backup never blocks the unlock.
* **Cryptomator 7 -> 8 migration** (`migrateCryptomator7To8`): backs up the key file, writes a signed
  `vault.cryptomator`, re-saves the key file as version 999. One way. It refuses anything that is not a genuine
  format 7 vault (including a format 8 key file whose `vault.cryptomator` has not synced yet) and, unlike
  official, aborts before changing anything if the backup cannot be written.

Not migrated: `foldercheck/` (Check & Repair) keeps running on the Kotlin primitives and gets a live
session's keys from `NativeVaultSession.keyMaterial()`; `looksLikeVault` probes stay in Kotlin. Those primitives
(`GocryptfsConfig`, `GocryptfsMasterkey`, `GocryptfsFileNameCryptor`) follow the same rules as the engine above
(pre-HKDF / pre-Raw64 vaults, `LongNameMax`, strict base64, FIDO2 refused); their unit tests include the same
official-vector known answers.
