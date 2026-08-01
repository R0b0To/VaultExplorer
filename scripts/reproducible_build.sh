#!/usr/bin/env bash
# Canonical release-APK build procedure. Used identically by:
#   - .github/workflows/build-release.yml
#   - metadata/com.aeidolon.vaultexplorer.yml (F-Droid buildserver recipe)
#   - local dev, for byte-for-byte comparison against either of the above
#
# Existing as a single script -- rather than independently hand-maintained
# step lists -- is itself a reproducibility fix: divergence between "what CI
# does" and "what the F-Droid recipe does" (e.g. this repo briefly had CI on
# Node 22 while the recipe pinned Node 26 for the pdf.js minifier) is
# exactly the kind of bug that produces two APKs that differ for reasons
# that have nothing to do with the source code.
#
# Builds ONE ABI's APK per invocation, via a Gradle product flavor -- not
# `flutter build apk --split-per-abi` -- because F-Droid's build model is
# one metadata Build entry = one versionCode = one output APK; it does not
# support one build producing several simultaneous outputs. See the flavor
# comment in android/app/build.gradle.kts and the VercodeOperation comment
# in metadata/com.aeidolon.vaultexplorer.yml.
#
# Usage: scripts/reproducible_build.sh <flavor>
#   flavor: one of arm64 | armeabi | x64
#   (must match a `create("...")` in android/app/build.gradle.kts's
#   productFlavors block, and the argument passed in the matching `build:`
#   entry in metadata/com.aeidolon.vaultexplorer.yml)
#
# Prerequisites (not handled here -- these are infra/toolchain installs,
# which CI and the F-Droid recipe each do their own way):
#   - JDK 17 on PATH or JAVA_HOME set (also auto-provisioned via the Gradle
#     toolchain in android/app/build.gradle.kts if a Foojay-compatible JDK
#     resolver can reach the network)
#   - Flutter 3.44.0 with `flutter` on PATH
#   - Android NDK r28d (28.2.13676358) installed -- must match the
#     `ndkVersion` pin in android/app/build.gradle.kts
#   - Node.js 26 on PATH (only needed the first time; scripts/build_pdfjs.sh
#     caches its output under android/app/src/main/assets/pdfjs -- set
#     FORCE_REBUILD_PDFJS=1 to bypass that cache)
set -euo pipefail

FLAVOR="${1:-}"
case "$FLAVOR" in
  arm64)   TARGET_PLATFORM="android-arm64" ;;
  armeabi) TARGET_PLATFORM="android-arm" ;;
  x64)     TARGET_PLATFORM="android-x64" ;;
  *)
    echo "usage: $0 <arm64|armeabi|x64>" >&2
    exit 1
    ;;
esac

ORIG_DIR="$(pwd)"   # repo root -- all call sites invoke this script from there
CANONICAL_BUILD_DIR="/tmp/vaultexplorer_canonical_build"

# Normalize working directory path so libapp.so (the compiled Dart AOT
# snapshot) and any native code compiled from PUB_CACHE produce identical
# bytes on GitHub Actions, the F-Droid buildserver, and local dev machines,
# regardless of what absolute path each checked this repo out to.
if [ "$ORIG_DIR" != "$CANONICAL_BUILD_DIR" ]; then
  echo "Copying repository into canonical workspace $CANONICAL_BUILD_DIR..."
  rm -rf "$CANONICAL_BUILD_DIR"
  mkdir -p "$CANONICAL_BUILD_DIR"
  tar -cf - . | (cd "$CANONICAL_BUILD_DIR" && tar -xf -)

  cd "$CANONICAL_BUILD_DIR"
  ./scripts/reproducible_build.sh "$FLAVOR"

  OUT_NAME="app-${FLAVOR}-release.apk"
  mkdir -p "$ORIG_DIR/build/app/outputs/flutter-apk"
  cp "$CANONICAL_BUILD_DIR/build/app/outputs/flutter-apk/$OUT_NAME" \
     "$ORIG_DIR/build/app/outputs/flutter-apk/$OUT_NAME"
  echo "== Success ============================================="
  echo "Copied reproducible artifact to $ORIG_DIR/build/app/outputs/flutter-apk/$OUT_NAME"
  exit 0
