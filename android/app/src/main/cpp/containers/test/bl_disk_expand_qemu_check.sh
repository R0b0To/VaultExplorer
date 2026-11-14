#!/bin/bash
# End-to-end check of "Expand BitLocker container" for disk images: a real Windows-made BitLocker volume (from
# cryptsetup's test images) is placed in a partition of a virtual disk, wrapped as VHD / VHDX by qemu-img, expanded with
# blDiskLocate()/blDiskExpand(), and then validated by qemu-img, sfdisk, sgdisk and dislocker (decrypted content must be
# bit-identical, the volume must have its new size).
# Usage: bl_disk_expand_qemu_check.sh <bl_disk_expand_tool> <bitlk-images dir> [add-MiB]
set -u
TOOL=${1:?bl_disk_expand_tool}; IMGDIR=${2:?dir with the cryptsetup bitlk images}; ADD=${3:-60}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
MiB=1048576; fail=0
PW=anaconda

one() {  # bitlk-image  scheme(dos|gpt|none)  qemu-fmt  qemu-subopts  label
  local src=$IMGDIR/$1.img scheme=$2 fmt=$3 sub=$4 label=$5
  local sz=$(stat -c %s "$src") raw=$W/d.raw img=$W/d.$fmt raw2=$W/d2.raw problems=""
  local off=0 total=$sz
  if [ $scheme != none ]; then off=$MiB; total=$(( (sz + 2*MiB + MiB - 1) / MiB * MiB )); fi
  rm -f "$raw"; truncate -s $total "$raw"
  if [ $scheme != none ]; then
    local gt=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
    if [ $scheme = gpt ]; then printf 'label: gpt\nstart=2048, size=%d, type=%s\n' $((sz/512)) $gt | sfdisk -q "$raw" >/dev/null 2>&1
    else printf 'label: dos\nstart=2048, size=%d, type=7\n' $((sz/512)) | sfdisk -q "$raw" >/dev/null 2>&1; fi
  fi
  dd if="$src" of="$raw" bs=1M seek=$((off/MiB)) conv=notrunc status=none
  local vinfo; vinfo=$("$TOOL" vmk "$raw" $off $PW 2>&1 | grep '^vmk=') || { echo "SKIP $label (unlock failed)"; return; }
  local vmk=${vinfo#vmk=}; vmk=${vmk%% *}; local oldvol=$(echo "$vinfo" | sed 's/.*volume=\([0-9]*\).*/\1/'); local sha=${vinfo##*sha=}
  qemu-img convert -f raw -O $fmt -o "$sub" "$raw" "$img" 2>/dev/null || { echo "SKIP $label (qemu-img cannot create it)"; return; }
  local newdisk=$(( total + ADD*MiB ))
  local out; out=$("$TOOL" expand "$img" "$vmk" $newdisk 2>&1); local rc=$?
  [ $rc -eq 0 ] || problems="$problems expand-rc=$rc[$(echo "$out" | tr '\n' ' ' | cut -c1-200)]"
  # qemu's independent view of the expanded image
  [ $fmt = vhdx ] && { qemu-img check "$img" >/dev/null 2>&1 || problems="$problems qemu-check"; }
  qemu-img convert -f $fmt -O raw "$img" "$raw2" 2>/dev/null || problems="$problems qemu-convert"
  local gotsz=$(stat -c %s "$raw2" 2>/dev/null || echo 0)
  [ "$fmt" = vpc ] || [ $gotsz -eq $newdisk ] || problems="$problems disk-size=$gotsz"
  # partition table validity + expected new volume size
  local newvol
  if [ $scheme = none ]; then newvol=$gotsz
  else
    sfdisk -V "$raw2" >/dev/null 2>&1 || problems="$problems sfdisk-V"
    local totsec=$(( gotsz / 512 ))
    if [ $scheme = gpt ]; then
      sgdisk -v "$raw2" 2>&1 | grep -q "No problems found" || problems="$problems sgdisk-v"
      newvol=$(( (totsec - 2081) * 512 ))
    else newvol=$(( (totsec - 2048) * 512 )); fi
  fi
  # BitLocker rounds its volume down to its own sector size (512 or 4096)
  local ss=$(python3 -c "import struct;print(struct.unpack('<H',open('$src','rb').read(0x0D)[0x0B:0x0D])[0])")
  newvol=$(( newvol / ss * ss ))
  # dislocker: unlocks, new size, old content identical, new tail readable
  local v; v=$("$TOOL" verify "$raw2" $off $PW $oldvol "$sha" $newvol 2>&1 | tail -1); local vrc=$?
  echo "$v" | grep -q "content=identical" || problems="$problems dislocker:[$v]"
  echo "$v" | grep -q "volume=$newvol " || problems="$problems volume-size:[$v]"
  if [ -z "$problems" ]; then printf "PASS %-44s %s\n" "$label" "(volume $oldvol -> $newvol bytes; content identical)"; else printf "FAIL %-44s%s\n" "$label" "$problems"; fail=1; fi
}

for sch in dos gpt none; do
  one bitlk-aes-xts-128          $sch vpc  subformat=dynamic,force_size=on "xts-128   $sch  vhd-dynamic"
  one bitlk-aes-xts-128          $sch vpc  subformat=fixed,force_size=on   "xts-128   $sch  vhd-fixed"
  one bitlk-aes-xts-128          $sch vhdx subformat=dynamic               "xts-128   $sch  vhdx-dynamic"
  one bitlk-aes-xts-128          $sch vhdx subformat=fixed                 "xts-128   $sch  vhdx-fixed"
done
for img in bitlk-aes-cbc-128-4k bitlk-aes-cbc-elephant-128 bitlk-aes-xts-256; do
  one $img gpt vhdx subformat=dynamic "$img gpt vhdx-dynamic"
  one $img dos vpc  subformat=dynamic,force_size=on "$img dos vhd-dynamic"
done
exit $fail
