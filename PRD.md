# PRD: debiandroid

**Product Requirement Document**
Version 0.1 (draft) | 2026-11-16 | Status: Draft

## 1. Overview

debiandroid is a tooling repository (scripts and documentation) for installing a headless **Debian/Ubuntu server** on top of a **mainline ARM64 Linux kernel** on Android phones that never shipped UEFI (Unified Extensible Firmware Interface):

- **Xiaomi Mi6 (sagit)**: Snapdragon 835 (MSM8998), UFS (Universal Flash Storage) 64/128 GB, RAM (Random Access Memory) 4/6 GB.
- **Redmi Note 4X (mido)**: Snapdragon 625 (MSM8953), eMMC (embedded MultiMediaCard) 32/64 GB, RAM 3/4 GB.
- **Redmi 4X (santoni)**: Snapdragon 435 (MSM8937), eMMC 16/32 GB, RAM 2/3 GB.

Intended use: pocket servers (SSH access, server packages, light containers). Not a desktop, not a daily-driver phone.

## 2. Problem

1. Old phones pile up unused while their CPU, RAM, and storage exceed what a small server needs.
2. Existing phone Linux distributions (postmarketOS, Droidian) are desktop-oriented: they need a display, a compositor, and large RAM budgets.
3. These phones have no UEFI firmware, so standard boot paths (EFI stub, GRUB) are unavailable without porting new firmware.
4. Installation documentation is scattered and non-idempotent: every attempt requires different manual steps.

## 3. Product Goals

- **G1**: Boot an ARM64 mainline Linux kernel directly through fastboot, without UEFI.
- **G2**: Install a selectable server root filesystem: Debian, Ubuntu, or a prebuilt image.
- **G3**: Provide two installation modes: dual-boot (Android preserved) and dedicated (all storage for the server).
- **G4**: Reproducible: one command per stage, per-device configuration in a single file.

## 4. Users and Actors

| Actor | Need |
|---|---|
| Operator | Device owner, comfortable with the CLI (Command Line Interface), bootloader already unlocked, wants a stable server |
| Contributor | Adds a new device or distro backend without touching the core scripts |

## 5. Platform and Devices

- Architecture: ARM64 (aarch64), physical devices.
- Build host: Linux x86_64 (recommended) or WSL2 (Windows Subsystem for Linux).
- Boot: fastboot on top of aboot (Little Kernel, LK). No UEFI.
- Initial devices: **santoni** (hardware on hand), then **mido** and **sagit**.

## 6. Scope

**In scope**
- Kernel and boot image support for santoni, mido, and sagit.
- Build mainline/community kernels; assemble `boot.img` (kernel + DTB (Device Tree Blob) + initramfs).
- `stock-repack` path: keep the vendor kernel and DTB byte for byte and replace only the initramfs. This is the first hardware milestone. Mainline follows on msm8953/msm8940 behind a second-stage bootloader (lk2nd), which has no msm8998 target.
- Rootfs backends: Debian (debootstrap), Ubuntu (ubuntu-base), prebuilt image (postmarketOS).
- Installation modes: dual-boot and dedicated.
- TWRP (Team Win Recovery Project) zip installer, equivalent to flashing a custom ROM, plus a fastboot path.
- GitHub Actions CI on `v*` tags: `boot.img`, rootfs per channel, `SHA256SUMS`, installer zip.
- Minimal on-device verification: boot, network, SSH.
- Documentation: PRD.md, README.md, AGENTS.md, docs/design.md, docs/validation.md.

**Out of scope (non-goals)**
- Desktop GUI, display manager, GPU acceleration.
- Modem/cellular (SMS, calls, data), camera, full audio.
- dreamlte (Exynos 8895) device.
- Porting UEFI (edk2) as a prerequisite.

**Future considerations**
- Support for dreamlte and optional edk2-msm8998 UEFI on sagit.
- Pre-flashed integrated images per release.
- Interactive CLI/panel for distro selection.

## 7. Delivery Level

Production-ready at the **tooling** level, not the operating-system level:
- Idempotent scripts that stop before destructive steps without confirmation.
- Complete preflight checks (fastboot detected, bootloader unlocked, sufficient capacity).
- Documentation and the device status matrix kept in sync with the code.

## 8. Actors and Access Control

There is no application authentication. Access control is physical and operational:

- The bootloader must be unlocked (Mi Unlock for sagit, `fastboot oem unlock` for mido).
- Destructive scripts require explicit confirmation (there is no `--yes`; confirmation is interactive).
- SSH access uses public keys; root SSH login is disabled.

