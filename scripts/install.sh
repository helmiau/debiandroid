#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Install the built rootfs on a device (host-side path).
# Usage: install.sh <codename> --mode dual-boot|dedicated [--device /dev/...] [--dry-run]
# Kept conservative in P1: resolves paths, runs preflight and the partition guard.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

MODE=""; TARGET_DEV=""; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    --device) TARGET_DEV="${2:-}"; shift 2 ;;
    --device=*) TARGET_DEV="${1#*=}"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"
load_device "${1:-}"
case "$MODE" in dual-boot|dedicated) ;; *) usage_die "--mode must be dual-boot or dedicated" ;; esac

"$ROOT_DIR/scripts/lib/preflight.sh" "$DEVICE" --require-device
[ -n "$TARGET_DEV" ] || die "missing --device /dev/<partition> for mode $MODE"
"$ROOT_DIR/scripts/lib/partition-guard.sh" "$TARGET_DEV" "$ROOT_PARTNAME_EXPECTED" "$ROOT_MARKER"

ROOTFS="$CACHE_DIR/releases/*/rootfs-*-arm64-*-*.tar.zst"
# shellcheck disable=SC2086
set -- $ROOTFS
[ -f "$1" ] || die "no downloaded rootfs; run scripts/fetch.sh --backend debian --channel stable"

if [ "$MODE" = "dedicated" ]; then
  warn "dedicated mode erases $TARGET_DEV"
  confirm "Format $TARGET_DEV as ext4 and install?"
  run mkfs.ext4 -L debiandroid "$TARGET_DEV"
fi
# Layout must match initramfs/init:
#   dedicated  -> rootfs at the partition root (init mounts the "debiandroid" partition)
#   dual-boot  -> rootfs at <userdata>/debian-server/rootfs
MNT="$CACHE_DIR/mnt/$DEVICE"
SUBDIR=""
[ "$MODE" = dual-boot ] && SUBDIR=/debian-server/rootfs
run mkdir -p "$MNT$SUBDIR"
run mount "$TARGET_DEV" "$MNT"
run zstd -d -c "$1" | tar -x -C "$MNT$SUBDIR"
run mkdir -p "$MNT$SUBDIR/etc"
run touch "$MNT$SUBDIR$ROOT_MARKER"
run sync
run umount "$CACHE_DIR/mnt/$DEVICE"
info "rootfs installed on $TARGET_DEV ($MODE)"
