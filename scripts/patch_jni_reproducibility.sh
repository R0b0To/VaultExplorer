#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo "=== JNI Patch Diagnostic Start ====================="
echo "===================================================="
echo "PUB_CACHE env var: '${PUB_CACHE:-<not set>}'"
echo "USER_HOME:         '$HOME'"
echo "PWD:               '$(pwd)'"

CANDIDATES=()
[ -n "${PUB_CACHE:-}" ] && CANDIDATES+=("$PUB_CACHE")
CANDIDATES+=("$HOME/.pub-cache")
CANDIDATES+=("/tmp/.pub-cache")
CANDIDATES+=("$(pwd)/.pub-cache")

SEARCH_DIRS=()
for dir in "${CANDIDATES[@]}"; do
  if [ -d "$dir" ]; then
    echo "[FOUND] Search candidate directory exists: $dir"
    SEARCH_DIRS+=("$dir")
  else
    echo "[SKIP] Search candidate directory does NOT exist: $dir"
  fi
done

if [ ${#SEARCH_DIRS[@]} -eq 0 ]; then
  echo "::warning::No pub cache directories exist on disk! Run 'flutter pub get' first."
  exit 0
fi

found=0
patched=0

for cache_dir in "${SEARCH_DIRS[@]}"; do
  echo "Scanning inside: $cache_dir"
  while IFS= read -r -d '' cmakelists; do
    found=$((found + 1))
    echo "----------------------------------------------------"
    echo "Found JNI CMakeLists.txt ($found): $cmakelists"
    
    if grep -q -- "--build-id=none" "$cmakelists"; then
      echo "Status: ALREADY PATCHED. Skipping."
      continue
    fi

    echo "Status: UNPATCHED. Applying patch..."
    echo "--- [BEFORE PATCH (last 5 lines)] ---"
    tail -n 5 "$cmakelists" || true
    echo "------------------------------------"

    sed -i -e 's/-Wl,/-Wl,--build-id=none,/' "$cmakelists" 2>/dev/null || true
    cat << 'EOF' >> "$cmakelists"

set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--build-id=none")
add_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}=/jni")
EOF

    echo "--- [AFTER PATCH (last 10 lines)] ---"
    tail -n 10 "$cmakelists"
    echo "-------------------------------------"

    patched=$((patched + 1))
  done < <(find "$cache_dir" -type f -name CMakeLists.txt -path "*/jni-*/*" -print0 2>/dev/null || true)
done

echo "===================================================="
echo "=== JNI Patch Diagnostic Summary ==================="
echo "Total JNI CMakeLists.txt files found: $found"
echo "Total files newly patched:            $patched"
if [ $found -eq 0 ]; then
  echo "::warning::CRITICAL: 0 jni-* CMakeLists.txt files were found in any pub cache directory!"
fi
echo "===================================================="