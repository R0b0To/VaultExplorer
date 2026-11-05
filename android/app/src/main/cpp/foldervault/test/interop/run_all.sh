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
run_one cryfs_interop.sh "cryfs" which cryfs
[ -n "${CRYPTOMATOR_CLI:-}" ] && run_one cryptomator_interop.sh "cryptomator-cli" test -x "$CRYPTOMATOR_CLI" || echo "SKIP cryptomator_interop.sh (set CRYPTOMATOR_CLI)"
exit $rc
