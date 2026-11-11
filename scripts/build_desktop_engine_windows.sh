#!/usr/bin/env bash
# Cross-compiles the desktop engine for 64-bit Windows from Linux (MinGW-w64) and, if Wine is present, runs the
# engine smoke test against the resulting DLL.
#
#   scripts/build_desktop_engine_windows.sh [output-dir]     (default: build/desktop-engine-win)
#
# Needs: cmake (>= 3.22), ninja, git, network access (CMake fetches the engine's third-party sources),
#   sudo apt install g++-mingw-w64-x86-64-posix gcc-mingw-w64-x86-64-posix        # the "posix" thread model
#   sudo apt install wine64                                                        # optional: run the test
# Output: <output-dir>/vaultexplorer_engine.dll  (self-contained: only system DLLs are imported)
#         <output-dir>/ve_smoke_test.exe
# Building ON Windows instead? Use the MSYS2 UCRT64 shell (pacman -S mingw-w64-ucrt-x86_64-{gcc,cmake,ninja}
# git) and run the same two cmake commands below without the toolchain file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/desktop-engine-win}"
cmake -S "$ROOT/android/app/src/main/cpp" -B "$OUT" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/scripts/toolchains/mingw-w64-x86_64.cmake" \
  -DVAULTEXPLORER_DESKTOP=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$OUT" --target vaultexplorer ve_smoke_test
echo
echo "engine DLL : $OUT/vaultexplorer_engine.dll"
if command -v wine >/dev/null 2>&1; then
  echo "running the smoke test under Wine (crypto + digests + single-file; pass 'fat exfat ntfs ext4' for the filesystem tests)..."
  (cd "$OUT" && WINEDEBUG=-all wine ve_smoke_test.exe crypto)
else
  echo "Wine not found: copy $OUT/vaultexplorer_engine.dll and ve_smoke_test.exe to a Windows machine and run"
  echo "  ve_smoke_test.exe fat exfat ntfs ext4"
fi
