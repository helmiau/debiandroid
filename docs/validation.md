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
| Dual-boot install | TWRP zip or `install.sh --mode dual-boot` | `findmnt /` shows a loop device, SSH reachable |
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
