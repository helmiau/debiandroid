#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Read a partition back through adb and compare it with the image that was written.
#
#   scripts/verify-flash.sh <codename> <partition> <image>
#
# Requires Android booted with root (Magisk) and adb authorised. fastboot has no
# portable read-back on MSM aboot devices, so the proof has to come from Android.
# Exit codes: 0 matched, 1 mismatch or missing device, 2 bad arguments.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=lib/platform-tools.sh
. "$ROOT_DIR/scripts/lib/platform-tools.sh"

DEVICE_NAME="${1:-}"
PARTITION="${2:-}"
IMAGE="${3:-}"
[ -n "$DEVICE_NAME" ] || usage_die "usage: verify-flash.sh <codename> <partition> <image>"
load_device "$DEVICE_NAME"
case "$PARTITION" in boot|recovery) ;; *) usage_die "partition must be boot or recovery" ;; esac
[ -f "$IMAGE" ] || die "image not found: $IMAGE"

ADB="${ADB_BIN:-adb}"
command -v "$ADB" >/dev/null 2>&1 || die "adb not found (run scripts/fetch.sh or set ADB_BIN)"

WANT="$(sha256sum "$IMAGE" | awk '{print $1}')"
info "image:  $IMAGE"
info "wanted: $WANT"

"$ADB" get-state >/dev/null 2>&1 || die "no adb device; boot Android and retry"

# Root: adb root on userdebug builds, otherwise Magisk's su.
ROOT_PREFIX=""
if ! "$ADB" shell id 2>/dev/null | tr -d '\r' | grep -q "uid=0"; then
  if "$ADB" shell su -c id 2>/dev/null | tr -d '\r' | grep -q "uid=0"; then
    ROOT_PREFIX="su -c"
  else
    die "no root shell (Magisk su or adb root required to read block devices)"
  fi
fi
root_shell() { # root_shell "<command>"
  if [ -n "$ROOT_PREFIX" ]; then
    # shellcheck disable=SC2086
    "$ADB" shell $ROOT_PREFIX "$1"
  else
    "$ADB" shell "$1"
  fi
}

DEV="$(root_shell "readlink -f /dev/block/by-name/$PARTITION" | tr -d '\r')"
[ -n "$DEV" ] || die "cannot resolve /dev/block/by-name/$PARTITION on the device"
case "$DEV" in */by-name/*) die "by-name/$PARTITION is a dangling link on this device" ;; esac
info "device: $DEV"

GOT="$(root_shell "dd if=$DEV bs=4096 2>/dev/null | sha256sum" | awk '{print $1}' | tr -d '\r')"
[ -n "$GOT" ] || die "failed to read $DEV"
info "got:    $GOT"

if [ "$GOT" = "$WANT" ]; then
  info "VERIFIED: $PARTITION matches $IMAGE"
  exit 0
fi
die "MISMATCH on $PARTITION: device has $GOT, image is $WANT"
