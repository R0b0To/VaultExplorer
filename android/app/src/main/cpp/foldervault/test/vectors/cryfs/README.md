# CryFS interop vectors

`cpp_0_11_config.bin` is a `cryfs.config` written by the official **C++** CryFS 0.11.3
(scrypt N=2^20, r=4, p=8, xchacha20-poly1305, 16 KiB blocks), password `mypassword`.
It is taken verbatim from the upstream test suite
(`crates/cryfs-config/src/config/encryption/mod.rs` in https://github.com/cryfs/cryfs).

Run it explicitly (about 20 s and 512 MiB of RAM, so it is not part of the default run):

    fv_test cryfs-vector
