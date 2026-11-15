#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Config and preflight behaviour. Run: bats tests/
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DEBIANDROID_OUT="$BATS_TEST_TMPDIR/out"
  export DEBIANDROID_CACHE="$BATS_TEST_TMPDIR/cache"
}

@test "every codename has an example env" {
  for dev in santoni mido sagit; do
    [ -f "$REPO_ROOT/devices/$dev.env.example" ]
  done
}

@test "example env declares DEVICE matching its filename" {
  for dev in santoni mido sagit; do
    run grep -x "DEVICE=$dev" "$REPO_ROOT/devices/$dev.env.example"
    [ "$status" -eq 0 ]
  done
}

@test "santoni uses eMMC page size 2048" {
  run grep -x "BOOTIMG_PAGESIZE=2048" "$REPO_ROOT/devices/santoni.env.example"
  [ "$status" -eq 0 ]
}

@test "sagit uses UFS page size 4096" {
  run grep -x "BOOTIMG_PAGESIZE=4096" "$REPO_ROOT/devices/sagit.env.example"
  [ "$status" -eq 0 ]
}

@test "preflight rejects an unknown codename with exit 2" {
  run "$REPO_ROOT/scripts/lib/preflight.sh" nosuchdevice
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown codename"* ]]
}

@test "preflight passes for a valid codename in dry-run" {
  cp "$REPO_ROOT/devices/santoni.env.example" "$BATS_TEST_TMPDIR/santoni.env"
  mkdir -p "$BATS_TEST_TMPDIR/devices"
  cp "$BATS_TEST_TMPDIR/santoni.env" "$BATS_TEST_TMPDIR/devices/santoni.env"
  run bash -c "cd '$BATS_TEST_TMPDIR' && '$REPO_ROOT/scripts/lib/preflight.sh' santoni --dry-run"
  [ "$status" -eq 0 ]
}

@test "partition guard refuses a non-block target" {
  run "$REPO_ROOT/scripts/lib/partition-guard.sh" /tmp/notablock userdata /etc/x --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"refusing non-block-device"* ]]
}

@test "flash dry-run needs no device" {
  mkdir -p "$DEBIANDROID_OUT/santoni"
  touch "$DEBIANDROID_OUT/santoni/boot-santoni.img"
  cp "$REPO_ROOT/devices/santoni.env.example" "$REPO_ROOT/devices/__tmp_santoni.env"
  run env FASTBOOT_BIN=true "$REPO_ROOT/scripts/flash.sh" santoni --ram-boot --dry-run
  status_saved=$status
  rm -f "$REPO_ROOT/devices/__tmp_santoni.env"
  [ "$status_saved" -eq 0 ]
}
