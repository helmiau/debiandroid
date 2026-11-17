#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Assemble boot-<codename>.img from kernel, DTB, and initramfs (header v0).
# A boot image without an initramfs is unbootable (the kernel panics looking
# for a rootfs), so this script REFUSES to produce one unless
# --allow-no-ramdisk is given explicitly. Use scripts/lib/verify-bootimg.py
# to re-verify any produced image.
#
# Usage: make-bootimg.sh <codename> [--allow-no-ramdisk] [--dry-run]
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

ALLOW_NO_RAMDISK=0
VERBOSE=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --allow-no-ramdisk) ALLOW_NO_RAMDISK=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

load_device "${1:-}"
KDIR="$OUT_DIR/$DEVICE"
KERNEL="$KDIR/Image.gz"
DTB="$KDIR/$(basename "$DTB_NAME")"
INITRAMFS="$KDIR/initramfs.cpio.gz"
OUTIMG="$KDIR/boot-$DEVICE.img"

[ -f "$KERNEL" ] || die "missing $KERNEL (run scripts/build-kernel.sh $DEVICE)"
[ -f "$DTB" ] || die "missing $DTB (run scripts/build-kernel.sh $DEVICE)"

# Core fix: an unbootable image is worse than no image at all.
if [ ! -f "$INITRAMFS" ]; then
  if [ "$ALLOW_NO_RAMDISK" = "1" ]; then
    warn "$INITRAMFS missing; building WITHOUT initramfs (NOT bootable, dev only)"
  else
    die "no initramfs at $INITRAMFS: boot image would panic on boot and can brick the device. Build the initramfs first, or pass --allow-no-ramdisk (dev only)"
  fi
fi

# Xiaomi/Qualcomm LK bootloaders (MSM8937/8953/8998) expect the DTB appended
# to the kernel (Image.gz-dtb), not as a separate boot.img section.
KERNEL_ARG="$KERNEL"
if [ -n "$DTB" ]; then
  cat "$KERNEL" "$DTB" > "$KDIR/kernel-dtb"
  KERNEL_ARG="$KDIR/kernel-dtb"
fi

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || die "python3 not found (set PYTHON=...)"

RAMDISK_OPT=()
if [ -f "$INITRAMFS" ]; then
  RAMDISK_OPT=(--ramdisk "$INITRAMFS")
fi

info "image: $OUTIMG (pagesize $BOOTIMG_PAGESIZE, board $DEVICE, appended DTB)"
set -- \
  --kernel "$KERNEL_ARG" \
  ${RAMDISK_OPT[@]+"${RAMDISK_OPT[@]}"} \
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

# Final verification before claiming success.
VERIFY_FLAGS=()
if [ "${ALLOW_NO_RAMDISK:-0}" = "1" ]; then
  VERIFY_FLAGS+=(--allow-no-ramdisk)
fi
if [ "${VERBOSE:-0}" = "1" ]; then
  VERIFY_FLAGS+=(-v)
fi
"$PYTHON" "$ROOT_DIR/scripts/lib/verify-bootimg.py" "$OUTIMG" "${VERIFY_FLAGS[@]}" \
  || die "boot image failed verification: $OUTIMG (refusing to keep a broken image)"

( cd "$KDIR" && sha256sum "boot-$DEVICE.img" > "boot-$DEVICE.img.sha256" )
info "done: $OUTIMG"