## 9. Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| REQ-KRN-001 | Build an ARM64 kernel per codename from the recorded source | P0 |
| REQ-KRN-002 | Produce `Image.gz`, DTB, and checksums in `out/<codename>/` | P0 |
| REQ-KRN-003 | Verify the recorded source commit and checksum before building | P0 |
| REQ-BOOT-001 | Assemble `boot.img` with the correct page size, cmdline, and initramfs | P0 |
| REQ-BOOT-002 | Test images on the recovery partition first; `fastboot boot` of an unproven image requires an explicit override | P0 |
| REQ-BOOT-003 | `stock-repack` kernel flavor: keep the vendor kernel and DTB, replace only the initramfs | P0 |
| REQ-BOOT-004 | Refuse to produce a boot image with no initramfs | P0 |
| REQ-BOOT-005 | Verify a written partition by reading it back and comparing SHA-256 | P0 |
| REQ-BOOT-006 | Save the stock boot and recovery images before any write | P0 |
| REQ-BOOT-007 | Test-mode initramfs arms a dead-man timer and reboots instead of hanging | P1 |
| REQ-SRV-001 | Mainline kernels enable the container prerequisites (namespaces, cgroups, overlayfs, veth, NAT); verified after the fragment merge | P1 |
| REQ-ROOT-001 | Debian rootfs backend via debootstrap | P0 |
| REQ-ROOT-002 | Ubuntu base rootfs backend | P1 |
| REQ-ROOT-003 | Prebuilt image backend (postmarketOS) plus server packages | P1 |
| REQ-INST-001 | Dual-boot mode: rootfs in a directory on the data partition (`/data/debian-server/rootfs`), no loop device | P0 |
| REQ-INST-002 | Dedicated mode: dedicated ext4 root partition | P1 |
| REQ-INST-003 | TWRP zip installer: flashed from TWRP, equivalent to a custom ROM | P0 |
| REQ-INST-004 | Verify partition identity (`PARTNAME`/UUID) and root marker before mount or mkfs | P0 |
| REQ-REL-001 | GitHub Actions CI builds artifacts only on `v*` tags | P0 |
| REQ-REL-002 | Release assets: `boot-<codename>.img`, rootfs per channel, `SHA256SUMS` | P0 |
| REQ-REL-003 | `fetch.sh` downloads and verifies checksums before use | P0 |
| REQ-REL-004 | Two rootfs channels: `snapshot` (reproducible) and `stable` (latest) | P1 |
| REQ-NET-001 | mido networking via `wlan0` | P0 |
| REQ-NET-002 | sagit networking via `usb0` gadget | P0 |
| REQ-NET-003 | santoni networking via `usb0` gadget, Wi-Fi if available | P0 |
| REQ-SEC-001 | Preflight check: device detected, bootloader unlocked, capacity sufficient | P0 |
| REQ-DOC-001 | PRD, README, AGENTS, and design stay in sync with the code | P0 |
| REQ-TST-001 | `shellcheck` and `bats` green | P1 |

## 10. Traceability

| Requirement | Implementation | Verification |
|---|---|---|
| REQ-KRN-001/002 | `scripts/build-kernel.sh`, `scripts/lib/kconfig-check.sh` | artifact check in `out/`, fragment options present after the merge |
| REQ-BOOT-001/002 | `scripts/make-bootimg.sh`, `scripts/flash.sh` | boot log via screen/USB, `--dry-run`, refusal of `--ram-boot` without `--allow-unproven` |
| REQ-BOOT-003/004 | `scripts/repack-stock.sh`, `scripts/lib/bootimg_v0.py` | byte-identical round trip; `verify-bootimg.py` rejects a missing ramdisk |
| REQ-BOOT-005/006 | `scripts/verify-flash.sh`, `scripts/backup-stock.sh` | partition SHA-256 compared after write; stock image saved before any write |
| REQ-BOOT-007 | `initramfs/init`, `rootfs/overlay/etc/systemd/system/debiandroid-health.service` | the test-mode timer is satisfied only by the health stamp |
| REQ-ROOT-001/002/003 | `scripts/rootfs/*.sh` | chroot mount, package check, SSH login |
| REQ-INST-001/002 | `scripts/install.sh` | reboot, `/proc/cmdline`, `df -h /` |
| REQ-KRN-003 | `scripts/build-kernel.sh` preflight, `devices/*.env` | negative test: wrong commit or checksum aborts build |
| REQ-INST-004 | `scripts/lib/partition-guard.sh`, `installer/update-binary` | negative test: wrong PARTNAME or missing marker aborts |
| REQ-REL-001/002 | `.github/workflows/release.yml` | tag `v0.1.0` produces all assets |
| REQ-REL-003 | `scripts/fetch.sh --verify` | negative test: wrong checksum rejected |
| REQ-REL-004 | workflow matrix, `fetch.sh --channel` | both channels downloaded and installed |
| REQ-NET-001/002/003 | `scripts/install.sh`, networkd units | `ip a`, ping gateway, SSH |
| REQ-SEC-001 | `scripts/lib/preflight.sh` | negative tests: no device, low capacity |
| REQ-TST-001 | `tests/` | `shellcheck`, `bats` |

