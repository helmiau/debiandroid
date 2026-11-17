#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build an initramfs for debiandroid.
#
#   scripts/initramfs/build.sh <codename> [--mode prod|test] [--busybox PATH]
#                              [--data-dir NAME] [--deadman SECONDS] [--out FILE]
#
# The image is a gzipped cpio newc archive containing:
#   /init               the boot script (initramfs/init)
#   /debiandroid.conf   build-time settings read by /init
#   /bin/busybox        static ARM64 busybox with applets installed at runtime
#
# busybox is required as payload. Resolution order: --busybox, $BUSYBOX, the
# per-device .cache/busybox-aarch64, then `busybox` on PATH (host arch, which
# only works when the host is aarch64).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

MODE=prod
BUSYBOX="${BUSYBOX:-}"
DATA_DIR=debian-server
DEADMAN=300
OUT_FILE=""
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --busybox) BUSYBOX="${2:-}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:-}"; shift 2 ;;
    --deadman) DEADMAN="${2:-}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) usage_die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"

load_device "${1:-}"
case "$MODE" in prod|test) ;; *) usage_die "--mode must be prod or test" ;; esac
case "$DEADMAN" in ''|*[!0-9]*) usage_die "--deadman must be seconds" ;; esac

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || die "python3 not found (set PYTHON=...)"

OUT_FILE="${OUT_FILE:-$OUT_DIR/$DEVICE/initramfs-$DEVICE-$MODE.cpio.gz}"

# --- locate busybox -----------------------------------------------------------
if [ -z "$BUSYBOX" ]; then
  for candidate in "$CACHE_DIR/busybox-aarch64" "$ROOT_DIR/.cache/busybox-aarch64"; do
    [ -x "$candidate" ] && { BUSYBOX="$candidate"; break; }
  done
fi
if [ -z "$BUSYBOX" ]; then
  if command -v busybox >/dev/null 2>&1; then
    BUSYBOX="$(command -v busybox)"
    warn "using host busybox at $BUSYBOX; it must be an ARM64 binary for $DEVICE to boot"
  else
    die "busybox (ARM64, static) not found. Set BUSYBOX=/path/to/busybox or place it at $CACHE_DIR/busybox-aarch64"
  fi
fi
[ -f "$BUSYBOX" ] || die "busybox not found at $BUSYBOX"
if command -v file >/dev/null 2>&1; then
  file -b "$BUSYBOX" | grep -qi 'aarch64\|ARM aarch64' \
    || warn "$BUSYBOX does not look like an aarch64 binary; the image will not run on $DEVICE"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/bin" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/mnt" "$STAGE/newroot"
cp "$BUSYBOX" "$STAGE/bin/busybox"
chmod 755 "$STAGE/bin/busybox" 2>/dev/null || true
cp "$ROOT_DIR/initramfs/init" "$STAGE/init"
chmod 755 "$STAGE/init" 2>/dev/null || true
cat > "$STAGE/debiandroid.conf" <<EOF
DEBIANDROID_MODE=$MODE
DEBIANDROID_DATA_DIR=$DATA_DIR
DEADMAN_SECONDS=$DEADMAN
EOF

sh -n "$STAGE/init" || die "initramfs/init has a syntax error"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] $PYTHON $ROOT_DIR/scripts/lib/mkcpio.py $STAGE $OUT_FILE --gzip --chmod init:755"
  log "[dry-run] would write $OUT_FILE (mode=$MODE busybox=$BUSYBOX)"
  exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
"$PYTHON" "$ROOT_DIR/scripts/lib/mkcpio.py" "$STAGE" "$OUT_FILE" --gzip \
  --chmod init:755 --chmod bin/busybox:755

# --- verify the archive contains what the kernel needs ------------------------
"$PYTHON" "$ROOT_DIR/scripts/lib/mkcpio.py" --list "$OUT_FILE" > "$STAGE/list.txt"
grep -qE '^- 0755 .* init$' "$STAGE/list.txt" || die "$OUT_FILE: /init is missing or not executable"
grep -qE '^- 0755 .* bin/busybox$' "$STAGE/list.txt" || die "$OUT_FILE: /bin/busybox is missing or not executable"
grep -q ' debiandroid.conf$' "$STAGE/list.txt" || die "$OUT_FILE: /debiandroid.conf is missing"

SIZE=$(wc -c < "$OUT_FILE" | tr -d ' ')
info "initramfs: $OUT_FILE ($SIZE bytes, mode=$MODE)"
sha256sum "$OUT_FILE" 2>/dev/null | awk '{print "sha256: " $1}' >&2 || true
