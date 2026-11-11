# gocryptfs example filesystems (test vectors)

Verbatim copies of `tests/example_filesystems/*` from the official gocryptfs
repository (<https://github.com/rfjakob/gocryptfs>, MIT licence, see
`LICENSE.gocryptfs`). The password of every vault is `test`.

They are the on-disk formats the *official* implementation promises to keep
mounting (v0.7 ... v2.2: with and without HKDF / Raw64 / LongNames, AES-GCM,
AES-SIV, XChaCha20-Poly1305, plaintext names, `-deterministic-names`) and
the ones it deliberately refuses (v0.4 - v0.6, "too old").

`fv_tests.cpp` (testGocryptfsOfficialVectors) copies each vault to a scratch
directory before touching it, so these files are never modified.

Every vault contains `status.txt` ("It works!\n"). Most also hold a
255-byte long-name file, and some have symlinks, which this app does not
show (the Android storage model has no symlinks) but leaves untouched.
