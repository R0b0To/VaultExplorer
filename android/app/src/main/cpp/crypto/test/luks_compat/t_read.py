# Direction A: real cryptsetup creates -> app must recover identical master key + geometry
from common import *
pw = pwfile("pw", b"correct horse battery staple")
cases = []
def add(name, ver, extra=(), kdf=None, size=40): cases.append((name, ver, tuple(extra), kdf, size))

# ---- LUKS1
add("L1 aes-xts-plain64 512 sha256", 1, ["--cipher","aes-xts-plain64","--key-size","512","--hash","sha256"])
add("L1 aes-xts-plain64 256 (AES-128-XTS)", 1, ["--cipher","aes-xts-plain64","--key-size","256","--hash","sha256"])
for h in ["sha1","sha512","ripemd160","whirlpool"]:
    add(f"L1 aes-xts-plain64 512 {h}", 1, ["--cipher","aes-xts-plain64","--key-size","512","--hash",h])
add("L1 aes-cbc-essiv:sha256 256", 1, ["--cipher","aes-cbc-essiv:sha256","--key-size","256","--hash","sha1"])
add("L1 aes-cbc-plain64 256", 1, ["--cipher","aes-cbc-plain64","--key-size","256"])
add("L1 aes-cbc-essiv:sha256 128", 1, ["--cipher","aes-cbc-essiv:sha256","--key-size","128"])
add("L1 aes-xts-plain64 512 --align-payload 8192", 1, ["--cipher","aes-xts-plain64","--key-size","512","--align-payload","8192"])
# ---- LUKS2
add("L2 default (pbkdf2 sha256 aes-xts 512)", 2)
for h in ["sha1","sha512"]:
    add(f"L2 pbkdf2 {h}", 2, ["--hash",h])
add("L2 aes-xts-plain64 256 (AES-128-XTS)", 2, ["--cipher","aes-xts-plain64","--key-size","256"])
add("L2 aes-cbc-essiv:sha256 256 (32B MK, 64B area key)", 2, ["--cipher","aes-cbc-essiv:sha256","--key-size","256"])
add("L2 aes-cbc-plain64 256", 2, ["--cipher","aes-cbc-plain64","--key-size","256"])
for st in ["512","1024","2048","4096"]:
    add(f"L2 sector-size {st}", 2, ["--sector-size", st])
add("L2 argon2id", 2, ["--hash","sha256"], ["--pbkdf","argon2id","--pbkdf-force-iterations","4","--pbkdf-memory","64","--pbkdf-parallel","1"])
add("L2 argon2i", 2, ["--hash","sha256"], ["--pbkdf","argon2i","--pbkdf-force-iterations","4","--pbkdf-memory","64","--pbkdf-parallel","2"])
add("L2 argon2id sha512", 2, ["--hash","sha512"], ["--pbkdf","argon2id","--pbkdf-force-iterations","4","--pbkdf-memory","128","--pbkdf-parallel","2"])
for ms in ["32768","65536","131072","262144","524288","1048576","2097152","4194304"]:
    add(f"L2 metadata-size {int(ms)//1024}k", 2, ["--luks2-metadata-size", ms, "--luks2-keyslots-size", "4194304" if int(ms)<2097152 else "8388608"], size=60)
add("L2 keyslot-cipher serpent? (aes-cbc-essiv:sha256 area)", 2, ["--keyslot-cipher","aes-cbc-essiv:sha256","--keyslot-key-size","256"])
add("L2 keyslot-key-size 256 (AES-128-XTS area)", 2, ["--keyslot-cipher","aes-xts-plain64","--keyslot-key-size","256"])
add("L2 --offset 8192 sectors", 2, ["--offset","32768"], size=40)
add("L2 --label/--subsystem", 2, ["--label","mylabel","--subsystem","mysub"])
add("L2 --integrity hmac-sha256 (AEAD-ish)", 2, ["--integrity","hmac-sha256","--cipher","aes-xts-plain64","--key-size","512"])
add("L2 --uuid fixed", 2, ["--uuid","11111111-2222-3333-4444-555555555555"])
for h in ["sha224","sha384","sha3-256","sha3-512","ripemd160","whirlpool"]:
    add(f"L2 pbkdf2/af/digest hash {h}", 2, ["--hash", h])
for h in ["sha224","sha384","sha3-256"]:
    add(f"L1 hash {h}", 1, ["--cipher","aes-xts-plain64","--key-size","512","--hash", h])
for c, k in [("aes-cbc-plain","256"),("aes-xts-plain","512")]:
    add(f"L1 {c} {k}", 1, ["--cipher", c, "--key-size", k])
add("L1 aes-cbc-essiv:sha256 256 + whirlpool", 1, ["--cipher","aes-cbc-essiv:sha256","--key-size","256","--hash","whirlpool"])
add("L2 keyslot area aes-cbc-plain64/256", 2, ["--keyslot-cipher","aes-cbc-plain64","--keyslot-key-size","256"])

res = []
for name, ver, extra, kdf, size in cases:
    img = os.path.join(WD, "r.img")
    r = cs_format(img, ver, pw, size_mb=size, extra=extra, kdf_args=kdf)
    if r.returncode:
        res.append((name, "SKIP(cs format failed)", r.stderr.strip().splitlines()[-1][:90] if r.stderr.strip() else "")); continue
    mk_cs = cs_mk(img, pw)
    mk_app, info = app_unlock(img, pw)
    if mk_cs is None: res.append((name, "SKIP(cs dump failed)", "")); continue
    if mk_app is None: res.append((name, "FAIL unlock", "app returned false")); continue
    if mk_app != mk_cs: res.append((name, "FAIL wrong key", f"cs={len(mk_cs)//2}B app={len(mk_app)//2}B")); continue
    res.append((name, "OK", f"keybytes={info['keybytes']} mode={info['mode']} sector={info['sectorsize']} off={info['dataoffset']}"))
w = max(len(r[0]) for r in res)
for n, s, d in res: print(f"{n:<{w}}  {s:<24} {d}")
print("\nSUMMARY:", sum(1 for r in res if r[1]=="OK"), "OK /", sum(1 for r in res if r[1].startswith("FAIL")), "FAIL /", sum(1 for r in res if r[1].startswith("SKIP")), "SKIP")
