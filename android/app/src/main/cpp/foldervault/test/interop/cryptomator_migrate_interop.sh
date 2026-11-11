#!/bin/bash
# Format 7 -> 8 migration: this engine vs official Version8Migrator, on identical copies of one genuine v7 vault.
set -u
export LC_ALL=C.UTF-8 LANG=C.UTF-8
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FV=${FVCLI:?set FVCLI to the built fvcli binary}
O=${ORACLE:-$HERE/oracle/run.sh}
T=${WORKDIR:-/tmp/fv_cryptomator_migrate_interop}; rm -rf $T; mkdir -p $T
fail=0
eq() { if [ "$2" == "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1"; echo "       expected [${3:0:150}]"; echo "       got      [${2:0:150}]"; fail=1; fi; }
jwt() { python3 - "$1" <<'PY'
import sys,json,base64
t=open(sys.argv[1]).read().strip().split('.')
d=lambda s: json.loads(base64.urlsafe_b64decode(s+'='*(-len(s)%4)))
h,p=d(t[0]),d(t[1])
print(h.get('alg'),h.get('kid'),h.get('typ'),p.get('format'),p.get('cipherCombo'),p.get('shorteningThreshold'),'jti' in p)
PY
}
mkver() { python3 -c "import json;print(json.load(open('$1/masterkey.cryptomator'))['version'])"; }
LONG=$(python3 -c "print('N'*170)")
echo hello > $T/h.txt; head -c 200000 /dev/urandom > $T/big.bin

echo "== build one genuine format 7 vault (official-written CTR-MAC data, v7 key file, no vault.cryptomator)"
V0=$T/v0; $O create-ctrmac $V0 pw >/dev/null
$O mkdir $V0 pw /docs/sub; $O put $V0 pw /docs/h.txt $T/h.txt; $O put $V0 pw /docs/sub/big.bin $T/big.bin
$O put $V0 pw "/$LONG.txt" $T/h.txt; $O symlink $V0 pw /docs/ln "../target" >/dev/null
BEFORE=$($O dump $V0 pw)
$O downgrade $V0 pw >/dev/null
eq "precondition: masterkey version 7" "$(mkver $V0)" "7"
[ ! -e $V0/vault.cryptomator ] && echo "  ok   precondition: no vault.cryptomator" || { echo "  FAIL precondition"; fail=1; }
eq "probe (password-free) says format 7 on the genuine v7 vault" "$($FV cryptomator $V0 - probe)" "7"
cp -r $V0 $T/ours; cp -r $V0 $T/off

echo "== both implementations migrate their own copy"
$FV cryptomator $T/ours pw migrate7to8 >/dev/null; eq "our migration exit code" "$?" "0"
$O migrate $T/off pw >/dev/null;                    eq "official migration exit code" "$?" "0"
eq "probe says 8 after our migration / after official's" "$($FV cryptomator $T/ours - probe)/$($FV cryptomator $T/off - probe)" "8/8"
eq "vault.cryptomator header+claims identical in shape" "$(jwt $T/ours/vault.cryptomator)" "$(jwt $T/off/vault.cryptomator)"
eq "claims are what the spec says" "$(jwt $T/ours/vault.cryptomator)" "HS256 masterkeyfile:masterkey.cryptomator JWT 8 SIV_CTRMAC 220 True"
eq "masterkey version after (ours / official)" "$(mkver $T/ours)/$(mkver $T/off)" "999/999"
eq "masterkey backup name identical (ours == official, same old file)" "$(ls $T/ours | grep '^masterkey.cryptomator\..*bkup$')" "$(ls $T/off | grep '^masterkey.cryptomator\..*bkup$')"
eq "backup is the untouched v7 key file" "$(cmp $T/ours/masterkey.cryptomator.*.bkup $V0/masterkey.cryptomator && echo same)" "same"
eq "tree untouched (d/ identical to the v7 original)" "$(diff -r $V0/d $T/ours/d >/dev/null && echo same)" "same"

echo "== cross-open: each implementation opens the OTHER's migrated vault"
eq "official reads OUR migrated vault == original tree" "$($O dump $T/ours pw)" "$BEFORE"
eq "official reads ITS migrated vault == original tree" "$($O dump $T/off pw)" "$BEFORE"
eq "we read OUR migrated vault (file content)" "$($FV cryptomator $T/ours pw cat docs/h.txt)" "hello"
eq "we read OFFICIAL's migrated vault (file content)" "$($FV cryptomator $T/off pw cat docs/h.txt)" "hello"
eq "we read big file from official-migrated vault (hash)" "$($FV cryptomator $T/off pw cat docs/sub/big.bin | sha256sum | cut -c1-16)" "$(sha256sum $T/big.bin | cut -c1-16)"
eq "we read the shortened-name file after migration" "$($FV cryptomator $T/ours pw cat "$LONG.txt")" "hello"
eq "we still see the symlink after migration" "$($FV cryptomator $T/ours pw readlink docs/ln)" "../target"
$FV cryptomator $T/ours pw put new.txt $T/h.txt >/dev/null 2>&1
eq "official reads a file we write into the migrated vault" "$($O cat $T/ours pw /new.txt)" "hello"
$O put $T/off pw /fromoff.txt $T/h.txt
eq "we read a file official writes into the migrated vault" "$($FV cryptomator $T/off pw cat fromoff.txt)" "hello"

echo "== refusals leave the vault byte-for-byte untouched"
snap() { (cd $1 && find . -type f ! -path './d/*' | sort | xargs sha256sum); }
cp -r $V0 $T/w; S1=$(snap $T/w)
$FV cryptomator $T/w wrongpw migrate7to8 >/dev/null 2>&1; eq "wrong password -> exit 3" "$?" "3"
eq "wrong password changed nothing" "$(snap $T/w)" "$S1"
$FV cryptomator $T/ours pw migrate7to8 >/dev/null 2>&1; eq "already migrated -> refused" "$?" "1"
$O create $T/v8 pw >/dev/null; $FV cryptomator $T/v8 pw migrate7to8 >/dev/null 2>&1; eq "genuine format 8 vault -> refused" "$?" "1"
cp -r $T/off $T/nocfg; rm $T/nocfg/vault.cryptomator; S2=$(snap $T/nocfg)
$FV cryptomator $T/nocfg pw migrate7to8 >/dev/null 2>&1; eq "format 8 key file without vault.cryptomator -> refused (never 'migrate' a half-synced v8)" "$?" "1"
eq "...and nothing changed" "$(snap $T/nocfg)" "$S2"
$FV cryptomator $T/nocfg pw ls '' >/dev/null 2>&1; eq "...and open still refuses it (unchanged behaviour)" "$?" "1"
eq "probe says -8 for that half-synced format 8 vault (the UI must say wait, never upgrade)" "$($FV cryptomator $T/nocfg - probe)" "-8"
eq "probe says 8 for a genuine format 8 vault" "$($FV cryptomator $T/v8 - probe)" "8"
eq "probe says 0 for something that is not a vault" "$($FV cryptomator $T/nonexist - probe)" "0"
$FV cryptomator $T/nonexist pw migrate7to8 >/dev/null 2>&1; eq "not a vault -> refused" "$?" "1"
echo "RESULT fail=$fail"; exit $fail
