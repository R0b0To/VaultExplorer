#!/bin/bash
# Needs: cryptomator-cli 0.6.x (+ a JRE and FUSE), FVCLI=<fvcli>, CRYPTOMATOR_CLI=<cryptomator-cli/bin/cryptomator-cli>.
# Interop: vaults written by fvcli must be accepted by the real Cryptomator
# (cryptomator-cli 0.6.2 over FUSE), and files written by the real one must
# be readable by fvcli.
set -u
export LC_ALL=C.UTF-8 LANG=C.UTF-8 JAVA_TOOL_OPTIONS="-Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8"
FV=${FVCLI:?set FVCLI to the built fvcli binary}; CLI=${CRYPTOMATOR_CLI:?set CRYPTOMATOR_CLI to cryptomator-cli/bin/cryptomator-cli}
T=${WORKDIR:-/tmp/fv_interop}/cryptomator; rm -rf $T; mkdir -p $T; cd $T
V=$T/vault; M=$T/mnt; echo pw > $T/pw.txt
head -c 1000000 /dev/urandom > big.bin; head -c 32768 /dev/urandom > exact32k.bin; head -c 65536 /dev/urandom > exact64k.bin
head -c 5 /dev/urandom > tiny.bin; : > empty.bin; head -c 100001 /dev/urandom > odd.bin
LONG=$(python3 -c "print('L'*170 + '.txt')")        # long cleartext name -> shortened .c9s
UNI=$'caf\u00e9 \u65e5\u672c\u8a9e \U0001F600.txt'
fail=0
start_cli() {
  rm -rf $M; mkdir -p $M
  setsid nohup $CLI unlock --password:file=$T/pw.txt --mounter=org.cryptomator.frontend.fuse.mount.LinuxFuseMountProvider --mountPoint=$M $V > $T/cli.log 2>&1 < /dev/null &
  for i in $(seq 1 60); do sleep 1; mount | grep -q " $M " && return 0; done
  echo "FAIL: real cryptomator did not mount"; cat $T/cli.log | head -20; fail=1; return 1
}
stop_cli() {
  fusermount3 -u $M 2>/dev/null || fusermount3 -uz $M 2>/dev/null
  for p in $(pgrep -f '[c]ryptomator-cli.*unlock'); do kill $p 2>/dev/null; done
  sleep 2
}
mkdir -p $V && $FV cryptomator $V pw create >/dev/null || { echo "FAIL create"; exit 1; }
$FV cryptomator $V pw mkdir docs >/dev/null || { echo "FAIL mkdir"; fail=1; }
$FV cryptomator $V pw mkdir docs/deep >/dev/null
$FV cryptomator $V pw mkdir "$UNI-dir" >/dev/null
$FV cryptomator $V pw put docs/big.bin big.bin
$FV cryptomator $V pw putchunks docs/odd.bin odd.bin
$FV cryptomator $V pw putfile exact32k.bin exact32k.bin
$FV cryptomator $V pw put exact64k.bin exact64k.bin
$FV cryptomator $V pw put tiny.bin tiny.bin
$FV cryptomator $V pw put empty.bin empty.bin
$FV cryptomator $V pw putchunks "docs/deep/$LONG" tiny.bin
$FV cryptomator $V pw put "$UNI" tiny.bin
$FV cryptomator $V pw put "$UNI-dir/inside.bin" odd.bin
$FV cryptomator $V pw put torename.bin tiny.bin
$FV cryptomator $V pw mv torename.bin docs/renamed.bin
$FV cryptomator $V pw put gone.bin tiny.bin
$FV cryptomator $V pw rm gone.bin
$FV cryptomator $V pw mv "docs/deep/$LONG" "docs/$LONG"        # shortened name, across directories
$FV cryptomator $V pw mv tiny.bin "tiny.$LONG"                 # plain -> shortened in place
$FV cryptomator $V pw mv "docs/$LONG" docs/short.txt           # shortened -> plain
$FV cryptomator $V pw mv docs/short.txt "docs/$LONG"           # plain -> shortened again
$FV cryptomator $V pw mkdir "docs/dir-$LONG" >/dev/null
$FV cryptomator $V pw put "docs/dir-$LONG/x.bin" tiny.bin
$FV cryptomator $V pw touch docs/big.bin 1700000000
$FV cryptomator $V pw cat docs/big.bin | cmp - big.bin || { echo "FAIL self-read big"; fail=1; }

