# LUKS compatibility suite (differential tests against upstream cryptsetup)

Compiles the **unmodified production sources** (`crypto/luks_header.cpp`, `luks_cipher.cpp`,
`cascade.cpp`, `cipher_shim.cpp`, ...) for the host and drives them side by side with the real
`cryptsetup` binary, so "compatible" means *both implementations agree on the same bytes*.

## Run

    # one-time: VeraCrypt sources at the commit pinned in CMakeLists.txt, and mbedTLS 3.6.x built
    export VC=/path/to/VeraCrypt/src
    export MBED=/path/to/mbedtls            # needs build/library/libmbedcrypto.a
    ./run_all.sh                            # FUZZ_N=250 (per format) is the default

Needs: `cryptsetup` >= 2.4 (root is not required for file images), `python3-cryptography`, `libgcrypt20`,
`libcjson-dev`, `libssl-dev`, g++/gcc. No kernel device-mapper is needed (and cryptsetup can then only
*create* AES volumes; Serpent/Twofish/Camellia are covered by `t_cipher.py` against libgcrypt instead).

## What each suite proves

| Suite | Direction / purpose |
|---|---|
| `t_cipher.py` | `luks_cipher` (XTS-128/256, CBC plain/plain64/essiv, 512..4096-byte units) vs Python `cryptography` and libgcrypt |
| `t_read.py` | cryptsetup **creates** (LUKS1/2, ciphers, hashes, PBKDF2/Argon2, sector sizes, 16 KiB..4 MiB metadata, keyslot-cipher options) -> app must recover the identical master key |
| `t_create.py` | app **creates** -> cryptsetup must dump, open, add/change keys, back up, repair it and agree on the master key |
| `t_ops.py` | multi-keyslot, kill-slot, priority `ignore`, damaged primary header, app password change then cryptsetup opens |
| `t_misc.py` | probe, data-segment offset, header repair/restore (also vs `cryptsetup repair`), LUKS2 fixed-size segment expansion |
| `t_crash.py` | password change interrupted after every possible write: volume must never be left without a working passphrase |
| `t_hostile.py` | crafted headers under ASAN/UBSan: no overflow, no allocation bomb, no hang |
| `t_fuzz.py` | JSON-aware mutation fuzzing (checksums repaired) of unlock + password change under ASAN/UBSan |

Not covered here (needs a Linux kernel with device-mapper): real dm-crypt data I/O, dm-integrity volumes.
