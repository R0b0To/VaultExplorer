#!/usr/bin/env bash
# Runs the whole LUKS compatibility suite. Needs: cryptsetup (>= 2.4), python3 + `cryptography`, libgcrypt20,
# and VC=/path/to/VeraCrypt/src MBED=/path/to/mbedtls (see Makefile). Fuzz iterations: FUZZ_N (default 250/format).
set -u
cd "$(dirname "$0")"
make -s && make -s asan || { echo "build failed"; exit 2; }
status=0
export ASAN_OPTIONS=detect_leaks=0
for t in t_cipher t_read t_create t_ops t_misc t_crash; do
  echo "=== $t"; HARNESS="$PWD/build/luks_cli" python3 $t.py || status=1
done
echo "=== t_hostile (ASAN/UBSAN)"; python3 t_hostile.py "$PWD/build_asan/luks_cli" || status=1
echo "=== t_fuzz (ASAN/UBSAN)"; HARNESS_ASAN="$PWD/build_asan/luks_cli" python3 t_fuzz.py "${FUZZ_N:-250}" || status=1
exit $status
