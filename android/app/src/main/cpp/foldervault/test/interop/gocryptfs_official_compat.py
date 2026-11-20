#!/usr/bin/env python3
"""Differential test: the foldervault gocryptfs engine against the REAL gocryptfs.

Needs: gocryptfs 2.x, FUSE (fusermount3), python3 >= 3.9 and FVCLI=<path to fvcli>.

    FVCLI=build/fvcli ./gocryptfs_official_compat.py [phase ...]

Phases (default: all)
  A  vaults made by gocryptfs (every -init flavour) are read, then modified, by this engine; the result
     must be exactly what gocryptfs itself shows, and `gocryptfs -fsck` must be happy
  B  vaults made by this engine (every create option) are read by gocryptfs and pass `-fsck`; then
     gocryptfs modifies them and this engine must see the same tree
  C  the official example filesystems (tests/example_filesystems): same engine behaviour as gocryptfs
     (accepts what it accepts, refuses what it refuses), writes it makes are accepted by gocryptfs
  D  the synchronisation scenario of issue #228: two devices, one running gocryptfs and one this engine,
     create the same folder offline; a file-sync tool merges the ciphertext
  E  tampered / damaged ciphertext: this engine must show exactly the entries gocryptfs shows

The oracle is always gocryptfs' own view of the vault (a real FUSE mount), compared name by name, size by
size and SHA-256 by SHA-256. Final line: "RESULT fail=N".
"""
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FVCLI = os.environ.get("FVCLI") or sys.exit("set FVCLI to the built fvcli binary")
GOCRYPTFS = os.environ.get("GOCRYPTFS", "gocryptfs")
WORK = os.path.join(os.environ.get("WORKDIR", "/tmp/fv_interop"), "gocryptfs_official")
VECTORS = os.environ.get("FV_VECTORS", os.path.join(HERE, "..", "vectors", "gocryptfs"))
PW = "interop-pw"
VERBOSE = bool(os.environ.get("VERBOSE"))
FAILS = 0


def check(ok, msg):
    global FAILS
    if ok:
        if VERBOSE:
            print("  ok   " + msg)
    else:
        FAILS += 1
        print("  FAIL " + msg)
    return ok


# --------------------------------------------------------------------------- process helpers
def run(args, timeout=180, env=None):
    return subprocess.run(args, capture_output=True, timeout=timeout, env=env)


def ve(vault, *args, env=None, pw=PW):
    e = dict(os.environ)
    e.update(env or {})
    return run([FVCLI, "gocryptfs", vault, pw, *args], env=e)


def real_init(c, flags=()):
    os.makedirs(c, exist_ok=True)
    p = run([GOCRYPTFS, "-q", "-init", "-nosyslog", "-scryptn", "10", "-extpass", "echo " + PW, *flags, c])
    return check(p.returncode == 0, "gocryptfs -init %s: %s" % (" ".join(flags), p.stderr.decode()[:200]))


def real_fsck(c, pw=PW):
    p = run([GOCRYPTFS, "-q", "-fsck", "-nosyslog", "-extpass", "echo " + pw, c], timeout=300)
    return p.returncode == 0, (p.stdout + p.stderr).decode(errors="replace")[:600]


class Mount:
    """A detached real gocryptfs mount (so the test never blocks on the daemon's stdio)."""

    def __init__(self, c, m, extra=(), pw=PW):
        self.c, self.m, self.extra, self.pw = c, m, list(extra), pw

    def __enter__(self):
        os.makedirs(self.m, exist_ok=True)
        self.log = open(self.m + ".log", "wb")
        self.p = subprocess.Popen([GOCRYPTFS, "-fg", "-nosyslog", "-q", "-extpass", "echo " + self.pw, *self.extra, self.c, self.m],
                                  stdout=subprocess.DEVNULL, stderr=self.log, start_new_session=True)
        for _ in range(150):
            if os.path.ismount(self.m):
                return self.m
            if self.p.poll() is not None:
                break
            time.sleep(0.1)
        raise RuntimeError("gocryptfs mount failed (rc=%s): %s" % (self.p.poll(), open(self.m + ".log").read()[:300]))

    def __exit__(self, *a):
        run(["fusermount3", "-u", self.m])
        try:
            self.p.wait(15)
        except subprocess.TimeoutExpired:
            run(["fusermount3", "-uz", self.m])
            self.p.kill()
        self.log.close()


