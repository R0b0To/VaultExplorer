# Mutation fuzzing of header metadata under ASAN+UBSAN: unlock + password change must never crash, hang or read out of bounds.
import json, hashlib, random, struct, shutil, sys, os, subprocess
from multiprocessing import Pool
from common import *
H = os.environ.get("HARNESS_ASAN", os.path.join(HERE, "build_asan", "luks_cli"))
ENV = {**os.environ, "ASAN_OPTIONS": "detect_leaks=0:exitcode=99:allocator_may_return_null=1", "UBSAN_OPTIONS": "halt_on_error=1:exitcode=98:print_stacktrace=1"}
pwA = pwfile("fz_pw", b"pwA"); pwN = pwfile("fz_new", b"newpw")
BOUNDARY = [0, 1, 2, 7, 8, 511, 512, 4095, 4096, 4097, 65535, 65536, 2**31-1, 2**31, 2**32-1, 2**32, 2**53, 2**63, 2**64-1, -1, -2**31]
def mk_bases():
    out = {}
    def mk(name, ver, extra=(), kdf=None):
        p = os.path.join(WD, f"fz_base_{name}.img"); r = cs_format(p, ver, pwA, size_mb=8, extra=extra, kdf_args=kdf)
        if r.returncode == 0:
            for i in range(2): sh(["cryptsetup","luksAddKey","--batch-mode","--pbkdf-force-iterations","1000",*(["--pbkdf","pbkdf2"] if ver==2 else []),"--key-file",pwA,p,pwfile(f"fz_k{i}",f"k{i}".encode())])
            out[name] = (ver, p)
    mk("l1xts", 1, ["--cipher","aes-xts-plain64","--key-size","512"])
    mk("l1cbc", 1, ["--cipher","aes-cbc-essiv:sha256","--key-size","256"])
    mk("l2", 2); mk("l2cbc", 2, ["--cipher","aes-cbc-essiv:sha256","--key-size","256"])
    mk("l2argon", 2, [], ["--pbkdf","argon2id","--pbkdf-force-iterations","4","--pbkdf-memory","64","--pbkdf-parallel","1"])
    mk("l2_32k", 2, ["--luks2-metadata-size","32768","--luks2-keyslots-size","1048576"])
    return out
def fix_l2(img, hs):
    data = open(img, "rb").read(2*hs)
    for off in (0, hs):
        h = bytearray(data[off:off+4096]); js = data[off+4096:off+hs]; h[448:512] = b"\0"*64
        h[448:480] = hashlib.sha256(bytes(h) + js).digest()
        with open(img, "r+b") as f: f.seek(off); f.write(bytes(h))
def mutate_json(j, rnd):
    paths = []
    def walk(o, path):
        if isinstance(o, dict):
            for k, v in o.items(): walk(v, path + [k])
        elif isinstance(o, list):
            for i, v in enumerate(o): walk(v, path + [i])
        else: paths.append(path)
    walk(j, [])
    for _ in range(rnd.randint(1, 3)):
        p = rnd.choice(paths); o = j
        for k in p[:-1]: o = o[k]
        cur = o[p[-1]]
        choice = rnd.random()
        if isinstance(cur, str) and choice < 0.5: o[p[-1]] = rnd.choice(["", "0", "-1", "dynamic", "A"*300, str(rnd.choice(BOUNDARY)), "!!!!", cur[:len(cur)//2], cur + cur])
        elif choice < 0.85: o[p[-1]] = rnd.choice(BOUNDARY)
        elif choice < 0.92: o[p[-1]] = None
        else: o[p[-1]] = rnd.choice([[], {}, "x", [1,2], True])
def one(args):
    name, ver, base, seed = args
    rnd = random.Random(seed); img = os.path.join(WD, f"fz_{os.getpid()}.img"); shutil.copy(base, img)
    desc = ""
    if ver == 1:
        with open(img, "r+b") as f:
            b = bytearray(f.read(592))
            if rnd.random() < 0.5:
                for _ in range(rnd.randint(1, 4)): b[rnd.randrange(592)] = rnd.randrange(256)
            else:
                for _ in range(rnd.randint(1, 3)):
                    off = rnd.choice([108, 164, 6, 104] + [208 + 48*i + d for i in range(8) for d in (0, 4, 40, 44)])
                    v = rnd.choice(BOUNDARY) & 0xFFFFFFFF; b[off:off+4] = struct.pack(">I", v)
            f.seek(0); f.write(b)
    else:
        hs = 32768 if "32k" in name else 16384
        data = open(img, "rb").read(2*hs); js = data[4096:hs].split(b"\0")[0]
        mode = rnd.random()
        with open(img, "r+b") as f:
            if mode < 0.55:
                j = json.loads(js); mutate_json(j, rnd)
                new = json.dumps(j, separators=(",", ":")).encode()
                if len(new) < hs-4096:
                    for off in (0, hs): f.seek(off+4096); f.write(new.ljust(hs-4096, b"\0"))
            elif mode < 0.8:
                for off in (0, hs):
                    f.seek(off+4096+rnd.randrange(len(js))); f.write(bytes([rnd.randrange(256)]))
            else:
                for off in (0, hs):
                    f.seek(off + rnd.choice([6, 8, 16, 256, 264, 24, 72])); f.write(os.urandom(rnd.randint(1, 8)))
        if rnd.random() < 0.8: fix_l2(img, hs)
    bad = []
    for cmd in (["unlock", img, pwA], ["chpw", img, pwA, pwN]):
        try:
            r = subprocess.run([H, *cmd], capture_output=True, text=True, errors="replace", timeout=30, env=ENV)
        except subprocess.TimeoutExpired:
            bad.append((cmd[0], "TIMEOUT")); keep = img + f".timeout{seed}"; shutil.copy(img, keep); continue
        if r.returncode in (98, 99) or "AddressSanitizer" in r.stderr or "runtime error" in r.stderr:
            keep = os.path.join(WD, f"crash_{name}_{seed}.img"); shutil.copy(img, keep)
            first = [l for l in r.stderr.splitlines() if "ERROR: AddressSanitizer" in l or "runtime error" in l][:1]
            bad.append((cmd[0], (first[0][:160] if first else f"rc={r.returncode}"), keep))
        if cmd[0] == "chpw": shutil.copy(base, img)
    return (name, seed, bad)
if __name__ == "__main__":
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    bases = mk_bases(); jobs = [(n, v, p, s) for n, (v, p) in bases.items() for s in range(N)]
    print(f"fuzzing {len(jobs)} mutated headers ({len(bases)} formats x {N}) under ASAN+UBSAN ...", flush=True)
    findings = []
    with Pool(8) as pool:
        for name, seed, bad in pool.imap_unordered(one, jobs, chunksize=4):
            if bad: findings.append((name, seed, bad))
    print(f"done: {len(jobs)} cases, {len(findings)} with findings")
    for name, seed, bad in findings[:15]: print("  ", name, seed, bad)
    sys.exit(1 if findings else 0)
