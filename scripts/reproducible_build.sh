#!/usr/bin/env bash
# Canonical release-APK build procedure. Used identically by:
#   - .github/workflows/build-release.yml
#   - metadata/com.aeidolon.vaultexplorer.yml (F-Droid buildserver recipe)
#   - local dev, for byte-for-byte comparison against either of the above
#
# Existing as a single script -- rather than three independently
# hand-maintained step lists -- is itself a reproducibility fix: divergence
# between "what CI does" and "what the F-Droid recipe does" (e.g. this repo
# briefly had CI on Node 22 while the recipe pinned Node 26 for the pdf.js
# minifier) is exactly the kind of bug that produces two APKs that differ
# for reasons that have nothing to do with the source code.
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
cd "$(dirname "$0")/.."   # repo root

echo "== Toolchain versions in use =========================="
java -version
flutter --version
node --version 2>/dev/null || echo "node: not on PATH (fine if assets/pdfjs is already built)"
echo "========================================================"

# Embedded timestamps: derive from the commit being built, not wall-clock
# time, so the same commit always produces the same SOURCE_DATE_EPOCH
# regardless of when or where it's built. Overridable for the (rare) case
# of comparing against a build made from a dirty/unpushed tree.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH ($(date -u -d "@$SOURCE_DATE_EPOCH" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH"))"

# Placed under the checkout root by convention (matches
# metadata/com.aeidolon.vaultexplorer.yml's `export PUB_CACHE=$(pwd)/.pub-cache`)
# rather than left to default to $HOME/.pub-cache, whose path is unique per
# machine/user. The projectDir-based -ffile-prefix-map fix in
# android/app/build.gradle.kts is what actually neutralizes PUB_CACHE's
# absolute path leaking into native pub packages' compiled output --
# this is just for consistency / defense in depth on top of that.
export PUB_CACHE="${PUB_CACHE:-$(pwd)/.pub-cache}"
echo "PUB_CACHE=$PUB_CACHE"

flutter config --no-analytics
flutter pub get

# R8/D8 output can depend on CPU core count (F-Droid's "Concurrency"
# reproducibility notes). Pin to one core rather than mutating the whole
# machine's online CPU set.
if command -v taskset >/dev/null 2>&1; then
  TASKSET="taskset -c 0"
else
  TASKSET=""
  echo "warning: taskset not found -- R8 output may not match a build that used it" >&2
fi

$TASKSET flutter build apk --release --target-platform android-arm64

APK="build/app/outputs/flutter-apk/app-release.apk"
echo "Built: $APK"

# Fail loudly if the build-id-removal patch didn't apply, rather than
# silently shipping an unreproducible APK.
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$APK" -d "$VERIFY_DIR"
fail=0
for so in "$VERIFY_DIR"/lib/*/libdartjni.so; do
  [ -f "$so" ] || continue
  if readelf -W -S "$so" 2>/dev/null | grep -q '\.note\.gnu\.build-id'; then
    echo "error: $so still has .note.gnu.build-id -- reproducibility patch didn't apply" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "OK: $APK"