fi

echo "== Toolchain & Environment ============================="
echo "Flavor             : $FLAVOR ($TARGET_PLATFORM)"
echo "Working directory   : $(pwd)"
java -version 2>&1 | head -n 2
flutter --version | head -n 2
node --version 2>/dev/null || echo "node: not on PATH (fine if assets/pdfjs is already built)"
echo "========================================================"

# Pre-check: warn if CRLF line endings exist in static assets or scripts.
if command -v file >/dev/null 2>&1; then
  if find assets/ scripts/ -type f -exec file {} + 2>/dev/null | grep -q 'CRLF'; then
    echo "warning: CRLF line endings detected in static text files!" >&2
    echo "         Run 'git add --renormalize .' to enforce LF line endings." >&2
  fi
fi

# Embedded timestamps: derive from commit timestamp, not wall-clock time.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH ($(date -u -d "@$SOURCE_DATE_EPOCH" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH"))"

# Placed under checkout root by convention (matches
# metadata/com.aeidolon.vaultexplorer.yml's `export PUB_CACHE=$(pwd)/.pub-cache`).
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

# --target-platform restricts which Dart AOT snapshot(s) get compiled at
# all (a build-time optimization -- Gradle's per-flavor ndk.abiFilters is
# what actually restricts which .so end up packaged, for every native
# library regardless of source, and is the real correctness mechanism).
$TASKSET flutter build apk --release --flavor "$FLAVOR" --target-platform "$TARGET_PLATFORM"

APK="build/app/outputs/flutter-apk/app-${FLAVOR}-release.apk"
echo "Built: $APK"

# ==============================================================================
# VERIFICATION CHECKS
# Fail loudly if any reproducibility patch, or the ABI split itself, didn't
# apply as expected, rather than silently shipping a bad APK.
# ==============================================================================
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$APK" -d "$VERIFY_DIR"
fail=0

echo "== Verification Checks ================================="

# Check 1: exactly one lib/<abi> directory is present, and it's the right one.
ABI_DIR_FOR_FLAVOR="armeabi-v7a"
[ "$FLAVOR" = "arm64" ] && ABI_DIR_FOR_FLAVOR="arm64-v8a"
[ "$FLAVOR" = "x64" ] && ABI_DIR_FOR_FLAVOR="x86_64"
LIB_ABIS="$(find "$VERIFY_DIR/lib" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tr '\n' ' ')"
if [ "$LIB_ABIS" != "$ABI_DIR_FOR_FLAVOR " ]; then
  echo "error: expected lib/$ABI_DIR_FOR_FLAVOR only, got: $LIB_ABIS" >&2
  fail=1
fi

# Check 2: .note.gnu.build-id was removed from project native libraries.
for so in "$VERIFY_DIR"/lib/*/libvaultexplorer.so "$VERIFY_DIR"/lib/*/libdartjni.so; do
  [ -f "$so" ] || continue
  if readelf -W -S "$so" 2>/dev/null | grep -q '\.note\.gnu\.build-id'; then
    echo "error: $so still has .note.gnu.build-id -- build-id removal patch failed" >&2
    fail=1
  fi
done

# Check 3: CMake build paths (.cxx / build_tree) were stripped from native binaries.
for so in "$VERIFY_DIR"/lib/*/libvaultexplorer.so; do
  [ -f "$so" ] || continue
  if strings "$so" 2>/dev/null | grep -qE '\.cxx|/tmp/vaultexplorer_canonical_build'; then
    echo "error: $so contains unmapped build-tree paths -- CMake prefix-map missing!" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Verification FAILED: Output APK is not reproducible!" >&2
  exit 1
fi

echo "OK: All reproducibility verification checks passed for $APK"