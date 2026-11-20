# crypto/prims tests

`prims_tests.cpp` checks `../prims.cpp` against `prims_vectors.inc`, which is **generated** by
`gen_prims_vectors.py` using implementations independent of the code under test (Python `hmac` /
`hashlib`, and `cryptography` for AES). Regenerate after changing the case lists:

    python3 gen_prims_vectors.py > prims_vectors.inc

The generator asserts its RFC 6238 TOTP table against the values published in the RFC, so a broken
generator cannot silently bless a broken implementation. Needs `pip install cryptography`.
