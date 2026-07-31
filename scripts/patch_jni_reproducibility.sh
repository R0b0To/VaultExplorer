#!/usr/bin/env bash
# Appends -Wl,--build-id=none to jni pub package's CMakeLists.txt
# so libdartjni.so doesn't embed a random build ID -- required for F-Droid.
set -euo pipefail

PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
HOSTED_DIR="$PUB_CACHE_DIR/hosted/pub.dev"

if [ ! -d "$HOSTED_DIR" ]; then
  if [ -d "$PUB_CACHE_DIR/hosted/pub.dartlang.org" ]; then
    HOSTED_DIR="$PUB_CACHE_DIR/hosted/pub.dartlang.org"
  else
    echo "warning: pub cache directory not found -- skipping." >&2
    exit 0
  fi
fi

JNI_DIR="$(find "$HOSTED_DIR" -maxdepth 1 -name 'jni-*' 2>/dev/null | head -n 1 || true)"

if [ -z "$JNI_DIR" ]; then
  echo "warning: no jni-* package found under $HOSTED_DIR -- skipping." >&2
  exit 0
fi

# Standard F-Droid patch: insert --build-id=none into jni's CMake link options
sed -i -E 's/^(-Wl,)(--build-id=none,)?/\1--build-id=none,/' "$JNI_DIR/src/CMakeLists.txt" 2>/dev/null || \
sed -i -e 's/-Wl,/-Wl,--build-id=none,/' "$JNI_DIR/src/CMakeLists.txt" 2>/dev/null || true

echo "patch_jni_reproducibility: patched $JNI_DIR/src/CMakeLists.txt"