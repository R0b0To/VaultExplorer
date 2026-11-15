import json, hashlib, shutil, re
from common import *
pw = pwfile("pwA", b"pwA")
def res(ok, label, d=""): print(f"   {'PASS' if ok else 'FAIL'}  {label}{(' — '+d) if d else ''}"); return ok
allok = True
def fmt(ver, extra=(), size=40, kdf=None):
    img = os.path.join(WD, "m.img"); r = cs_format(img, ver, pw, size_mb=size, extra=extra, kdf_args=kdf); assert r.returncode == 0, r.stderr; return img
def cs_data_offset(img):
    out = sh(["cryptsetup", "luksDump", img]).stdout
    m = re.search(r"offset:\s+(\d+) \[bytes\]", out.split("Data segments:")[1]) if "Data segments:" in out else None
    if m: return int(m.group(1))
    m = re.search(r"Payload offset:\s+(\d+)", out); return int(m.group(1)) * 512 if m else None
def rewrite_json(img, hdrsize, fn):
    data = open(img, "rb").read(2*hdrsize); jl = hdrsize - 4096
    j = json.loads(data[4096:hdrsize].split(b"\0")[0]); fn(j)
    newjs = json.dumps(j, separators=(",", ":")).encode().ljust(jl, b"\0")
    for off in (0, hdrsize):
        h = bytearray(data[off:off+4096]); h[448:512] = b"\0"*64
        h[448:480] = hashlib.sha256(bytes(h) + newjs).digest()
        with open(img, "r+b") as f: f.seek(off); f.write(bytes(h)); f.write(newjs)

print("##### probe / data offset vs cryptsetup")
for name, ver, extra in [("LUKS1", 1, []), ("LUKS1 cbc-essiv", 1, ["--cipher","aes-cbc-essiv:sha256","--key-size","256"]), ("LUKS2 16k", 2, []),
                         ("LUKS2 64k", 2, ["--luks2-metadata-size","65536","--luks2-keyslots-size","4194304"]), ("LUKS2 4M", 2, ["--luks2-metadata-size","4194304","--luks2-keyslots-size","8388608"])]:
    img = fmt(ver, extra, size=60 if "4M" in name else 40)
    p = sh([HARNESS, "integrity", img]).stdout; probe = int(re.search(r"probe=(\d+)", p).group(1))
    allok &= res(probe == 0, f"{name}: probe says valid", f"probe={probe}")
    if ver == 2:
        d = sh([HARNESS, "dataoffset", img]).stdout.split(); allok &= res(d[0] == "OK" and int(d[1]) == cs_data_offset(img), f"{name}: data segment offset == cryptsetup", f"app={d[1]} cs={cs_data_offset(img)}")
junk = os.path.join(WD, "junk.img"); open(junk, "wb").write(os.urandom(1 << 20))
p = sh([HARNESS, "integrity", junk]).stdout; allok &= res("probe=1" in p, "random data: probe says NOT LUKS", p.strip())

print("\n##### header repair/restore (primary damaged, secondary intact)")
for name, extra in [("16k", []), ("32k", ["--luks2-metadata-size","32768","--luks2-keyslots-size","4194304"]), ("256k", ["--luks2-metadata-size","262144","--luks2-keyslots-size","4194304"])]:
    for how in ("wipe first 4096 bytes", "flip JSON byte"):
        img = fmt(2, extra); ms = 16384 if name == "16k" else int(name[:-1])*1024
        with open(img, "r+b") as f:
            if how.startswith("wipe"): f.write(b"\0"*4096)
            else: f.seek(4096+50); b = f.read(1); f.seek(4096+50); f.write(bytes([b[0]^0xFF]))
        before = sh([HARNESS, "integrity", img]).stdout
        t = os.path.join(WD, "m_cs.img"); shutil.copy(img, t)
        csrep = sh(["cryptsetup", "repair", "--batch-mode", t])
        r = sh([HARNESS, "restore", img]).stdout.strip(); after = sh([HARNESS, "integrity", img]).stdout
        okc = cs_test_pass(img, pw).returncode == 0 and sh(["cryptsetup", "luksDump", img]).returncode == 0
        allok &= res(("primary=0" in before) and r == "RESTORED" and "primary=1 secondary=1" in after and okc and csrep.returncode == 0,
                     f"{name}, {how}: app restore -> {r}; both copies valid={'primary=1 secondary=1' in after}; cryptsetup accepts={okc}")
    r = sh([HARNESS, "restore", img]).stdout.strip(); allok &= res(r == "REFUSED", f"{name}: restore refuses when primary already verifies", r)

print("\n##### LUKS2 fixed-size segment expansion (metadata rewrite) vs cryptsetup")
for name, extra, hs in [("16k", [], 16384), ("32k", ["--luks2-metadata-size","32768","--luks2-keyslots-size","4194304"], 32768), ("128k", ["--luks2-metadata-size","131072","--luks2-keyslots-size","4194304"], 131072)]:
    img = fmt(2, extra, size=40); old = 40*1024*1024
    off = cs_data_offset(img); fixed = old - off
    def mk_fixed(j): j["segments"]["0"]["size"] = str(fixed)
    rewrite_json(img, hs, mk_fixed)
    new = 60*1024*1024; os.truncate(img, new)
    v = sh([HARNESS, "resize-validate", img, str(old), str(new)]).stdout.strip()
    allok &= res(v.startswith("OK") and "dynamic=0" in v, f"{name}: resize-validate accepts fixed segment", v)
    r = sh([HARNESS, "resize", img, str(old), str(new)]).stdout.strip()
    dump = sh(["cryptsetup", "luksDump", img]); m = re.search(r"length:\s+(\d+) \[bytes\]", dump.stdout.split("Data segments:")[1]) if dump.returncode == 0 else None
    okc = cs_test_pass(img, pw).returncode == 0
    integ = sh([HARNESS, "integrity", img]).stdout
    allok &= res(r == "RESIZED" and m and int(m.group(1)) == new - off and okc and "primary=1 secondary=1" in integ,
                 f"{name}: resize commit -> {r}; cryptsetup sees segment size={m.group(1) if m else '?'} (want {new-off}); opens={okc}; both copies valid")
# refuse non-xts and dynamic
img = fmt(2, ["--cipher","aes-cbc-essiv:sha256","--key-size","256"]); rewrite_json(img, 16384, lambda j: j["segments"]["0"].__setitem__("size", str(40*1024*1024-16777216))); os.truncate(img, 60*1024*1024)
v = sh([HARNESS, "resize-validate", img, str(40*1024*1024), str(60*1024*1024)]).stdout.strip(); allok &= res(v.startswith("REFUSED"), "CBC volume: resize refused (zero-fill is XTS-only)", v)
raise SystemExit(0 if allok else 1)
