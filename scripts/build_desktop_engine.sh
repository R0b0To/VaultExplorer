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
echo "engine library : $OUT/libvaultexplorer_engine.so"
echo "smoke test     : $OUT/ve_smoke_test fat exfat ntfs ext4"
