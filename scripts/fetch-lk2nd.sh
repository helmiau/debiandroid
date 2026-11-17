#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Download the pinned lk2nd image recorded in devices/<codename>.env and verify it.
#
#   scripts/fetch-lk2nd.sh <codename> [--from FILE] [--out FILE] [--dry-run]
#
# lk2nd is a second-stage bootloader: on msm8953/msm8940 the mainline kernel does not
# select the display panel without it. Taking the upstream release instead of building
# it is deliberate: the image is 322 KiB (msm8952) or 360 KiB (msm8953) and its exact
# bytes are pinned by SHA-256 in the device file, which is what reproducibility needs.
#
# lk2nd carries no network stack. It cannot cause, fix or avoid a networking bug; it
# only loads the kernel. Networking is kernel + firmware + userspace.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

FROM=""
OUT_FILE=""
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) usage_die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"

load_device "${1:-}"
[ "$BOOTLOADER" = "lk2nd" ] || die "BOOTLOADER=$BOOTLOADER in devices/$DEVICE.env; set BOOTLOADER=lk2nd to use lk2nd"
OUT_FILE="${OUT_FILE:-$OUT_DIR/$DEVICE/lk2nd-$LK2ND_TARGET.img}"

if [ -n "$FROM" ]; then
  [ -f "$FROM" ] || die "no such file: $FROM"
  info "source: $FROM (local)"
else
  info "source: $LK2ND_URL"
fi
info "target: $OUT_FILE"
info "sha256: $LK2ND_SHA256"

if [ "$DRY_RUN" = "1" ]; then
  if [ -n "$FROM" ]; then
    log "[dry-run] cp $FROM $OUT_FILE"
  else
    log "[dry-run] curl -fL -o $OUT_FILE $LK2ND_URL"
  fi
  log "[dry-run] sha256sum -c against $LK2ND_SHA256"
  exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
if [ -n "$FROM" ]; then
  run cp "$FROM" "$OUT_FILE"
else
  require_cmd curl
  run curl -fL --retry 3 -o "$OUT_FILE" "$LK2ND_URL"
fi

GOT="$(sha256sum "$OUT_FILE" | awk '{print $1}')"
if [ "$GOT" != "$LK2ND_SHA256" ]; then
  rm -f "$OUT_FILE"
  die "checksum mismatch for lk2nd: got $GOT, expected $LK2ND_SHA256"
fi
SIZE=$(wc -c < "$OUT_FILE" | tr -d ' ')
info "verified lk2nd ($SIZE bytes) -> $OUT_FILE"
info "next: flash.sh $DEVICE --flash-lk2nd   (then --flash-recovery for the test image)"
