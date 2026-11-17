#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Repack a stock boot image with a debiandroid initramfs, keeping the vendor
# kernel and device tree byte for byte.
#
#   scripts/repack-stock.sh <codename> --stock-boot FILE [--initramfs FILE]
#                           [--out FILE] [--mode prod|test] [--dry-run]
#
# Why: the vendor kernel and DTB are the only parts the bootloader is known to
# accept. Replacing them (the mainline path) is a separate, unproven step. This
# command produces a bootable image whose only new bytes are the initramfs.
#
# Xiaomi's published kernel source does not always contain the device tree
# (santoni-n-oss has no msm8937-santoni.dts), so building a stock kernel from
# source is not a reliable alternative. The stock image from the device is the
# source of truth.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

STOCK_BOOT=""
INITRAMFS=""
OUT_FILE=""
MODE=prod
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --stock-boot) STOCK_BOOT="${2:-}"; shift 2 ;;
    --initramfs) INITRAMFS="${2:-}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) usage_die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"

load_device "${1:-}"
[ -n "$STOCK_BOOT" ] || usage_die "--stock-boot FILE is required (pull it from the device first)"
[ -f "$STOCK_BOOT" ] || die "stock boot image not found: $STOCK_BOOT"
[ "$MODE" = prod ] || [ "$MODE" = test ] || usage_die "--mode must be prod or test"

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || die "python3 not found (set PYTHON=...)"
TOOL="$ROOT_DIR/scripts/lib/bootimg_v0.py"
VERIFY="$ROOT_DIR/scripts/lib/verify-bootimg.py"

if [ -z "$INITRAMFS" ]; then
  for candidate in \
    "$OUT_DIR/$DEVICE/initramfs-$DEVICE-$MODE.cpio.gz" \
    "$ROOT_DIR/out/$DEVICE/initramfs-$DEVICE-$MODE.cpio.gz"; do
    [ -f "$candidate" ] && { INITRAMFS="$candidate"; break; }
  done
fi
[ -n "$INITRAMFS" ] || die "no initramfs found; run scripts/initramfs/build.sh $DEVICE --mode $MODE"
[ -f "$INITRAMFS" ] || die "initramfs not found: $INITRAMFS"
OUT_FILE="${OUT_FILE:-$OUT_DIR/$DEVICE/boot-$DEVICE-stock-$MODE.img}"

info "stock image:  $STOCK_BOOT"
info "initramfs:    $INITRAMFS"
info "output:       $OUT_FILE"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] $PYTHON $TOOL info $STOCK_BOOT"
  log "[dry-run] $PYTHON $TOOL repack $STOCK_BOOT --ramdisk $INITRAMFS --out $OUT_FILE"
  log "[dry-run] $PYTHON $VERIFY $OUT_FILE"
  exit 0
fi

"$PYTHON" "$TOOL" info "$STOCK_BOOT"
mkdir -p "$(dirname "$OUT_FILE")"
"$PYTHON" "$TOOL" repack "$STOCK_BOOT" --ramdisk "$INITRAMFS" --out "$OUT_FILE"
"$PYTHON" "$VERIFY" "$OUT_FILE" || die "repacked image failed verification; not usable"

sha256sum "$OUT_FILE"
info "next: scripts/flash.sh $DEVICE --flash-recovery --image $OUT_FILE"
info "      then scripts/verify-flash.sh $DEVICE recovery $OUT_FILE (once Android is up)"
