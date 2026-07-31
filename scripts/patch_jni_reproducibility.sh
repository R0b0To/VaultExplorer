#!/usr/bin/env bash
# Patches jni pub package's CMakeLists.txt to strip build-id at the target level
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
  
  cat << 'EOF' >> "$cmakelists"

if(TARGET dartjni)
  target_link_options(dartjni PRIVATE "-Wl,--build-id=none")
  target_compile_options(dartjni PRIVATE "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=/jni")
else()
  string(APPEND CMAKE_SHARED_LINKER_FLAGS " -Wl,--build-id=none")
endif()
EOF

  patched=$((patched + 1))
done < <(find "$HOSTED_DIR" -type f -name CMakeLists.txt -path "*/jni-*/*" -print0 2>/dev/null || true)

echo "patch_jni_reproducibility: patched $patched CMakeLists.txt file(s)"