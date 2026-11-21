#!/usr/bin/env python3
"""Keeps the portable C++ engine free of JNI and Android headers.

The directories listed in PORTABLE_DIRS (the volume engine, the folder-vault core, the volume
manager, the transfer and crypto helpers, ...) are meant to build for a desktop front-end as well
as for Android. That only holds while none of their files includes <jni.h>, an <android/...>
header or one of the bridge headers (jni_callbacks.h, jni_bridge_common.h, ...). Everything such
a file needs from the host goes through platform/engine_hooks.h (progress, cancellation, USB I/O)
and platform/engine_log.h (logging), which have no JNI or Android type in them.

This is a cheap static check on #include lines -- it needs no compiler and no third-party headers --
so it can run anywhere, including CI before the native build. For a stronger check, compile an
engine translation unit with no jni.h and no android/ directory on the include path.

Usage:  python3 scripts/check_engine_portable.py
Exit status 1 if any violation is found.
"""

import re
import sys
from pathlib import Path

CPP_ROOT = Path(__file__).resolve().parent.parent / "android" / "app" / "src" / "main" / "cpp"

PORTABLE_DIRS = [
    "session", "io", "filesystems", "containers", "crypto", "foldervault",
    "volman", "xfer", "platform", "Common", "archive", "docscan", "dislocker",
]

# #include <jni.h> | "jni_callbacks.h" | "jni/anything.h" | <android/anything.h> | session_guard_jni.h ...
FORBIDDEN = re.compile(
    r'^\s*#\s*include\s*[<"]'
    r'(jni\.h|jni/[A-Za-z0-9_./]+|jni_[A-Za-z0-9_]+\.h|[A-Za-z0-9_]+_jni\.h|android/[A-Za-z0-9_./]+)'
    r'[>"]'
)

# The one place allowed to reach for the NDK: the logging shim, behind #if defined(__ANDROID__).
ALLOWED = {"platform/engine_log.h"}

SOURCE_SUFFIXES = {".cpp", ".cc", ".c", ".h", ".hpp"}


def violations():
    found = []
    for d in PORTABLE_DIRS:
        base = CPP_ROOT / d
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in SOURCE_SUFFIXES or "test" in path.relative_to(base).parts:
                continue
            rel = path.relative_to(CPP_ROOT).as_posix()
            if rel in ALLOWED:
                continue
            for lineno, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
                if FORBIDDEN.match(line):
                    found.append((rel, lineno, line.strip()))
    return found


def main():
    if not CPP_ROOT.is_dir():
        print(f"cannot find {CPP_ROOT}", file=sys.stderr)
        return 2
    found = violations()
    if not found:
        print("engine portability OK: no JNI or Android includes in " + ", ".join(PORTABLE_DIRS))
        return 0
    print("Portable engine files must not include JNI or Android headers:\n")
    for rel, lineno, line in found:
        print(f"  {rel}:{lineno}: {line}")
    print("\nUse platform/engine_hooks.h for host callbacks and platform/engine_log.h for logging;"
          "\nJNI-specific code belongs under jni/.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