## 11. Primary Workflow

```text
Operator boots the device into fastboot
|-> preflight: detect device, check unlock, check capacity
|-> backup the stock boot and recovery partitions first
|-> build the initramfs, then either repack the stock image or build the mainline one
|-> flash the recovery partition (test image), never the boot partition on the first attempt
|-> read the partition back and compare SHA-256
|-> choose rootfs backend and installation mode
|-> install rootfs
|-> reboot into the test image; the dead-man timer reverts to Android if nothing reports healthy
|-> verify: initramfs -> rootfs -> network -> SSH
```

Failure path: preflight fails -> stop before any destructive step; the test image fails -> the dead-man timer reboots to Android, and the images saved in step 1 are the restore source.

## 12. Architecture Summary

Details in `docs/design.md`. Summary:

- `devices/<codename>.env`: single source of per-device parameters.
- `scripts/build-kernel.sh`: kernel cross-compile.
- `scripts/make-bootimg.sh`: `boot.img` assembly.
- `scripts/rootfs/*.sh`: three rootfs backends.
- `scripts/install.sh`: dual-boot/dedicated orchestration.
- `scripts/flash.sh`: fastboot with confirmation.

## 13. Technology

| Component | Choice | Reason |
|---|---|---|
| Scripting | Bash 5.3 | Available on the host, no extra dependency |
| Cross compiler | `aarch64-linux-gnu-gcc` | Standard ARM64 build |
| Boot image | `mkbootimg` + `dtbtool` | Android boot image format |
| Rootfs | `debootstrap`, `ubuntu-base`, tar images | No emulator required |
| Lint/test | `shellcheck`, `bats-core` | Lightweight, no heavy framework |
| Transfer | `fastboot` | Official device boot path |

## 14. Data and Configuration

No database. Configuration is text files.

`devices/<codename>.env`:

```text
KERNEL_FLAVOR=mainline|stock-repack   # stock-repack builds no kernel at all
KERNEL_REPO=
KERNEL_REF=
KERNEL_COMMIT=
KERNEL_ARCHIVE_SHA256=
DEFCONFIG=
KCONFIG_FRAGMENT=          # per-device fragment
KCONFIG_FRAGMENT_EXTRA=    # optional shared fragments, merged after it
DTB_NAME=
DTB_VARIANT=
CMDLINE=
BOOTIMG_PAGESIZE=          # 4096 sagit (UFS), 2048 mido and santoni (eMMC)
BOOTIMG_BASE=
NET_MODE=wlan0|usb0
ROOT_PARTNAME_EXPECTED=
ROOT_MARKER=/etc/debiandroid-root
MIN_FREE_GB=
```

Real `.env` files are never committed; examples ship as `.env.example`.

## 15. Security

- No secrets in the repository. SSH keys are generated on the device or copied by the operator.
- `PermitRootLogin no` and `PasswordAuthentication no` in the default rootfs.
- Kernel and boot image checksums are verified before flashing.
- Scripts refuse to run when `fastboot devices` is empty.
- Explicit warning before any partition is destroyed (dedicated mode).

## 16. Validation and Error Handling

| Condition | Behavior |
|---|---|
| Unknown codename | Exit 2, list valid codenames |
| Device not detected by fastboot | Exit 3, instructions to enter fastboot |
| Bootloader locked | Exit 3, unlock instructions |
| Insufficient space | Exit 3, show required vs available |
| Confirmation declined | Exit 0, no changes |
| Kernel build failure | Exit 1, save `out/<codename>/build.log` |

## 17. Edge Cases

- Kernel does not provide a device DTB: detect at build time, stop with a clear message.
- Dual-boot with nearly full data partition: `MIN_FREE_GB` enforced.
- Android update overwrites the boot partition: restore procedure documented.
- `usb0` does not appear: fall back to a USB OTG (On-The-Go) Ethernet adapter; documented.
- Power loss during flashing: verify checksums and re-flash the boot image.
- Slow or failing eMMC: read/write verification before installation.

## 18. Non-Functional Requirements