start_cli || exit 1
chk() { cmp "$1" "$2" 2>/dev/null || { echo "FAIL content: $2"; fail=1; }; }
chk big.bin $M/docs/big.bin; chk odd.bin $M/docs/odd.bin; chk exact32k.bin $M/exact32k.bin
chk exact64k.bin $M/exact64k.bin; chk empty.bin $M/empty.bin; chk tiny.bin "$M/docs/$LONG"
chk tiny.bin "$M/$UNI"; chk odd.bin "$M/$UNI-dir/inside.bin"; chk tiny.bin $M/docs/renamed.bin
chk tiny.bin "$M/tiny.$LONG"; chk tiny.bin "$M/docs/dir-$LONG/x.bin"
[ ! -e $M/gone.bin ] || { echo "FAIL gone.bin still visible"; fail=1; }
[ ! -e $M/torename.bin ] || { echo "FAIL torename visible"; fail=1; }
[ -d $M/docs/deep ] || { echo "FAIL docs/deep missing"; fail=1; }
[ "$(stat -c %Y $M/docs/big.bin)" = 1700000000 ] || { echo "FAIL mtime: $(stat -c %Y $M/docs/big.bin)"; fail=1; }
[ "$(stat -c %s $M/docs/big.bin)" = 1000000 ] || { echo "FAIL size: $(stat -c %s $M/docs/big.bin)"; fail=1; }
ls $M | sort > $T/ls_real.txt
echo "written by real cryptomator" > $M/from_real.txt; mkdir -p $M/realdir/sub; echo nested > $M/realdir/sub/x.txt
cp big.bin $M/realdir/real_big.bin
cp tiny.bin "$M/real-$LONG"; mkdir "$M/realdir-$LONG"; echo longdir > "$M/realdir-$LONG/f.txt"
echo "unicode" > "$M/real-$UNI"
stop_cli

$FV cryptomator $V pw cat from_real.txt | grep -q "written by real cryptomator" || { echo "FAIL read real-written file"; fail=1; }
$FV cryptomator $V pw cat realdir/sub/x.txt | grep -q nested || { echo "FAIL nested real file"; fail=1; }
$FV cryptomator $V pw cat realdir/real_big.bin | cmp - big.bin || { echo "FAIL real big file"; fail=1; }
$FV cryptomator $V pw cat "real-$LONG" | cmp - tiny.bin || { echo "FAIL real long-name file"; fail=1; }
$FV cryptomator $V pw cat "realdir-$LONG/f.txt" | grep -q longdir || { echo "FAIL real long-name dir"; fail=1; }
$FV cryptomator $V pw cat "real-$UNI" | grep -q unicode || { echo "FAIL real unicode file"; fail=1; }
$FV cryptomator $V pw ls "" | grep -q "realdir-" || { echo "FAIL ls missing realdir-long"; fail=1; }

# delete a directory tree through fvcli, then make sure the real one agrees and nothing is orphaned
$FV cryptomator $V pw rm realdir/sub; $FV cryptomator $V pw rm realdir
before=$(find $V/d -type f | wc -l)
$FV cryptomator $V pw passwd newpw >/dev/null || { echo "FAIL passwd"; fail=1; }
echo newpw > $T/pw.txt
start_cli && { chk big.bin $M/docs/big.bin; [ ! -e $M/realdir ] || { echo "FAIL deleted dir still visible"; fail=1; }; stop_cli; }
$FV cryptomator $V pw ls "" >/dev/null 2>&1 && { echo "FAIL old password still works"; fail=1; }
echo "dirs under d after deletes: $(find $V/d -mindepth 2 -maxdepth 2 -type d | wc -l)"
echo "RESULT fail=$fail"
