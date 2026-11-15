# CryFS cross-implementation interop checks

These tools run **upstream CryFS's own code** (the Rust `cryfs` workspace, https://github.com/cryfs/cryfs) against
vaults written by this app's native core, and the app's native core against vaults written by upstream. They are
developer tools (not part of the app build or CI) and are what the interoperability claims in the CryFS code are
checked with. The older `cryfs_interop.sh` in this directory does the same against the real C++ binary through FUSE.

## Files

| File | Purpose |
|---|---|
| `interop_tool.cpp` | Driver around the app's native core: `create` a vault full of awkward content (empty file, single-leaf and depth-2 trees, a 300-entry directory, Unicode names, symlink, cross-directory move, directory rename, overwrite, delete), `dump` any vault to a manifest, `modify` an existing vault. Password is `mypassword`. |
| `upstream_interop_export.rs` | Test for upstream's `cryfs-check` crate: `export_vault_and_manifest` writes a vault with upstream's code and a manifest read back with upstream's reader; `dump_vault_manifest` re-opens any vault **with upstream's integrity records** and fails on any integrity violation. |
| `run_check.py` | Runs upstream's `cryfs-check` binary on a vault, answering its password prompt through a pty. |

A manifest has one line per entry: `D<TAB>path`, `F<TAB>path<TAB>size<TAB>sha256`, `L<TAB>path<TAB>target`, sorted.

## Running

1. Build `interop_tool` from the repo root (host build; mbedTLS 3.6 needed, see `foldervault/test/` for the source list
   the unit tests use): compile `interop_tool.cpp` together with `foldervault/*.cpp` (except tests), `crypto/{eme,siv,scrypt,
   xchacha20poly1305,cryfs_block_cipher,cryfs_legacy_ciphers}.cpp`, linked with `libmbedcrypto`.
2. In a checkout of upstream CryFS: copy `upstream_interop_export.rs` to `crates/check/tests/interop_export.rs`, add
   `sha2.workspace = true` under `[dev-dependencies]` of `crates/check/Cargo.toml`, and `cargo build -p cryfs-check`
   plus `cargo test -p cryfs-check --test interop_export --no-run`. Upstream needs Rust 1.95+ and OpenSSL headers.

**App writes, upstream reads**

    interop_tool create out/vault out/state aes-256-gcm 4096 > out/app_manifest.txt
    run_check.py out/vault out/checkstate                     # expect "Found 0 errors"
    INTEROP_DUMP=out/vault INTEROP_STATE=out/upstream_state INTEROP_OUT=out \
        cargo test -p cryfs-check --test interop_export dump_vault_manifest   # writes out/dump.txt
    diff out/dump.txt out/app_manifest.txt                    # expect no difference

**Upstream writes, app reads** (the fixture needs tiny blocks, so use the minimum: 118 for AES, 126 for XChaCha)

    INTEROP_CIPHER=xchacha20-poly1305 INTEROP_BLOCKSIZE=126 INTEROP_OUT=out2 \
        cargo test -p cryfs-check --test interop_export export_vault_and_manifest -- --nocapture
    interop_tool dump out2/vault out2/appstate > out2/app_dump.txt
    diff out2/expected.txt out2/app_dump.txt                  # only difference: upstream's empty-target symlink fixture

**Multi-client** (the app changes a vault upstream wrote; upstream then re-opens it with its own integrity records)

    interop_tool modify out2/vault out2/appstate_mod
    INTEROP_DUMP=out2/vault INTEROP_STATE=out2/state INTEROP_OUT=out2 cargo test ... dump_vault_manifest
    run_check.py out2/vault out2/state

`INTEROP_VERBOSE=1` makes `interop_tool` log per-directory/per-file timings, `INTEROP_ONLY=<path>` reads a single file.