- Boot target: mido under 60 seconds, sagit under 45 seconds (until SSH is ready).
- Minimal rootfs size: 800 MB or less installed.
- Scripts are idempotent: re-running `install.sh` does not duplicate data.
- Logs are re-readable and contain no sensitive data.
- Usable on WSL2 with a full `--dry-run`.

## 19. Testing and Verification

| Level | Coverage |
|---|---|
| Static | `shellcheck` across all scripts |
| Unit | `bats` for argument parsing, `--dry-run`, `.env` resolution |
| Host integration | kernel build and `boot.img` assembly produce valid artifacts |
| On-device | recovery-partition flash, read-back comparison, `dmesg`, `ip a`, `ssh` checks |

P0 verification matrix:

| Requirement | Proof |
|---|---|
| REQ-KRN-001 | kernel artifact exists, checksum matches |
| REQ-BOOT-002/003 | boot log appears, initramfs runs, the vendor kernel is unchanged |
| REQ-INST-001 | `findmnt /` points at `/data/debian-server/rootfs`, no loop device |
| REQ-INST-003 | zip flashes in TWRP, reboot, SSH works |
| REQ-KRN-003 | wrong commit or checksum aborts before compile |
| REQ-INST-004 | wrong PARTNAME or missing marker aborts before mount |
| REQ-BOOT-005 | `verify-flash.sh` matches the image SHA-256 after a write |
| REQ-NET-001 | `ip -br a` shows `wlan0` with an IP |
| REQ-NET-002 | `ip -br a` shows `usb0` with an IP |
| REQ-NET-003 | `ip -br a` shows `usb0` or `wlan0` with an IP on santoni |
| REQ-SEC-001 | preflight negative tests |

## 20. TWRP Installation (zip installer)

The primary path for operators without a Linux host. Designed to feel like flashing a custom ROM.

**Zip layout** (`installer-debiandroid-<tag>.zip`):

```text
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
tools/busybox
tools/zstd
payload/rootfs.tar.zst
payload/boot-<codename>.img
config/device.env
```

**`update-binary` behavior** (executed by TWRP):

1. Read `config/device.env`, match the device codename, reject on mismatch.
2. Ask for the mode: `dual-boot` or `dedicated` (volume keys, shown on the TWRP screen).
3. `dual-boot`: extract the tarball into `/data/debian-server/rootfs` (plain directory, no loop device), then write `boot-<codename>.img` with the initramfs.
4. `dedicated`: `mkfs.ext4` the target partition, extract, write `boot-<codename>.img`.
5. Verify payload checksums before extracting.
6. Never touch any partition when verification fails.

**Constraints that must be handled:**

- TWRP does not always ship a complete `zstd`/`tar`: bundle `busybox` and a static `zstd`.
- `/data` encryption: older TWRP cannot decrypt it. `dedicated` mode is safer on older TWRP.
- Large zip (roughly 400 MB): use `zstd -3` on the payload so flashing is not slow.
- `update-binary` must be idempotent: re-running must not duplicate the rootfs.

## 21. Distribution, Releases, and CI

**Distribution model.** Artifacts are built in CI, not on the operator host. The operator only downloads and verifies.

GitHub Actions CI:

- Trigger: `v*` tags and manual `workflow_dispatch` only. No nightly or scheduled runs.
- Matrix: `backend` (debian, ubuntu) x `channel` (snapshot, stable) for rootfs; `codename` (mido, sagit) for `boot.img`.
- x86_64 runners with `aarch64-linux-gnu-gcc` cross-compilation; rootfs from official base images plus `qemu-user-static`, with the snapshot channel pinned via `snapshot.debian.org`.

Assets per release:

```text
boot-mido.img
boot-sagit.img
rootfs-debian-arm64-snapshot-<tag>.tar.zst
rootfs-debian-arm64-stable-<tag>.tar.zst
rootfs-ubuntu-arm64-snapshot-<tag>.tar.zst
rootfs-ubuntu-arm64-stable-<tag>.tar.zst
installer-debiandroid-<tag>.zip
SHA256SUMS
```

Rules:

1. One tag equals one consistent set (boot images and rootfs from the same tag).
2. `SHA256SUMS` pins every asset; `fetch.sh --verify` rejects mismatches.
3. Rootfs is device-independent: one ARM64 rootfs serves mido and sagit. Only `boot.img` differs (UFS 4096 vs eMMC 2048 page size, cmdline, DTB).
4. The `snapshot` channel is reproducible; `stable` uses the latest packages at release time.
5. Compress with `zstd -19`; use `zstd -3` when transferring over USB 2.0 ADB.

