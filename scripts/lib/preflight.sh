#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Preflight checks: config, host tools, device visibility, capacity.
# Usage: preflight.sh <codename> [--require-device] [--require-host-tools] [--dry-run]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

REQUIRE_DEVICE=0
REQUIRE_TOOLS=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --require-device) REQUIRE_DEVICE=1 ;;
    --require-host-tools) REQUIRE_TOOLS=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"
load_device "${1:-}"

fail=0
note() { [ "$1" = "fail" ] && fail=1; printf '%-6s %s\n' "${1^^}" "$2" >&2; }

# 1. Configuration sanity.
if [ -n "${KERNEL_COMMIT:-}" ]; then
  case "$KERNEL_COMMIT" in *[!0-9a-f]*) note fail "KERNEL_COMMIT is not lowercase hex";; esac
  [ "${#KERNEL_COMMIT}" -eq 40 ] || note fail "KERNEL_COMMIT must be 40 hex characters"
  note ok "kernel pinned to $KERNEL_COMMIT"
else
  note warn "KERNEL_COMMIT empty: build will not be reproducible"
fi
if [ -n "${KERNEL_ARCHIVE_SHA256:-}" ]; then
  case "$KERNEL_ARCHIVE_SHA256" in *[!0-9a-fA-F]*|"") note fail "KERNEL_ARCHIVE_SHA256 is not hex";; esac
  [ "${#KERNEL_ARCHIVE_SHA256}" -eq 64 ] || note fail "KERNEL_ARCHIVE_SHA256 must be 64 hex characters"
else
  note warn "KERNEL_ARCHIVE_SHA256 empty: archive checksum not enforced"
fi
case "$DTB_NAME" in *.dtb) ;; *) note fail "DTB_NAME must end in .dtb";; esac
note ok "config $DEVICE ($SOC) loaded"

# 2. Host tool availability (build-side only).
if [ "$REQUIRE_TOOLS" = "1" ]; then
  for tool in git make aarch64-linux-gnu-gcc mkbootimg; do
    if command -v "$tool" >/dev/null 2>&1; then note ok "host tool $tool"; else note fail "missing host tool $tool"; fi
  done
fi

# 3. Device visibility.
if [ "$REQUIRE_DEVICE" = "1" ]; then
  if ! command -v "$FASTBOOT_BIN" >/dev/null 2>&1; then
    note fail "fastboot missing ($FASTBOOT_BIN)"
  elif [ "$DRY_RUN" = "1" ]; then
    note ok "[dry-run] would check '$FASTBOOT_BIN devices'"
  else
    line="$("$FASTBOOT_BIN" devices 2>/dev/null | head -1 || true)"
    if [ -z "$line" ]; then
      note fail "no fastboot device: power off, then hold Volume Down + Power, connect USB"
    else
      note ok "fastboot device present: $line"
      serial="$(printf '%s' "$line" | awk '{print $1}')"
      state="$("$FASTBOOT_BIN" getvar unlocked 2>&1 | sed -n 's/.*unlocked:[[:space:]]*//p' | head -1)"
      case "$state" in
        1|yes|true|YES) note ok "bootloader unlocked ($serial)" ;;
        "") note warn "could not read unlock state for $serial" ;;
        *) note fail "bootloader locked ($serial): unlock first" ;;
      esac
    fi
  fi
fi

# 4. Free space on the host output directory.
mkdir -p "$OUT_DIR"
if [ "$DRY_RUN" = "0" ]; then
  avail_kb="$(df -Pk "$OUT_DIR" 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "${avail_kb:-}" ]; then
    need_kb=$(( MIN_FREE_GB * 1024 * 1024 ))
    if [ "$avail_kb" -ge "$need_kb" ]; then
      note ok "space ${avail_kb}KiB >= $((need_kb/1024/1024))GiB"
    else
      note fail "insufficient space: ${avail_kb}KiB < $((need_kb/1024/1024))GiB"
    fi
  else
    note warn "could not determine free space for $OUT_DIR"
  fi
fi

[ "$fail" = "0" ] || die "preflight failed for $DEVICE" 3
info "preflight OK for $DEVICE"
