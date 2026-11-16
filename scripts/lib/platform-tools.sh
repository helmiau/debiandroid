#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Auto-provisi Android platform-tools (adb + fastboot) dari Google.
#
# Pengguna tidak perlu menginstal adb/fastboot manual di Windows, Linux, dan
# macOS. Berkas diunduh sekali ke .cache/platform-tools/<os>/ lalu dipakai ulang.
#
# Urutan pencarian:
#   1. binary di PATH (pakai yang sudah terpasang)
#   2. vendor/platform-tools/<os>/ (paket offline yang dibagikan terpisah)
#   3. .cache/platform-tools/<os>/ (hasil unduhan otomatis)
#   4. unduh dari dl.google.com
#
# Usage: source common.sh, lalu source berkas ini, lalu panggil require_fastboot
# atau require_adb sebelum memakai $FASTBOOT_BIN / $ADB_BIN.

PLATFORM_TOOLS_ROOT="${DEBIANDROID_CACHE:-${CACHE_DIR:-$ROOT_DIR/.cache}}/platform-tools"
PLATFORM_TOOLS_VENDOR="${DEBIANDROID_VENDOR:-${ROOT_DIR:-.}/vendor}/platform-tools"
PLATFORM_TOOLS_URL_BASE="https://dl.google.com/android/repository"

_pt_exe_suffix() {
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
  echo "$(platform_tools_dir)/fastboot$(_pt_exe_suffix)"
}

adb_bin() {
  echo "$(platform_tools_dir)/adb$(_pt_exe_suffix)"
}

_pt_is_exec() {
  [ -f "$1" ] || return 1
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) [ -x "$1" ] ;;
  esac
}

# Ambil binary dari paket offline vendor/ bila disediakan.
_pt_try_vendor() {
  local plat bin
  plat="$(platform_name)"
  for bin in fastboot adb; do
    if [ -f "$PLATFORM_TOOLS_VENDOR/$plat/$bin$(_pt_exe_suffix)" ]; then
      : # vendor tersedia
    else
      return 1
    fi
  done
  info "memakai platform-tools dari vendor/$plat"
  run mkdir -p "$(platform_tools_dir)"
  run cp -f "$PLATFORM_TOOLS_VENDOR/$plat/"* "$(platform_tools_dir)/"
  run chmod +x "$(platform_tools_dir)/"* 2>/dev/null || true
  return 0
}

# Ekstrak zip dengan alat yang tersedia di host.
_pt_extract() {
  local zip="$1" dest="$2"
  if command -v unzip >/dev/null 2>&1; then
    run unzip -qo "$zip" -d "$dest"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$zip" "$dest" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
  elif command -v tar >/dev/null 2>&1 && tar --version 2>/dev/null | grep -qi bsdtar; then
    run tar -xf "$zip" -C "$dest"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command \
      "Expand-Archive -LiteralPath '$(cygpath -w "$zip" 2>/dev/null || echo "$zip")' -DestinationPath '$(cygpath -w "$dest" 2>/dev/null || echo "$dest")' -Force"
  else
    die "butuh unzip, python3, bsdtar, atau PowerShell untuk mengekstrak platform-tools" 3
  fi
}

# Unduh platform-tools resmi Google jika belum ada di cache.
ensure_platform_tools() {
  local plat dest zip tmp
  plat="$(platform_name)"
  dest="$(platform_tools_dir)"

  if _pt_is_exec "$(fastboot_bin)" && _pt_is_exec "$(adb_bin)"; then
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] akan menyediakan platform-tools ($plat) di $dest"
    return 0
  fi

  if _pt_try_vendor; then
    _pt_is_exec "$(fastboot_bin)" || die "vendor platform-tools tidak berisi fastboot yang dapat dieksekusi"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "butuh curl untuk mengunduh platform-tools" 3

  info "adb/fastboot belum tersedia; mengunduh platform-tools ($plat)"
  run mkdir -p "$dest"
  zip="$PLATFORM_TOOLS_ROOT/dl-${plat}.zip"
  tmp="$PLATFORM_TOOLS_ROOT/tmp-${plat}"

  run curl -fsL --retry 3 --retry-delay 2 \
    "$PLATFORM_TOOLS_URL_BASE/platform-tools-latest-${plat}.zip" -o "$zip"

  # Tolak berkas yang jelas bukan zip (mis. halaman error HTML).
  if ! head -c 2 "$zip" 2>/dev/null | grep -q "PK"; then
    die "unduhan platform-tools gagal atau rusak (bukan berkas zip): $zip" 3
  fi

  run rm -rf "$tmp"
  run mkdir -p "$tmp"
  _pt_extract "$zip" "$tmp"

  if [ -d "$tmp/platform-tools" ]; then
    run cp -f "$tmp/platform-tools/"* "$dest/"
  else
    run cp -f "$tmp/"* "$dest/"
  fi
  run rm -rf "$tmp" "$zip"
  run chmod +x "$dest/adb$(_pt_exe_suffix)" "$dest/fastboot$(_pt_exe_suffix)" 2>/dev/null || true

  _pt_is_exec "$(fastboot_bin)" || die "fastboot tidak ditemukan setelah ekstrak: $(fastboot_bin)" 3
  _pt_is_exec "$(adb_bin)" || die "adb tidak ditemukan setelah ekstrak: $(adb_bin)" 3
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
