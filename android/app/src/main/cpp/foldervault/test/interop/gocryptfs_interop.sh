#!/bin/bash
# Needs: gocryptfs 2.x, FUSE (fusermount3), and FVCLI=<path to fvcli>.
# Interop: vaults written by fvcli must be accepted by real gocryptfs 2.4.0.
set -u
FV=${FVCLI:?set FVCLI to the built fvcli binary}; T=${WORKDIR:-/tmp/fv_interop}/gocryptfs; rm -rf $T; mkdir -p $T; cd $T
head -c 1000000 /dev/urandom > big.bin; head -c 4096 /dev/urandom > exact4k.bin; head -c 8192 /dev/urandom > exact8k.bin
head -c 5 /dev/urandom > tiny.bin; : > empty.bin; head -c 70001 /dev/urandom > odd.bin
LONG=$(python3 -c "print('L'*200 + '.txt')")      # 204 chars -> cipher name > 255 -> longname
fail=0
run() { # mode cipher plainflag
  local mode=$1 cipher=$2 plain=$3
  local c=c_$mode m=m_$mode
  mkdir -p $c $m
  env FV_CIPHER=$cipher ${plain:+FV_PLAINNAMES=1} $FV gocryptfs $c pw create >/dev/null || { echo "FAIL create $mode"; fail=1; return; }
  $FV gocryptfs $c pw mkdir docs >/dev/null || { echo "FAIL mkdir"; fail=1; }
  $FV gocryptfs $c pw mkdir docs/deep >/dev/null
  $FV gocryptfs $c pw put docs/big.bin big.bin
  $FV gocryptfs $c pw putchunks docs/odd.bin odd.bin
  $FV gocryptfs $c pw putfile exact4k.bin exact4k.bin
  $FV gocryptfs $c pw put exact8k.bin exact8k.bin
  $FV gocryptfs $c pw put tiny.bin tiny.bin
  $FV gocryptfs $c pw put empty.bin empty.bin
  $FV gocryptfs $c pw putchunks "docs/deep/$LONG" tiny.bin
  $FV gocryptfs $c pw put torename.bin tiny.bin
  $FV gocryptfs $c pw mv torename.bin docs/renamed.bin
  $FV gocryptfs $c pw put gone.bin tiny.bin
  $FV gocryptfs $c pw rm gone.bin
  $FV gocryptfs $c pw mv "docs/deep/$LONG" "docs/$LONG"      # long-name file moved across dirs
  $FV gocryptfs $c pw touch docs/big.bin 1700000000
  # read back with our own code first
  $FV gocryptfs $c pw cat docs/big.bin | cmp - big.bin || { echo "FAIL self-read big $mode"; fail=1; }
  # now real gocryptfs
  local opt=""; [ -z "$plain" ] || opt=""
  echo pw | gocryptfs -q -nosyslog $c $m 2>$T/mnt_$mode.err || { echo "FAIL mount $mode: $(cat $T/mnt_$mode.err)"; fail=1; return; }
  chk() { cmp "$1" "$2" 2>/dev/null || { echo "FAIL content $2 ($mode)"; fail=1; }; }
  chk big.bin $m/docs/big.bin; chk odd.bin $m/docs/odd.bin; chk exact4k.bin $m/exact4k.bin
  chk exact8k.bin $m/exact8k.bin; chk tiny.bin $m/tiny.bin; chk empty.bin $m/empty.bin
  chk tiny.bin $m/docs/renamed.bin; chk tiny.bin "$m/docs/$LONG"
  [ ! -e $m/gone.bin ] || { echo "FAIL gone.bin still there ($mode)"; fail=1; }
  [ ! -e $m/torename.bin ] || { echo "FAIL torename still there ($mode)"; fail=1; }
  [ "$(stat -c %Y $m/docs/big.bin)" = 1700000000 ] || { echo "FAIL mtime ($mode): $(stat -c %Y $m/docs/big.bin)"; fail=1; }
  [ -d $m/docs/deep ] || { echo "FAIL docs/deep missing ($mode)"; fail=1; }
  # real gocryptfs writes into our vault, we read it back
  echo "written by real gocryptfs" > $m/from_real.txt; mkdir -p $m/realdir; echo nested > $m/realdir/x.txt
  fusermount3 -u $m
  $FV gocryptfs $c pw cat from_real.txt | grep -q "written by real gocryptfs" || { echo "FAIL read of real-written file ($mode)"; fail=1; }
  $FV gocryptfs $c pw cat realdir/x.txt | grep -q nested || { echo "FAIL nested real file ($mode)"; fail=1; }
  # fsck
  out=$(echo pw | gocryptfs -fsck -q -nosyslog $c 2>&1); rc=$?
  [ $rc -eq 0 ] || { echo "FAIL fsck ($mode) rc=$rc: $out" | head -5; fail=1; }
  # change password then mount with the new one
  $FV gocryptfs $c pw passwd newpw >/dev/null || { echo "FAIL passwd ($mode)"; fail=1; }
  echo newpw | gocryptfs -q -nosyslog $c $m 2>/dev/null && { chk big.bin $m/docs/big.bin; fusermount3 -u $m; } || { echo "FAIL mount after passwd ($mode)"; fail=1; }
  $FV gocryptfs $c pw ls "" >/dev/null 2>&1 && { echo "FAIL old password still works ($mode)"; fail=1; }
  echo "done $mode"
}
run gcm "" ""
run xchacha xchacha ""
run aessiv aessiv ""
run plain "" 1
echo "RESULT fail=$fail"
