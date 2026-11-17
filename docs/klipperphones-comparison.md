# Cross-project analysis: KlipperPhonesLinux

Compared against [umeiko/KlipperPhonesLinux](https://github.com/umeiko/KlipperPhonesLinux)
(clone at `ec721c7`, 2026-07-23, single squashed commit, ~712 MB with CAD/PCB assets).
Same destination as debiandroid: a real ARM64 Linux distribution on an old phone, no
Android running. Different purpose: it is an appliance image for a Klipper 3D-printer
host, not a general-purpose server distribution.

Most relevant fact for this project: **it lists both `xiaomi-mido` and `xiaomi-santoni`
as supported devices**, and it does so with a rebuilt kernel, not a vendor one.

## 1. Boot stack

| Layer | KlipperPhonesLinux | debiandroid (mainline flavor) |
|---|---|---|
| Second-stage bootloader | **lk2nd**, flashed first; the phone reboots into it during flashing and continues | none: stock aboot loads `boot.img` directly |
| Kernel | rebuilt mainline/community: `msm89x7-mainline/linux` branch `msm89x7/6.6-experiment` for santoni, `msm8953-mainline/linux` for mido | `MrArtemSid/linux-msm89x7` branch `santoni` (pinned `f47205ee`), mainline v6.19 for mido/sagit |
| Kernel config | per-SoC file in the repo (`LinuxKernels/msm8940/.config`, `LinuxKernels/msm8953/.config`) | per-device fragment in `kernel/config/` merged onto a defconfig |
| DTB | from the kernel tree, plus device DTS tweaks (`msm8940/dts/santoni_usb_host.dts`, `santoni_usb_peripheral.dts`) | built from the kernel tree and appended |
| Boot image | `mkbootimg` v0, base `0x80000000`, kernel offset `0x8000`, ramdisk offset `0x01000000`, tags `0x0100`, page 2048, appended DTB | same parameters for santoni (`devices/santoni.env`) |
| Initramfs | the Debian `initramfs-tools` output from `make-kpkg`, installed into the rootfs chroot | purpose-built `initramfs/init` with rescue console and dead-man timer |
| Root filesystem | sparse image (`img2simg`), flashed to a dedicated partition, mounted by `root=UUID=...` | directory on userdata (dual-boot) or a dedicated partition |
| Distribution | Ubuntu 20.04 with Klipper, Moonraker, Fluidd, KlipperScreen preinstalled | Debian/Ubuntu server base, services chosen by the user |

No UEFI anywhere. The boot path is still Qualcomm aboot, with lk2nd inserted as a
second stage. That is the answer to the UEFI question in the original brief: these
projects reach native Linux without UEFI, and nobody in this space is porting it.

## 2. lk2nd is the piece debiandroid is missing

Verified in the current lk2nd tree (`cf45aef`, 2026-11-07):

| Device | SoC | lk2nd target | Device DTS |
|---|---|---|---|
| mido (Redmi Note 4X) | msm8953 | `target/msm8953` | yes |
| santoni (Redmi 4X) | msm8940 | `target/msm8952` | yes: `lk2nd/device/dts/msm8952/msm8940-xiaomi-santoni.dts` |
| sagit (Mi 6) | msm8998 | **absent** (`msm8996` is the newest Qualcomm MSM target) | no |
| dreamlte (Galaxy S8) | Exynos 8895 | **absent**, Exynos is out of lk2nd's scope | no |

Consequence: for mido and santoni the proven path to a modern mainline kernel is
lk2nd + mainline, not stock aboot + mainline. For sagit and dreamlte, lk2nd cannot help;
those two need their own approach (Renegade/edk2 or vendor-aboot on msm8998; Samsung's
boot shim on Exynos) and should stay out of scope until the Qualcomm 8953/8940 pair is
finished.

Our current `mainline` flavor assumes aboot alone will load a freshly built
`Image.gz` + appended DTB. KlipperPhonesLinux, postmarketOS, and lk2nd all indicate
that assumption is the weak link on these two SoCs.

## 3. Reusable artifacts

- `LinuxKernels/msm8940/.config` (5,164 lines, Linux 6.6.0 for msm89x7) and
  `LinuxKernels/msm8953/.config` (7,143 lines). Both enable `SYSVIPC`, `FHANDLE`,
  `USB_CONFIGFS` with `ACM` and `NCM`, and the `ft5x06` touchscreen family. These are
  evidence-backed starting points for `kernel/config/*.config`, better than guessing
  from upstream defconfigs.
- `msm8940/dts/*.dts`: the only device-tree work they needed beyond the kernel tree,
  a USB host/peripheral mode switch. Cheap to adopt.
- Their acknowledgement of postmarketOS firmware blobs (`LinuxKernels/msm8953/firmware/`)
  matches what a working display/Wi-Fi needs.

Their kernel pin is a moving branch (`6.6-experiment`), not a commit. Ours is a pinned
commit, which is the right choice for reproducibility; borrow the config, not the pin.

## 4. What it does not solve

| Gap | Detail |
|---|---|
| No restore path | No stock-image backup step anywhere; flashing is destructive and irreversible without an external ROM collection |
| No pre-write proof | `flash_klipper_os.bat` flashes a batch; nothing reads the partition back |
| No failure containment | No dead-man timer, no health flag; a bad boot is diagnosed over USB serial after the fact |
| No dual-boot | Rootfs owns a partition outright |
| Weak credentials | Fixed `umeko`/`1234`, SSH and a web terminal exposed on the LAN by default |
| EOL base | Ubuntu 20.04 reached end of standard support in 2025 |
| No CI, no tests | Builds are a documented manual sequence on Ubuntu 20.04 |

These are the same gaps a51-server-os avoids; KlipperPhonesLinux has the opposite
profile, strong on mainline bring-up and weak on safety.

## 5. What this means for debiandroid

Ranked, smallest change first:

1. **Add `BOOTLOADER=aboot|lk2nd`** to `devices/*.env`, with `lk2nd` documented as the
   supported value for mido and santoni in the mainline flavor. Keep `aboot` as the
   default until an lk2nd image is verified on hardware.
2. **Document the two-step flash**: stock backup, then lk2nd, then the kernel. lk2nd
   replaces the boot the same way any image does; `backup-stock.sh` already covers the
   restore source.
3. **Adopt their `.config` as the base for the mainline fragments** and diff against
   ours, rather than extending a defconfig by hand.
4. **Keep our safety layer**: dead-man timer, rescue console, read-back verification,
   and the `stock-repack` flavor all remain strictly better than their workflow.
5. **Drop sagit and dreamlte from the near-term mainline matrix** until the
   mido/santoni path boots on hardware. Neither has an lk2nd target, and attempting
   them first repeats the santoni EDL incident on devices with less community support.

## 6. Where the three projects leave the design

| Project | Kernel | Bootloader | Safety | Value to us |
|---|---|---|---|---|
| a51-server-os | vendor, unchanged | vendor | strong (timer, rescue, read-back) | the safety architecture we adopted |
| KlipperPhonesLinux | mainline 6.6, rebuilt | lk2nd | weak | the bootloader that makes mainline work, plus working configs |
| debiandroid | mainline, pinned | aboot (+ lk2nd planned) | medium, being built | reproducible builds, CI, structural verification |

The correct end state combines them: lk2nd for the boot path, a pinned mainline kernel
with their config as the base, and a51's safety layer on top.