## 22. Environment Prerequisites

- Host: Linux x86_64 or WSL2. Native Windows without WSL2 is unsupported.
- Host packages: `git make gcc-aarch64-linux-gnu mkbootimg android-sdk-platform-tools debootstrap shellcheck bats`.
- Device: unlocked bootloader, data-capable USB cable, host recognizes `fastboot`.

Environment variables (no secret values):

```text
DEBIANDROID_OUT=./out
DEBIANDROID_CACHE=./.cache
FASTBOOT_BIN=fastboot
```

## 23. Development Phases

| Phase | Work | Completion criteria |
|---|---|---|
| P0 | Documentation: PRD, README, AGENTS, design | Consistent and cross-referenced |
| P1 | Repo skeleton, `devices/*.env.example`, preflight, `--dry-run` | `--dry-run` exits 0 for santoni, mido, and sagit |
| P2 (done) | Build pipeline, structural verification, `stock-repack` flavor, initramfs with rescue console and dead-man timer | 37/37 tests green; artifacts verified structurally; no device boot yet |
| P3 | Hardware proof on santoni with the vendor kernel: backup, initramfs, repack, recovery flash, read-back | `verify-flash.sh` reports a match; SSH or the rescue console answers |
| P4 | lk2nd + mainline on santoni, then mido (lk2nd has targets for both) | kernel 6.x boots; `findmnt /` shows the expected root; SSH over `usb0` |
| P5 | Containers on the mainline build; Ubuntu and prebuilt backends; dedicated mode | `docker run --rm hello-world`; all backends and both modes pass |
| P6 | sagit on aboot mainline (lk2nd has no msm8998 target); dreamlte stays out of scope | SSH on sagit, or a documented blocker |
| P7 | TWRP zip installer, `v*` release workflow, CI test job | tag `v0.1.0` produces 9 assets + `SHA256SUMS`; CI runs shellcheck and bats |

## 24. Acceptance Criteria and Definition of Done

- santoni boots the vendor kernel with the debiandroid initramfs (`stock-repack`); then mido and santoni boot mainline behind lk2nd; sagit follows once its boot path is settled.
- Debian/Ubuntu server installs and is reachable over SSH with no desktop.
- Dual-boot preserves Android; dedicated mode works and is verified.
- The TWRP zip installer installs from TWRP without a Linux host, in both modes.
- A `v*` tag produces every release asset plus `SHA256SUMS`, and `fetch.sh --verify` rejects a bad checksum.
- All three rootfs backends run at least on one device.
- Preflight prevents destructive steps when conditions are unsafe.
- `shellcheck` and `bats` are green; the P0 verification matrix passes.
- Documentation is accurate against the code.
- Limits (no modem, camera, audio, DVFS) are documented.

## 25. Assumptions and Open Decisions

**Assumptions**
1. Both devices can be unlocked and flashed via fastboot.
2. The build host is Linux/WSL2; native Windows is unsupported.
3. Kernel sources follow the community repositories recorded in `devices/*.env`; exact versions are updated during implementation.
4. sagit uses `usb0` because Wi-Fi is not in mainline yet; mido uses `wlan0`.
5. The user accepts the result as a server, not a phone.

**Open decisions**
- Whether dedicated mode ships an Android restore script (requires a partition dump).
- Whether the default rootfs installs Docker/Podman (increases size).

## 26. Licensing

See `LICENSES/README.md` for the authoritative map.

| Path | License |
|---|---|
| `scripts/`, `installer/`, `tests/`, `tools/` | MIT |
| `kernel/patches/`, `kernel/config/`, `kernel/devicetree/` | GPL-2.0-only |
| `docs/`, `PRD.md`, `README.md`, `AGENTS.md` | CC-BY-4.0 |

Every source file carries an SPDX identifier. Rootfs artifacts keep the licenses of their upstream distributions and are not relicensed by this repository.

## 27. Glossary

- **UEFI**: Unified Extensible Firmware Interface; not present on these devices.
- **SoC**: System on Chip.
- **DTB**: Device Tree Blob, the hardware description passed to the kernel.
- **UFS**: Universal Flash Storage.
- **eMMC**: embedded MultiMediaCard.
- **LK**: Little Kernel, the Android bootloader (aboot).
- **fastboot**: bootloader mode for flashing or booting images over USB.
- **initramfs**: temporary early filesystem before the real rootfs.
- **rootfs**: root filesystem of the operating system.
- **gadget**: USB device mode (e.g., the `g_ether` Ethernet gadget).
- **DVFS**: Dynamic Voltage and Frequency Scaling.
