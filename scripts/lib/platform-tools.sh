#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Auto-provisi Android platform-tools (adb + fastboot) dari Google sehingga repo
# ini bekerja di host yang tidak menginstal android-platform-tools.
#
# Usage: source common.sh terlebih dahulu, kemudian source berkas ini; panggil
# require_fastboot atau require_adb sebelum menggunakan $FASTBOOT_BIN /
# $ADB_BIN. Unduh hanya saat binary benar-benar dibutuhkan dan belum ada di
# cache.

PLATFORM_TOOLS_ROOT="${DEBIANDROID_CACHE:-${CACHE_DIR:-$ROOT_DIR/.cache}}/platform-tools"

exe_suffix() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) echo .exe ;;
    *) echo ;;
  esac
}

platform_name() {
  case "$(uname -s)" in
    Linux*) echo linux ;;
    Darwin*) echo darwin ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) die "host $(uname -s) tidak didukung untuk auto-provisi platform-tools" 3 ;;
  esac
}

platform_tools_dir() {
  echo "$PLATFORM_TOOLS_ROOT/$(platform_name)"
}

fastboot_bin() {
  echo "$(platform_tools_dir)/fastboot$(exe_suffix)"
}

adb_bin() {
  echo "$(platform_tools_dir)/adb$(exe_suffix)"
}

# Unduh platform-tools resmi Google jika belum ada di cache.
ensure_platform_tools() {
  local plat dest zip tmp
  plat="$(platform_name)"
  dest="$(platform_tools_dir)"

  if [ -x "$(fastboot_bin)" ] && [ -x "$(adb_bin)" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] akan unduh platform-tools ($plat) ke $dest"
    return 0
  fi

  info "fastboot/adb belum ditemukan; unduh platform-tools ($plat) ke $dest"
  run mkdir -p "$dest"
  zip="$(mktemp)"
  run curl -fsL --retry 3 \
    "https://dl.google.com/android/repository/platform-tools-latest-${plat}.zip" \
    -o "$zip"
  tmp="$(mktemp -d)"
  run python3 - "$zip" "$tmp" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
  # zip Google berisi direktori platform-tools/
  if [ -d "$tmp/platform-tools" ]; then
    run mv "$tmp/platform-tools/"* "$dest/"
  else
    run mv "$tmp/"* "$dest/"
  fi
  run chmod +x "$dest/adb$(exe_suffix)" "$dest/fastboot$(exe_suffix)"
  run rm -rf "$tmp" "$zip"
  info "platform-tools siap: $(fastboot_bin)"
}

require_fastboot() {
  if command -v fastboot >/dev/null 2>&1; then
    export FASTBOOT_BIN=fastboot
    return 0
  fi
  ensure_platform_tools
  export FASTBOOT_BIN="$(fastboot_bin)"
}

require_adb() {
  if command -v adb >/dev/null 2>&1; then
    export ADB_BIN=adb
    return 0
  fi
  ensure_platform_tools
  export ADB_BIN="$(adb_bin)"
}
