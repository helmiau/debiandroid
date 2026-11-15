#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Config, preflight, and dry-run behaviour. Run: bats tests/
setup() {
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
      "$REPO_ROOT/scripts/flash.sh" santoni --ram-boot --dry-run
  [ "$status" -eq 0 ]
}

@test "flash dry-run fails clearly when the image is missing" {
  run env DEBIANDROID_REPO_ROOT="$DEBIANDROID_REPO_ROOT" \
      "$REPO_ROOT/scripts/flash.sh" santoni --ram-boot --dry-run
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
