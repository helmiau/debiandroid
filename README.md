# debiandroid

Install a headless **Debian/Ubuntu server** on top of a **mainline ARM64 Linux kernel** on Android phones that never shipped UEFI.

Built for pocket servers: SSH, server packages, light containers. Not a desktop.

## Supported devices

| Device | Codename | SoC (System on Chip) | RAM | Storage | Network path |
|---|---|---|---|---|---|
| Redmi 4X | santoni | Snapdragon 435 (MSM8937) | 2/3 GB | eMMC | USB gadget (`usb0`) |
| Xiaomi Mi6 | sagit | Snapdragon 835 (MSM8998) | 4/6 GB | UFS | USB gadget (`usb0`) |
| Redmi Note 4X | mido | Snapdragon 625 (MSM8953) | 3/4 GB | eMMC | Wi-Fi (mainline 6.4) |

Mainline status: mido has the best networking support (WLAN/Bluetooth 6.4); sagit wins on UFS storage and CPU performance; santoni has the least mature mainline support and is the hardware currently on hand.

## Prerequisites

- Device bootloader unlocked; `fastboot` can detect the device.
- Linux x86_64 build host (or WSL2) with: `bash`, `git`, `make`, `aarch64-linux-gnu-gcc`, `mkbootimg`, `fastboot`, `debootstrap`, `shellcheck`.
- At least 8 GB free storage for dedicated mode, or 4 GB free on the data partition for dual-boot.

## Quick start (santoni)

```bash
# 1. Prepare the device configuration
cp devices/santoni.env.example devices/santoni.env

# 2. Save the stock boot and recovery images (the only reliable restore path)
./scripts/backup-stock.sh santoni

# 3. Build the initramfs (needs a static ARM64 busybox)
./scripts/initramfs/build.sh santoni --mode test

# 4a. Safe path: keep the vendor kernel, replace only the initramfs
./scripts/repack-stock.sh santoni --stock-boot out/santoni/stock/boot-stock-santoni.img

# 4b. Mainline path: build kernel and boot image (structural validator runs)
./scripts/build-kernel.sh santoni
./scripts/make-bootimg.sh santoni

# 5. Test from the recovery partition, then prove the write by reading it back
./scripts/flash.sh santoni --flash-recovery --image out/santoni/boot-santoni-stock-test.img
./scripts/verify-flash.sh santoni recovery out/santoni/boot-santoni-stock-test.img

# 6. Install the server rootfs (choose a backend)
./scripts/rootfs/debian.sh santoni --mode dual-boot
./scripts/install.sh santoni --mode dual-boot
```

After reboot, connect over SSH:

```bash
ssh debian@<device-ip>
```

## Installation modes

| Mode | Effect | Android safe |
|---|---|---|
| `dual-boot` | Rootfs in `/data/debian-server/rootfs` on the data partition; Android untouched | Yes |
| `dedicated` | Dedicated root partition; all storage used by the server | No (Android is erased) |

## Choose a rootfs backend

```bash
./scripts/rootfs/debian.sh   # Debian arm64, debootstrap
./scripts/rootfs/ubuntu.sh   # Ubuntu base arm64
./scripts/rootfs/prebuilt.sh # prebuilt image (e.g. postmarketOS) plus server packages
```

## Install via TWRP (no Linux host)

Artifacts ship on GitHub Releases; download the installer and flash it like a custom ROM.

1. Download `installer-debiandroid-<tag>.zip` from the Release page.
2. Verify: `sha256sum -c SHA256SUMS`.
3. Boot into TWRP, choose **Install**, select the zip, confirm.
4. Pick the mode on the TWRP screen: `dual-boot` (Android preserved) or `dedicated` (Android erased).
5. Reboot, then connect over SSH.

On a Linux host, the alternative path:

```bash
./scripts/fetch.sh --backend debian --channel stable --verify
./scripts/install.sh santoni --mode dual-boot
```

## Releases and CI

CI runs only on `v*` tags. Assets per release:

```text
boot-mido.img  boot-sagit.img
rootfs-{debian,ubuntu}-arm64-{snapshot,stable}-<tag>.tar.zst
installer-debiandroid-<tag>.zip
SHA256SUMS
```

The `snapshot` channel is reproducible; `stable` uses the latest packages at release time.

## Command reference

```bash
./scripts/build-kernel.sh <codename> [--clean]
./scripts/make-bootimg.sh <codename> [--verbose]   # run also verify-bootimg.py [--verbose]
./scripts/flash.sh <codename> [--ram-boot|--flash-boot|--flash-recovery] [--image FILE]
./scripts/rootfs/debian.sh <codename> [--mode dual-boot|dedicated] [--size 4G]
./scripts/install.sh <codename> --mode dual-boot|dedicated
./scripts/fetch.sh --backend debian|ubuntu|prebuilt --channel snapshot|stable --verify
```

Every command accepts `--dry-run`.

## Quick verification after boot

```bash
ip -br a                 # mido: wlan0, santoni+sagit: usb0
findmnt /                # must point at the rootfs, not the initramfs
systemctl status ssh
```

## Repository layout

```
debiandroid/
├── AGENTS.md         # agent working rules
├── PRD.md            # product requirements
├── README.md
├── docs/design.md    # architecture and implementation plan
├── devices/          # per-device configuration (*.env)
├── scripts/
│   ├── build-kernel.sh
│   ├── make-bootimg.sh
│   ├── flash.sh
│   ├── install.sh
│   ├── fetch.sh
│   ├── initramfs/
│   └── rootfs/{debian,ubuntu,prebuilt}.sh
├── installer/        # TWRP zip payload and update-binary
└── tests/
```

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `fastboot devices` empty | Not in fastboot mode / driver issue | Retry the button combo, check cable and udev |
| Kernel does not boot | Wrong DTB or cmdline | Test with `fastboot boot`, check page size |
| No IP address | Network service inactive | `systemctl restart systemd-networkd` |
| santoni or sagit has no network | Wi-Fi not in mainline | Use `usb0` or an OTG adapter |

Detailed recovery steps, including the Windows "Error Code 28 / Android
Bootloader Interface missing" case: [docs/troubleshooting.md](docs/troubleshooting.md).

## Known limits

- No modem: no SMS, calls, or cellular data.
- No camera and no full audio.
- santoni and sagit: Wi-Fi is not in mainline, use the USB gadget.
- Both `dual-boot` and `dedicated` are destructive at the installation point; scripts require explicit confirmation.

## Documentation map

| File | Purpose |
|---|---|
| `PRD.md` | Requirements, scope, acceptance criteria |
| `docs/design.md` | Architecture, boot chain, phases, risks |
| `docs/validation.md` | What is proven vs not proven, per release |
| `docs/troubleshooting.md` | Recovery mode, fastboot, and Windows driver fixes |
| `docs/a51-comparison.md` | Cross-project analysis of a51-server-os and the changes it implies |
| `docs/klipperphones-comparison.md` | KlipperPhonesLinux: lk2nd + mainline on mido/santoni, reusable configs, and its gaps |
| `docs/docker-on-android-comparison.md` | Container kernel prerequisites, and which Android workarounds we do not need |
| `AGENTS.md` | Working rules for coding agents |
| `LICENSES/README.md` | License map per directory |
