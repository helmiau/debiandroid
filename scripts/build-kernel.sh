#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fetch and cross-compile the kernel recorded in devices/<codename>.env.
# Usage: build-kernel.sh <codename> [--check-only] [--clean] [--dry-run]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

CHECK_ONLY=0; CLEAN=0; ARGS=()
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    --clean) CLEAN=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"
load_device "${1:-}"

SRC="$CACHE_DIR/src/$DEVICE"
KDIR="$OUT_DIR/$DEVICE"
LOG="$KDIR/build.log"
run mkdir -p "$KDIR"

# 1. Source checkout.
if [ ! -d "$SRC/.git" ]; then
  info "cloning $KERNEL_REPO -> $SRC"
  run git clone --filter=blob:none "$KERNEL_REPO" "$SRC"
fi
run git -C "$SRC" fetch --all --tags --quiet
run git -C "$SRC" checkout --quiet "$KERNEL_REF"
if [ "$DRY_RUN" = "1" ] && [ ! -d "$SRC/.git" ]; then
  log "[dry-run] would verify HEAD == $KERNEL_COMMIT"
  head_sha="<dry-run>"
else
  head_sha="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
if [ -n "${KERNEL_COMMIT:-}" ]; then
  [ "${#KERNEL_COMMIT}" -eq 40 ] || warn "KERNEL_COMMIT is not a 40-character commit id"
  if [ "$head_sha" != "$KERNEL_COMMIT" ] && [ "$head_sha" != "<dry-run>" ]; then
    die "source pin mismatch: HEAD=$head_sha expected=$KERNEL_COMMIT"
  fi
  info "source pin OK: $head_sha"
else
  warn "KERNEL_COMMIT unset: building an unpinned checkout $head_sha"
fi
[ "$CHECK_ONLY" = "1" ] && { info "check-only complete"; exit 0; }

require_cmd make aarch64-linux-gnu-gcc
[ "$CLEAN" = "1" ] && run make -C "$SRC" O="$KDIR" ARCH=arm64 mrproper

# 2. Configure.
run cp "$SRC/arch/arm64/configs/$DEFCONFIG" "$KDIR/.config"
if [ -n "${KCONFIG_FRAGMENT:-}" ]; then
  FRAG="$ROOT_DIR/$KCONFIG_FRAGMENT"
  [ -f "$FRAG" ] || die "KCONFIG_FRAGMENT not found: $FRAG"
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] scripts/kconfig/merge_config.sh -m $KDIR/.config $FRAG"
  else
    "$SRC/scripts/kconfig/merge_config.sh" -m -O "$KDIR" "$KDIR/.config" "$FRAG" >/dev/null
    info "merged fragment $KCONFIG_FRAGMENT"
  fi
fi
run make -C "$SRC" O="$KDIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# 3. Compile.
info "building kernel (log: $LOG)"
if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] make -C $SRC O=$KDIR ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j Image dtbs"
  exit 0
fi
make -C "$SRC" O="$KDIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  -j"$(nproc 2>/dev/null || echo 4)" Image dtbs 2>&1 | tee "$LOG"
[ -f "$KDIR/arch/arm64/boot/Image.gz" ] || die "kernel build produced no Image.gz, see $LOG"

# 4. Device tree.
DTB="$KDIR/arch/arm64/boot/dts/$DTB_NAME"
[ -f "$DTB" ] || die "DTB not found: $DTB (check DTB_NAME in devices/$DEVICE.env)"

# 5. Artifacts and checksums.
cp "$KDIR/arch/arm64/boot/Image.gz" "$KDIR/Image.gz"
cp "$DTB" "$KDIR/$(basename "$DTB")"
( cd "$KDIR" && sha256sum Image.gz "$(basename "$DTB")" > SHA256SUMS )
info "artifacts in $KDIR"
