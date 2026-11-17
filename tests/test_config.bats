#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Config, preflight, and dry-run behaviour. Run: bats tests/
setup() {
  PY="${PYTHON:-python3}"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DEBIANDROID_OUT="$BATS_TEST_TMPDIR/out"
  export DEBIANDROID_CACHE="$BATS_TEST_TMPDIR/cache"
  export FASTBOOT_BIN=true
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  cp -r "$REPO_ROOT/devices" "$BATS_TEST_TMPDIR/repo/"
  for d in santoni mido sagit; do
    cp "$REPO_ROOT/devices/$d.env.example" "$BATS_TEST_TMPDIR/repo/devices/$d.env"
  done
  export DEBIANDROID_REPO_ROOT="$BATS_TEST_TMPDIR/repo"
}

@test "every codename has an example env" {
  for dev in santoni mido sagit; do
    [ -f "$REPO_ROOT/devices/$dev.env.example" ]
  done
}

@test "example env DEVICE matches its filename" {
  for dev in santoni mido sagit; do
    run grep -x "DEVICE=$dev" "$REPO_ROOT/devices/$dev.env.example"
    [ "$status" -eq 0 ]
  done
}

@test "santoni pins a 40-character commit" {
  run grep -E '^KERNEL_COMMIT=[0-9a-f]{40}$' "$REPO_ROOT/devices/santoni.env.example"
  [ "$status" -eq 0 ]
}

@test "santoni uses eMMC page size 2048" {
  run grep -x "BOOTIMG_PAGESIZE=2048" "$REPO_ROOT/devices/santoni.env.example"
  [ "$status" -eq 0 ]
}

@test "sagit uses UFS page size 4096" {
  run grep -x "BOOTIMG_PAGESIZE=4096" "$REPO_ROOT/devices/sagit.env.example"
  [ "$status" -eq 0 ]
}

@test "CMDLINE is quoted" {
  for dev in santoni mido sagit; do
    run grep -E '^CMDLINE=".+"$' "$REPO_ROOT/devices/$dev.env.example"
    [ "$status" -eq 0 ]
  done
}

@test "preflight rejects an unknown codename with exit 2" {
  run "$REPO_ROOT/scripts/lib/preflight.sh" nosuchdevice
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown codename"* ]]
}

@test "preflight passes for every codename in dry-run" {
  for dev in santoni mido sagit; do
    run env DEBIANDROID_ROOT_OVERRIDE=1 "$REPO_ROOT/scripts/lib/preflight.sh" "$dev" --dry-run
    [ "$status" -eq 0 ]
  done
}

@test "preflight fails on a malformed commit pin" {
  sed -i 's/^KERNEL_COMMIT=.*/KERNEL_COMMIT=zzz/' "$DEBIANDROID_REPO_ROOT/devices/santoni.env"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/lib/preflight.sh" santoni --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"KERNEL_COMMIT"* ]]
}

@test "partition guard refuses a non-block target" {
  run "$REPO_ROOT/scripts/lib/partition-guard.sh" /tmp/notablock userdata /etc/x --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"refusing non-block-device"* ]]
}

@test "flash dry-run succeeds without a device" {
  mkdir -p "$DEBIANDROID_OUT/santoni"
  touch "$DEBIANDROID_OUT/santoni/boot-santoni.img"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/flash.sh" santoni --flash-recovery --dry-run
  [ "$status" -eq 0 ]
}
@test "flash refuses a RAM boot of an unproven image" {
  mkdir -p "$DEBIANDROID_OUT/santoni"
  touch "$DEBIANDROID_OUT/santoni/boot-santoni.img"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/flash.sh" santoni --ram-boot --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"--allow-unproven"* ]]
}
@test "flash dry-run fails clearly when the image is missing" {
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/flash.sh" santoni --flash-recovery --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"boot image not built"* ]]
}
@test "santoni declares a kconfig fragment that exists" {
  run grep -E '^KCONFIG_FRAGMENT=kernel/config/santoni-server.config$' "$REPO_ROOT/devices/santoni.env.example"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/kernel/config/santoni-server.config" ]
}

@test "server fragment enables the USB gadget stack" {
  for opt in CONFIG_USB_CONFIGFS CONFIG_USB_CONFIGFS_NCM CONFIG_BLK_DEV_LOOP CONFIG_EXT4_FS; do
    run grep -x "$opt=y" "$REPO_ROOT/kernel/config/santoni-server.config"
    [ "$status" -eq 0 ]
  done
}

@test "build-kernel dry-run reports the pin before failing on host tools" {
  run "$REPO_ROOT/scripts/build-kernel.sh" santoni --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"would verify HEAD"* ]]
}

@test "mkbootimg.py writes a valid v0 header with the right page size" {
  local tmp="$BATS_TEST_TMPDIR/mk1"; mkdir -p "$tmp"
  local wtmp; wtmp="$(cd "$tmp" && pwd -W 2>/dev/null || echo "$tmp")"
  "$PY" -c "open(r'$wtmp/k.gz','wb').write(bytes(4096))"
  run "$PY" "$REPO_ROOT/scripts/lib/mkbootimg.py" --kernel "$wtmp/k.gz" \
      --pagesize 2048 --cmdline "console=ttyMSM0" --board santoni --output "$wtmp/b.img"
  [ "$status" -eq 0 ]
  run "$PY" -c "
import struct,sys
d=open(r'$wtmp/b.img','rb').read()
assert d[:8]==b'ANDROID!'
f=struct.unpack('<10I',d[8:48])
assert f[7]==2048, f[7]
assert len(d)%2048==0
"
  [ "$status" -eq 0 ]
}

