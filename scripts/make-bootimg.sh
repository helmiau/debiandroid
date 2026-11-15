#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Assemble boot-<codename>.img from kernel, DTB, and initramfs.
# Usage: make-bootimg.sh <codename> [--dry-run]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

ARGS=(); for arg in "$@"; do case "$arg" in *) ARGS+=("$arg");; esac; done
set -- "${ARGS[@]:-}"
load_device "${1:-}"

KDIR="$OUT_DIR/$DEVICE"
KERNEL="$KDIR/Image.gz"
DTB="$KDIR/$(basename "$DTB_NAME")"
[ -f "$KERNEL" ] || die "missing $KERNEL (run scripts/build-kernel.sh $DEVICE)"
[ -f "$DTB" ] || die "missing $DTB (run scripts/build-kernel.sh $DEVICE)"
require_cmd mkbootimg

RAMDISK=""
if [ -f "$KDIR/initramfs.cpio.gz" ]; then
  RAMDISK="--ramdisk $KDIR/initramfs.cpio.gz"
fi

CMD="mkbootimg --kernel $KERNEL $( [ -n "$RAMDISK" ] && printf -- '--ramdisk %s' "$KDIR/initramfs.cpio.gz" ) \
 --base $BOOTIMG_BASE --kernel_offset $BOOTIMG_KERNEL_OFFSET \
 --ramdisk_offset $BOOTIMG_RAMDISK_OFFSET --tags_offset $BOOTIMG_TAGS_OFFSET \
 --pagesize $BOOTIMG_PAGESIZE --cmdline \"$CMDLINE\" --board \"$DEVICE\" \
 --output $KDIR/boot-$DEVICE.img"

info "image: $KDIR/boot-$DEVICE.img (pagesize $BOOTIMG_PAGESIZE)"
if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $CMD"; exit 0; fi
eval "$CMD"
[ -f "$KDIR/boot-$DEVICE.img" ] || die "mkbootimg produced no image"
( cd "$KDIR" && sha256sum "boot-$DEVICE.img" >> SHA256SUMS )
info "done: $KDIR/boot-$DEVICE.img"
