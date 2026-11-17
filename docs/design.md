# Architecture and Implementation Plan

Companion document to `PRD.md`. Contents: boot chain, build pipeline, rootfs backends, installation modes, release flow, TWRP installer, phases, risk matrix.

## 1. Boot chain

Neither device has UEFI. The path used:

```mermaid
flowchart TD
    A[Power on] --> B[SBL1 primary bootloader]
    B --> C[aboot = Little Kernel]
    C --> D[fastboot mode]
    D -->|fastboot boot / flash| E[boot.img]
    E --> F[kernel Image.gz + DTB]
    F --> G[initramfs]
    G --> H[mount rootfs]
    H --> I[switch_root into Debian/Ubuntu]
```

Implication: no EFI stub, GRUB, or new firmware is required. A valid `boot.img` is enough.
`mainline` on msm8953/msm8940 also needs a second-stage bootloader: lk2nd. It is written by `fastboot flash lk2nd` (the stock bootloader is used once, in `fastboot boot lk2nd.img`, to get there), occupies the first 512 KiB of the `boot` partition, and then exposes `boot` at that offset. Images are taken from the pinned upstream release: 322 KiB for `msm8952` (santoni) and 360 KiB for `msm8953` (mido). lk2nd carries no network stack; it loads the kernel and nothing else.

Two kernel sources are supported, selected by `KERNEL_FLAVOR` in `devices/<codename>.env`:

| Flavor | Kernel | DTB | What changes | Risk |
|---|---|---|---|---|
| `mainline` (default) | built from `KERNEL_REPO` | built from source, appended to the kernel | everything | high: every artifact is unproven until a device boots it |
| `stock-repack` | the vendor's, byte for byte | the vendor's, byte for byte | only the initramfs | low: the bootloader already accepts these bytes |

`mainline` on MSM8953/MSM8940 is only proven with a second-stage bootloader: lk2nd has
targets for both (msm8953 for mido, msm8952 with an `msm8940-xiaomi-santoni` DTS for
santoni) and is what KlipperPhonesLinux and postmarketOS use. Stock aboot alone has not
been shown to load a freshly built modern kernel on either SoC. `devices/*.env` gains a
`BOOTLOADER=aboot|lk2nd` key; `aboot` stays the default until lk2nd is verified on
hardware. lk2nd has no msm8998 or Exynos target, so sagit and dreamlte are out of the
near-term mainline matrix.

`stock-repack` exists because a failed mainline attempt on santoni (2026-11-16) left the
device in EDL. It is the same approach as a51-server-os: keep what the bootloader
validates, replace what it does not look at. Xiaomi's published source does not always
contain the device tree (`santoni-n-oss` has no `msm8937-santoni.dts`), so building a
stock kernel from source is not a reliable substitute for the vendor image.


## 2. Kernel build pipeline

1. Fetch the source recorded in `devices/<codename>.env` (kernel.org mainline or a community fork).
2. Cross-compile with `aarch64-linux-gnu-gcc`, targeting `Image.gz` + DTB.
3. Assemble `boot.img` with `mkbootimg`: page size (4096 for UFS, 2048 for eMMC), cmdline, initramfs.
4. Store artifacts in `out/<codename>/` together with checksums.

**Container prerequisites.** `kernel/config/containers.config` is merged after the
per-device fragment (`KCONFIG_FRAGMENT_EXTRA`) and enables namespaces, cgroups
(`PIDS`, `DEVICE`, `FREEZER`, `MEMCG`), `OVERLAY_FS`, `VETH`, `BRIDGE` and NAT.
`scripts/lib/kconfig-check.sh` then proves the options survived the merge; Kconfig drops
a symbol whose dependencies are unmet and `merge_config.sh` only warns. The
`stock-repack` flavor cannot run containers: vendor kernels lack the cgroup controllers.

**Sources used**
- santoni: `MrArtemSid/linux-msm89x7` branch `santoni`, pinned to `f47205ee`. Provides `msm8940-xiaomi-santoni.dts` and `santoni_openwrt_defconfig`. MSM8940 is the Redmi 4X variant of MSM8937. Out-of-tree panel drivers exist in `drm/panel/msm89x7-generated/` (`panel-xiaomi-santoni-hx8394f-boe`, `-ili9881c-ebbg`, `-ili9881c-ebbgdjn`); identify your panel before enabling one.
- sagit: the MSM8998 community fork that explicitly supports the Xiaomi Mi6.
- mido: mainline MSM8953 (base DT since 5.18) or the postmarketOS `qcom-msm8953` kernel as a ready reference.

## 3. initramfs and rootfs
`initramfs/init` is a POSIX shell script run by a static ARM64 busybox:

1. mount `/proc`, `/sys`, `/dev`, `/dev/pts`;
2. set `hung_task_panic = 0` (vendor kernels panic when a task blocks and Android's
   daemons are gone);
3. clear a stale `boot-recovery` message in `misc`, otherwise every reboot returns to
   the recovery loop;
4. bring up a USB gadget with `acm` and `ncm`, retrying for 25 s because the UDC may
   only appear after the cable is detected; this is the rescue console;
5. find the root filesystem: a partition named `debiandroid` (dedicated mode) or
   `<userdata>/debian-server/rootfs` (dual-boot mode);
6. in test mode, arm a dead-man timer of `DEADMAN_SECONDS` (default 300): if the system
   does not write `/run/debiandroid/healthy-<boot_id>`, the device reboots. The stamp is in
   `/run` because that tmpfs is visible after `switch_root`; `rootfs/overlay` installs the
   `debiandroid-health` unit that writes it, ordered after `sshd`;
7. `switch_root` into the rootfs and exec `runit` (or `/sbin/init`).

Build-time settings live in `/debiandroid.conf` inside the archive. Any failure drops to
a shell on the USB serial console instead of hanging silently.

`scripts/initramfs/build.sh <codename> --mode prod|test` assembles the archive with
`scripts/lib/mkcpio.py` (a cpio newc writer in Python, so no `cpio` binary is needed on
the host). Rootfs backend: `debian.sh` (`debootstrap --arch=arm64` plus base server packages).
Ubuntu and prebuilt images are deferred; supporting one distribution end to end is
cheaper than three half-verified ones, and `fetch.sh` rejects their backend names so no
release advertises an asset that is not built.

## 4. Installation modes

| Mode | Mechanism | Risk |
|---|---|---|
| dual-boot | Directory `/data/debian-server/rootfs` on the data partition; no loop device is needed because Android is not running | Android update can overwrite boot; limited space |
| dedicated | Dedicated ext4 partition, Android erased; kernel in the boot partition | Destructive, no return without a restore |

## 4b. Kiosk display (opt-in)
With `KIOSK=0` (default) nothing is drawn on the panel: the device boots to a blank
screen and is managed entirely over SSH through `usb0` or `wlan0`.

With `KIOSK=1`, `cage` (a single-window Wayland compositor over DRM/KMS) and
`epiphany-browser` are added to the image and `debiandroid-kiosk.service` is enabled.
The unit reads `KIOSK_URL` from `/etc/debiandroid/kiosk.conf`, default
`http://127.0.0.1:8080/`, so the device behaves like an OpenWrt panel: boot, then show
one page. Adreno is driven by freedreno in the mainline kernel; no proprietary userspace
is involved. The unit runs as root until a dedicated account is provisioned.

## 5. Networking

- santoni: `usb0` `g_ether` gadget via configfs; Wi-Fi only if the mainline kernel exposes it.
- mido: `wlan0` via `systemd-networkd` + `wpa_supplicant` (WLAN mainline 6.4).
- sagit: `usb0` `g_ether` gadget via configfs; the host gets DHCP over RNDIS.
- Fallback: USB OTG (On-The-Go) Ethernet adapter on all devices.

## 6. Implementation phases

| Phase | Content | Done criteria |
|---|---|---|
| P0 | Documents (PRD, README, AGENTS, design) | Four documents exist and are consistent |
| P1 | Repo skeleton: `devices/*.env.example`, preflight, `--dry-run` | `--dry-run` works for both codenames |
| P2 (done) | Build pipeline, verification, `stock-repack`, initramfs | 37/37 tests; artifacts verified; no device boot |
| P3 | santoni on the vendor kernel: backup, repack, recovery flash, read-back | `verify-flash.sh` match; SSH or rescue console |
| P4 | lk2nd + mainline on santoni, then mido | kernel 6.x boots; SSH over `usb0` |
| P5 | containers, Ubuntu/prebuilt backends, dedicated mode | `docker run hello-world`; all backends and modes |
| P6 | sagit on aboot mainline; dreamlte out of scope | SSH on sagit or documented blocker |
| P7 | TWRP installer, release workflow, CI test job | `v0.1.0` assets; CI green |

## 7. Risk matrix

| Risk | Impact | Mitigation |
|---|---|---|
| Kernel has no device DTB | Boot fails | Test with `fastboot boot` first; keep the old kernel |
| santoni/sagit Wi-Fi not in mainline | No network | `usb0` gadget plus OTG adapter |
| DVFS (Dynamic Voltage and Frequency Scaling) not working | Rapid battery drain | Power-saving script, operational notes |
| Modem dead | Not a phone | Documented limitation; server target |
| Android update overwrites boot | Dual-boot lost | Documented restore procedure |