@test "mkbootimg.py rejects a cmdline longer than header v0 allows" {
  local tmp="$BATS_TEST_TMPDIR/mk2"; mkdir -p "$tmp"
  local wtmp; wtmp="$(cd "$tmp" && pwd -W 2>/dev/null || echo "$tmp")"
  "$PY" -c "open(r'$wtmp/k.gz','wb').write(bytes(16))"
  long=$("$PY" -c "print('a'*600)")
  run "$PY" "$REPO_ROOT/scripts/lib/mkbootimg.py" --kernel "$wtmp/k.gz" --cmdline "$long" --output "$wtmp/b.img"
  [ "$status" -eq 2 ]
}

@test "kernel-pin dry-run mentions tags as well as branches" {
  cp "$REPO_ROOT/devices/mido.env.example" "$DEBIANDROID_REPO_ROOT/devices/mido.env"
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/lib/kernel-pin.sh" mido --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"refs/tags/"* ]]
}

@test "mido and sagit pin the same verified upstream tag" {
  run grep -x "KERNEL_REF=v6.19" "$REPO_ROOT/devices/mido.env.example"
  [ "$status" -eq 0 ]
  run grep -x "KERNEL_REF=v6.19" "$REPO_ROOT/devices/sagit.env.example"
  [ "$status" -eq 0 ]
  run grep -x "KERNEL_COMMIT=05f7e89ab9731565d8a62e3b5d1ec206485eeb0b" "$REPO_ROOT/devices/sagit.env.example"
  [ "$status" -eq 0 ]
}

@test "sagit uses 4096-byte boot pages for UFS" {
  run grep -x "BOOTIMG_PAGESIZE=4096" "$REPO_ROOT/devices/sagit.env.example"
  [ "$status" -eq 0 ]
}

@test "platform-tools helper resolves per-OS paths" {
  run bash -c "cd '$REPO_ROOT' && . scripts/lib/common.sh && . scripts/lib/platform-tools.sh && fastboot_bin"
  [ "$status" -eq 0 ]
  [[ "$output" == */platform-tools/*/fastboot* ]]
}

@test "platform-tools helper reports its platform name" {
  run bash -c "cd '$REPO_ROOT' && . scripts/lib/common.sh && . scripts/lib/platform-tools.sh && platform_name"
  [ "$status" -eq 0 ]
  case "$output" in linux|darwin|windows) ;; *) false ;; esac
}

@test "flash requires fastboot via the helper, not a system binary" {
  run grep -q "require_fastboot" "$REPO_ROOT/scripts/flash.sh"
  [ "$status" -eq 0 ]
  run grep -q "require_fastboot" "$REPO_ROOT/scripts/lib/preflight.sh"
  [ "$status" -eq 0 ]
}

@test "verify-bootimg rejects an image with no ramdisk" {
  local tmp="$BATS_TEST_TMPDIR/vb"; mkdir -p "$tmp"
  local wtmp; wtmp="$(cd "$tmp" && pwd -W 2>/dev/null || echo "$tmp")"
  "$PY" -c "open(r'$wtmp/k.gz','wb').write(bytes(4096))"
  run "$PY" "$REPO_ROOT/scripts/lib/mkbootimg.py" --kernel "$wtmp/k.gz" \
      --pagesize 2048 --cmdline "console=ttyMSM0" --output "$wtmp/b.img"
  [ "$status" -eq 0 ]
  run "$PY" "$REPO_ROOT/scripts/lib/verify-bootimg.py" "$wtmp/b.img"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ramdisk_size is 0"* ]]
}

@test "verify-bootimg accepts an image with an initramfs" {
  local tmp="$BATS_TEST_TMPDIR/vb2"; mkdir -p "$tmp"
  local wtmp; wtmp="$(cd "$tmp" && pwd -W 2>/dev/null || echo "$tmp")"
  "$PY" -c "import gzip; open(r'$wtmp/k.gz','wb').write(gzip.compress(bytes(256)))"
  "$PY" -c "import gzip; open(r'$wtmp/r.cpio.gz','wb').write(gzip.compress(b'070701'*10))"
  run "$PY" "$REPO_ROOT/scripts/lib/mkbootimg.py" --kernel "$wtmp/k.gz" \
      --ramdisk "$wtmp/r.cpio.gz" --pagesize 2048 --cmdline "console=ttyMSM0" \
      --output "$wtmp/b.img"
  [ "$status" -eq 0 ]
  run "$PY" "$REPO_ROOT/scripts/lib/verify-bootimg.py" "$wtmp/b.img"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "make-bootimg refuses to build without an initramfs" {
  local tmp="$BATS_TEST_TMPDIR/mb"; mkdir -p "$tmp/repo/devices" "$tmp/out/santoni"
  local wtmp; wtmp="$(cd "$tmp" && pwd -W 2>/dev/null || echo "$tmp")"
  cp "$REPO_ROOT/devices/santoni.env.example" "$tmp/repo/devices/santoni.env.example"
  cp "$REPO_ROOT/devices/santoni.env.example" "$tmp/repo/devices/santoni.env"
  "$PY" -c "open(r'$wtmp/out/santoni/Image.gz','wb').write(bytes(4096))"
  "$PY" -c "open(r'$wtmp/out/santoni/msm8940-xiaomi-santoni.dtb','wb').write(bytes(64))"
  run env DEBIANDROID_REPO_ROOT="$tmp/repo" DEBIANDROID_OUT="$tmp/out" \
      "$REPO_ROOT/scripts/make-bootimg.sh" santoni
  [ "$status" -ne 0 ]
  [[ "$output" == *"no initramfs"* ]]
}
