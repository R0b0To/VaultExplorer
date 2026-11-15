# Hostile/malformed-header robustness (upstream rejects every one of these). Run against ASAN build.
import struct, shutil, json, sys
from common import *
H = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("HARNESS_ASAN", HARNESS)
import common; common.HARNESS = H
pw = pwfile("pwA", b"pwA")
def run_app(img):
    try:
        r = subprocess.run([H, "unlock", img, pw], capture_output=True, text=True, timeout=20, env={**os.environ, "ASAN_OPTIONS":"detect_leaks=0:abort_on_error=0:exitcode=99:allocator_may_return_null=1", "UBSAN_OPTIONS":"print_stacktrace=0:halt_on_error=1:exitcode=98"})
    except subprocess.TimeoutExpired:
        class R: returncode=-9; stdout=""; stderr="TIMEOUT"
        return R()
    return r
def verdict(r):
    if r.stderr == "TIMEOUT": return "HANG/DoS: no result after 20s"
    if r.returncode in (98, 99) or "ERROR: AddressSanitizer" in r.stderr or "runtime error" in r.stderr:
        first = [l for l in r.stderr.splitlines() if "ERROR: AddressSanitizer" in l or "runtime error" in l]
        return "MEMORY-UNSAFE: " + (first[0][:130] if first else f"rc={r.returncode}")
    return "ok (rc=%d, %s)" % (r.returncode, "rejected" if r.stdout.startswith("FAIL") else "accepted")
def l1(mut_desc, fn):
    img = os.path.join(WD, "h.img"); cs_format(img, 1, pw, size_mb=8)
    b = bytearray(open(img, "rb").read(4096)); fn(b); open(img, "r+b").write(bytes(b))
    print(f"  LUKS1 {mut_desc:<52} {verdict(run_app(img))}")
SLOT = 208  # keyslot[0] offset in phdr
def be32(b, off, v): b[off:off+4] = struct.pack(">I", v)
l1("slot0.stripes = 0",              lambda b: be32(b, SLOT+4+4+32+4, 0))
l1("slot0.stripes = 1",              lambda b: be32(b, SLOT+4+4+32+4, 1))
l1("slot0.stripes = 0x10000001",     lambda b: be32(b, SLOT+4+4+32+4, 0x10000001))
l1("keyBytes = 0",                   lambda b: be32(b, 108, 0))
l1("keyBytes = 0x7fffffff",          lambda b: be32(b, 108, 0x7fffffff))
l1("keyBytes = 1 (too small for XTS)",lambda b: be32(b, 108, 1))
l1("keyBytes=0x10000, stripes=0x10001 (u32 overflow)", lambda b: (be32(b,108,0x10000), be32(b,SLOT+4+4+32+4,0x10001)))
l1("slot0.keyMaterialOffset = 0xffffffff", lambda b: be32(b, SLOT+4+4+32, 0xffffffff))
l1("hashSpec unterminated (32x 's')", lambda b: b.__setitem__(slice(72,104), b"s"*32))
l1("cipherName unterminated (32x 'a')", lambda b: b.__setitem__(slice(8,40), b"a"*32))
l1("slot0.iterations = 0",           lambda b: be32(b, SLOT+4, 0))
l1("mkDigestIter = 0",               lambda b: be32(b, 164, 0))

def l2(mut_desc, mutate_json, mutate_bin=None, size=8):
    img = os.path.join(WD, "h2.img"); cs_format(img, 2, pw, size_mb=size)
    data = open(img, "rb").read(32768)
    hdr = bytearray(data[:4096]); js = data[4096:16384].split(b"\0")[0]
    j = json.loads(js); mutate_json(j)
    newjs = json.dumps(j, separators=(",", ":")).encode().ljust(12288, b"\0")
    import hashlib
    for off in (0, 16384):
        h = bytearray(data[off:off+4096]); 
        if mutate_bin: mutate_bin(h)
        h[448:512] = b"\0"*64
        h[448:480] = hashlib.sha256(bytes(h) + newjs).digest()
        with open(img, "r+b") as f: f.seek(off); f.write(bytes(h)); f.write(newjs)
    print(f"  LUKS2 {mut_desc:<52} {verdict(run_app(img))}")
ks = lambda j: j["keyslots"]["0"]
l2("af.stripes = 0",            lambda j: ks(j)["af"].__setitem__("stripes", 0))
l2("af.stripes = -1",           lambda j: ks(j)["af"].__setitem__("stripes", -1))
l2("af.stripes = 2^31-1",       lambda j: ks(j)["af"].__setitem__("stripes", 2**31-1))
l2("area.size = 1 (<< AF size)",lambda j: ks(j)["area"].__setitem__("size", "1"))
l2("area.size = 2^40 (alloc bomb)", lambda j: ks(j)["area"].__setitem__("size", str(2**40)))
l2("area.size = 513 (not sector multiple)", lambda j: ks(j)["area"].__setitem__("size", "513"))
l2("area.offset = 2^64-1",      lambda j: ks(j)["area"].__setitem__("offset", str(2**64-1)))
l2("area.key_size = 0",         lambda j: ks(j)["area"].__setitem__("key_size", 0))
l2("area.key_size = 100000",    lambda j: ks(j)["area"].__setitem__("key_size", 100000))
l2("keyslot.key_size = 0",      lambda j: ks(j).__setitem__("key_size", 0))
l2("keyslot.key_size = 1<<20",  lambda j: ks(j).__setitem__("key_size", 1<<20))
l2("kdf.salt = '' (empty)",     lambda j: ks(j)["kdf"].__setitem__("salt", ""))
l2("kdf.iterations = 0",        lambda j: ks(j)["kdf"].__setitem__("iterations", 0))
l2("digest.digest = '' (empty)",lambda j: j["digests"]["0"].__setitem__("digest", ""))
l2("digest.iterations = 0",     lambda j: j["digests"]["0"].__setitem__("iterations", 0))
l2("segment.sector_size = 4097",lambda j: j["segments"]["0"].__setitem__("sector_size", 4097))
l2("hdr_size = 8MiB (bin hdr says huge)", lambda j: None, lambda h: h.__setitem__(slice(8,16), struct.pack(">Q", 8*1024*1024)))
l2("argon2id memory = 2^31 KiB, cpus=0", lambda j: ks(j).__setitem__("kdf", {"type":"argon2id","time":1,"memory":2**31-1,"cpus":0,"salt":ks(j)["kdf"]["salt"]}))
l2("argon2id time = 0",         lambda j: ks(j).__setitem__("kdf", {"type":"argon2id","time":0,"memory":64,"cpus":1,"salt":ks(j)["kdf"]["salt"]}))
