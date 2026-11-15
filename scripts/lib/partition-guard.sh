#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify a block device is the expected root partition before any mount or mkfs.
# Usage: partition-guard.sh <device> <expected-partname> <marker-path> [--allow-empty-marker] [--dry-run]
# Exit: 0 ok, 3 mismatch or unsafe target, 2 bad arguments.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

ALLOW_EMPTY=0
POS=()
for arg in "$@"; do
  case "$arg" in
    --allow-empty-marker) ALLOW_EMPTY=1 ;;
    *) POS+=("$arg") ;;
  esac
done
[ "${#POS[@]}" -ge 3 ] || usage_die "usage: partition-guard.sh <device> <partname> <marker> [--allow-empty-marker] [--dry-run]"
DEV="${POS[0]}"; EXPECTED="${POS[1]}"; MARKER="${POS[2]}"

case "$DEV" in
  /dev/mmcblk*|/dev/sd*|/dev/loop*|/dev/disk/*) ;;
  *) die "refusing non-block-device target: $DEV" 3 ;;
esac
[ -b "$DEV" ] || die "not a block device: $DEV" 3

# 1. Name check from the kernel uevent, not from the caller's assumption.
if command -v lsblk >/dev/null 2>&1; then
  actual="$(lsblk -no PARTNAME "$DEV" 2>/dev/null | head -1 | tr -d ' ')"
else
  sys="/sys/class/block/$(basename "$DEV")/uevent"
  actual="$(sed -n 's/^PARTNAME=//p' "$sys" 2>/dev/null | head -1)"
fi
[ -n "$actual" ] || die "cannot read PARTNAME for $DEV (not a partition?)" 3
if [ "$actual" != "$EXPECTED" ]; then
  die "partition identity mismatch: $DEV has PARTNAME=$actual, expected $EXPECTED" 3
fi
info "partition identity OK: $DEV is $EXPECTED"

# 2. Marker check. An installed system must carry the marker directory entry.
if command -v debugfs >/dev/null 2>&1 && [ "$DRY_RUN" = "0" ]; then
  if debugfs -R "stat ${MARKER}" "$DEV" >/dev/null 2>&1; then
    info "root marker present: $MARKER"
  elif [ "$ALLOW_EMPTY" = "1" ]; then
    warn "root marker absent on $DEV (allowed for first install)"
  else
    die "root marker $MARKER missing on $DEV; refusing to touch it" 3
  fi
elif command -v blkid >/dev/null 2>&1 && [ "$DRY_RUN" = "0" ]; then
  fs="$(blkid -o value -s TYPE "$DEV" 2>/dev/null || true)"
  case "$fs" in
    ext2|ext3|ext4) ;;
    "") warn "no filesystem on $DEV (allowed for first install)" ;;
    *) die "unexpected filesystem '$fs' on $DEV" 3 ;;
  esac
else
  warn "[dry-run] would inspect $MARKER on $DEV"
fi

info "partition guard passed: $DEV"
