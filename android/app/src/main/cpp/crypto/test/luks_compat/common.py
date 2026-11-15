import subprocess, os, re, json, shutil, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.environ.get("HARNESS", os.path.join(HERE, "build", "luks_cli"))
WD = os.environ.get("TWD", os.path.join(tempfile.gettempdir(), "luks_compat_work")); os.makedirs(WD, exist_ok=True)

def sh(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)

def pwfile(name, data: bytes):
    p = os.path.join(WD, name); open(p, "wb").write(data); return p

def cs_format(img, ver, pw, size_mb=40, extra=(), kdf_args=None):
    if os.path.exists(img): os.remove(img)
    with open(img, "wb") as f: f.truncate(size_mb * 1024 * 1024)
    kdf = kdf_args if kdf_args is not None else (["--pbkdf-force-iterations", "1000"] if ver == 1 else ["--pbkdf", "pbkdf2", "--pbkdf-force-iterations", "1000"])
    r = sh(["cryptsetup", "luksFormat", "--type", f"luks{ver}", "--batch-mode", *kdf, *extra, "--key-file", pw, img])
    return r

def cs_mk(img, pw):
    r = sh(["cryptsetup", "luksDump", "--dump-master-key", "--batch-mode", "--key-file", pw, img])
    if r.returncode: return None
    m = re.search(r"MK dump:(.*)", r.stdout, re.S)
    return re.sub(r"\s", "", m.group(1)) if m else None

def app_unlock(img, pw):
    r = sh([HARNESS, "unlock", img, pw])
    out = r.stdout.strip().splitlines()
    if not out or out[0] == "FAIL" or r.returncode:
        return None, {"raw": r.stdout + r.stderr, "rc": r.returncode}
    info = dict(kv.split("=", 1) for kv in out[0].split()[1:])
    mk = out[1].split()[1]
    return mk, info

def cs_test_pass(img, pw, *extra):
    return sh(["cryptsetup", "open", "--test-passphrase", "--key-file", pw, *extra, img])
