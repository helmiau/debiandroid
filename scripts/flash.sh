#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Boot or flash a built boot image.
#
#   scripts/flash.sh <codename> [--ram-boot|--flash-boot|--flash-recovery]
#                               [--image FILE] [--allow-unproven] [--dry-run]
#
# --ram-boot        fastboot boot: no storage write, but the image runs untested.
#                   Refused unless --allow-unproven is also given: a wrong image
#                   can leave the device in EDL (santoni, 2026-11-16).
# --flash-boot      write the boot partition, requires confirmation.
# --flash-recovery  write the recovery partition, requires confirmation. This is
#                   the preferred test target: a bad image costs one reboot into
#                   Android instead of losing the boot path.
#
# Always verify the partition after writing: scripts/verify-flash.sh <codename>
# <partition> <image> reads it back through adb and compares SHA-256.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=lib/platform-tools.sh
. "$ROOT_DIR/scripts/lib/platform-tools.sh"

MODE=""
IMAGE=""
ALLOW_UNPROVEN=0
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ram-boot) MODE=ram ;;
    --flash-boot) MODE=boot ;;
    --flash-recovery) MODE=recovery ;;
    --image) IMAGE="${2:-}"; shift ;;
    --allow-unproven) ALLOW_UNPROVEN=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -*) usage_die "unknown option: $1" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
set -- "${ARGS[@]:-}"

load_device "${1:-}"
[ -n "$MODE" ] || usage_die "choose a target: --ram-boot, --flash-boot, or --flash-recovery"

IMG="${IMAGE:-$OUT_DIR/$DEVICE/boot-$DEVICE.img}"
[ -f "$IMG" ] || die "boot image not built: $IMG (run scripts/make-bootimg.sh $DEVICE)"
require_fastboot

case "$MODE" in
  ram)
    if [ "$ALLOW_UNPROVEN" != "1" ]; then
      warn "fastboot boot runs an untested kernel in RAM; a failure can leave the device in EDL."
      warn "Prefer the recovery partition: scripts/flash.sh $DEVICE --flash-recovery"
      die "refusing --ram-boot without --allow-unproven"
    fi
    info "RAM boot (no storage writes): $IMG"
    run "$FASTBOOT_BIN" boot "$IMG"
    ;;
  boot|recovery)
    warn "This overwrites partition '$MODE' on $DEVICE."
    warn "A wrong image leaves the phone unbootable until a stock restore."
    warn "Keep the stock image at hand: scripts/backup-stock.sh $DEVICE"
    confirm "Flash $(basename "$IMG") to the $MODE partition of $DEVICE?"
    run "$FASTBOOT_BIN" flash "$MODE" "$IMG"
    info "wrote $IMG to $MODE"
    info "verify after booting Android: scripts/verify-flash.sh $DEVICE $MODE $IMG"
    ;;
esac
