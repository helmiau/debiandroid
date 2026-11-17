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

@test "kconfig-check accepts a fragment that survived the merge" {
  printf 'CONFIG_CGROUP_DEVICE=y\nCONFIG_VETH=m\n# a comment\nCONFIG_SOMETHING=n\n' > "$BATS_TEST_TMPDIR/frag"
  printf 'CONFIG_CGROUP_DEVICE=y\nCONFIG_VETH=m\n' > "$BATS_TEST_TMPDIR/merged"
  run "$REPO_ROOT/scripts/lib/kconfig-check.sh" "$BATS_TEST_TMPDIR/merged" "$BATS_TEST_TMPDIR/frag"
  [ "$status" -eq 0 ]
}

@test "kconfig-check names an option the tree dropped" {
  printf 'CONFIG_CGROUP_DEVICE=y\nCONFIG_NO_SUCH_SYMBOL=y\n' > "$BATS_TEST_TMPDIR/frag"
  printf 'CONFIG_CGROUP_DEVICE=y\n' > "$BATS_TEST_TMPDIR/merged"
  run "$REPO_ROOT/scripts/lib/kconfig-check.sh" "$BATS_TEST_TMPDIR/merged" "$BATS_TEST_TMPDIR/frag"
  [ "$status" -eq 3 ]
  [[ "$output" == *"CONFIG_NO_SUCH_SYMBOL"* ]]
}

@test "kconfig-check reports a value downgraded to module" {
  printf 'CONFIG_OVERLAY_FS=y\n' > "$BATS_TEST_TMPDIR/frag"
  printf 'CONFIG_OVERLAY_FS=m\n' > "$BATS_TEST_TMPDIR/merged"
  run "$REPO_ROOT/scripts/lib/kconfig-check.sh" "$BATS_TEST_TMPDIR/merged" "$BATS_TEST_TMPDIR/frag"
  [ "$status" -eq 3 ]
  [[ "$output" == *"requested CONFIG_OVERLAY_FS=y"* ]]
}

@test "fetch refuses a deferred rootfs backend" {
  run "$REPO_ROOT/scripts/fetch.sh" --backend ubuntu --channel stable --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"deferred"* ]]
}

@test "fetch still accepts debian" {
  run "$REPO_ROOT/scripts/fetch.sh" --backend debian --channel stable --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"rootfs-debian-arm64-stable"* ]]
}

make_lk2nd_env() {
  cat > "$BATS_TEST_TMPDIR/repo/devices/lk2nddev.env" <<'ENV'
DEVICE=lk2nddev
SOC=msm8940
KERNEL_FLAVOR=mainline
KERNEL_REPO=local
KERNEL_REF=main
DEFCONFIG=msm8937_defconfig
DTB_NAME=qcom/x.dtb
BOOTIMG_PAGESIZE=2048
BOOTIMG_BASE=0x80000000
CMDLINE="console=ttyMSM0"
NET_MODE=usb0
ROOT_PARTNAME_EXPECTED=userdata
ROOT_MARKER=/etc/debiandroid-root
MIN_FREE_GB=4
BOOTLOADER=lk2nd
LK2ND_TARGET=msm8952
LK2ND_URL=https://example.invalid/lk2nd-msm8952.img
LK2ND_SHA256=0000000000000000000000000000000000000000000000000000000000000000
ENV
}

@test "lk2nd fetch dry-run reports the pinned source and target" {
  make_lk2nd_env
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" DEBIANDROID_OUT="$DEBIANDROID_OUT" \
      "$REPO_ROOT/scripts/fetch-lk2nd.sh" lk2nddev --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.invalid/lk2nd-msm8952.img"* ]]
  [[ "$output" == *"lk2nd-msm8952.img"* ]]
}

@test "lk2nd fetch rejects an image whose hash differs" {
  make_lk2nd_env
  printf 'not-lk2nd' > "$BATS_TEST_TMPDIR/bad.img"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" DEBIANDROID_OUT="$DEBIANDROID_OUT" \
      "$REPO_ROOT/scripts/fetch-lk2nd.sh" lk2nddev --from "$BATS_TEST_TMPDIR/bad.img"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum mismatch"* ]]
}

@test "flash refuses an lk2nd image that does not match the pin" {
  make_lk2nd_env
  mkdir -p "$DEBIANDROID_OUT/lk2nddev"
  printf 'junk' > "$DEBIANDROID_OUT/lk2nddev/lk2nd-msm8952.img"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" DEBIANDROID_OUT="$DEBIANDROID_OUT" \
      FASTBOOT_BIN=true "$REPO_ROOT/scripts/flash.sh" lk2nddev --flash-lk2nd --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to flash"* ]]
}

@test "flash dry-runs an lk2nd image that matches the pin" {
  make_lk2nd_env
  mkdir -p "$DEBIANDROID_OUT/lk2nddev"
  printf 'pinned-bytes' > "$BATS_TEST_TMPDIR/pinned.img"
  SUM="$(sha256sum "$BATS_TEST_TMPDIR/pinned.img" | awk '{print $1}')"
  sed -i "s/^LK2ND_SHA256=.*/LK2ND_SHA256=$SUM/" "$BATS_TEST_TMPDIR/repo/devices/lk2nddev.env"
  cp "$BATS_TEST_TMPDIR/pinned.img" "$DEBIANDROID_OUT/lk2nddev/lk2nd-msm8952.img"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" DEBIANDROID_OUT="$DEBIANDROID_OUT" \
      FASTBOOT_BIN=true "$REPO_ROOT/scripts/flash.sh" lk2nddev --flash-lk2nd --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"fastboot flash lk2nd"* ]]
}

make_cloudflared_env() {
  cat > "$BATS_TEST_TMPDIR/repo/devices/cfdev.env" <<'ENV'
DEVICE=cfdev
SOC=msm8953
KERNEL_FLAVOR=mainline
BOOTLOADER=aboot
KERNEL_REPO=local
KERNEL_REF=main
DEFCONFIG=msm8953_defconfig
DTB_NAME=qcom/x.dtb
BOOTIMG_PAGESIZE=2048
BOOTIMG_BASE=0x80000000
CMDLINE="console=ttyMSM0"
NET_MODE=wlan0
ROOT_PARTNAME_EXPECTED=userdata
ROOT_MARKER=/etc/debiandroid-root
MIN_FREE_GB=4
KIOSK=0
CLOUDFLARED=1
ENV
}

@test "debian.sh dry-run downloads cloudflared when CLOUDFLARED=1" {
  make_cloudflared_env
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" DEBIANDROID_CACHE="$DEBIANDROID_CACHE" \
      DEBIANDROID_OUT="$DEBIANDROID_OUT" CLOUDFLARED=1 \
      "$REPO_ROOT/scripts/rootfs/debian.sh" cfdev --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"cloudflared"* ]]
  [[ "$output" == *"cloudflared-linux-arm64"* ]]
}

@test "debian.sh dry-run skips cloudflared when CLOUDFLARED=0" {
  make_cloudflared_env
  sed -i 's/^CLOUDFLARED=1$/CLOUDFLARED=0/' "$BATS_TEST_TMPDIR/repo/devices/cfdev.env"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "debootstrap stub"\n' > "$BATS_TEST_TMPDIR/bin/debootstrap"
  chmod +x "$BATS_TEST_TMPDIR/bin/debootstrap"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      DEBIANDROID_CACHE="$DEBIANDROID_CACHE" DEBIANDROID_OUT="$DEBIANDROID_OUT" \
      "$REPO_ROOT/scripts/rootfs/debian.sh" cfdev --dry-run
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"cloudflared"* ]]
}
