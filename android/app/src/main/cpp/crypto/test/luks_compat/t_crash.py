# Crash-safety: kill the password change after k successful writes, for every k.
# Invariant: after ANY interruption the volume still opens with the OLD or the NEW passphrase.
import shutil
from common import *
old = pwfile("pwOLD", b"old-passphrase"); new = pwfile("pwNEW", b"new-passphrase")
def run(ver, label, setup):
    base = os.path.join(WD, "crash_base.img"); setup(base)
    mk = cs_mk(base, old); assert mk
    # how many writes does a full change take?
    full = os.path.join(WD, "crash_full.img"); shutil.copy(base, full)
    r = sh([HARNESS, "chpw-fail", full, old, new, "1000"]); total = int(r.stdout.split("writes=")[1]); assert r.stdout.startswith("OK"), r.stdout
    bad = []; 
    for k in range(0, total + 1):
        t = os.path.join(WD, "crash_t.img"); shutil.copy(base, t)
        sh([HARNESS, "chpw-fail", t, old, new, str(k)])
        o = cs_test_pass(t, old).returncode == 0; n = cs_test_pass(t, new).returncode == 0
        ao, _ = app_unlock(t, old); an, _ = app_unlock(t, new)
        if not (o or n) or not (ao or an) or (o != bool(ao)) or (n != bool(an)):
            bad.append((k, o, n, bool(ao), bool(an)))
    print(f"  {'PASS' if not bad else 'FAIL'}  {label}: {total+1} interruption points (after 0..{total} writes), "
          f"{'never locked out; cryptsetup and app always agree' if not bad else 'PROBLEMS (k, cs_old, cs_new, app_old, app_new): '+str(bad)}")
    return not bad
def l1(extra=()):
    def f(img): cs_format(img, 1, old, size_mb=40, extra=extra)
    return f
def l2(extra=(), kdf=None):
    def f(img): cs_format(img, 2, old, size_mb=40, extra=extra, kdf_args=kdf)
    return f
def l1_full(img):   # all 8 slots used -> no free slot -> in-place fallback
    cs_format(img, 1, old, size_mb=40)
    for i in range(7): assert sh(["cryptsetup","luksAddKey","--batch-mode","--pbkdf-force-iterations","1000","--key-file",old,img,pwfile(f"x{i}",f"extra{i}".encode())]).returncode == 0
ok = True
ok &= run(1, "LUKS1 (free slot available => relocate, retire old)", l1())
ok &= run(2, "LUKS2 (free area available => relocate, retire old)", l2())
ok &= run(2, "LUKS2 argon2id", l2(kdf=["--pbkdf","argon2id","--pbkdf-force-iterations","4","--pbkdf-memory","64","--pbkdf-parallel","1"]))
ok &= run(2, "LUKS2 32k metadata", l2(["--luks2-metadata-size","32768","--luks2-keyslots-size","4194304"]))
print("\nKnown, upstream-identical exception: with NO free slot/area the change overwrites in place:")
base = os.path.join(WD, "crash_full8.img"); l1_full(base)
d = sh(["cryptsetup","luksDump",base]).stdout
r = sh([HARNESS,"chpw",base,old,new]); print(f"  LUKS1 with 8/8 slots used: app chpw -> {r.stdout.strip()}; cryptsetup accepts new pw: {cs_test_pass(base,new).returncode==0}; old pw rejected: {cs_test_pass(base,old).returncode!=0}")
raise SystemExit(0 if ok else 1)
