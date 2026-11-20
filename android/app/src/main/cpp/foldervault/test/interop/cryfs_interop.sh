#!/bin/bash
# Needs: cryfs 0.11.x, FUSE (fusermount3), and FVCLI=<path to fvcli>.
# Interop: vaults written by fvcli must be accepted by the real CryFS 0.11.4,
# and vice versa. Run per (cipher, blocksize).
set -u
export LC_ALL=C.UTF-8 LANG=C.UTF-8 TMPDIR=/tmp
export HOME=${WORKDIR:-/tmp/fv_interop}/cryfs_home CRYFS_FRONTEND=noninteractive CRYFS_NO_UPDATE_CHECK=true
FV=${FVCLI:?set FVCLI to the built fvcli binary}; T=${WORKDIR:-/tmp/fv_interop}/cryfs; rm -rf $T $HOME; mkdir -p $T $HOME; cd $T
head -c 3000000 /dev/urandom > big.bin; head -c 100000 /dev/urandom > odd.bin; head -c 5 /dev/urandom > tiny.bin; : > empty.bin
UNI=$'caf\u00e9 \u65e5\u672c\u8a9e \U0001F600.txt'
fail=0
start_real() { # basedir mountdir password
  (setsid nohup sh -c "echo $3 | cryfs -f $1 $2" > $T/real.log 2>&1 < /dev/null &)
  for i in $(seq 1 60); do sleep 1; mount | grep -q " $2 " && return 0; done
  echo "FAIL: real cryfs did not mount: $(tail -4 $T/real.log)"; fail=1; return 1
}
stop_real() { fusermount3 -u $1 2>/dev/null || fusermount3 -uz $1 2>/dev/null; sleep 2; }
chk() { cmp "$1" "$2" 2>/dev/null || { echo "FAIL content: $2"; fail=1; }; }

run() { # cipher blocksize
  local cipher=$1 bsz=$2 tag=$1_$2
  local V=$T/v_$tag M=$T/m_$tag; export FV_LOCALSTATE=$T/state_$tag
  mkdir -p $V $M
  env FV_CIPHER=$cipher FV_BLOCKSIZE=$bsz $FV cryfs $V pw create >/dev/null || { echo "FAIL create $tag"; fail=1; return; }
  $FV cryfs $V pw mkdir docs >/dev/null; $FV cryfs $V pw mkdir docs/deep >/dev/null; $FV cryfs $V pw mkdir "$UNI-dir" >/dev/null
  $FV cryfs $V pw put docs/big.bin big.bin
  $FV cryfs $V pw putchunks docs/odd.bin odd.bin
  $FV cryfs $V pw putfile tiny.bin tiny.bin
  $FV cryfs $V pw put empty.bin empty.bin
  $FV cryfs $V pw put "$UNI" tiny.bin
  $FV cryfs $V pw put "$UNI-dir/inside.bin" odd.bin
  $FV cryfs $V pw put torename.bin tiny.bin
  $FV cryfs $V pw mv torename.bin docs/deep/renamed.bin        # cross-directory move
  $FV cryfs $V pw put gone.bin tiny.bin; $FV cryfs $V pw rm gone.bin
  $FV cryfs $V pw put docs/big.bin odd.bin                      # overwrite an existing, multi-block file
  $FV cryfs $V pw put docs/big.bin big.bin                      # ...and back (rewrite over replaced root)
  $FV cryfs $V pw touch docs/big.bin 1700000000
  $FV cryfs $V pw cat docs/big.bin | cmp - big.bin || { echo "FAIL self-read big $tag"; fail=1; }
  [ "$($FV cryfs $V pw size docs/big.bin)" = 3000000 ] || { echo "FAIL size $tag"; fail=1; }

  start_real $V $M pw || return
  chk big.bin $M/docs/big.bin; chk odd.bin $M/docs/odd.bin; chk tiny.bin $M/tiny.bin; chk empty.bin $M/empty.bin
  chk tiny.bin "$M/$UNI"; chk odd.bin "$M/$UNI-dir/inside.bin"; chk tiny.bin $M/docs/deep/renamed.bin
  [ ! -e $M/gone.bin ] || { echo "FAIL gone.bin visible ($tag)"; fail=1; }
  [ ! -e $M/torename.bin ] || { echo "FAIL torename visible ($tag)"; fail=1; }
  [ "$(stat -c %Y $M/docs/big.bin)" = 1700000000 ] || { echo "FAIL mtime ($tag): $(stat -c %Y $M/docs/big.bin)"; fail=1; }
  [ "$(stat -c %s $M/docs/big.bin)" = 3000000 ] || { echo "FAIL real size ($tag): $(stat -c %s $M/docs/big.bin)"; fail=1; }
  echo "written by real cryfs" > $M/from_real.txt; mkdir -p $M/realdir/sub; echo nested > $M/realdir/sub/x.txt
  cp big.bin $M/realdir/real_big.bin; mv $M/docs/odd.bin $M/docs/odd_moved_by_real.bin
  stop_real $M

  # the second mount must have kept our vault consistent: read everything back with ours
  $FV cryfs $V pw cat from_real.txt | grep -q "written by real cryfs" || { echo "FAIL read real file ($tag)"; fail=1; }
  $FV cryfs $V pw cat realdir/sub/x.txt | grep -q nested || { echo "FAIL real nested ($tag)"; fail=1; }
  $FV cryfs $V pw cat realdir/real_big.bin | cmp - big.bin || { echo "FAIL real big ($tag)"; fail=1; }
  $FV cryfs $V pw cat docs/odd_moved_by_real.bin | cmp - odd.bin || { echo "FAIL real-moved file ($tag)"; fail=1; }
  # delete a whole tree with ours; real must agree afterwards
  $FV cryfs $V pw rm realdir >/dev/null || { echo "FAIL rm tree ($tag)"; fail=1; }
  $FV cryfs $V pw passwd newpw >/dev/null || { echo "FAIL passwd ($tag)"; fail=1; }
  start_real $V $M newpw && { chk big.bin $M/docs/big.bin; [ ! -e $M/realdir ] || { echo "FAIL deleted tree visible ($tag)"; fail=1; }; stop_real $M; }
  $FV cryfs $V pw ls "" >/dev/null 2>&1 && { echo "FAIL old password still works ($tag)"; fail=1; }
  echo "blocks left on disk ($tag): $(find $V -type f ! -name cryfs.config | wc -l)"
  echo "done $tag"
}
run xchacha20-poly1305 32768
run aes-256-gcm 4096
echo "RESULT fail=$fail"
