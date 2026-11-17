#!/usr/bin/env bash
# Builds the desktop (dart:ffi) engine library + its black-box smoke test.
#
#   scripts/build_desktop_engine.sh [output-dir]      (default: build/desktop-engine)
#
# Linux: needs cmake (>= 3.22), ninja, a C/C++ toolchain, git, zlib headers, and network access
# (the engine's third-party sources are fetched by CMake FetchContent on first configure).
# Output: <output-dir>/libvaultexplorer_engine.so and <output-dir>/ve_smoke_test.
# Windows: see docs/desktop-port.md (MSYS2 UCRT64 toolchain; not yet validated).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/desktop-engine}"
cmake -S "$ROOT/android/app/src/main/cpp" -B "$OUT" -G Ninja \
  -DVAULTEXPLORER_DESKTOP=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$OUT" --target vaultexplorer ve_smoke_test
echo
if [[ "$(uname -s)" == "Linux" ]]; then
  if grep -q '^VE_FUSE3_INCLUDE_DIR:PATH=/' "$OUT/CMakeCache.txt" 2>/dev/null; then
    echo "OS mounts      : ENABLED (FUSE 3; needs libfuse3 + fusermount3 at run time)"
  else
    echo "OS mounts      : DISABLED -- libfuse3 development headers not found."
    echo "                 Install libfuse3-dev (Debian/Ubuntu/KDE neon) or fuse3-devel (Fedora/openSUSE),"
    echo "                 then run this script again."
  fi
fi
echo "engine library : $OUT/libvaultexplorer_engine.so"
echo "smoke test     : $OUT/ve_smoke_test fat exfat ntfs ext4"
