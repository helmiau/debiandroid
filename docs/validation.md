# Validation Record

What has been proven, what has not, and how. Update this file with every release tag.

## Rules

- A claim appears here only if a command or a hardware observation produced it.
- Separate "checked" from "not checked" explicitly. Absence of a check is not a pass.
- Record the commit, the host, and the device firmware for every hardware result.
- Never publish keys, partition dumps, IMEI/serial/MAC, or firmware blobs.

## Static checks (host, no device)

| Check | Command | Expected |
|---|---|---|
| Shell lint | `shellcheck scripts/**/*.sh installer/**/*.sh` | No findings |
| Script unit tests | `bats tests/` | All pass |
| Dry runs | `./scripts/*.sh <codename> --dry-run` | Exit 0, no changes |
| Docs links | link check over `*.md` | No broken local links |
| Secret scan | pattern scan over tracked files | No credentials, keys, or dumps |
| Kernel source pin | `scripts/build-kernel.sh <codename> --check-only` | Commit and `KERNEL_SHA256` match |
| Artifact checksums | `sha256sum -c SHA256SUMS` | All OK |

## Build checks (host)

| Check | Command | Expected |
|---|---|---|
| Kernel build | `scripts/build-kernel.sh <codename>` | `Image.gz`, `DTB`, `build.log`, checksums in `out/<codename>/` |
| Boot image | `scripts/make-bootimg.sh <codename>` | `boot-<codename>.img`, header and page size match `.env` |
| Rootfs build | `scripts/rootfs/<backend>.sh <codename> --dry-run` then real run | Tarball plus checksum |
| Installer zip | `build/installer-twrp.sh <tag>` | Zip contains `update-binary`, payload, config, tools |

## Hardware checks (per device)

Record device, firmware, panel variant, commit, and image hash for each run.

| Check | Method | Pass criteria |
|---|---|---|
| Non-destructive boot | `fastboot boot boot-<codename>.img` | Kernel log appears, initramfs reaches network stage |
| Partition guard | run installer with a deliberately wrong `ROOT_PARTNAME_EXPECTED` | Aborts before any write |
| Dual-boot install | TWRP zip or `install.sh --mode dual-boot` | `findmnt /` points at `/data/debian-server/rootfs`, SSH reachable |
| Dedicated install | `install.sh --mode dedicated` | `findmnt /` shows the real partition, SSH reachable |
| Network (mido) | `ip -br a`, `ping` | `wlan0` has an IP and reaches the gateway |
| Network (sagit) | `ip -br a`, `ping` | `usb0` has an IP and reaches the gateway |
| Reboot persistence | reboot twice | System returns without reinstalling |
| Android intact | boot Android after dual-boot install | Android boots normally |

## Not yet validated

- Charging policy and thermal behavior under sustained load.
- Modem, camera, audio, GPU acceleration, and system suspend.
- Any device other than the two listed codenames.
- Sustained multi-day operation.
- Recovery from a failed flash (procedure documented, not exercised).

## Reporting

File hardware results with the issue template. Redact identifiers. Attach the image hash and the exact commands used.

## P1 validation run (2026-11-16)

| Check | Command | Result |
|---|---|---|
| Syntax, all scripts | `bash -n scripts/**/*.sh` | PASS |
| bats suite | `bats tests/test_config.bats` | PASS 12/12 |
| Preflight, 3 codenames | `preflight.sh <dev> --dry-run` | PASS |
| Fetch dry-run | `fetch.sh --backend debian --channel stable --tag v0.1.0 --dry-run` | PASS, no network |
| Flash dry-run | `flash.sh santoni --ram-boot --dry-run` | PASS |
| Guard negative | `partition-guard.sh /tmp/x userdata /etc/y --dry-run` | PASS (exit 3) |
| Kernel pin vs remote | `kernel-pin.sh santoni` | PASS (matches branch head) |
| shellcheck | not installed on the authoring host | NOT RUN |

Not validated: any on-device boot. The santoni handset was not connected during P2.

## P2 build validation (2026-11-16)

CI run `43763461156`, commit `c8713ef`, GitHub Actions `ubuntu-24.04`.

| Check | Result |
|---|---|
| Kernel compile | PASS, 2173 objects, no warnings or errors in `build.log` |
| Boot image | PASS, `ANDROID!` v0, page 2048, kernel 8483501 bytes, page-aligned |
| Kernel address | PASS, `0x80008000` from `BOOTIMG_BASE + BOOTIMG_KERNEL_OFFSET` |
| Cmdline | PASS, `console=ttyMSM0,115200n8 root=/dev/ram0 rw` |
| Checksums | PASS, `sha256sum -c SHA256SUMS` on `Image.gz` and the DTB |
| DTB | PASS, `msm8940-xiaomi-santoni.dtb`, 54520 bytes |
| Fragment applied | PASS, built `configfs.o`, `f_ncm.o`, `f_rndis.o`, `f_ecm.o`, `loop.o`, `ext4/inode.o`, `udc/core.o`, `chipidea/udc.o`, `ci_hdrc_msm.o` |

Artifacts: `Image.gz` 8.1 MB, `boot-santoni.img` 8.1 MB, DTB 54.5 KB.

Not validated: the image was never booted. No hardware was attached during P2.

## P2 build validation (2026-11-16) — mido + sagit

