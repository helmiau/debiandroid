# Cross-project analysis: a51-server-os

Compared against [NotNumberFour/a51-server-os](https://github.com/NotNumberFour/a51-server-os)
(Samsung Galaxy A51, SM-A515F, Exynos 9611, stock kernel 4.14.113, bootloader U8).
Same goal as debiandroid: a headless Debian ARM64 server on a phone, no Android running.

This document records what that project does differently, which of its decisions are
transferable, and which of our failures it already solved.

## 1. The decisive difference: which kernel is trusted

| | a51-server-os | debiandroid (current) |
|---|---|---|
| Kernel | **Stock Samsung 4.14, byte-for-byte unchanged** | Built from source (mainline v6.19 / vendor tree) |
| DTB | **Stock, unchanged** | Built from source, appended to kernel |
| What gets replaced | **Only the ramdisk** | Kernel + DTB + ramdisk |
| Boot image format | Header v2, recovery DTBO, Samsung `SEANDROIDENFORCE` tail, AVB footer round-tripped | Header v0, appended DTB |
| Proven bootable | Yes, author's device in daily service | **No** |
| Mainline features | None (stock kernel limits: no systemd, no Docker, no PostgreSQL) | Full mainline goal |
| Risk of a bad image | Low: kernel and DTB already validated by the vendor | **High: every artifact is unproven** |

The A51 project works because it never asks the bootloader to accept a new kernel. Its
own README states the bootloader "accepts a modified `boot.img` (orange state)"; the
kernel, DTB and signing structures are preserved. Everything new lives in the initramfs
and in `/data/debian-server/rootfs`.

debiandroid replaces the kernel. That is the harder half of the problem, and the half
that is unproven on hardware. The santoni crash-to-EDL on 2026-11-16 was an image with
`ramdisk_size = 0`: a kernel with no rootfs. The A51 project cannot produce that class
of artifact because its ramdisk is the entire point.

## 2. Its safety architecture (all transferable)

1. **Two boot images, two partitions.** `recovery` holds the test image, `boot` holds
   production. A failed test only costs a reboot into Android.
2. **Dead-man timer.** Test-mode `/init` starts a 300 s watchdog. If Debian does not
   write `/var/log/a51/healthy-<boot_id>` (SSH up and reachable) in time, the phone
   force-reboots into Android. One timer covers every boot phase, including after
   `switch_root`, because Debian's static busybox keeps running.
3. **Byte-identical repack, verified before use.** `tools/bootimg.py` unpacks and repacks
   stock images; the README instructs the user to confirm the round trip on their own
   files before trusting it. Every field — header, DTBO, DTB, Samsung tail, AVB footer —
   is preserved or rewritten with new offsets.
4. **Read-back verification after writing.** `tools/flash-partition.sh` accepts exactly
   `boot` or `recovery`, compares partition size to image size, checks SHA-256 before
   writing, refuses non-`ANDROID!` files, then `dd`s with `conv=fsync` and **reads the
   partition back** to compare hashes.
5. **Rescue console instead of a boot loop.** USB gadget ACM serial (`ttyGS0`) plus NCM
   network, with a 25 s retry because the DWC3 UDC only appears after cable detection
   (~10 s). Any failure drops to a shell on that console; it does not reboot. Without a
   console, a failed native boot is indistinguishable from a dead phone.
6. **Backup before touching anything.** Read-only `dd` of `efs`, `sec_efs`, `boot`,
   `recovery`, `vbmeta`, `dtbo`, `param` and others, before the first write. IMEI data
   cannot be recovered from any other source.
7. **BCB clearing.** Android writes `boot-recovery` to the `misc` partition; stock
   recovery clears it on exit. A custom initramfs that does not clear it traps the phone
   in a recovery loop. Their `/init` zeroes the first 32 bytes when they match.
8. **`hung_task_panic = 0`.** The Samsung kernel panics when a task blocks >120 s
   (`hung_task_panic=1`). Without Android's `tzdaemon`, TrustZone threads block forever
   and killed the system at ~242 s. `/init` disables the panic first thing. Any kernel
   that expects vendor daemons to service it needs this.

## 3. Device-specific quirks worth knowing (not directly reusable)

- Samsung S-Boot requires the **stock signed `vbmeta`** even when unlocked; only the
  boot image may change. Flashing Magisk's modified vbmeta causes `AVB Fail`.
- Gadget control goes through `/sys/class/android_usb/android0/{functions,enable}`
  (`acm,ncm`), not plain configfs; the NCM interface is `ncm0`, not `usb0`.
- `console=ram` in the stock cmdline leaves runit children with closed stdio; services
  die instantly unless `/etc/runit/2` redirects stdio before `runsvdir`.
- Android mounts `/data` `nosuid`, so `sudo` fails in a chroot until a bind remount with
  `suid,dev`.
- `CONFIG_ANDROID_PARANOID_NETWORK=y`: socket creation needs GID 3003/3004.
- Panel ignores brightness 0; `fb0/blank = 4` actually powers it down.

These are Samsung/MSM-era specifics. The **patterns** are portable; the constants are not.

## 4. What debiandroid should adopt

Ordered by risk removed per unit of work.

| Priority | Change | Why |
|---|---|---|
| P0 | **Two-flavor kernel: `KERNEL_FLAVOR=stock\|mainline` per device** | The stock path is provably bootable and lets the Debian side mature before mainline bring-up. Mainline stays the goal, not the first step. |
| P0 | Initramfs is mandatory before any boot image is produced | Done: `make-bootimg.sh` refuses without an initramfs; `verify-bootimg.py` rejects `ramdisk_size = 0`. |
| P1 | **Dead-man timer + health flag** in test-mode initramfs | Converts "bricked, needs a PC" into "rebooted itself". |
| P1 | **Flash to `recovery` first, never `fastboot boot` on a live device** | Our `fastboot boot` of an unproven image wedged santoni into EDL. A recovery-partition test with a timer has a bounded blast radius. |
| P1 | **Read-back verification** after every write | Our flash path trusts the write. Theirs proves it. |
| P1 | **Pre-staged stock restore image** (`boot.img` original) before any write | We only restored santoni because the owner had the file and could pull the battery. |
| P2 | **Rescue console over USB ACM serial** in initramfs | Without it, failures are silent. Our own diagnosis needed a PC and a working driver. |
| P2 | **BCB / `misc` clearing** in initramfs | Prevents the recovery loop class of failure. |
| P2 | **`hung_task_panic = 0`** in initramfs | Vendor kernels panic on blocked TrustZone threads. |
| P2 | **Byte-identical round-trip test** for `mkbootimg.py` against a known-good stock image | Validates the writer before it touches a phone. |
| P3 | **Per-failure lessons log** (`docs/lessons-learned.md`) | Their doc is the most valuable file in that repo. Ours is split across `validation.md` and `troubleshooting.md`. |

## 5. What debiandroid already does better

- **Reproducible builds from pinned sources.** Their tree is a one-off set of files; ours
  pins commits and rebuilds in CI (`v6.19` at `05f7e89a`, santoni at `f47205ee`).
- **Verification tooling.** `verify-bootimg.py`, 26 bats tests, `preflight.sh`,
  `kernel-pin.sh`. Their repo has no CI and no tests.
- **Multi-device matrix** with per-device config fragments.
- **Self-contained tooling.** Platform-tools auto-provisioning means a fresh host needs
  no manual `adb`/`fastboot` install.

## 6. Honest conclusion

a51-server-os solves the *delivery* problem (get Debian running, keep it running, recover
from failure) on top of a kernel it did not build. debiandroid is attempting the
*integration* problem (bring up a mainline kernel) while still lacking the delivery
safety net.

The correct sequence for debiandroid is therefore:

1. Ship the Debian side on the stock kernel (proven bootable), with timer, rescue
   console, read-back flashing and a restore image.
2. Only then swap in the mainline kernel, one device at a time, behind
   `KERNEL_FLAVOR=mainline`, with the stock path retained as the fallback.

Booting mainline first, as attempted on santoni, inverts the risk order: it puts the
least proven component (a freshly built kernel with no ramdisk) in the position with the
largest blast radius.
