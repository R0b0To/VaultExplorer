#!/bin/bash
# Runs every interop script that has its prerequisites installed.
#   FVCLI=build/fvcli CRYPTOMATOR_CLI=/opt/cryptomator-cli/bin/cryptomator-cli ./run_all.sh
here=$(cd "$(dirname "$0")" && pwd)
rc=0
run_one() {
  local script=$1 what=$2; shift 2
  if ! "$@" >/dev/null 2>&1; then echo "SKIP $script ($what not available)"; return; fi
  echo "== $script"
  out=$("$here/$script" 2>&1); echo "$out" | tail -3 | sed 's/^/   /'
  echo "$out" | grep -q "RESULT fail=0" || rc=1
}
run_one gocryptfs_interop.sh "gocryptfs" which gocryptfs
# Differential test against the real gocryptfs: every -init flavour, both directions, -fsck, the official
# example filesystems, the sync-merge scenario and damaged ciphertext. (GOCRYPTFS=<binary> to choose one.)
run_one gocryptfs_official_compat.py "gocryptfs + python3" bash -c "which \"${GOCRYPTFS:-gocryptfs}\" && which python3"
run_one cryfs_interop.sh "cryfs" which cryfs
[ -n "${CRYPTOMATOR_CLI:-}" ] && run_one cryptomator_interop.sh "cryptomator-cli" test -x "$CRYPTOMATOR_CLI" || echo "SKIP cryptomator_interop.sh (set CRYPTOMATOR_CLI)"
# These drive the OFFICIAL cryptofs through a small Java program (needs a JDK 21 and `oracle/fetch_oracle.sh` once).
if [ -n "${FVCLI:-}" ] && [ -d "$here/oracle/lib" ] && command -v java >/dev/null; then
  for n in symlink backup migrate; do run_one cryptomator_${n}_interop.sh "oracle" test -d "$here/oracle/lib"; done
else
  echo "SKIP cryptomator_{symlink,backup,migrate}_interop.sh (set FVCLI, install a JDK 21 and run oracle/fetch_oracle.sh)"
fi
exit $rc
