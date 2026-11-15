#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Assemble boot-<codename>.img from kernel, DTB, and initramfs (header v0).
# Uses scripts/lib/mkbootimg.py, so no external mkbootimg package is required.
# Usage: make-bootimg.sh <codename> [--dry-run]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

ARGS=(); for arg in "$@"; do ARGS+=("$arg"); done
set -- "${ARGS[@]:-}"
load_device "${1:-}"

KDIR="$OUT_DIR/$DEVICE"
KERNEL="$KDIR/Image.gz"
DTB="$KDIR/$(basename "$DTB_NAME")"
OUTIMG="$KDIR/boot-$DEVICE.img"
[ -f "$KERNEL" ] || die "missing $KERNEL (run scripts/build-kernel.sh $DEVICE)"
[ -f "$DTB" ] || die "missing $DTB (run scripts/build-kernel.sh $DEVICE)"

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || die "python3 not found (set PYTHON=...)"

RAMDISK_OPT=()
[ -f "$KDIR/initramfs.cpio.gz" ] && RAMDISK_OPT=(--ramdisk "$KDIR/initramfs.cpio.gz")

info "image: $OUTIMG (pagesize $BOOTIMG_PAGESIZE, board $DEVICE)"
set -- \
  --kernel "$KERNEL" \
  ${RAMDISK_OPT[@]+"${RAMDISK_OPT[@]}"} \
  --dtb "$DTB" \
  --base "$BOOTIMG_BASE" \
  --kernel_offset "$BOOTIMG_KERNEL_OFFSET" \
  --ramdisk_offset "$BOOTIMG_RAMDISK_OFFSET" \
  --tags_offset "$BOOTIMG_TAGS_OFFSET" \
  --pagesize "$BOOTIMG_PAGESIZE" \
  --cmdline "$CMDLINE" \
  --board "$DEVICE" \
  --output "$OUTIMG"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] $PYTHON $ROOT_DIR/scripts/lib/mkbootimg.py $*"
  exit 0
fi
"$PYTHON" "$ROOT_DIR/scripts/lib/mkbootimg.py" "$@"
[ -f "$OUTIMG" ] || die "no image produced"
( cd "$KDIR" && sha256sum "boot-$DEVICE.img" > "boot-$DEVICE.img.sha256" )
info "done: $OUTIMG"
