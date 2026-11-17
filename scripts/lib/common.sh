#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared helpers. Source this file; do not execute it.
set -euo pipefail

# ROOT_DIR always points at the real checkout, so helper scripts are found even
# when DEBIANDROID_REPO_ROOT redirects device configuration to a test copy.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVICES_DIR="${DEBIANDROID_REPO_ROOT:-$ROOT_DIR}/devices"
OUT_DIR="${DEBIANDROID_OUT:-$ROOT_DIR/out}"
CACHE_DIR="${DEBIANDROID_CACHE:-$ROOT_DIR/.cache}"
FASTBOOT_BIN="${FASTBOOT_BIN:-fastboot}"

DRY_RUN=0
for _arg in "$@"; do
  [ "$_arg" = "--dry-run" ] && DRY_RUN=1
done
unset _arg
COLOR_RESET=''; COLOR_RED=''; COLOR_YELLOW=''; COLOR_GREEN=''
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  COLOR_RESET=$'\033[0m'; COLOR_RED=$'\033[31m'; COLOR_YELLOW=$'\033[33m'; COLOR_GREEN=$'\033[32m'
fi

log()  { printf '%s\n' "$*" >&2; }
info() { printf '%s%s%s\n' "$COLOR_GREEN" "$*" "$COLOR_RESET" >&2; }
warn() { printf '%s%s%s\n' "$COLOR_YELLOW" "$*" "$COLOR_RESET" >&2; }
die()  { printf '%s%s%s\n' "$COLOR_RED" "$*" "$COLOR_RESET" >&2; exit "${2:-1}"; }

usage_die() { die "$*" 2; }

# run CMD...: execute, or print when --dry-run is active.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] %s\n' "$*" >&2
    return 0
  fi
  "$@"
}

# parse_common_flags "$@" -> sets DRY_RUN, consumes --dry-run
parse_common_flags() {
  local rest=()
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=1 ;;
      *) rest+=("$arg") ;;
    esac
  done
  printf '%s\n' "${rest[@]:-}"
}

# load_device CODENAME: source devices/<codename>.env and validate required keys.
load_device() {
  local codename="${1:-}"
  [ -n "$codename" ] || usage_die "missing codename"
  local file="$DEVICES_DIR/$codename.env"
  if [ ! -f "$file" ]; then
    local available
    available="$(cd "$DEVICES_DIR" && ls -1 *.env.example 2>/dev/null | sed 's/\.env\.example$//' | tr '\n' ' ')"
    usage_die "unknown codename '$codename'. available: ${available:-none}"
  fi
  # shellcheck disable=SC1090
  . "$file"
  # Two kernel sources:
  #   mainline     build from KERNEL_REPO; every kernel key is required
  #   stock-repack keep the vendor kernel and DTB, replace only the initramfs
  KERNEL_FLAVOR="${KERNEL_FLAVOR:-mainline}"
  case "$KERNEL_FLAVOR" in
    mainline|stock-repack) ;;
    *) die "$file: KERNEL_FLAVOR must be mainline or stock-repack (got $KERNEL_FLAVOR)" ;;
  esac
  BOOTLOADER="${BOOTLOADER:-aboot}"
  case "$BOOTLOADER" in
    aboot) ;;
    lk2nd)
      local lk
      for lk in LK2ND_TARGET LK2ND_URL LK2ND_SHA256; do
        [ -n "${!lk:-}" ] || die "$file: BOOTLOADER=lk2nd needs $lk"
      done
      [ "${#LK2ND_SHA256}" -eq 64 ] || die "$file: LK2ND_SHA256 must be a 64-character SHA-256"
      ;;
    *) die "$file: BOOTLOADER must be aboot or lk2nd (got $BOOTLOADER)" ;;
  esac
  KIOSK="${KIOSK:-0}"
  case "$KIOSK" in 0|1) ;; *) die "$file: KIOSK must be 0 or 1" ;; esac
  local key
  local -a needed=(DEVICE SOC ROOT_PARTNAME_EXPECTED ROOT_MARKER MIN_FREE_GB)
  if [ "$KERNEL_FLAVOR" = mainline ]; then
    needed+=(KERNEL_REPO KERNEL_REF DEFCONFIG DTB_NAME BOOTIMG_PAGESIZE BOOTIMG_BASE CMDLINE NET_MODE)
  fi
  for key in "${needed[@]}"; do
    [ -n "${!key:-}" ] || die "$file: missing required key $key"
  done
  [ "$DEVICE" = "$codename" ] || die "$file: DEVICE=$DEVICE does not match filename $codename"
  if [ "$KERNEL_FLAVOR" = mainline ]; then
    case "$BOOTIMG_PAGESIZE" in 2048|4096) ;; *) die "$file: BOOTIMG_PAGESIZE must be 2048 or 4096" ;; esac
    case "$NET_MODE" in wlan0|usb0|eth0) ;; *) die "$file: NET_MODE must be wlan0, usb0, or eth0" ;; esac
  fi
  [ "${MIN_FREE_GB:-0}" -ge 1 ] 2>/dev/null || die "$file: MIN_FREE_GB must be a positive integer"
  export DEVICE SOC KERNEL_FLAVOR KCONFIG_FRAGMENT_EXTRA BOOTLOADER KIOSK \
         LK2ND_TARGET LK2ND_URL LK2ND_SHA256 KERNEL_REPO KERNEL_REF KERNEL_COMMIT KERNEL_ARCHIVE_SHA256 DEFCONFIG DTB_NAME DTB_VARIANT \
         BOOTIMG_PAGESIZE BOOTIMG_BASE CMDLINE NET_MODE ROOT_PARTNAME_EXPECTED ROOT_MARKER MIN_FREE_GB
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing command: $c"
  done
}

confirm() {
  local prompt="$1"
  [ "$DRY_RUN" = "1" ] && { log "[dry-run] would ask: $prompt"; return 0; }
  [ -t 0 ] || die "refusing destructive action without an interactive terminal: $prompt"
  printf '%s [yes/NO] ' "$prompt" >&2
  local answer; read -r answer
  [ "$answer" = "yes" ] || { log "aborted"; exit 0; }
}
