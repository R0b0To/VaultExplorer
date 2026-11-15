# Direction B: app creates -> real cryptsetup must accept it and agree on every field
from common import *
pw = pwfile("pw", b"correct horse battery staple")
pw2 = pwfile("pw2", b"second passphrase")
SIZE = 40*1024*1024
cases = []
for ver in (1, 2):
    for cipher in ("aes",):
        for h in ("sha256", "sha512"):
            cases.append((ver, cipher, h, ["1000"]))
cases.append((2, "aes", "sha256", ["argon2", "64", "4", "1"]))
cases.append((2, "aes", "sha512", ["argon2", "256", "5", "2"]))
cases.append((1, "aes", "sha1", ["1000"]))   # not documented as supported by creator; see what happens

def line(ok, label, detail=""): print(f"   {'PASS' if ok else 'FAIL'}  {label}{(' — '+detail) if detail else ''}")
for ver, cipher, h, kdf in cases:
    img = os.path.join(WD, "c.img")
    if os.path.exists(img): os.remove(img)
    r = sh([HARNESS, "create", img, pw, str(SIZE), str(ver), cipher, h, *kdf])
    print(f"\n=== LUKS{ver} {cipher} {h} {kdf[0] if kdf[0]=='argon2' else 'pbkdf2'}  -> create: {r.stdout.splitlines()[0][:60] if r.stdout else r.stderr[:80]}")
    if not r.stdout.startswith("OK"): continue
    app_mk = r.stdout.splitlines()[1].split()[1]
    d = sh(["cryptsetup", "luksDump", img])
    line(d.returncode == 0, "cryptsetup luksDump accepts header", d.stderr.strip()[:150])
    t = cs_test_pass(img, pw)
    line(t.returncode == 0, "cryptsetup open --test-passphrase", t.stderr.strip()[:150])
    mk = cs_mk(img, pw)
    line(mk == app_mk, "cryptsetup master key == app master key", "" if mk else "dump failed")
    bad = pwfile("bad", b"nope"); tb = cs_test_pass(img, bad)
    line(tb.returncode != 0, "cryptsetup rejects wrong passphrase")
    # add a 2nd key with real cryptsetup, then app must unlock with it
    a = sh(["cryptsetup", "luksAddKey", "--batch-mode", "--pbkdf-force-iterations", "1000", *(["--pbkdf","pbkdf2"] if ver==2 else []), "--key-file", pw, img, pw2])
    line(a.returncode == 0, "cryptsetup luksAddKey (second keyslot)", a.stderr.strip()[:150])
    if a.returncode == 0:
        mk2, _ = app_unlock(img, pw2); line(mk2 == app_mk, "app unlocks with cryptsetup-added key")
        c = sh(["cryptsetup", "luksChangeKey", "--batch-mode", "--pbkdf-force-iterations", "1000", *(["--pbkdf","pbkdf2"] if ver==2 else []), "--key-file", pw2, img, pwfile("pw3", b"third")])
        line(c.returncode == 0, "cryptsetup luksChangeKey", c.stderr.strip()[:120])
    # header backup/restore roundtrip with cryptsetup
    bk = os.path.join(WD, "hdr.bak")
    if os.path.exists(bk): os.remove(bk)
    b = sh(["cryptsetup", "luksHeaderBackup", "--batch-mode", "--header-backup-file", bk, img])
    line(b.returncode == 0, "cryptsetup luksHeaderBackup", b.stderr.strip()[:120])
    if ver == 2:
        rp = sh(["cryptsetup", "repair", "--batch-mode", img]); line(rp.returncode == 0, "cryptsetup repair (no-op expected)", (rp.stdout+rp.stderr).strip()[:120])
    ch = sh(["cryptsetup", "isLuks", "-v", img]); line(ch.returncode == 0, "cryptsetup isLuks")
