#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build a Debian ARM64 server rootfs tarball (host-side, cross-debootstrap).
# Usage: debian.sh <codename> [--mode dual-boot|dedicated] [--size 4G] [--dry-run]
# CI builds the released tarball; this script is the local equivalent.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

SIZE="4G"; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) shift 2 ;;
    --mode=*) shift ;;
    --size) SIZE="${2:-}"; shift 2 ;;
    --size=*) SIZE="${1#*=}"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"
load_device "${1:-}"

command -v debootstrap >/dev/null 2>&1 || die "debootstrap missing (apt install debootstrap)"
RUMP="$CACHE_DIR/rootfs/debian-$DEVICE"
TARBALL="$CACHE_DIR/rootfs/rootfs-debian-arm64-stable-$DEVICE.tar.zst"
run mkdir -p "$CACHE_DIR/rootfs"

PACKAGES=openssh-server,systemd-sysv,iproute2,zstd
if [ "${KIOSK:-0}" = "1" ]; then
  info "KIOSK=1: adding cage and Epiphany for the panel"
  PACKAGES="$PACKAGES,cage,epiphany-browser,libgl1-mesa-dri,fonts-dejavu-core"
fi
info "debootstrap bookworm arm64 -> $RUMP"
run debootstrap --arch=arm64 --variant=minbase --include="$PACKAGES" \
  bookworm "$RUMP" http://deb.debian.org/debian
info "(CI adds snapshot pinning for the snapshot channel)"
# Overlay: the health stamp unit and anything else the image needs at boot.
OVERLAY="$ROOT_DIR/rootfs/overlay"
if [ -d "$OVERLAY" ]; then
  info "applying rootfs overlay $OVERLAY"
  run cp -a "$OVERLAY/." "$RUMP/"
  run mkdir -p "$RUMP/etc/systemd/system/multi-user.target.wants"
  run ln -sf /etc/systemd/system/debiandroid-health.service \
    "$RUMP/etc/systemd/system/multi-user.target.wants/debiandroid-health.service"
  if [ "${KIOSK:-0}" = "1" ]; then
    run ln -sf /etc/systemd/system/debiandroid-kiosk.service \
      "$RUMP/etc/systemd/system/multi-user.target.wants/debiandroid-kiosk.service"
    info "kiosk unit enabled; edit /etc/debiandroid/kiosk.conf for the URL"
  fi
fi
run touch "$RUMP$ROOT_MARKER"
info "tarball: $TARBALL"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] tar -C $RUMP -cf - . | zstd -19 -o $TARBALL"
  exit 0
fi
tar -C "$RUMP" -cf - . | zstd -19 -o "$TARBALL"
info "done: $TARBALL"
