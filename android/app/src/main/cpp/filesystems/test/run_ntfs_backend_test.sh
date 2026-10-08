#!/bin/sh
# Builds and runs ntfs_backend_test.cpp on the host. See the header of that file for
# what it covers.
#
# What gets built, mirroring CMakeLists.txt so the test exercises the same code:
#   - ntfs-3g at the commit CMakeLists.txt pins (cloned from GitHub into a cache
#     directory the first time; set NTFS3G_SRC to use an existing checkout instead),
#     compiled with the config.h CMakeLists.txt generates and the same file list;
#   - the app's embedded mkntfs, from filesystems/mkntfs_embedded.c.in;
#   - filesystems/ntfs_backend.cpp itself.
# Needs: g++, gcc, git (+ network the first time), libssl-dev and libmbedtls-dev
# (headers only -- volume_state.h pulls in the crypto types), and for the independent
# oracles the ntfs-3g tools (ntfsfix, ntfsls, ntfscat).
#   Debian/Ubuntu: apt-get install g++ git ntfs-3g libssl-dev libmbedtls-dev
# FatFs, jni.h and android/log.h are replaced by the stubs in host_stubs/; BitLocker,
# VHD/VHDX and the cipher cascade by stubs inside the test, since the plain-volume
# I/O path never reaches them.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CPP=$(cd "$HERE/../.." && pwd)
CMAKE="$CPP/CMakeLists.txt"

SHA=$(awk '/^ +ntfs3g$/{f=1} f && /GIT_TAG/{print $2; exit}' "$CMAKE")
[ -n "$SHA" ] || { echo "could not read the ntfs-3g GIT_TAG from $CMAKE" >&2; exit 2; }
CACHE="${NTFS_TEST_CACHE:-${TMPDIR:-/tmp}/vaultexplorer-ntfs-host-cache}/$SHA"
SRC="${NTFS3G_SRC:-$CACHE/src}"
mkdir -p "$CACHE"

if [ ! -f "$SRC/libntfs-3g/volume.c" ]; then
    echo "fetching ntfs-3g $SHA ..."
    rm -rf "$SRC"; mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin https://github.com/tuxera/ntfs-3g.git
    git -C "$SRC" fetch -q --depth 1 origin "$SHA"
    git -C "$SRC" checkout -q FETCH_HEAD
fi

# config.h: the very text CMakeLists.txt writes (step 3b).
sed -n '/^set(CONFIG_H_CONTENT "/,/^")$/p' "$CMAKE" | sed '1d;$d' > "$CACHE/config.h"
[ -s "$CACHE/config.h" ] || { echo "could not extract config.h from $CMAKE" >&2; exit 2; }

CFLAGS="-w -O1 -DHAVE_CONFIG_H -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -include stdint.h -include stddef.h -include sys/types.h"
CINC="-I $CACHE -I $SRC/include -I $SRC/include/ntfs-3g -I $SRC/ntfsprogs"

LIB="$CACHE/libntfs3g_host.a"
if [ ! -f "$LIB" ] || [ "$CMAKE" -nt "$LIB" ]; then
    echo "building ntfs-3g ..."
    rm -rf "$CACHE/obj"; mkdir -p "$CACHE/obj"
    {
        grep -o 'NTFS_3G_SRC_DIR}/[A-Za-z0-9_-]*\.c' "$CMAKE" | sed "s#^NTFS_3G_SRC_DIR}#$SRC/libntfs-3g#"
        grep -o 'ntfsprogs/[a-z_]*\.c' "$CMAKE" | grep -v mkntfs.c | sed "s#^#$SRC/#"
    } | sort -u > "$CACHE/sources.txt"
    xargs -P "$(nproc 2>/dev/null || echo 2)" -I{} sh -c \
        'gcc -c '"$CFLAGS $CINC"' "$1" -o "'"$CACHE"'/obj/$(basename "$1" .c).o"' _ {} < "$CACHE/sources.txt"
    rm -f "$LIB"; ar rcs "$LIB" "$CACHE"/obj/*.o
fi

OUT="${TMPDIR:-/tmp}/ntfs_backend_test.$$"
WORK="${TMPDIR:-/tmp}/ntfs_backend_test_build.$$"
mkdir -p "$WORK"
trap 'rm -rf "$OUT" "$WORK"' EXIT

# The app's own mkntfs wrapper, rendered from the same template CMake uses.
sed "s#@NTFS3G_MKNTFS_SOURCE@#$SRC/ntfsprogs/mkntfs.c#" "$CPP/filesystems/mkntfs_embedded.c.in" > "$WORK/mkntfs_embedded.c"
gcc -c $CFLAGS $CINC "$WORK/mkntfs_embedded.c" -o "$WORK/mkntfs_embedded.o"

# ntfs-3g's headers define function-like min()/max() macros, which break any libstdc++
# header first included after them; pre-including the ones the project uses avoids that.
PRE="-include limits -include functional -include mutex -include memory -include string -include vector
     -include unordered_map -include unordered_set -include thread -include condition_variable -include chrono
     -include atomic -include algorithm -include optional -include array -include map -include set -include deque
     -include fstream -include sstream"

# Note the order: ntfs-3g's include dirs come before host_stubs/, so its real volume.h wins
# over the one-line stub the ext test uses.
${CXX:-g++} -std=c++17 -O1 -g -w -DHAVE_CONFIG_H -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 $PRE \
    -I "$CACHE" -I "$SRC/include" -I "$SRC/include/ntfs-3g" -I "$HERE/host_stubs" \
    -I "$CPP" -I "$CPP/filesystems" -I "$CPP/containers" -I "$CPP/session" -I "$CPP/io" \
    -I "$CPP/crypto" -I "$CPP/Common" -I "$CPP/jni" -I "$CPP/dislocker" \
    "$HERE/ntfs_backend_test.cpp" "$CPP/filesystems/ntfs_backend.cpp" \
    "$WORK/mkntfs_embedded.o" "$LIB" -o "$OUT"
"$OUT"
