#!/usr/bin/env bash
# Appends CMAKE_SHARED_LINKER_FLAGS to jni pub package's CMakeLists.txt
set -euo pipefail

PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
HOSTED_DIR="$PUB_CACHE_DIR/hosted"

if [ ! -d "$HOSTED_DIR" ]; then
  echo "warning: pub cache hosted dir not found at $HOSTED_DIR -- skipping." >&2
  exit 0
fi

patched=0
while IFS= read -r -d '' cmakelists; do
  if grep -q -- "--build-id=none" "$cmakelists"; then
    continue   # already patched
  fi
  
  echo -e '\nset(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--build-id=none")\nadd_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}=/jni")\n' >> "$cmakelists"
  patched=$((patched + 1))
done < <(find "$HOSTED_DIR" -type f -name CMakeLists.txt -path "*/jni-*/*" -print0 2>/dev/null || true)

echo "patch_jni_reproducibility: patched $patched CMakeLists.txt file(s)"