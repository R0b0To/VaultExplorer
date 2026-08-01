#!/usr/bin/env bash
# Canonical release-APK build procedure. Used identically by:
#   - .github/workflows/build-release.yml
#   - metadata/com.aeidolon.vaultexplorer.yml (F-Droid buildserver recipe)
#   - local dev, for byte-for-byte comparison against either of the above
#
# Reproducibility fixes enforced in this setup:
#   1. Identical Node/JDK/Flutter toolchain versions.
#   2. Fixed SOURCE_DATE_EPOCH derived from git commit timestamp.
#   3. Isolated PUB_CACHE under checkout root.
#   4. CPU affinity pinning via taskset for deterministic R8/D8 output.
#   5. LF line-ending normalization for static assets (.gitattributes).
#   6. CMake -ffile-prefix-map stripping dynamic .cxx build paths in C++ libs.
#   7. Removal of .note.gnu.build-id from shared libraries.
#
# Prerequisites (infra/toolchain installs):
#   - JDK 17 on PATH or JAVA_HOME set
#   - Flutter 3.44.0 with `flutter` on PATH
#   - Android NDK r28d (28.2.13676358) installed
#   - Node.js 26 on PATH (optional if assets/pdfjs is already built)


# Normalize working directory path so libapp.so (dart_plugin_registrant.dart)
# produces identical bytes on GitHub Actions, F-Droid, and local dev machines.
CANONICAL_BUILD_DIR="/tmp/vaultexplorer_canonical_build"
CURRENT_DIR="$(pwd)"

if [ "$CURRENT_DIR" != "$CANONICAL_BUILD_DIR" ]; then
  echo "Normalizing build path to $CANONICAL_BUILD_DIR..."
  rm -rf "$CANONICAL_BUILD_DIR"
  mkdir -p "$(dirname "$CANONICAL_BUILD_DIR")"
  ln -s "$CURRENT_DIR" "$CANONICAL_BUILD_DIR"
  cd "$CANONICAL_BUILD_DIR"
fi

set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

echo "== Toolchain & Environment ============================="
echo "Working directory : $(pwd)"
java -version 2>&1 | head -n 2
flutter --version | head -n 2
node --version 2>/dev/null || echo "node: not on PATH (fine if assets/pdfjs is already built)"
echo "========================================================"

# Pre-check: Warn if CRLF line endings exist in static assets or scripts
if command -v file >/dev/null 2>&1; then
  if find assets/ scripts/ -type f -exec file {} + 2>/dev/null | grep -q 'CRLF'; then
    echo "warning: CRLF line endings detected in static text files!" >&2
    echo "         Run 'git add --renormalize .' to enforce LF line endings." >&2
  fi
fi

# Embedded timestamps: derive from commit timestamp, not wall-clock time
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH ($(date -u -d "@$SOURCE_DATE_EPOCH" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH"))"

# Placed under checkout root by convention (matches F-Droid recipe export)
export PUB_CACHE="${PUB_CACHE:-$(pwd)/.pub-cache}"
echo "PUB_CACHE=$PUB_CACHE"

flutter config --no-analytics
flutter pub get

# R8/D8 output can depend on CPU core count. Pin to one core if available.
if command -v taskset >/dev/null 2>&1; then
  TASKSET="taskset -c 0"
else
  TASKSET=""
  echo "warning: taskset not found -- R8 output may not match a build that used it" >&2
fi

# Build release APK
$TASKSET flutter build apk --release --target-platform android-arm64

APK="build/app/outputs/flutter-apk/app-release.apk"
echo "Built: $APK"

# ==============================================================================
# VERIFICATION CHECKS
# Fail loudly if any reproducibility patches failed to apply during compilation.
# ==============================================================================
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$APK" -d "$VERIFY_DIR"
fail=0

echo "== Verification Checks ================================="

# Check 1: Ensure .note.gnu.build-id was removed from ALL native libraries
for so in "$VERIFY_DIR"/lib/*/*.so; do
  [ -f "$so" ] || continue
  if readelf -W -S "$so" 2>/dev/null | grep -q '\.note\.gnu\.build-id'; then
    echo "error: $so still has .note.gnu.build-id -- build-id removal patch failed" >&2
    fail=1
  fi
done

# Check 2: Ensure CMake build paths (.cxx) were stripped from native binaries
for so in "$VERIFY_DIR"/lib/*/libvaultexplorer.so; do
  [ -f "$so" ] || continue
  if strings "$so" 2>/dev/null | grep -q '\.cxx'; then
    echo "error: $so contains unmapped .cxx paths -- CMake prefix-map missing!" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Verification FAILED: Output APK is not reproducible!" >&2
  exit 1
fi

echo "OK: All reproducibility verification checks passed for $APK"