## 8. Locked decisions

1. No UEFI: direct fastboot path.
2. Initial devices: santoni (hardware on hand), then mido and sagit.
3. One rootfs backend: Debian. Ubuntu and prebuilt images stay deferred until the Debian path is verified on hardware.
4. Both dual-boot and dedicated modes are provided and chosen at install time.

## 9. Artifact distribution and CI

Trigger: `v*` tags only. Local builds remain supported for development (`--dry-run`, `--ram-boot`).

```mermaid
flowchart LR
    T[tag v*] --> W[workflow release.yml]
    W --> K1[build boot-mido.img]
    W --> K2[build boot-sagit.img]
    W --> R1[rootfs debian snapshot/stable]
    K1 --> Z[zip installer + SHA256SUMS]
    K2 --> Z
    R1 --> Z
    Z --> G[GitHub Release]
    G --> F[fetch.sh --verify]
```

Technical notes:
- x86_64 runners with aarch64 cross-compilation.
- The `snapshot` channel pins `snapshot.debian.org` to a fixed timestamp; `stable` uses current mirrors.
- Rootfs is not per device: one ARM64 rootfs serves mido and sagit.

## 10. TWRP zip installer

Zip layout and `update-binary` logic are specified in PRD section 20. Architecture points:

- `update-binary` is POSIX shell, not Bash, so it is safe inside TWRP.
- Device detection: read `ro.product.device` and match it against `config/device.env`.
- `dual-boot`: extract into `/data/debian-server/rootfs`; the initramfs mounts userdata (f2fs or ext4) and uses that directory directly. No loop device, because Android is not running to hold `/data`.
- `dedicated`: `mkfs.ext4` on the partition named `debiandroid`, then write `boot-<codename>.img`; the initramfs mounts that partition as the root.
- Idempotent: extracting over an existing rootfs updates it instead of recreating it.

TWRP risks:
- Older TWRP cannot decrypt `/data` (blocks dual-boot).
- TWRP `/tmp` is small; extract progressively rather than from one blob.

## 11. Verification commands

```bash
shellcheck scripts/**/*.sh
bats tests/
./scripts/flash.sh mido --dry-run
./scripts/fetch.sh --backend debian --channel stable --verify --dry-run
```

On-device after install:

```bash
findmnt / && ip -br a && systemctl status ssh
```

## 12. Source pinning and partition safety

Two guards adopted from a comparable hardware bring-up project (Xiaomi Mi 11 Pro native UEFI port). Neither depends on UEFI.

**Source pinning.** `devices/<codename>.env` records `KERNEL_REPO`, `KERNEL_REF`, `KERNEL_COMMIT` (40-hex pin) and `KERNEL_ARCHIVE_SHA256` (optional tarball checksum). `scripts/lib/kernel-pin.sh` checks the pin against the remote without cloning; `scripts/build-kernel.sh` then compares `HEAD` to `KERNEL_COMMIT` and aborts on mismatch. This keeps builds reproducible across machines and months.

**Partition identity guard.** Before any `mount` or `mkfs`, the installer confirms:

1. the block device `PARTNAME` matches `ROOT_PARTNAME_EXPECTED`, and
2. the target filesystem contains `ROOT_MARKER` (default `/etc/debiandroid-root`) when the mode is dual-boot or reinstalling.

Dedicated mode additionally requires an explicit `--format` flag; a missing flag aborts instead of guessing. `scripts/lib/partition-guard.sh` implements both checks and is reused by `install.sh` and the TWRP `update-binary`.

## 13. CI build pipeline

Two workflows, both Ubuntu 24.04 runners (x86_64) with an AArch64 cross toolchain.

| Workflow | Trigger | Job |
|---|---|---|
| `build-kernel.yml` | `workflow_dispatch` (choose codename) or `v*` tag | preflight, pin verify, kernel build, `boot.img`, checksums, artifact upload |
| `release.yml` | `v*` tag | matrix over codenames, build, then publish `boot-<codename>.img` + `SHA256SUMS` to the Release |

Device-specific kernel configuration is expressed as a base defconfig plus a Kconfig fragment in `kernel/config/<codename>-server.config`, merged with `scripts/kconfig/merge_config.sh`. For santoni the base is `santoni_openwrt_defconfig` from the pinned community tree, and the fragment adds the missing server essentials: USB configfs gadget (NCM/RNDIS/ECM), ext4, loop devices, initramfs support, netfilter.

The runner compiles only kernel and boot image. Rootfs tarballs are built separately and published as release assets; they are not part of the kernel job.

Local dry runs (`--dry-run`) exercise the same code paths without a toolchain, so the workflow logic can be checked on any host.
