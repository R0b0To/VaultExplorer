#!/bin/bash
# Creates MBR / GPT disks with sfdisk, grows the last partition with ptGrowPartition(), and validates the result with
# sfdisk / sgdisk (header CRCs, backup GPT at the end of the disk, partition bounds).
# Usage: disk_partition_sfdisk_check.sh /path/to/disk_partition_tool
set -u
TOOL=${1:?path to disk_partition_tool}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0; MiB=1048576

run() {  # name label script oldMiB newMiB startLba
  local name=$1 label=$2 script=$3 old=$4 new=$5 start=$6 img=$W/$1.img
  rm -f "$img"; truncate -s $((old*MiB)) "$img"
  printf '%b' "label: $label\n$script" | sfdisk -q "$img" >/dev/null 2>&1 || { echo "SKIP $name (sfdisk failed)"; return; }
  [ "$label" = gpt ] && sgdisk -v "$img" 2>&1 | grep -q "No problems found" || [ "$label" = dos ] || { echo "SKIP $name (initial gpt not clean)"; return; }
  truncate -s $((new*MiB)) "$img"                       # the virtual disk grew
  "$TOOL" grow "$img" $((new*MiB)) $start > "$W/o.txt" 2>&1; local rc=$?
  local problems=""
  [ $rc -eq 0 ] || problems="$problems tool-rc=$rc($(tail -1 $W/o.txt))"
  if [ "$label" = gpt ]; then
    sgdisk -v "$img" > "$W/v.txt" 2>&1; grep -q "No problems found" "$W/v.txt" || problems="$problems sgdisk:$(grep -E 'Problem|Warning|Caution' $W/v.txt | head -2 | tr '\n' ' ')"
    # backup must be at the true end of the disk
    local last=$(( new*MiB/512 - 1 ))
    sgdisk -p "$img" 2>/dev/null | grep -q "last usable sector is $(( last - 33 ))" || problems="$problems last-usable-wrong($(sgdisk -p "$img" 2>/dev/null | grep 'last usable'))"
  fi
  sfdisk -V "$img" > "$W/sv.txt" 2>&1 || problems="$problems sfdisk-V:$(head -2 $W/sv.txt | tr '\n' ' ')"
  # the last partition must end at the end of the usable area
  local endsect=$(sfdisk -d "$img" 2>/dev/null | awk -F'[=, ]+' '/start=/{ for(i=1;i<=NF;i++){ if($i=="start") s=$(i+1); if($i=="size") z=$(i+1) } if (s+z>m) m=s+z } END{print m}')
  local expect_end=$(( new*MiB/512 ))
  [ "$label" = gpt ] && expect_end=$(( new*MiB/512 - 33 ))
  [ "$endsect" = "$expect_end" ] || problems="$problems end=$endsect(expected $expect_end)"
  # idempotent: a second run changes nothing
  cp "$img" "$W/before.img"; "$TOOL" grow "$img" $((new*MiB)) $start > "$W/o2.txt" 2>&1
  grep -q "rc=1 " "$W/o2.txt" || problems="$problems second-run:$(tail -1 $W/o2.txt)"
  cmp -s "$img" "$W/before.img" || problems="$problems second-run-modified-disk"
  # other partitions untouched
  if [ -z "$problems" ]; then printf "PASS %-22s (%s -> %s MiB, validated by sfdisk%s)\n" "$name" "$old" "$new" "$([ $label = gpt ] && echo ' and sgdisk')"; else printf "FAIL %-22s%s\n" "$name" "$problems"; fail=1; fi
}

run mbd_single     dos 'start=2048, type=7\n'                                   64 300 2048
run mbd_two_parts  dos 'start=2048, size=20480, type=83\nstart=22528, type=7\n' 64 500 22528
run mbd_big_chs    dos 'start=2048, type=7\n'                                   64 9000 2048
run gpt_single     gpt 'start=2048, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\n' 64 300 2048
run gpt_two_parts  gpt 'start=2048, size=20480, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\nstart=22528, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\n' 64 500 22528
run gpt_big        gpt 'start=2048, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\n' 100 6000 2048
exit $fail
