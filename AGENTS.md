# AGENTS.md: working rules for debiandroid

Read `PRD.md` and `docs/design.md` before touching code. Those documents are the source of truth for scope.

## Language and style

- Responses and documents: English. Keep technical terms in English.
- Expand every abbreviation on first use, e.g. "UFS (Universal Flash Storage)".
- No em dashes. No filler.

## Principles

1. **Safety first.** Every destructive step (flash, format, repartition) requires explicit confirmation and a preflight check.
2. **Test in the partition with the smallest blast radius.** Save the stock boot and recovery images first (`scripts/backup-stock.sh`), then flash the **recovery** partition. `fastboot boot` runs an unproven kernel in RAM and can leave the device in EDL; `flash.sh` refuses it without `--allow-unproven`.
3. **Idempotent.** Scripts can be re-run without damaging results.
4. **One configuration source.** All device parameters live in `devices/<codename>.env`.
5. **No secrets in the repository.** SSH keys, tokens, and credentials are never committed.
6. **No unused dependencies.** Bash plus system utilities are sufficient at this stage.

## Script conventions

- `#!/usr/bin/env bash` and `set -euo pipefail`.
- The first argument is always the device codename. Long options (`--mode`, `--ram-boot`, `--dry-run`).
- Every script supports `--dry-run`, which prints commands without executing them.
- Logs go to stderr; structured results go to stdout.
- Exit codes: 0 success, 1 general error, 2 bad arguments, 3 preflight failure.

## Structure

- `devices/*.env`: KERNEL_FLAVOR, KERNEL_REPO, KERNEL_REF, DEFCONFIG, KCONFIG_FRAGMENT, KCONFIG_FRAGMENT_EXTRA, DTB_NAME, CMDLINE, BOOTIMG_PARAMS, NET_MODE.
- `scripts/build-kernel.sh`: clone the source, cross-compile, output to `out/<codename>/`; merges the fragment plus extras and verifies them.
- `scripts/make-bootimg.sh`: assemble `boot.img` from kernel, DTB, and initramfs.
- `scripts/repack-stock.sh` + `scripts/lib/bootimg_v0.py`: replace only the ramdisk of a stock image (the safe first hardware path).
- `initramfs/init` + `scripts/initramfs/build.sh` + `scripts/lib/mkcpio.py`: boot script, archive builder, cpio writer.
- `rootfs/overlay/`: files baked into every rootfs, including the `debiandroid-health` systemd unit the dead-man timer needs.
- `scripts/rootfs/*.sh`: build the rootfs per backend.
- `scripts/install.sh`: installation orchestration for the selected `--mode`.
- `scripts/flash.sh`: flash `lk2nd`, `boot` or `recovery`, with confirmation and a RAM-boot override.
- `scripts/fetch-lk2nd.sh`: download the pinned lk2nd release image and verify its SHA-256.
- `rootfs/overlay/etc/systemd/system/debiandroid-kiosk.service`: opt-in fullscreen browser (`KIOSK=1`, default off).
- One rootfs image serves multiple devices; kernel, DTB and initramfs remain device-specific.
- `scripts/verify-flash.sh`: read the partition back through adb and compare SHA-256.
- `scripts/backup-stock.sh`: save the stock boot and recovery images before any write.

## Required verification

```bash
shellcheck scripts/*.sh scripts/lib/*.sh scripts/initramfs/*.sh
bats tests/
python3 scripts/lib/bootimg_v0.py selfcheck
./scripts/flash.sh mido --flash-recovery --dry-run   # after cp devices/mido.env.example devices/mido.env
```

The third command proves the boot image layout round-trips byte for byte. The fourth
must never touch a device: with an image in `out/<codename>/` it exits 0 after printing
the fastboot command, and with no image it exits 1 with "boot image not built".

Behavior changes must update `PRD.md` and `docs/design.md` when they affect scope.

## Releases and CI

- The workflow triggers only on `v*` tags or `workflow_dispatch`. Never add a schedule.
- Matrix: `backend` x `channel` for rootfs; `codename` for `boot.img`.
- Every asset must be listed in `SHA256SUMS`; `fetch.sh` rejects a wrong checksum.
- Never rename assets without updating README, PRD, and `fetch.sh`.

## TWRP installer

- `update-binary` (POSIX shell, executed by TWRP) must be idempotent and verify the payload before touching any partition.
- Bundle `tools/busybox` and a static `tools/zstd`; never assume TWRP ships either.
- Dual confirmation for modes: both `dual-boot` and `dedicated` are destructive at the install point.
- Test on real TWRP before releasing.

## Prohibited

- Never claim a boot succeeded without evidence from the device: kernel log on the console plus network or SSH access.
- Never flash a boot image that `verify-bootimg.py` rejects, or one with no initramfs.
- Never ship `KERNEL_FLAVOR=stock-repack` claiming mainline features; it keeps the vendor kernel.
- Never attribute networking behaviour to lk2nd: it is a bootloader with no network stack. Networking is kernel, firmware and userspace.
- Never flash an lk2nd image whose SHA-256 does not match `devices/<codename>.env`.
- Never build a stock kernel from Xiaomi's published tree expecting a device tree: `santoni-n-oss` has no `msm8937-santoni.dts`. The device image is the source of truth.
- Never add device support outside scope without an owner decision.
- Never silently switch the default mode (dual-boot) to dedicated.

## Documentation maintenance

- `docs/validation.md` is updated with every release tag: what was checked, how, and what was not.
- A cross-project reference gets its own `docs/<project>-comparison.md` and a row in the README documentation map; strategy changes cite it.
- Never mark a check as passed without the command output that produced it.
- Update `LICENSES/README.md` when adding a directory or a file with a different license.
- Every source file starts with an SPDX identifier.
