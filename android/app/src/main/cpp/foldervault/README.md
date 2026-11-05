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

gocryptfs security-key (`-fido2`) vaults need no separate entry point: the host performs the CTAP2
hmac-secret exchange itself and passes the raw 32-byte output as the "password" bytes (`fv::Config::fido2`
carries the credential id / salt / assert options the host needs; `GocryptfsCreateOptions::fido2` makes
`createGocryptfs` write the `FIDO2` flag and section, and `changeGocryptfsPassword` refuses such a vault).

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
ctest -R foldervault_test                               # 1291 checks, ~1 min
FVCLI=<build>/fvcli CRYPTOMATOR_CLI=<cryptomator-cli> test/interop/run_all.sh   # real implementations over FUSE
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
AES-GCM, shallow and deep block trees).

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

Not migrated: `foldercheck/` (Check & Repair) keeps running on the Kotlin primitives and gets a live
session's keys from `NativeVaultSession.keyMaterial()`; `looksLikeVault` probes stay in Kotlin.
