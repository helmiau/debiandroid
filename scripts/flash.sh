#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Boot or flash a built boot image.
# Usage: flash.sh <codename> [--ram-boot|--flash-boot] [--dry-run]
# --ram-boot    : fastboot boot, no storage writes (default)
# --flash-boot  : write the boot partition, requires confirmation

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=lib/platform-tools.sh
. "$ROOT_DIR/scripts/lib/platform-tools.sh"

MODE=ram
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --ram-boot) MODE=ram ;;
    --flash-boot) MODE=flash ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"
load_device "${1:-}"
IMG="$OUT_DIR/$DEVICE/boot-$DEVICE.img"
[ -f "$IMG" ] || die "boot image not built: $IMG (run scripts/make-bootimg.sh $DEVICE)"
require_fastboot

if [ "$MODE" = "flash" ]; then
  warn "This writes partition 'boot' on $DEVICE."
  warn "A wrong image can make the phone unbootable until a stock restore."
  confirm "Flash boot-$DEVICE.img to $DEVICE?"
  run "$FASTBOOT_BIN" flash boot "$IMG"
  info "flashed $IMG; reboot to apply"
else
  info "RAM boot (no storage writes)"
  run "$FASTBOOT_BIN" boot "$IMG"
fi
