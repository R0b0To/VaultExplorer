#!/bin/bash
# Cross-check of symlink handling: OFFICIAL cryptofs 2.8.0 <-> this engine (fvcli). Both directions.
set -u
export LC_ALL=C.UTF-8 LANG=C.UTF-8
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FV=${FVCLI:?set FVCLI to the built fvcli binary}
O=${ORACLE:-$HERE/oracle/run.sh}
T=${WORKDIR:-/tmp/fv_cryptomator_symlink_interop}; rm -rf $T; mkdir -p $T; V=$T/vault
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1"; echo "       expected: [${3:0:120}]"; echo "       actual:   [${2:0:120}]"; fi; }
fv()  { $FV cryptomator $V pw "$@"; }
LONG=$(python3 -c "print('L'*170 + '.lnk')")              # long cleartext name -> shortened .c9s node
UNI=$'caf\u00e9 \u65e5\u672c\u8a9e \U0001F600.lnk'
UTARGET=$'\u76ee\u6a19/\u30d5\u30a1\u30a4\u30eb \U0001F600.txt'
BIGT=$(python3 -c "print('a/'*5000 + 'z')")                # 10001 chars
echo hello > $T/hello.txt

echo "== A: official writes symlinks, this engine reads them"
$O create $V pw >/dev/null || { echo "oracle create failed"; exit 1; }
$O mkdir $V pw /docs
$O put $V pw /docs/file.txt $T/hello.txt
$O symlink $V pw /rootlink "docs/file.txt" >/dev/null
$O symlink $V pw /docs/rel "../rootlink" >/dev/null
$O symlink $V pw "/docs/$LONG" "/abs/target" >/dev/null
$O symlink $V pw "/$UNI" "$UTARGET" >/dev/null
$O symlink $V pw /docs/bigtarget "$BIGT" >/dev/null
eq "root lsl names+sizes"  "$(fv lsl '' | sed 's/^L [0-9]* //' | sort | tr '\n' '|')" "$(printf '%s\n' "$UNI" rootlink | sort | tr '\n' '|')"
eq "docs lsl names"        "$(fv lsl docs | sed 's/^L [0-9]* //' | sort | tr '\n' '|')" "$(printf '%s\n' bigtarget rel "$LONG" | sort | tr '\n' '|')"
eq "readlink rootlink"     "$(fv readlink rootlink)" "docs/file.txt"
eq "readlink relative"     "$(fv readlink docs/rel)" "../rootlink"
eq "readlink shortened"    "$(fv readlink "docs/$LONG")" "/abs/target"
eq "readlink unicode"      "$(fv readlink "$UNI")" "$UTARGET"
eq "readlink 10001 chars"  "$(fv readlink docs/bigtarget)" "$BIGT"
eq "size == target bytes (rootlink)"  "$(fv lsl '' | awk '$3=="rootlink"{print $2}')" "13"
eq "size == target bytes (unicode)"   "$(fv lsl '' | grep -F "$UNI" | awk '{print $2}')" "$(printf %s "$UTARGET" | wc -c)"
eq "plain ls hides symlinks (root)"   "$(fv ls '' | awk '{print $1":"$3}' | tr '\n' '|')" "D:docs|"
eq "plain ls hides symlinks (docs)"   "$(fv ls docs | awk '{print $1":"$3}' | tr '\n' '|')" "F:file.txt|"
eq "regular file still readable"      "$(fv cat docs/file.txt)" "hello"
eq "hidden count is 0 (links are not hidden)" "$(fv hidden '')" "0"
fv cat rootlink >/dev/null 2>&1 && bad "cat on a symlink must fail" || ok "cat on a symlink fails (never read as a file)"
fv size rootlink | grep -qx -- "-1" && ok "size of a symlink is -1" || bad "size of a symlink is -1"
fv mkdir rootlink >/dev/null 2>&1 && bad "mkdir over a symlink must fail" || ok "mkdir over a symlink fails"
fv put rootlink $T/hello.txt >/dev/null 2>&1 && bad "writing over a symlink must fail" || ok "writing a file over a symlink fails"
fv readlink docs/file.txt >/dev/null 2>&1 && bad "readlink on a regular file must fail" || ok "readlink on a regular file fails"
fv readlink docs >/dev/null 2>&1 && bad "readlink on a folder must fail" || ok "readlink on a folder fails"

