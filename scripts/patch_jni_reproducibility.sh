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
    
    # Check if already patched with the modern CMAKE_SHARED_LINKER_FLAGS fix
    if grep -q "CMAKE_SHARED_LINKER_FLAGS.*--build-id=none" "$cmakelists"; then
      echo "Status: ALREADY PATCHED with CMAKE_SHARED_LINKER_FLAGS. Skipping."
      continue
    fi

    # Clean old broken line-1 patches if restored from flutter-action cache
    sed -i '/add_link_options("-Wl,--build-id=none")/d' "$cmakelists" 2>/dev/null || true

    echo "Status: Applying fresh working CMAKE_SHARED_LINKER_FLAGS patch..."
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
echo "===================================================="