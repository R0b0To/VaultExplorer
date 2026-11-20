from common import *
import struct, shutil
P = {n: pwfile(n, n.encode()) for n in ("pwA", "pwB", "pwC", "pwNEW")}
def res(ok, label, d=""): print(f"   {'PASS' if ok else 'FAIL'}  {label}{(' — '+d) if d else ''}"); return ok
def fmt(ver, extra=(), kdf=None, size=40):
    img = os.path.join(WD, "o.img"); r = cs_format(img, ver, P["pwA"], size_mb=size, extra=extra, kdf_args=kdf)
    assert r.returncode == 0, r.stderr
    return img
def addkey(img, ver, usepw, newpw):
    return sh(["cryptsetup","luksAddKey","--batch-mode","--pbkdf-force-iterations","1000",*(["--pbkdf","pbkdf2"] if ver==2 else []),"--key-file",usepw,img,newpw])

for ver in (1, 2):
    print(f"\n##### LUKS{ver}: multiple keyslots / kill slot / change password")
    img = fmt(ver)
    addkey(img, ver, P["pwA"], P["pwB"]); addkey(img, ver, P["pwA"], P["pwC"])
    mk = cs_mk(img, P["pwA"])
    for n in ("pwA","pwB","pwC"):
        m, _ = app_unlock(img, P[n]); res(m == mk, f"app unlocks with {n} (3 active keyslots)")
    r = sh([HARNESS,"chpw",img,P["pwB"],P["pwNEW"]]); res(r.stdout.strip()=="OK", "app chpw pwB->pwNEW", r.stdout.strip())
    res(cs_test_pass(img, P["pwNEW"]).returncode==0, "cryptsetup accepts new password after app chpw")
    res(cs_test_pass(img, P["pwB"]).returncode!=0, "cryptsetup rejects old password after app chpw")
    res(cs_test_pass(img, P["pwA"]).returncode==0 and cs_test_pass(img, P["pwC"]).returncode==0, "cryptsetup: other keyslots untouched")
    res(cs_mk(img, P["pwNEW"])==mk, "master key unchanged after chpw")
    r = sh([HARNESS,"chpw",img,P["pwC"],P["pwC"]]); res(r.stdout.strip()=="OK", "app chpw pwC->pwC (same pw, new salt)")
    r = sh([HARNESS,"chpw",img,P["pwB"],P["pwNEW"]]); res(r.stdout.strip()=="WRONGPW", "app chpw with stale pw => WRONGPW", r.stdout.strip())
    # kill slot 0 -> pwA must stop working in both
    k = sh(["cryptsetup","luksKillSlot","--batch-mode","--key-file",P["pwC"],img,"0"])
    res(k.returncode==0, "cryptsetup luksKillSlot 0", k.stderr.strip()[:100])
    m, _ = app_unlock(img, P["pwA"]); res(m is None, "app rejects pwA after slot killed")
    m, _ = app_unlock(img, P["pwNEW"]); res(m == mk, "app still unlocks other slot after kill")
    d = sh(["cryptsetup","luksDump",img]); res(d.returncode==0, "cryptsetup luksDump after app chpw + kill")

print("\n##### LUKS2: priority 'ignore' keyslot (cryptsetup skips unless --key-slot given)")
img = fmt(2); addkey(img, 2, P["pwA"], P["pwB"])
c = sh(["cryptsetup","config","--priority","ignore","--key-slot","1",img]); res(c.returncode==0,"cryptsetup config --priority ignore --key-slot 1")
res(cs_test_pass(img,P["pwB"]).returncode!=0, "cryptsetup: ignored slot not usable without --key-slot")
m,_ = app_unlock(img,P["pwB"]); res(m is None, "app also refuses ignored-priority slot (interchangeable behaviour)", "app unlocked it" if m else "")

print("\n##### LUKS2: corrupted primary header, secondary intact (cryptsetup transparently falls back)")
for ms in (16384, 32768, 65536, 4194304):
    img = fmt(2, ["--luks2-metadata-size", str(ms), "--luks2-keyslots-size","4194304"] if ms<2097152 else ["--luks2-metadata-size", str(ms), "--luks2-keyslots-size","8388608"], size=60)
    mk = cs_mk(img, P["pwA"])
    for how in ("zero magic", "flip JSON byte"):
        t = os.path.join(WD, "cp.img"); shutil.copy(img, t)
        with open(t, "r+b") as f:
            if how == "zero magic": f.seek(0); f.write(b"\0"*8)
            else: f.seek(4096+100); b = f.read(1); f.seek(4096+100); f.write(bytes([b[0]^0xFF]))
        csok = cs_test_pass(t, P["pwA"]).returncode==0
        m,_ = app_unlock(t, P["pwA"])
        res((m == mk) or (not csok), f"hdr {ms//1024}k, primary '{how}': cryptsetup={'ok' if csok else 'fail'} app={'ok' if m==mk else 'FAIL'}")
    # secondary corrupted
    t = os.path.join(WD, "cp.img"); shutil.copy(img, t)
    with open(t, "r+b") as f: f.seek(ms+4096+100); b=f.read(1); f.seek(ms+4096+100); f.write(bytes([b[0]^0xFF]))
    m,_ = app_unlock(t, P["pwA"]); res(m==mk, f"hdr {ms//1024}k, secondary corrupted: app unlocks via primary")

print("\n##### LUKS2 non-default metadata size: app chpw + integrity tool vs real cryptsetup")
for ms in (32768, 65536, 262144):
    img = fmt(2, ["--luks2-metadata-size", str(ms), "--luks2-keyslots-size","4194304"], size=60)
    mk = cs_mk(img, P["pwA"])
    i = sh([HARNESS,"integrity",img]); res("primary=1 secondary=1" in i.stdout, f"hdr {ms//1024}k: app integrity check says both copies valid (cryptsetup does)", i.stdout.strip())
    bk = os.path.join(WD,"pre.img"); shutil.copy(img, bk)
    r = sh([HARNESS,"chpw",img,P["pwA"],P["pwNEW"]])
    ok = cs_test_pass(img, P["pwNEW"]).returncode==0
    d = sh(["cryptsetup","luksDump",img])
    res(r.stdout.strip()=="OK" and ok, f"hdr {ms//1024}k: app chpw result={r.stdout.strip()}, cryptsetup opens with new pw={ok}", (d.stderr.strip()[:120] if d.returncode else ""))
