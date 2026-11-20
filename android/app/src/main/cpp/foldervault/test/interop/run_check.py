#!/usr/bin/env python3
"""Run upstream's cryfs-check on a vault directory, answering the interactive password prompt through a pty."""
import os, pty, select, sys, time

def run(vault, state, password="mypassword", binary="/home/claude/build/cargo-target/debug/cryfs-check", timeout=1500):
    env = dict(os.environ, CRYFS_LOCAL_STATE_DIR=state, CRYFS_NO_UPDATE_CHECK="1", TERM="dumb",
               LD_LIBRARY_PATH="/home/claude/build/rs/lib")
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(binary, [binary, vault], env)
    out = b""; sent = False; deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            out += data
            if not sent and b"assword" in out:
                os.write(fd, (password + "\n").encode()); sent = True
    try:
        _, status = os.waitpid(pid, 0)
        code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
    except ChildProcessError:
        code = -1
    return code, out.decode(errors="replace")

if __name__ == "__main__":
    code, text = run(sys.argv[1], sys.argv[2])
    print(text)
    print("EXIT CODE:", code)
    sys.exit(code if code >= 0 else 1)
