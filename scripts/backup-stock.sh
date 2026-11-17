#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Save the stock boot and recovery images from the phone before any write.
#
#   scripts/backup-stock.sh <codename> [--partition boot|recovery|both] [--out DIR]
#
# Without a stock image there is no restore path. Xiaomi's published kernel
# source does not contain every device tree (santoni-n-oss has no
# msm8937-santoni.dts), so the phone itself is the only reliable source.
#
# Requires Android booted with root (Magisk) and adb authorised.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=lib/platform-tools.sh
. "$ROOT_DIR/scripts/lib/platform-tools.sh"

PARTITION=both
OUT_SUBDIR=""
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --partition) PARTITION="${2:-}"; shift 2 ;;
    --out) OUT_SUBDIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) usage_die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"

load_device "${1:-}"
case "$PARTITION" in boot|recovery|both) ;; *) usage_die "--partition must be boot, recovery, or both" ;; esac

ADB="${ADB_BIN:-adb}"
command -v "$ADB" >/dev/null 2>&1 || die "adb not found (run scripts/fetch.sh or set ADB_BIN)"
DEST="${OUT_SUBDIR:-$OUT_DIR/$DEVICE/stock}"
mkdir -p "$DEST"

"$ADB" get-state >/dev/null 2>&1 || die "no adb device; boot Android and retry"
ROOT_PREFIX=""
if ! "$ADB" shell id 2>/dev/null | tr -d '\r' | grep -q "uid=0"; then
  "$ADB" shell su -c id 2>/dev/null | tr -d '\r' | grep -q "uid=0" \
    || die "no root shell (Magisk su required to read block devices)"
  ROOT_PREFIX="su -c"
fi
root_shell() {
  if [ -n "$ROOT_PREFIX" ]; then
    # shellcheck disable=SC2086
    "$ADB" shell $ROOT_PREFIX "$1"
  else
    "$ADB" shell "$1"
  fi
}

save_partition() {
  local name="$1" dev out
  dev="$(root_shell "readlink -f /dev/block/by-name/$name" | tr -d '\r')"
  [ -n "$dev" ] || { warn "cannot resolve $name on this device; skipped"; return 1; }
  out="$DEST/$name-stock-$DEVICE.img"
  info "saving $name ($dev) -> $out"
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] $ADB exec-out $ROOT_PREFIX dd if=$dev bs=4096 > $out"
    return 0
  fi
  # shellcheck disable=SC2086
  "$ADB" exec-out $ROOT_PREFIX "dd if=$dev bs=4096 2>/dev/null" > "$out"
  local size
  size="$(wc -c < "$out" | tr -d ' ')"
  if [ "$size" -lt 1024 ]; then
    rm -f "$out"
    die "saved $name is only $size bytes; the read failed"
  fi
  if head -c 8 "$out" 2>/dev/null | grep -q 'ANDROID!'; then
    info "  $size bytes, ANDROID! header present"
  else
    warn "  $size bytes, no ANDROID! header (raw partition dump; still a valid restore source)"
  fi
  sha256sum "$out" | tee -a "$DEST/SHA256SUMS"
}

rc=0
case "$PARTITION" in
  boot) save_partition boot || rc=1 ;;
  recovery) save_partition recovery || rc=1 ;;
  both) save_partition boot || rc=1; save_partition recovery || rc=1 ;;
esac

info "stock images in $DEST"
info "restore: scripts/flash.sh $DEVICE --flash-boot --image $DEST/boot-stock-$DEVICE.img"
exit "$rc"