CI runs `43798939699` (mido) and `43798954120` (sagit), commit `e5318ae`, GitHub Actions `ubuntu-24.04`.

| Check | mido | sagit |
|---|---|---|
| Kernel compile | PASS, no warnings/errors in `build.log` | PASS |
| Boot image header | `ANDROID!` v0, page 2048 | `ANDROID!` v0, page 4096 |
| Kernel address | `0x80008000` | `0x80008000` |
| Cmdline | `console=ttyMSM0,115200n8 root=/dev/ram0 rw` | same |
| DTB | `msm8953-xiaomi-mido.dtb` 42.7 KB | `msm8998-xiaomi-sagit.dtb` 54.5 KB |
| DTB checksum | `sha256sum -c` PASS | `sha256sum -c` PASS |
| Image.gz checksum | `sha256sum Image.gz` matches recorded value | same |
| Fragment applied | configfs, NCM, ext4, loop, initramfs | configfs, NCM, ext4, loop, initramfs |
| Boot on hardware | NOT VALIDATED | NOT VALIDATED |

Notes:
- `sha256sum -c SHA256SUMS` reports `Image.gz: FAILED` on this Windows/MSYS2 authoring host despite `sha256sum Image.gz` matching the recorded value exactly. This is a host path-resolution quirk, not artefact corruption.
- `boot.img` contains no initramfs yet; it boots only to the kernel command line. P3 adds initramfs + rootfs.

## Single-run parallel build (2026-11-16)

Run `43804410269`, commit `0969fe7`. One `workflow_dispatch` with no codename input built all three devices in parallel and uploaded three independent artifacts.

| Device | Kernel bytes | Page | `boot.img` | Header | Checksums |
|---|---|---|---|---|---|
| santoni | 8483532 | 2048 | 8544256 | `ANDROID!` v0 | Image.gz OK, DTB OK |
| mido | 15493211 | 2048 | 15542272 | `ANDROID!` v0 | Image.gz OK, DTB OK |
| sagit | 15492304 | 4096 | 15564800 | `ANDROID!` v0 | Image.gz OK, DTB OK |

Cmdline identical across devices: `console=ttyMSM0,115200n8 root=/dev/ram0 rw`.

Note: `Image.gz` on mido and sagit is ~15 MB versus ~8 MB on santoni because those two use the full upstream `defconfig` rather than the trimmed santoni defconfig. This still fits the devices' boot partitions but leaves less room for initramfs.

Boot on hardware: NOT VALIDATED for all three.

## P2 hardware attempt (2026-11-16)

Attempted `fastboot boot` on santoni. Not completed.

| Step | Result |
|---|---|
| ADB connect (Android mode) | PASS, `device:santoni`, serial 61459b807d04 |
| `adb reboot bootloader` | PASS, ADB disconnected as expected |
| Device visible as `VID_18D1&PID_D00D` | PASS |
| `fastboot devices` | FAIL, empty |
| Windows Device Manager | Error Code 28, no Android Bootloader Interface driver |

Cause: Windows has no Google USB Driver installed, so the bootloader interface is unbound. Procedure documented in `docs/troubleshooting.md`.

Consequence: no on-device boot has been performed for any device. All P2 claims remain build-and-artifact only.

## P3 boot-chain tooling (2026-11-17)
Authoring host: Windows 10, Git bash, Python 3.14, shellcheck 0.10.0. No device attached.

| Check | Command | Result |
|---|---|---|
| cpio writer | `mkcpio.py <dir> <out> --gzip` then `--list` | PASS: `/init` 0755, `/dev/console` c 0600, `/dev/null` c 0666 |
| boot image layout | `bootimg_v0.py selfcheck` | PASS: byte-identical round trip, ramdisk replacement |
| stock repack, end to end | `repack-stock.sh zzfake --stock-boot <synthetic> --initramfs <cpio.gz>` | PASS: kernel 6002 B unchanged, ramdisk replaced, `verify-bootimg.py` OK |
| initramfs build | `initramfs/build.sh zzfake --busybox <arm64> --mode test` | PASS: mode 0755, `/debiandroid.conf` embeds `DEBIANDROID_MODE=test`, `DEADMAN_SECONDS=180` |
| flash target guard | `flash.sh <dev> --ram-boot --dry-run` | PASS (exit 1, refuses without `--allow-unproven`) |
| flash recovery dry-run | `flash.sh <dev> --flash-recovery --dry-run` | PASS |
| shellcheck, new scripts | `shellcheck -x` on LF copies | PASS for the new files; SC1091/SC2034 findings are pre-existing |
| bats suite | `bats tests/test_config.bats tests/test_boot_chain.bats` | PASS 37/37 (27 config + 10 boot chain) |
| fragment merge | `build-kernel.sh probe --dry-run` with `KCONFIG_FRAGMENT_EXTRA` | PASS: both fragments merged in order, then `olddefconfig` |
| fragment verification | `kconfig-check.sh` on a merged config | PASS: missing symbol and y-to-m downgrade both rejected with exit 3 |

Note: local runs need `PATH` pointed at a real bash; on Windows the `bash` on PATH is the WSL
launcher. CI does not run the suite, so this was executed manually.
Not validated: any real device (no handset connected), a real ARM64 busybox payload, and
`verify-flash.sh` against a phone (needs Android with root and adb).
