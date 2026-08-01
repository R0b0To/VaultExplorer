#!/usr/bin/env bash
# Canonical release-APK build procedure for single-ABI target builds.
set -euo pipefail

# Container Safeguard 1: Allow Git operations in Docker containers
git config --global --add safe.directory '*' 2>/dev/null || true

# Container Safeguard 4: never let `flutter` write directly to a live pipe.
# flutter_tools has a long-standing, still-unresolved bug where its stdout
# writer throws an unhandled exception and crashes the whole process the
# moment the pipe it's writing to closes or hiccups mid-write
# (flutter/flutter#8580, #99617, #51872, #81660 -- 2017 through present).
# Buildserver/CI log capture is exactly the kind of pipe that triggers this
# -- it hit us on the very first `flutter --version` call, while
# flutter_tools was still bootstrapping itself. Buffering through a real
# file and `cat`-ing it afterward sidesteps this entirely: `cat` exits
# quietly on a closed pipe (default SIGPIPE handling) instead of throwing.
run_flutter() {
  local log
  log="$(mktemp)"
  set +e
  "$@" >"$log" 2>&1
  local rc=$?
  set -e
  cat "$log"
  rm -f "$log"
  return $rc
}

FLAVOR="${1:-}"
case "$FLAVOR" in
  arm64)
    TARGET_PLATFORM="android-arm64"
    TARGET_ABI="arm64-v8a"
    OFFSET=1
    ;;
  armeabi)
    TARGET_PLATFORM="android-arm"
    TARGET_ABI="armeabi-v7a"
    OFFSET=2
    ;;
  x64)
    TARGET_PLATFORM="android-x64"
    TARGET_ABI="x86_64"
    OFFSET=3
    ;;
  *)
    echo "usage: $0 <arm64|armeabi|x64>" >&2
    exit 1
    ;;
esac

ORIG_DIR="$(pwd)"
CANONICAL_BUILD_DIR="/tmp/vaultexplorer_canonical_build"

if [ "$ORIG_DIR" != "$CANONICAL_BUILD_DIR" ]; then
  echo "Copying repository into canonical workspace $CANONICAL_BUILD_DIR..."
  rm -rf "$CANONICAL_BUILD_DIR"
  mkdir -p "$CANONICAL_BUILD_DIR"
  tar -cf - . | (cd "$CANONICAL_BUILD_DIR" && tar -xf -)

  cd "$CANONICAL_BUILD_DIR"
  # Container Safeguard 2: Explicitly invoke bash for re-execution
  bash ./scripts/reproducible_build.sh "$FLAVOR"

  OUT_NAME="app-${FLAVOR}-release.apk"
  mkdir -p "$ORIG_DIR/build/app/outputs/flutter-apk"
  cp "$CANONICAL_BUILD_DIR/build/app/outputs/flutter-apk/$OUT_NAME" \
     "$ORIG_DIR/build/app/outputs/flutter-apk/$OUT_NAME"
  echo "== Success ============================================="
  echo "Copied reproducible artifact to $ORIG_DIR/build/app/outputs/flutter-apk/$OUT_NAME"
  exit 0
fi

echo "== Toolchain & Environment ============================="
echo "Target             : $FLAVOR ($TARGET_PLATFORM / $TARGET_ABI)"
echo "Working directory   : $(pwd)"
java -version
run_flutter flutter --version
node --version 2>/dev/null || echo "node: not on PATH (fine if assets/pdfjs is already built)"
echo "========================================================"

# Container Safeguard 3: Point Flutter at Android SDK if defined
if [ -n "${ANDROID_HOME:-}" ]; then
  run_flutter flutter config --android-sdk "$ANDROID_HOME" >/dev/null 2>&1 || true
fi

# Pre-check: warn if CRLF line endings exist in static assets or scripts.
if command -v file >/dev/null 2>&1; then
  if find assets/ scripts/ -type f -exec file {} + 2>/dev/null | grep -q 'CRLF'; then
    echo "warning: CRLF line endings detected in static text files!" >&2
    echo "         Run 'git add --renormalize .' to enforce LF line endings." >&2
  fi
fi

# Embedded timestamps: derive from commit timestamp
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH ($(date -u -d "@$SOURCE_DATE_EPOCH" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH"))"

export PUB_CACHE="${PUB_CACHE:-$(pwd)/.pub-cache}"
echo "PUB_CACHE=$PUB_CACHE"

run_flutter flutter config --no-analytics
run_flutter flutter pub get

# Extract base build number from pubspec.yaml
BASE_BUILD_NUMBER=$(grep '^version:' pubspec.yaml | sed -n 's/.*+\([0-9]*\)/\1/p')
if [ -z "$BASE_BUILD_NUMBER" ]; then
  BASE_BUILD_NUMBER=1
fi

# Calculate final versionCode matching F-Droid VercodeOperation (100 * %c + OFFSET)
VERSION_CODE=$(( BASE_BUILD_NUMBER * 100 + OFFSET ))
echo "Calculated versionCode for $FLAVOR: $VERSION_CODE (Base $BASE_BUILD_NUMBER * 100 + $OFFSET)"

# Export target ABI for build.gradle.kts System.getenv("VAULTEXPLORER_TARGET_ABI")
export VAULTEXPLORER_TARGET_ABI="$TARGET_ABI"

# Pin R8/D8 output to single core
if command -v taskset >/dev/null 2>&1; then
  TASKSET="taskset -c 0"
else
  TASKSET=""
  echo "warning: taskset not found -- R8 output may not match a build that used it" >&2
fi

# Build release APK
run_flutter $TASKSET flutter build apk --release \
  --target-platform "$TARGET_PLATFORM" \
  --build-number "$VERSION_CODE"

RAW_APK="build/app/outputs/flutter-apk/app-release.apk"
OUT_APK="build/app/outputs/flutter-apk/app-${FLAVOR}-release.apk"
cp "$RAW_APK" "$OUT_APK"
echo "Built: $OUT_APK"

# Verification Checks
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$OUT_APK" -d "$VERIFY_DIR"
fail=0

echo "== Verification Checks ================================="

# Check 1: exactly one lib/<abi> directory is present, and it's the right one.
LIB_ABIS="$(ls -1 "$VERIFY_DIR/lib" 2>/dev/null | tr '\n' ' ' | xargs)"
if [ "$LIB_ABIS" != "$TARGET_ABI" ]; then
  echo "error: expected lib/$TARGET_ABI only, got: '$LIB_ABIS'" >&2
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

# Check 3: Ensure dynamic local user build paths (.cxx) were stripped.
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

echo "OK: All reproducibility verification checks passed for $OUT_APK"