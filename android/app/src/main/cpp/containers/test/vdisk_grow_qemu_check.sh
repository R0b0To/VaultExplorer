#!/bin/bash
# Grows qemu-img-created VHD / VHDX images with vdiskGrow() and checks the result with qemu-img (an independent
# implementation) and with the app's own VhdImage / VhdxImage readers (via vdisk_grow_tool verify).
# Needs: qemu-img, a built vdisk_grow_tool. Usage: vdisk_grow_qemu_check.sh /path/to/vdisk_grow_tool
set -u
TOOL=${1:?path to vdisk_grow_tool}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
MiB=1048576

check() {  # name  qemu-format  create-opts  oldMiB  newMiB  [dataMiB]
  local name=$1 fmt=$2 opts=$3 oldMiB=$4 newMiB=$5
  local data=${6:-$((oldMiB*3/4))}
  local raw=$W/$name.raw img=$W/$name.img out=$W/$name.out
  head -c $((oldMiB*MiB)) /dev/zero > "$raw"
  head -c $((data*MiB)) /dev/urandom | dd of="$raw" conv=notrunc status=none          # random content, zero tail
  qemu-img convert -f raw -O "$fmt" ${opts:+-o "$opts"} "$raw" "$img" 2>/dev/null || { echo "SKIP $name (qemu-img cannot create it)"; return; }
  "$TOOL" grow "$img" $((newMiB*MiB)) > "$W/g.txt" 2>&1; local rc=$?
  local line=$(cat "$W/g.txt")
  local problems=""
  # independent check 1: qemu opens it (VHD: footer checksum verified by qemu) and the structures are consistent
  local vs=$(qemu-img info --output=json "$img" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["virtual-size"])' 2>/dev/null)
  [ -n "$vs" ] || problems="$problems qemu-cannot-open"
  if [ "$fmt" = vhdx ]; then
    qemu-img check "$img" > "$W/c.txt" 2>&1 || problems="$problems qemu-check-failed"
    [ "$vs" = $((newMiB*MiB)) ] || problems="$problems qemu-size=$vs"
  else
    # VHD: qemu derives the size from the CHS geometry, so check the footer itself: current size must be exact and
    # qemu's size must equal the capacity of the geometry written there (cyl*heads*spt sectors).
    python3 - "$img" $((newMiB*MiB)) "$vs" "$opts" <<'PY' || problems="$problems footer"
import struct, sys, os
img, want, qsize, opts = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
d = open(img, 'rb').read()
f = d[-512:]
cur = struct.unpack('>Q', f[48:56])[0]
cyl, heads, spt = struct.unpack('>HBB', f[56:60])
ok = cur == want
if 'fixed' in opts:
    ok = ok and os.path.getsize(img) == want + 512
else:
    ok = ok and qsize == cyl * heads * spt * 512 and d[:512] == f      # header copy at offset 0 refreshed too
sys.exit(0 if ok else 1)
PY
  fi
  # independent check 2: qemu's view of the data: the original content is intact (VHD: compared over the old size)
  qemu-img convert -f "$fmt" -O raw "$img" "$out" 2>/dev/null
  cmp -s -n $((oldMiB*MiB)) "$out" "$raw" || problems="$problems qemu-data-differs"
  if [ "$fmt" = vhdx ]; then  # VHDX sizes are exact, so the added range can be checked too
    head -c $((newMiB*MiB)) /dev/zero > "$W/exp.raw"; dd if="$raw" of="$W/exp.raw" conv=notrunc status=none
    cmp -s "$out" "$W/exp.raw" || problems="$problems qemu-tail-not-zero"
  fi
  # check 3: the app's own readers see the old content followed by zeros over the whole new size
  "$TOOL" verify "$img" "$raw" > "$W/v.txt" 2>&1 || problems="$problems app-reader:$(tail -1 $W/v.txt)"
  [ $rc -eq 0 ] || problems="$problems grow-rc=$rc[$line]"
  if [ -z "$problems" ]; then
    printf "PASS %-26s %s\n" "$name" "($oldMiB -> $newMiB MiB; qemu opens it, data intact, app readers ok)"
  else
    printf "FAIL %-26s%s\n" "$name" "$problems"; fail=1
  fi
}

check vhd_fixed              vpc  subformat=fixed          64   200
check vhd_dynamic_inplace    vpc  subformat=dynamic        64   200
check vhd_dynamic_relocate   vpc  subformat=dynamic        64  1024
check vhd_dynamic_big        vpc  subformat=dynamic       100  3000 40
check vhdx_dynamic           vhdx subformat=dynamic        64   200
check vhdx_dynamic_chunk     vhdx subformat=dynamic       512  6144 64
check vhdx_dynamic_1m_block  vhdx subformat=dynamic,block_size=1M 64 300
check vhdx_fixed             vhdx subformat=fixed          64   200
check vhdx_fixed_chunk       vhdx subformat=fixed,block_size=32M 512 4800 64
exit $fail
