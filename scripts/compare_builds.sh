#!/usr/bin/env bash
# Compares two APKs built from the same commit (e.g. one from CI, one from
# a local build, one from the F-Droid buildserver) using F-Droid's
# documented verification method:
# https://f-droid.org/docs/Reproducible_Builds/#diffing-the-apk
#
# apksigcopier's `compare` copies the first APK's signature onto a copy of
# the second and checks whether the result verifies -- this is the same
# check F-Droid's publish step performs, and is signature-scheme-aware
# (v1 vs v2/v3 cover different subsets of the APK's bytes) in a way a plain
# `diff`/`sha256sum` on the raw files isn't. If it doesn't verify, this
# falls back to diffoscope for a byte-level breakdown of what differs.
#
# Usage: scripts/compare_builds.sh <apk-a> <apk-b> [--unsigned]
#   --unsigned   pass through to apksigcopier if apk-b is unsigned
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <apk-a> <apk-b> [--unsigned]" >&2
  exit 1
fi

APK_A="$1"
APK_B="$2"
EXTRA_ARGS=("${@:3}")

for tool in apksigcopier; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found. Install with: pip install apksigcopier" >&2
    exit 1
  }
done

echo "== apksigcopier compare ================================"
if apksigcopier compare "${EXTRA_ARGS[@]}" "$APK_A" "$APK_B"; then
  echo "VERIFIED: $APK_A and $APK_B are reproducible (identical apart from signature)."
  exit 0
fi

echo
echo "NOT VERIFIED. Falling back to diffoscope for details..."
echo "=========================================================="

if ! command -v diffoscope >/dev/null 2>&1; then
  echo "diffoscope not found -- install with: pip install diffoscope" >&2
  echo "(or apt install diffoscope, for the full format-aware backend set)" >&2
  exit 1
fi

REPORT="./diffoscope-report.html"
diffoscope "$APK_A" "$APK_B" --html "$REPORT" || true
echo "Report written to $REPORT"
exit 1
