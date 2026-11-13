# Independent verification of luks_cipher against Python `cryptography` (AES) and libgcrypt (serpent/twofish/camellia).
import ctypes, ctypes.util, os, struct, hashlib, random, subprocess, sys
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from common import HARNESS
random.seed(1234)
gc = ctypes.CDLL(ctypes.util.find_library("gcrypt") or "libgcrypt.so.20")
gc.gcry_check_version(None)
GC = {"serpent": 306, "twofish": 10, "camellia": 312}  # SERPENT256=306, TWOFISH=10 (256-bit), CAMELLIA256=312 (verified via gcry_cipher_algo_name)
class GcEcb:
    def __init__(self, algo, key, enc):
        self.h = ctypes.c_void_p(); self.enc = enc
        assert gc.gcry_cipher_open(ctypes.byref(self.h), GC[algo], 1, 0) == 0   # mode 1 = ECB
        assert gc.gcry_cipher_setkey(self.h, key, len(key)) == 0
    def blk(self, b):
        out = ctypes.create_string_buffer(16)
        f = gc.gcry_cipher_encrypt if self.enc else gc.gcry_cipher_decrypt
        assert f(self.h, out, 16, b, 16) == 0; return out.raw
def ecb_fn(cipher, key, enc):
    if cipher == "aes":
        c = Cipher(algorithms.AES(key), modes.ECB()); x = c.encryptor() if enc else c.decryptor()
        return lambda b: x.update(b)
    g = GcEcb(cipher, key, enc); return g.blk
def xor(a, b): return bytes(x ^ y for x, y in zip(a, b))
def gf_mul(t):
    v = int.from_bytes(t, "little"); carry = v >> 127; v = (v << 1) & ((1 << 128) - 1)
    if carry: v ^= 0x87
    return v.to_bytes(16, "little")
def ref_iv(sector, mode, key, cipher):
    if mode.endswith("plain"): return struct.pack("<I", sector & 0xFFFFFFFF) + b"\0"*12
    iv = struct.pack("<Q", sector) + b"\0"*8
    if mode.endswith("essiv:sha256"): return ecb_fn(cipher, hashlib.sha256(key).digest(), True)(iv)
    return iv
def ref_crypt(cipher, mode, key, iv512, ss, enc, data):
    out = b""
    chain = mode.split("-")[0]
    for s in range(len(data)//ss):
        blk = data[s*ss:(s+1)*ss]; sec = iv512 + s*(ss//512); iv = ref_iv(sec, mode, key, cipher)
        if chain == "xts":
            h = len(key)//2; e = ecb_fn(cipher, key[:h], enc); t = ecb_fn(cipher, key[h:], True)(iv); o = b""
            for i in range(0, ss, 16): o += xor(e(xor(blk[i:i+16], t)), t); t = gf_mul(t)
            out += o
        else:
            e = ecb_fn(cipher, key, enc); o = b""; prev = iv
            for i in range(0, ss, 16):
                p = blk[i:i+16]
                if enc: c = e(xor(p, prev)); o += c; prev = c
                else: o += xor(e(p), prev); prev = p
            out += o
    return out
def app(cipher, mode, key, iv512, ss, enc, data):
    r = subprocess.run([HARNESS, "cipher", cipher, mode, key.hex(), str(iv512), str(ss), "enc" if enc else "dec", data.hex()], capture_output=True, text=True)
    return r.stdout.strip()
fails = 0; n = 0
def check(cipher, mode, keylen, ss=512, nsec=3, iv512=None):
    global fails, n
    key = bytes(random.randrange(256) for _ in range(keylen)); data = bytes(random.randrange(256) for _ in range(ss*nsec))
    iv512 = random.randrange(1<<40) if iv512 is None else iv512
    for enc in (True, False):
        exp = ref_crypt(cipher, mode, key, iv512, ss, enc, data).hex(); got = app(cipher, mode, key, iv512, ss, enc, data); n += 1
        if exp != got:
            fails += 1; print(f"  MISMATCH {cipher}-{mode} key={keylen*8}b ss={ss} {'enc' if enc else 'dec'} got={got[:40]}")
for cipher in ("aes", "serpent", "twofish", "camellia"):
    for ss in (512, 4096): check(cipher, "xts-plain64", 64, ss)
check("aes", "xts-plain64", 32, 512); check("aes", "xts-plain64", 32, 4096)           # AES-128-XTS
check("aes", "xts-plain64", 64, 1024, iv512=2**33+7); check("aes", "xts-plain64", 64, 512, iv512=0)
for cipher in ("aes", "serpent", "twofish", "camellia"):
    for mode in ("cbc-essiv:sha256", "cbc-plain64", "cbc-plain"):
        check(cipher, mode, 32); 
check("aes", "cbc-essiv:sha256", 16); check("aes", "cbc-plain64", 16); check("aes", "cbc-plain", 16)
check("aes", "cbc-plain", 32, iv512=2**32+5)       # plain truncates the sector number to 32 bits
check("aes", "xts-plain", 64, iv512=2**32+5)
check("aes", "cbc-essiv:sha256", 32, ss=4096)
# in-place + rejection behaviour
for c, m, k in [("aes","ecb",32), ("aes","xts-essiv:sha256",64), ("aes","cbc-benbi",32), ("aes","cbc-essiv:sha512",32), ("aes","lrw-benbi",48), ("aes","xts-plain64",48), ("serpent","cbc-plain64",16), ("des","cbc-plain",8), ("aes","cbc-tcw",32)]:
    r = subprocess.run([HARNESS,"cipher",c,m,("00"*k),"0","512","enc","00"*512],capture_output=True,text=True).stdout.strip(); n += 1
    if r not in ("REJECT","INITFAIL"): fails += 1; print(f"  NOT REJECTED: {c}-{m} key={k*8}: {r[:30]}")
print(f"cipher module: {n-fails}/{n} checks agree with independent implementations" + ("" if not fails else f"  ({fails} FAILED)"))
sys.exit(1 if fails else 0)