def try_mount(c, m, pw=PW):
    """Does real gocryptfs accept this vault? (returns bool)"""
    try:
        with Mount(c, m, pw=pw):
            return True
    except RuntimeError:
        return False


# --------------------------------------------------------------------------- tree snapshots
def sha(b):
    return hashlib.sha256(b).hexdigest()


def real_tree(m):
    """gocryptfs' own view. Symlinks and names that are not valid UTF-8 are returned separately: the
    engine cannot represent them (Android has no symlinks, Java/Dart strings are Unicode)."""
    mb = os.fsencode(m)
    tree, symlinks, odd = {}, [], []
    for dp, dns, fns in os.walk(mb):
        for n in dns + fns:
            full = os.path.join(dp, n)
            rel = os.path.relpath(full, mb)
            try:
                rels = rel.decode("utf-8")
            except UnicodeDecodeError:
                odd.append(rel)
                continue
            if os.path.islink(full):
                symlinks.append(rels)
            elif os.path.isdir(full):
                tree[rels] = ("D", 0, "-")
            else:
                with open(full, "rb") as f:
                    d = f.read()
                tree[rels] = ("F", len(d), sha(d))
    # entries below a symlinked or undecodable directory never show up above, so nothing to filter
    return tree, symlinks, odd


def unesc(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\"}.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def ve_tree(c, pw=PW):
    p = ve(c, "tree", pw=pw)
    if p.returncode != 0:
        return None
    tree = {}
    for line in p.stdout.decode("utf-8", "surrogateescape").split("\n"):
        if not line:
            continue
        t, size, h, path = line.split("\t", 3)
        tree[unesc(path)] = (t, int(size), h)
    return tree


def diff(expected, actual):
    probs = []
    for k in sorted(set(expected) | set(actual)):
        if expected.get(k) != actual.get(k):
            probs.append("%r: expected %s, got %s" % (k, expected.get(k), actual.get(k)))
    return probs


def same_tree(label, expected, actual):
    if actual is None:
        return check(False, "%s: could not list the vault" % label)
    probs = diff(expected, actual)
    return check(not probs, "%s: %d difference(s)%s" % (label, len(probs), "".join("\n         " + x for x in probs[:8])))


# --------------------------------------------------------------------------- test content
ODD_NAMES = [
    "plain.txt", "ünïcödé-名前-🙂.txt", "with space.txt", " leading and trailing ", "dots...", "...", ".hidden", "a.b.c.d",
    "x.name", "tab\tname", "nl\nname", "cr\rname", "crlf\r\nname", "repl-\ufffd-char", "q?*<>|\"':;",
    "gocryptfs.diriv", "gocryptfs.conf", "gocryptfs.conf.bak", "gocryptfs.longname.abc", "gocryptfs.longname.abc.name",
    "n" * 255, "n" * 254, "L" * 200 + ".txt", "h" * 100, "s" * 63, "l" * 64, "\u00e9" * 127 + "a", "K" * 130,
]
SIZES = [0, 1, 15, 16, 17, 4095, 4096, 4097, 8191, 8192, 8193, 12288, 65536, 100000, 1 << 20]


def data(seed, n):
    return random.Random(seed).randbytes(n)


def populate_real(m):
    """Fill a gocryptfs mount through the normal filesystem API."""
    def w(rel, d):
        p = os.path.join(m, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(d)
    for sz in SIZES:
        w("sizes/f%d.bin" % sz, data(sz, sz))
    p = os.path.join(m, "sparse", "hole.bin")      # holes: gocryptfs stores them as all-zero blocks
    os.makedirs(os.path.dirname(p))
    with open(p, "wb") as f:
        f.seek(3 * 4096 + 100)
        f.write(b"tail")
        f.truncate(10 * 4096 + 5)
    for i, n in enumerate(ODD_NAMES):
        w("names/" + n, data(1000 + i, 10 + i * 37))
    w("deep/a/b/c/d/e/f/file.txt", data(5, 300))
    w("D" * 255 + "/inner.txt", data(6, 1234))       # folder with a hashed (long) name
    w("E" * 200 + "/x/y.txt", data(7, 4321))
    os.makedirs(os.path.join(m, "empty"))
    for i in range(300):
        w("many/f%03d.txt" % i, data(2000 + i, i))
    os.symlink("plain.txt", os.path.join(m, "names", "rel"))      # what this app deliberately does not show
    os.symlink("/a/b/c/d", os.path.join(m, "names", "abs"))
    with open(os.path.join(os.fsencode(m), b"names", b"bad-\xff\xfe-name"), "wb") as f:   # not valid UTF-8
        f.write(b"x")


class Model:
    """What the vault should contain, maintained alongside the operations we perform."""

    def __init__(self, tree):
        self.t = dict(tree)

    def put(self, path, d):
        self.t[path] = ("F", len(d), sha(d))

    def mkdir(self, path):
        self.t.setdefault(path, ("D", 0, "-"))

    def rm(self, path):
        for k in [k for k in self.t if k == path or k.startswith(path + "/")]:
            del self.t[k]

    def mv(self, a, b):
        for k in sorted(k for k in self.t if k == a or k.startswith(a + "/")):
            self.t[b + k[len(a):]] = self.t.pop(k)


class VE:
    """Drives fvcli and keeps the Model in step."""

    def __init__(self, c, model, tmp, pw=PW):
        self.c, self.m, self.tmp, self.pw = c, model, tmp, pw

    def _local(self, d):
        p = os.path.join(self.tmp, "upload.bin")
        with open(p, "wb") as f:
            f.write(d)
        return p

    def put(self, path, d, how="put"):
        p = ve(self.c, how, path, self._local(d), pw=self.pw)
        if check(p.returncode == 0, "%s %r: %s" % (how, path[:40], p.stderr.decode()[:100])):
            self.m.put(path, d)

    def mkdir(self, path):
        p = ve(self.c, "mkdir", path, pw=self.pw)
        if check(p.returncode == 0, "mkdir %r: %s" % (path[:40], p.stderr.decode()[:100])):
            self.m.mkdir(path)

    def mv(self, a, b):
        p = ve(self.c, "mv", a, b, pw=self.pw)
        if check(p.returncode == 0, "mv %r -> %r: %s" % (a[:30], b[:30], p.stderr.decode()[:100])):
            self.m.mv(a, b)

    def rm(self, path):
        p = ve(self.c, "rm", path, pw=self.pw)
        if check(p.returncode == 0, "rm %r: %s" % (path[:40], p.stderr.decode()[:100])):
            self.m.rm(path)


def ve_workout(v, plain):
    """Operations an Android user would do. Names are chosen to hit every long-name transition."""
    v.mkdir("ve_new")
    v.mkdir("ve_new/sub")
    v.mkdir("ve_new/" + "D" * 200)
    v.mkdir("ve_new/nl\ndir")
    v.put("ve_new/a.txt", b"")
    v.put("ve_new/b.txt", b"b")
    v.put("ve_new/c.bin", data(11, 4097))
    v.put("ve_new/sub/big.bin", data(12, 100000))
    v.put("ve_new/" + "L" * 200 + ".txt", data(13, 5000))
    v.put("ve_new/" + "D" * 200 + "/inner.txt", data(14, 77))
    v.put("ve_new/ünï-🙂.txt", data(15, 123))
    v.put("ve_new/chunked.bin", data(16, 50000), how="putchunks")
    v.put("ve_new/over.txt", data(17, 100))
    v.put("ve_new/over.txt", data(18, 3000))                      # replace
    v.mv("ve_new/a.txt", "ve_new/renamed.txt")                      # short -> short
    v.mv("ve_new/b.txt", "ve_new/" + "M" * 180)                     # short -> long
    v.mv("ve_new/" + "L" * 200 + ".txt", "ve_new/short-now.txt")    # long -> short
    v.mv("ve_new/" + "M" * 180, "ve_new/sub/" + "N" * 190)          # long -> long, across folders
    v.mv("ve_new/sub", "ve_new/" + "S" * 210)                       # folder short -> long, with children
    v.mv("ve_new/" + "S" * 210, "ve_new/sub2")                      # folder long -> short
    v.rm("ve_new/c.bin")
    v.rm("ve_new/" + "D" * 200)                                     # long-named folder with content
    # things gocryptfs (or we) created earlier
    if "names/" + "n" * 255 in v.m.t:
        v.mv("names/" + "n" * 255, "names/renamed-255")
    if "names/nl\nname" in v.m.t:
        v.mv("names/nl\nname", "names/nl2\nname")
    if "many" in v.m.t:
        v.rm("many")
    if "deep/a" in v.m.t:
        v.rm("deep/a")
    if "E" * 200 in v.m.t:
        v.mv("E" * 200, "E-short")
    if not plain:                                                    # gocryptfs-the-name-is-free in encrypted vaults
        v.put("gocryptfs.conf", b"just a file")                      # ... a perfectly ordinary file name
        v.put("gocryptfs.diriv", b"just another file")


def real_workout(m, model):
    """What a Linux user does behind the app's back; the Model follows."""
    def p(rel):
        return os.path.join(m, rel)
    os.makedirs(p("lx"))
    model.mkdir("lx")
    for i, (n, sz) in enumerate([("one.txt", 10), ("L" * 230 + ".bin", 9000), ("ü-" * 40 + ".dat", 5000)]):
        d = data(300 + i, sz)
        with open(p("lx/" + n), "wb") as f:
            f.write(d)
        model.put("lx/" + n, d)
    os.rename(p("lx/one.txt"), p("lx/" + "R" * 220))
    model.mv("lx/one.txt", "lx/" + "R" * 220)
    # overwrite in the middle of an existing file, and truncate / extend
    target = "sizes/f100000.bin"
    if target in model.t:
        d = bytearray(data(100000, 100000))
        with open(p(target), "r+b") as f:
            f.seek(5000)
            f.write(b"PATCH" * 1000)
            d[5000:10000] = b"PATCH" * 1000
        model.put(target, bytes(d))
    target = "sizes/f65536.bin"
    if target in model.t:
        d = data(65536, 65536)
        os.truncate(p(target), 4100)
        model.put(target, d[:4100])
    target = "sizes/f4097.bin"
    if target in model.t:
        d = data(4097, 4097)
        os.truncate(p(target), 20000)
        model.put(target, d + b"\0" * (20000 - 4097))
    if "sparse" in model.t:
        shutil.rmtree(p("sparse"))
        model.rm("sparse")
    os.mkdir(p("lx/sub-dir"))
    model.mkdir("lx/sub-dir")
    shutil.move(p("lx/sub-dir"), p("lx/" + "Z" * 200))
    model.mv("lx/sub-dir", "lx/" + "Z" * 200)


# --------------------------------------------------------------------------- phase A
VARIANTS = [
    ("default (AES-GCM)", []),
    ("-aessiv", ["-aessiv"]),
    ("-xchacha", ["-xchacha"]),
    ("-plaintextnames", ["-plaintextnames"]),
    ("-deterministic-names", ["-deterministic-names"]),
    ("-deterministic-names -xchacha", ["-deterministic-names", "-xchacha"]),
    ("-deterministic-names -aessiv", ["-deterministic-names", "-aessiv"]),
    ("-longnamemax 62", ["-longnamemax", "62"]),
    ("-longnamemax 100 -deterministic-names", ["-longnamemax", "100", "-deterministic-names"]),
]


def phase_a(only=None):
    print("== A: vaults created by gocryptfs, read and modified by this engine")
    for name, flags in VARIANTS:
        if only and only not in name:
            continue
        print(" - " + name)
        base = os.path.join(WORK, "A", name.replace(" ", "_").replace("(", "").replace(")", ""))
        c, m, tmp = base + "/c", base + "/m", base + "/tmp"
        os.makedirs(tmp)
        plain = "-plaintextnames" in flags
        if not real_init(c, flags):
            continue
        cfg = json.load(open(c + "/gocryptfs.conf"))
        with Mount(c, m):
            populate_real(m)
            snap, symlinks, odd = real_tree(m)
        check(len(symlinks) == 2 and len(odd) == 1, "test content was created (symlinks/odd names)")
        # 1. this engine reads exactly what gocryptfs shows (symlinks and non-UTF-8 names excepted)
        same_tree("read", snap, ve_tree(c))
        ok, out = real_fsck(c)
        check(ok, "gocryptfs -fsck on the pristine vault: " + out)
        # 2. this engine modifies it ...
        model = Model(snap)
        ve_workout(VE(c, model, tmp), plain)
        # ... and gocryptfs sees exactly that, and finds nothing to complain about
        with Mount(c, m):
            after, _, _ = real_tree(m)
        same_tree("after our writes, as seen by gocryptfs", model.t, after)
        ok, out = real_fsck(c)
        check(ok, "gocryptfs -fsck after our writes: " + out)
        # 3. gocryptfs modifies it again; this engine follows
        with Mount(c, m):
            real_workout(m, model)
            after2, _, _ = real_tree(m)
        same_tree("after gocryptfs' writes, as seen by us", after2, ve_tree(c))
        same_tree("model vs gocryptfs", model.t, after2)
        # 4. the config really is plain gocryptfs: nothing we added or changed in it
        cfg2 = json.load(open(c + "/gocryptfs.conf"))
        check(cfg == cfg2, "gocryptfs.conf untouched by all of the above")
        if plain:
            check(ve(c, "put", "gocryptfs.conf", os.path.join(WORK, "A", "x")).returncode != 0, "refuses to overwrite the config")
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------- phase B
CREATE = [
    ("default (AES-GCM)", {}, []),
    ("aessiv", {"FV_CIPHER": "aessiv"}, ["-aessiv"]),
    ("xchacha", {"FV_CIPHER": "xchacha"}, ["-xchacha"]),
    ("plaintext names", {"FV_PLAINNAMES": "1"}, ["-plaintextnames"]),
    ("deterministic", {"FV_DETERMINISTIC": "1"}, ["-deterministic-names"]),
    ("deterministic xchacha", {"FV_DETERMINISTIC": "1", "FV_CIPHER": "xchacha"}, ["-deterministic-names", "-xchacha"]),
    ("deterministic aessiv", {"FV_DETERMINISTIC": "1", "FV_CIPHER": "aessiv"}, ["-deterministic-names", "-aessiv"]),
    ("longnamemax 62", {"FV_LONGNAMEMAX": "62"}, ["-longnamemax", "62"]),
    ("longnamemax 100 deterministic", {"FV_LONGNAMEMAX": "100", "FV_DETERMINISTIC": "1"}, ["-longnamemax", "100", "-deterministic-names"]),
    ("longnamemax 255 (the default)", {"FV_LONGNAMEMAX": "255"}, []),
]


def phase_b(only=None):
    print("== B: vaults created by this engine, read and modified by gocryptfs")
    for name, env, reference_flags in CREATE:
        if only and only not in name:
            continue
        print(" - " + name)
        base = os.path.join(WORK, "B", name.replace(" ", "_").replace("(", "").replace(")", ""))
        c, m, ref, tmp = base + "/c", base + "/m", base + "/ref", base + "/tmp"
        os.makedirs(c)
        os.makedirs(tmp)
        plain = "FV_PLAINNAMES" in env
        e = dict(env)
        e["FV_SCRYPTN"] = "10"
        p = ve(c, "create", env=e)
        if not check(p.returncode == 0, "create: " + p.stderr.decode()):
            continue
        # the config must be what `gocryptfs -init` with the same flags writes (same flags, same order, same limits)
        real_init(ref, reference_flags)
        ours, theirs = json.load(open(c + "/gocryptfs.conf")), json.load(open(ref + "/gocryptfs.conf"))
        check(ours["FeatureFlags"] == theirs["FeatureFlags"], "FeatureFlags %s == %s" % (ours["FeatureFlags"], theirs["FeatureFlags"]))
        check(ours.get("LongNameMax") == theirs.get("LongNameMax"), "LongNameMax %s == %s" % (ours.get("LongNameMax"), theirs.get("LongNameMax")))
        check(ours["Version"] == theirs["Version"] == 2, "Version")
        so, st = ours["ScryptObject"], theirs["ScryptObject"]
        check({k: so[k] for k in ("N", "R", "P", "KeyLen")} == {k: st[k] for k in ("N", "R", "P", "KeyLen")}, "scrypt parameters")
        check(len(so["Salt"]) == len(st["Salt"]) and len(ours["EncryptedKey"]) == len(theirs["EncryptedKey"]), "salt / key blob sizes")
        check(sorted(os.listdir(c)) == sorted(os.listdir(ref)), "same files in the vault root: %s vs %s" % (sorted(os.listdir(c)), sorted(os.listdir(ref))))
        # populate with this engine, in the same way phase A populates through gocryptfs
        model = Model({})
        v = VE(c, model, tmp)
        v.mkdir("sizes")
        for sz in SIZES:
            v.put("sizes/f%d.bin" % sz, data(sz, sz))
        v.mkdir("names")
        for i, n in enumerate(ODD_NAMES):
            v.put("names/" + n, data(1000 + i, 10 + i * 37), how="putchunks" if i % 3 == 0 else "put")
        v.mkdir("D" * 255)
        v.put("D" * 255 + "/inner.txt", data(6, 1234))
        v.mkdir("deep")
        v.mkdir("deep/a")
        v.put("deep/a/file.txt", data(5, 300))
        v.mkdir("many")
        for i in range(120):
            v.put("many/f%03d.txt" % i, data(2000 + i, i))
        v.mkdir("empty")
        ve_workout(v, plain)
        with Mount(c, m):
            seen, symlinks, odd = real_tree(m)
            check(not symlinks and not odd, "no stray entries")
        same_tree("as seen by gocryptfs", model.t, seen)
        ok, out = real_fsck(c)
        check(ok, "gocryptfs -fsck: " + out)
        # gocryptfs writes into it, we read
        with Mount(c, m):
            real_workout(m, model)
            after, _, _ = real_tree(m)
        same_tree("after gocryptfs' writes, as seen by us", after, ve_tree(c))
        ok, out = real_fsck(c)
        check(ok, "gocryptfs -fsck after its own writes: " + out)
        # password change by this engine must leave a vault gocryptfs can unlock with the new password
        p = ve(c, "passwd", "new pw é", pw=PW)
        check(p.returncode == 0, "passwd: " + p.stderr.decode())
        check(try_mount(c, m + "2", pw="new pw é"), "gocryptfs unlocks with the new password")
        check(not try_mount(c, m + "3", pw=PW), "gocryptfs refuses the old password")
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------- phase C
def phase_c():
    print("== C: the official example filesystems")
    names = sorted(d for d in os.listdir(VECTORS) if d.startswith("v") and os.path.isdir(os.path.join(VECTORS, d)))
    for vec in names:
        print(" - " + vec)
        base = os.path.join(WORK, "C", vec)
        c, m, tmp = base + "/c", base + "/m", base + "/tmp"
        os.makedirs(tmp)
        shutil.copytree(os.path.join(VECTORS, vec), c, symlinks=True)
        real_ok = try_mount(c, m + "0", pw="test")
        ours = ve_tree(c, pw="test")
        check((ours is not None) == real_ok, "accepts the vault exactly when gocryptfs does (gocryptfs: %s, us: %s)" % (real_ok, ours is not None))
        if not real_ok or ours is None:
            continue
        with Mount(c, m, pw="test"):
            snap, symlinks, odd = real_tree(m)
        same_tree("read", {k: v for k, v in snap.items()}, ours)
        st = ve(c, "cat", "status.txt", pw="test")
        check(st.stdout == b"It works!\n", "status.txt")
        plain = "PlaintextNames" in json.load(open(c + "/gocryptfs.conf"))["FeatureFlags"]
        # write the way the app does and let gocryptfs judge
        model = Model(snap)
        v = VE(c, model, tmp, pw="test")
        v.mkdir("ve_new")
        v.mkdir("ve_new/sub")
        v.put("ve_new/short.txt", data(1, 5000))
        v.put("ve_new/" + "L" * 200 + ".txt", data(2, 70000))
        v.mkdir("ve_new/" + "D" * 220)
        v.put("ve_new/" + "D" * 220 + "/f", data(3, 10))
        v.mv("ve_new/short.txt", "ve_new/" + "M" * 190)
        v.mv("ve_new/" + "L" * 200 + ".txt", "ve_new/sub/moved.txt")
        v.rm("ve_new/" + "D" * 220)
        if "status.txt" in model.t:
            v.mv("status.txt", "status-renamed.txt")
        with Mount(c, m + "2", pw="test"):
            after, _, _ = real_tree(m + "2")
        same_tree("after our writes, as seen by gocryptfs", model.t, after)
        # a password change has to keep the vault's own format (96-bit nonce, no HKDF, ...)
        p = ve(c, "passwd", "np", pw="test")
        check(p.returncode == 0, "passwd: " + p.stderr.decode())
        check(try_mount(c, m + "3", pw="np"), "gocryptfs unlocks with the new password")
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------- phase D
def physical_files(c):
    out = set()
    for dp, _, fns in os.walk(c):
        for f in fns:
            out.add(os.path.relpath(os.path.join(dp, f), c))
    return out


def merge_new_files(src, dst, base):
    """What a file-sync tool does: everything that appeared in [src] since [base] is copied to [dst]
    unless [dst] already has a file of that name (the conflict loser is dropped or renamed)."""
    for rel in sorted(physical_files(src) - physical_files(base)):
        target = os.path.join(dst, rel)
        if not os.path.exists(target):
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(os.path.join(src, rel), target)


def phase_d():
    print("== D: two devices, one folder created offline on both (issue #228)")
    for det in (True, False):
        print(" - %s names" % ("deterministic" if det else "random-diriv"))
        base = os.path.join(WORK, "D", "det" if det else "rand")
        b, a, d2, m, tmp = [base + "/" + x for x in ("base", "linux", "android", "m", "tmp")]
        os.makedirs(tmp)
        real_init(b, ["-deterministic-names"] if det else [])
        with Mount(b, m):
            for n in ("F1", "keep"):
                with open(os.path.join(m, n), "wb") as f:
                    f.write(data(1, 100))
        shutil.copytree(b, a)
        shutil.copytree(b, d2)
        # Linux (gocryptfs): add F0 and FD0/FF0, delete F1
        with Mount(a, m):
            with open(os.path.join(m, "F0"), "wb") as f:
                f.write(data(2, 5000))
            os.mkdir(os.path.join(m, "FD0"))
            with open(os.path.join(m, "FD0", "FF0"), "wb") as f:
                f.write(data(3, 9000))
            os.remove(os.path.join(m, "F1"))
        # Android (this engine): add folder FD0 (same name) with FF1
        model = Model({})
        v = VE(d2, model, tmp)
        v.mkdir("FD0")
        v.put("FD0/FF1", data(4, 7000))
        # sync: Android's new files go to Linux, Linux's new files go to Android, Linux's deletion is applied
        merged_a = base + "/merged"
        shutil.copytree(a, merged_a)
        merge_new_files(d2, merged_a, b)
        with Mount(merged_a, m):
            real_view, _, _ = real_tree(m)
        ours = ve_tree(merged_a)
        same_tree("both implementations show the same merged tree", real_view, ours)
        keys = set(real_view)
        want = {"F0", "FD0", "FD0/FF0", "keep"}
        check(want <= keys and "F1" not in keys, "F0, FD0/FF0 present and F1 gone: %s" % sorted(keys))
        if det:
            check("FD0/FF1" in keys and real_view.get("FD0/FF1", (0, 0, 0))[2] == sha(data(4, 7000)), "FD0/FF1 survives the merge (same folder, no conflict)")
            check(ours is not None and ours.get("FD0/FF1") == real_view.get("FD0/FF1"), "...and this engine reads it too")
        else:
            check("FD0/FF1" not in keys, "random diriv: FD0/FF1 is lost to the diriv conflict -- in gocryptfs and in this engine alike")
        ok, out = real_fsck(merged_a)
        if det:
            check(ok, "gocryptfs -fsck on the merged vault: " + out)
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------- phase E
def visible(cmd_out):
    return None if cmd_out is None else sorted(cmd_out)


def phase_e():
    print("== E: damaged ciphertext -- this engine shows what gocryptfs shows")
    for name, flags in (("default", []), ("deterministic", ["-deterministic-names"]), ("long names", ["-longnamemax", "100"])):
        print(" - " + name)
        base = os.path.join(WORK, "E", name.replace(" ", "_"))
        c, m = base + "/c", base + "/m"
        os.makedirs(base)
        real_init(c, flags)
        with Mount(c, m):
            os.mkdir(m + "/d")
            for n in ("alpha", "beta", "g" * 120, "delta", "epsilon"):
                with open("%s/d/%s" % (m, n), "wb") as f:
                    f.write(data(len(n), 200))
            os.mkdir(m + "/d/" + "S" * 150)
        phys_d = [x for x in os.listdir(c) if x not in ("gocryptfs.conf", "gocryptfs.diriv")]
        phys_d = [x for x in phys_d if os.path.isdir(os.path.join(c, x)) and not x.startswith("gocryptfs.longname")][0]
        D = os.path.join(c, phys_d)

        def views(label):
            with Mount(c, m):
                try:
                    real = sorted(os.listdir(m + "/d"))
                except OSError:
                    real = None
            tree = ve_tree(c)
            ours = None
            if tree is not None and tree.get("d", ("D",))[0] != "E":      # an "E" row: the folder could not be listed
                ours = sorted(k[2:] for k in tree if k.startswith("d/") and "/" not in k[2:])
            check(real == ours, "%s: gocryptfs lists %s, we list %s" % (label, real, ours))

        views("pristine")
        entries = sorted(os.listdir(D))
        plain_files = [e for e in entries if not e.startswith("gocryptfs.") and os.path.isfile(os.path.join(D, e))]
        longs = [e for e in entries if e.startswith("gocryptfs.longname.") and not e.endswith(".name")]
        victim = plain_files[0]
        # 1. a sync tool's conflict copy
        shutil.copy2(os.path.join(D, victim), os.path.join(D, victim + ".sync-conflict-20260101-000000-ABCDEFG"))
        views("syncthing conflict copy")
        os.remove(os.path.join(D, victim + ".sync-conflict-20260101-000000-ABCDEFG"))
        # 2. non-canonical base64: same bytes, different spelling
        alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        spelled = victim[:-1] + alpha[alpha.index(victim[-1]) | 1] if (alpha.index(victim[-1]) & 15) == 0 else None
        if spelled and spelled != victim:
            shutil.copy2(os.path.join(D, victim), os.path.join(D, spelled))
            views("malleable base64 name")
            os.remove(os.path.join(D, spelled))
        # 3. trailing newline / padding
        shutil.copy2(os.path.join(D, victim), os.path.join(D, victim + "="))
        views("name with stray '='")
        os.remove(os.path.join(D, victim + "="))
        # 4. long names: sidecar missing / empty / too big / orphaned
        if longs:
            L = longs[0]
            side = os.path.join(D, L + ".name")
            orig = open(side, "rb").read()
            os.remove(side)
            views("long name without its .name file")
            open(side, "wb").close()
            views("empty .name file")
            open(side, "wb").write(b"A" * 345)
            views(".name file of 345 bytes")
            open(side, "wb").write(orig)
            views("sidecar restored")
            shutil.copy2(side, os.path.join(D, "gocryptfs.longname.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.name"))
            views("orphan .name file")
            os.remove(os.path.join(D, "gocryptfs.longname.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.name"))
        # 5. the diriv: all-zero, truncated, missing
        if "gocryptfs.diriv" in entries:
            iv = open(os.path.join(D, "gocryptfs.diriv"), "rb").read()
            open(os.path.join(D, "gocryptfs.diriv"), "wb").write(b"\0" * 16)
            views("all-zero diriv")
            open(os.path.join(D, "gocryptfs.diriv"), "wb").write(iv[:15])
            views("15-byte diriv")
            os.remove(os.path.join(D, "gocryptfs.diriv"))
            views("missing diriv")
            open(os.path.join(D, "gocryptfs.diriv"), "wb").write(iv)
            views("diriv restored")
        # 6. a stray file with a nonsense name
        open(os.path.join(D, "not a valid name"), "wb").write(b"x")
        views("nonsense file name")
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------- main
def main():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    wanted = [a for a in sys.argv[1:] if a in "ABCDE" and len(a) == 1]
    only = next((a for a in sys.argv[1:] if len(a) > 1), None)
    for letter, fn in (("A", phase_a), ("B", phase_b), ("C", phase_c), ("D", phase_d), ("E", phase_e)):
        if wanted and letter not in wanted:
            continue
        try:
            fn(only) if fn in (phase_a, phase_b) else fn()
        except Exception as e:   # a crash is a failure, but keep going
            import traceback
            traceback.print_exc()
            check(False, "phase %s crashed: %s" % (letter, e))
    print("RESULT fail=%d" % FAILS)
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
