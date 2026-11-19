#!/usr/bin/env python3
"""Generates prims_vectors.inc for prims_tests.cpp with implementations independent of the C++
code under test: hmac / hashlib from the Python standard library, AES from `cryptography`
(OpenSSL). Re-run it after changing the case lists:   python3 gen_prims_vectors.py > prims_vectors.inc

The RFC 6238 TOTP table is additionally asserted against the values published in the RFC, so a
broken generator cannot silently bless a broken implementation.
"""
import hashlib, hmac, random, struct, sys
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import padding

rng = random.Random(0xC0FFEE)
def rb(n): return bytes(rng.getrandbits(8) for _ in range(n))
def h(b): return b.hex()
out = []
def emit(s=""): out.append(s)

HASHES = {"sha1": hashlib.sha1, "sha256": hashlib.sha256, "sha512": hashlib.sha512}

# ---- HMAC: key lengths around the block sizes (64 / 128), data lengths around them ----
emit("struct HmacV { const char* hash; const char* key; const char* data; const char* mac; };")
emit("static const HmacV kHmac[] = {")
for name, fn in HASHES.items():
    for klen in (1, 16, 20, 63, 64, 65, 128, 129, 200):
        for dlen in (0, 8, 64, 300):
            key, data = rb(klen), rb(dlen)
            emit(f'    {{"{name}", "{h(key)}", "{h(data)}", "{h(hmac.new(key, data, fn).digest())}"}},')
emit("};")

# ---- RFC 6238 appendix B: TOTP, 8 digits ----
def hotp(key, counter, fn, digits=8):
    mac = hmac.new(key, struct.pack(">Q", counter), fn).digest()
    off = mac[-1] & 0x0F
    code = (struct.unpack(">I", mac[off:off+4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return f"{code:0{digits}d}"
seeds = {"sha1": b"12345678901234567890", "sha256": b"12345678901234567890123456789012",
         "sha512": b"1234567890123456789012345678901234567890123456789012345678901234"}
times = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000]
rfc = {  # published values, RFC 6238 appendix B
    59:           {"sha1": "94287082", "sha256": "46119246", "sha512": "90693936"},
    1111111109:   {"sha1": "07081804", "sha256": "68084774", "sha512": "25091201"},
    1111111111:   {"sha1": "14050471", "sha256": "67062674", "sha512": "99943326"},
    1234567890:   {"sha1": "89005924", "sha256": "91819424", "sha512": "93441116"},
    2000000000:   {"sha1": "69279037", "sha256": "90698825", "sha512": "38618901"},
    20000000000:  {"sha1": "65353130", "sha256": "77737706", "sha512": "47863826"},
}
emit("struct TotpV { const char* hash; const char* key; unsigned long long counter; const char* code; };")
emit("static const TotpV kTotp[] = {")
for t in times:
    for name, fn in HASHES.items():
        code = hotp(seeds[name], t // 30, fn)
        assert code == rfc[t][name], (t, name, code, rfc[t][name])   # certifies the generator
        emit(f'    {{"{name}", "{h(seeds[name])}", {t // 30}ULL, "{code}"}},')
emit("};")

# ---- PBKDF2 ----
emit("struct Pbkdf2V { const char* hash; const char* pw; const char* salt; unsigned iters; unsigned outLen; const char* dk; };")
emit("static const Pbkdf2V kPbkdf2[] = {")
cases = [
    (b"password", b"salt", 1, 20), (b"password", b"salt", 2, 20), (b"password", b"salt", 4096, 20),
    (b"passwordPASSWORDpassword", b"saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 25),
    (b"", b"salt", 10, 32), (b"p", b"s", 1, 1), (b"password", b"salt", 3, 100), (b"password", b"salt", 3, 130),
    (rb(100), rb(70), 1000, 64), (rb(7), rb(300), 777, 48),
]
for name in HASHES:
    for pw, salt, it, ol in cases:
        dk = hashlib.pbkdf2_hmac(name, pw, salt, it, ol)
        emit(f'    {{"{name}", "{h(pw)}", "{h(salt)}", {it}, {ol}, "{h(dk)}"}},')
emit("};")

# ---- AES-GCM (ciphertext || tag) ----
emit("struct GcmV { const char* key; const char* iv; const char* aad; const char* pt; const char* ctTag; };")
emit("static const GcmV kGcm[] = {")
for klen in (16, 32):
    for ivlen in (8, 12, 16, 60):
        for aadlen, ptlen in ((0, 0), (0, 1), (5, 16), (33, 17), (16, 100)):
            key, iv, aad, pt = rb(klen), rb(ivlen), rb(aadlen), rb(ptlen)
            ct = AESGCM(key).encrypt(iv, pt, aad if aad else None)
            emit(f'    {{"{h(key)}", "{h(iv)}", "{h(aad)}", "{h(pt)}", "{h(ct)}"}},')
emit("};")

# ---- AES-CBC PKCS#7 ----
emit("struct CbcV { const char* key; const char* iv; const char* pt; const char* ct; };")
emit("static const CbcV kCbc[] = {")
for klen in (16, 24, 32):
    for ptlen in (0, 1, 15, 16, 17, 31, 32, 100, 1000):
        key, iv, pt = rb(klen), rb(16), rb(ptlen)
        padder = padding.PKCS7(128).padder()
        padded = padder.update(pt) + padder.finalize()
        enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
        ct = enc.update(padded) + enc.finalize()
        emit(f'    {{"{h(key)}", "{h(iv)}", "{h(pt)}", "{h(ct)}"}},')
emit("};")

# ---- AES-CBC: ciphertexts whose plaintext has INVALID padding (encrypted without a padder) ----
key, iv = rb(16), rb(16)
def raw_cbc(block_plain):
    enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    return enc.update(block_plain) + enc.finalize()
bad = {
    "pad byte 0":        b"A" * 15 + b"\x00",
    "pad byte 17":       b"A" * 15 + b"\x11",
    "inconsistent pad":  b"A" * 13 + b"\x03\x02\x03",
    "pad longer than 1": b"A" * 15 + b"\x02",
}
emit("struct CbcBadV { const char* what; const char* key; const char* iv; const char* ct; };")
emit("static const CbcBadV kCbcBad[] = {")
for what, blk in bad.items():
    emit(f'    {{"{what}", "{h(key)}", "{h(iv)}", "{h(raw_cbc(blk))}"}},')
emit("};")

sys.stdout.write("// GENERATED by gen_prims_vectors.py -- do not edit by hand.\n" + "\n".join(out) + "\n")
