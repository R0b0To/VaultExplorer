#!/usr/bin/env bash
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

if [ -f "$JNI_DIR/src/CMakeLists.txt" ]; then
  if ! grep -q -- "--build-id=none" "$JNI_DIR/src/CMakeLists.txt"; then
    echo -e '\nset(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--build-id=none")\n' >> "$JNI_DIR/src/CMakeLists.txt"
    echo "patch_jni_reproducibility: successfully patched $JNI_DIR/src/CMakeLists.txt"
  fi
fi