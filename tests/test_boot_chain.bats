#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Initramfs packing, boot image repacking, and flash safety.
# Run: bats tests/
setup() {
  PY="${PYTHON:-python3}"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DEBIANDROID_OUT="$BATS_TEST_TMPDIR/out"
  export DEBIANDROID_CACHE="$BATS_TEST_TMPDIR/cache"
  export FASTBOOT_BIN=true
  export PYTHON="$PY"
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  cp -r "$REPO_ROOT/devices" "$REPO_ROOT/scripts" "$REPO_ROOT/initramfs" "$BATS_TEST_TMPDIR/repo/"
  for d in santoni mido sagit; do
    cp "$REPO_ROOT/devices/$d.env.example" "$BATS_TEST_TMPDIR/repo/devices/$d.env"
  done
  export DEBIANDROID_REPO_ROOT="$BATS_TEST_TMPDIR/repo"
}

make_stock_image() { # make_stock_image <path> [header_version]
  "$PY" - "$1" "${2:-0}" <<'PYEOF'
import hashlib, struct, sys
path, hv = sys.argv[1], int(sys.argv[2])
page = 2048
kernel = b"\x1f\x8b" + b"K" * 6000
ramdisk = b"\x1f\x8b" + b"R" * 4000
header = bytearray(1632)
header[0:8] = b"ANDROID!"
for off, value in ((8, len(kernel)), (12, 0x80008000), (16, len(ramdisk)),
                   (20, 0x81000000), (24, 0), (28, 0x80F00000),
                   (32, 0x80000100), (36, page), (40, hv)):
    struct.pack_into("<I", header, off, value)
header[48:56] = b"santoni\0"
header[64:76] = b"console=tty0"
digest = hashlib.sha1()
for blob in (kernel, ramdisk, b""):
    digest.update(blob)
    digest.update(struct.pack("<I", len(blob)))
header[576:608] = digest.digest()
pad = lambda blob: blob + b"\0" * ((-len(blob)) % page)
open(path, "wb").write(pad(bytes(header)) + pad(kernel) + pad(ramdisk))
PYEOF
}

@test "mkcpio builds an archive with an executable init and device nodes" {
  mkdir -p "$BATS_TEST_TMPDIR/root/bin"
  printf '#!/bin/sh\ntrue\n' > "$BATS_TEST_TMPDIR/root/init"
  printf 'payload' > "$BATS_TEST_TMPDIR/root/bin/busybox"
  run "$PY" "$REPO_ROOT/scripts/lib/mkcpio.py" "$BATS_TEST_TMPDIR/root" \
      "$BATS_TEST_TMPDIR/ir.cpio.gz" --gzip --chmod init:755
  [ "$status" -eq 0 ]
  run "$PY" "$REPO_ROOT/scripts/lib/mkcpio.py" --list "$BATS_TEST_TMPDIR/ir.cpio.gz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- 0755"*" init"* ]]
  [[ "$output" == *"c 0600"*"dev/console"* ]]
  [[ "$output" == *"c 0666"*"dev/null"* ]]
}

@test "boot image layout round-trips byte for byte" {
  run "$PY" "$REPO_ROOT/scripts/lib/bootimg_v0.py" selfcheck
  [ "$status" -eq 0 ]
  [[ "$output" == *"selfcheck: OK"* ]]
}

@test "repack keeps the kernel and replaces the ramdisk" {
  make_stock_image "$BATS_TEST_TMPDIR/stock.img"
  printf '\x1f\x8bnew-ramdisk' > "$BATS_TEST_TMPDIR/ir.cpio.gz"
  run "$PY" "$REPO_ROOT/scripts/lib/bootimg_v0.py" repack "$BATS_TEST_TMPDIR/stock.img" \
      --ramdisk "$BATS_TEST_TMPDIR/ir.cpio.gz" --out "$BATS_TEST_TMPDIR/out.img"
  [ "$status" -eq 0 ]
  run "$PY" "$REPO_ROOT/scripts/lib/bootimg_v0.py" info "$BATS_TEST_TMPDIR/out.img"
  [[ "$output" == *"kernel          6002 bytes"* ]]
  [[ "$output" == *"ramdisk         13 bytes"* ]]
}

@test "repack refuses a v1/v2 header" {
  make_stock_image "$BATS_TEST_TMPDIR/stock2.img" 2
  printf '\x1f\x8bnew-ramdisk' > "$BATS_TEST_TMPDIR/ir.cpio.gz"
  run "$PY" "$REPO_ROOT/scripts/lib/bootimg_v0.py" repack "$BATS_TEST_TMPDIR/stock2.img" \
      --ramdisk "$BATS_TEST_TMPDIR/ir.cpio.gz" --out "$BATS_TEST_TMPDIR/out2.img"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported"* ]]
}

@test "repack refuses an empty ramdisk" {
  make_stock_image "$BATS_TEST_TMPDIR/stock3.img"
  : > "$BATS_TEST_TMPDIR/empty"
  run "$PY" "$REPO_ROOT/scripts/lib/bootimg_v0.py" repack "$BATS_TEST_TMPDIR/stock3.img" \
      --ramdisk "$BATS_TEST_TMPDIR/empty" --out "$BATS_TEST_TMPDIR/out3.img"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "initramfs build without busybox fails with instructions" {
  run env BUSYBOX= PATH="$PATH" DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/initramfs/build.sh" santoni --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"busybox"* ]]
}

@test "initramfs dry-run accepts an explicit busybox" {
  printf 'fake' > "$BATS_TEST_TMPDIR/busybox"
  run env BUSYBOX="$BATS_TEST_TMPDIR/busybox" DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/initramfs/build.sh" santoni --dry-run --mode test
  [ "$status" -eq 0 ]
  [[ "$output" == *"initramfs-santoni-test.cpio.gz"* ]]
}
