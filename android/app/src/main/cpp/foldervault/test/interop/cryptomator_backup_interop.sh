#!/bin/bash
# Key-file backups: names written by this engine must be exactly the names official cryptofs computes (otherwise
# official would add a second backup of the same file on its next open), in both directions.
set -u
export LC_ALL=C.UTF-8 LANG=C.UTF-8
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FV=${FVCLI:?set FVCLI to the built fvcli binary}
O=${ORACLE:-$HERE/oracle/run.sh}
T=${WORKDIR:-/tmp/fv_cryptomator_backup_interop}; rm -rf $T; mkdir -p $T
fail=0
eq() { if [ "$2" == "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (expected [$3] got [$2])"; fail=1; fi; }
n() { ls $1 | grep -c "^$2\..*\.bkup$"; }
echo "== A: vault created by this engine"
V=$T/a; mkdir -p $V; $FV cryptomator $V pw create >/dev/null
eq "no backups right after create" "$(n $V vault.cryptomator)/$(n $V masterkey.cryptomator)" "0/0"
$FV cryptomator $V pw ls '' >/dev/null
eq "we back up both key files on open" "$(n $V vault.cryptomator)/$(n $V masterkey.cryptomator)" "1/1"
VB=$(ls $V | grep "^vault.cryptomator\..*bkup$"); MB=$(ls $V | grep "^masterkey.cryptomator\..*bkup$")
$O dump $V pw >/dev/null
eq "official opens it: no second vault.cryptomator backup (same name)" "$(n $V vault.cryptomator)" "1"
eq "official's vault backup is the one we wrote" "$(ls $V | grep '^vault.cryptomator\..*bkup$')" "$VB"
eq "backup content == original (vault.cryptomator)" "$(cmp $V/vault.cryptomator $V/$VB && echo same)" "same"
eq "backup content == original (masterkey)" "$(cmp $V/masterkey.cryptomator $V/$MB && echo same)" "same"
echo "== B: vault created by official"
V=$T/b; $O create $V pw >/dev/null; $O mkdir $V pw /x
OVB=$(n $V vault.cryptomator)
eq "official backed up vault.cryptomator" "$OVB" "1"
OVN=$(ls $V | grep "^vault.cryptomator\..*bkup$")
$FV cryptomator $V pw ls '' >/dev/null
eq "we add no second vault.cryptomator backup (same name as official)" "$(ls $V | grep '^vault.cryptomator\..*bkup$')" "$OVN"
eq "we add the masterkey backup (desktop behaviour)" "$(n $V masterkey.cryptomator)" "1"
echo "== C: password change keeps official's naming for the old key file"
V=$T/c; mkdir -p $V; $FV cryptomator $V pw create >/dev/null; $FV cryptomator $V pw ls '' >/dev/null
MB1=$(ls $V | grep "^masterkey.cryptomator\..*bkup$")
$FV cryptomator $V pw passwd newpw >/dev/null
eq "old key file already backed up -> still one backup" "$(n $V masterkey.cryptomator)" "1"
$FV cryptomator $V newpw ls '' >/dev/null
eq "new key file gets its own backup on open" "$(n $V masterkey.cryptomator)" "2"
$O dump $V newpw >/dev/null && echo "  ok   official unlocks with the new password" || { echo "  FAIL official unlock"; fail=1; }
echo "RESULT fail=$fail"; exit $fail
