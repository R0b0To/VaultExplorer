#!/bin/sh
# Builds and runs ext_backend_test.cpp on the host. See the header of that file
# for what it covers. Needs: g++, libext2fs-dev (headers + libext2fs/libcom_err),
# libssl-dev and libmbedtls-dev (headers only -- volume_state.h pulls in the
# crypto types), and, for the consistency checks, e2fsprogs (e2fsck, mkfs.ext*).
#   Debian/Ubuntu: apt-get install g++ libext2fs-dev e2fsprogs libssl-dev libmbedtls-dev
#
# Everything else the backend includes that isn't in this repo (FatFs's ff.h and
# diskio.h, ntfs-3g's volume.h, jni.h, android/log.h) is replaced by the
# minimal declarations in host_stubs/.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CPP=$(cd "$HERE/.." && pwd)/..
CPP=$(cd "$CPP" && pwd)
OUT="${TMPDIR:-/tmp}/ext_backend_test.$$"
trap 'rm -f "$OUT"' EXIT
${CXX:-g++} -std=c++17 -O1 -g -Wall -Wno-unused-result \
    -I "$HERE/host_stubs" -I "$CPP" -I "$CPP/filesystems" -I "$CPP/containers" \
    -I "$CPP/session" -I "$CPP/io" -I "$CPP/crypto" -I "$CPP/Common" -I "$CPP/jni" \
    "$HERE/ext_backend_test.cpp" "$CPP/filesystems/ext_backend.cpp" \
    -lext2fs -lcom_err -o "$OUT"
"$OUT"