echo "== B: this engine writes symlinks, official reads them"
fv symlink "b1" "plain/target" || bad "create b1"
fv symlink "docs/b2" "$UTARGET" || bad "create b2 (unicode target)"
fv symlink "docs/$LONG.b3" "/x/y" || bad "create b3 (shortened name)"
fv symlink "$UNI.b4" "t" || bad "create b4 (unicode name)"
fv symlink docs/b5 "$BIGT" || bad "create b5 (10001 chars)"
fv symlink b1 "other" >/dev/null 2>&1 && bad "creating over an existing symlink must fail" || ok "create over existing symlink fails"
fv symlink docs/file.txt "other" >/dev/null 2>&1 && bad "creating over an existing file must fail" || ok "create over existing file fails"
fv symlink docs "other" >/dev/null 2>&1 && bad "creating over an existing folder must fail" || ok "create over existing folder fails"
fv symlink nodir/x "t" >/dev/null 2>&1 && bad "creating in a missing folder must fail" || ok "create in missing folder fails"
fv symlink empty "" >/dev/null 2>&1 && bad "empty target must be refused" || ok "empty target refused"
DUMP=$($O dump $V pw)
echo "$DUMP" | grep -qxF "L /b1 -> plain/target 12" && ok "official sees b1 with its size" || bad "official sees b1"
echo "$DUMP" | grep -qxF "L /docs/b2 -> $UTARGET $(printf %s "$UTARGET" | wc -c)" && ok "official reads unicode target" || bad "official reads unicode target"
echo "$DUMP" | grep -qxF "L /docs/$LONG.b3 -> /x/y 4" && ok "official reads shortened-name link" || bad "official reads shortened-name link"
echo "$DUMP" | grep -qxF "L /$UNI.b4 -> t 1" && ok "official reads unicode-named link" || bad "official reads unicode-named link"
echo "$DUMP" | grep -qF "L /docs/b5 -> $BIGT 10001" && ok "official reads 10001-char target" || bad "official reads 10001-char target"
eq "official readlink b1" "$($O readlink $V pw /b1)" "plain/target"

echo "== C: moves, deletes and mtimes across implementations"
fv mv b1 docs/b1moved || bad "mv symlink (plain -> plain, other folder)"
eq "official sees moved link"  "$($O readlink $V pw /docs/b1moved)" "plain/target"
fv ls '' | grep -q "b1" && bad "old name gone" || ok "old name gone"
fv mv docs/b1moved "$LONG.moved" || bad "mv symlink (plain -> shortened)"
eq "official sees plain->shortened move" "$($O readlink $V pw "/$LONG.moved")" "plain/target"
fv mv "$LONG.moved" short || bad "mv symlink (shortened -> plain)"
eq "official sees shortened->plain move" "$($O readlink $V pw /short)" "plain/target"
fv mv "docs/$LONG.b3" "docs/$LONG.b3-renamed" || bad "mv symlink (shortened -> shortened)"
eq "official sees shortened->shortened move" "$($O readlink $V pw "/docs/$LONG.b3-renamed")" "/x/y"
$O mv $V pw /short /oshort
eq "we read what official moved"  "$(fv readlink oshort)" "plain/target"
$O rm $V pw /oshort
fv readlink oshort >/dev/null 2>&1 && bad "official delete must be visible to us" || ok "official delete visible to us"
fv rm "docs/b2" || bad "rm symlink"
$O dump $V pw | grep -q "docs/b2" && bad "our delete must be visible to official" || ok "our delete visible to official"
find $V/d -name symlink.c9r | grep -q . || bad "sanity: symlink files exist"
fv touch rootlink 1700000000 && eq "mtime we set on a symlink is what official reads" "$($O mtime $V pw /rootlink)" "1700000000"
fv touch "docs/$LONG" 1600000000 && eq "mtime on a shortened symlink, read by official" "$($O mtime $V pw "/docs/$LONG")" "1600000000"
eq "listSymlinks reports that mtime too" "$(fv lslt '' | awk '$4=="rootlink"{print $3}')" "1700000000"
eq "listSymlinks reports the shortened link's mtime" "$(fv lslt docs | awk -v n="$LONG" '$4==n{print $3}')" "1600000000"
fv rm docs >/dev/null || bad "rm folder containing symlinks"
fv rm rootlink; fv rm "$UNI"; fv rm "$UNI.b4"; fv rm short 2>/dev/null
eq "no symlink.c9r / dir files left after deleting everything" "$(find $V/d -name symlink.c9r | wc -l)" "0"
$O dump $V pw >/dev/null 2>&1 && ok "official still opens the vault after all of it" || bad "official opens vault"
echo "RESULT fail=$fail"; exit $fail
