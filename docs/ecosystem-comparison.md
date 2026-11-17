# Ecosystem check: postmarketOS and neighbours

Question answered here: does another project already do what debiandroid does, or more,
on these exact devices? Sources read on 2026-11-17 from the postmarketOS wiki (now served
from `wiki.nura.eco`).

## 1. Per-device status

| Device | Status | Kernel | Bootloader | Notes |
|---|---|---|---|---|
| santoni (Redmi 4X) | **testing**, generic port `qcom-msm89x7` | 7.1.3, mainline yes | **lk2nd required** | screen, touch, Wi-Fi, Bluetooth, GPS, calls, SMS, data, GPU, FDE all "works"; camera and fingerprint broken |
| mido (Redmi Note 4X) | **community**, generic port `qcom-msm8953` | 7.1.3-2, mainline yes | **lk2nd required** | without lk2nd the mainline kernel does not select the panel and boots to a black screen; mobile data partial, camera partial |
| sagit (Mi 6) | **archived** | downstream 6.0; mainline "no" | aboot; edk2-msm8998 exists | most features broken or untested; the port is out of `pmbootstrap` unless the kernel is built by hand |
| dreamlte (Galaxy S8, Exynos) | not covered | n/a | n/a | outside the Qualcomm work entirely |

Feature tables, panel and touch controller variants, firmware packages and the exact
`pmbootstrap flasher flash_lk2nd` sequence are all documented on those pages. That is
strictly more hardware knowledge than this repository has.

## 2. What that means for debiandroid

postmarketOS is far ahead on hardware bring-up for mido and santoni. Competing there
would be wasted work, and it also settles the bootloader question: lk2nd is not optional
on msm8953/msm8940, it decides whether the panel comes up.

debiandroid should therefore not aim at "another Linux on phones". Its distinct value:

| Axis | postmarketOS | debiandroid |
|---|---|---|
| Userland | Alpine, musl | **Debian arm64, glibc** (the distribution upstream supports directly) |
| Install path | `pmbootstrap` on a Linux host, package building | prebuilt image plus a small script set; TWRP zip planned |
| Safety | assumes a developer audience | stock backup, recovery-partition testing, dead-man timer, read-back verification |
| Reproducibility | rolling packages per channel | pinned kernel commits, structural verification, SHA256SUMS |
| Containers | Alpine packages | Debian `docker.io` with verified kernel prerequisites |

So the honest position is: use their kernel, their firmware and their lk2nd builds, and
spend this project's effort on the Debian userland, the safety layer and the release
artifacts.

## 3. Neighbours, with what is actually verified

- **Droidian** (Debian on Halium, Android base underneath): the project wiki did not
  resolve at `wiki.droidian.org` when checked, so no claim is made here about these
  codenames. It also keeps an Android/Halium base, which is the model this project
  deliberately avoids.
- **Arch Linux on santoni** (`dreemurr-embedded/arch-linux-santoni`): historic, 3.18
  kernel, linked from the santoni wiki page. Not a modern reference.
- **Ubuntu Touch**: the santoni page lists a UBports maintainer among device owners, but
  no verified mainline status. Out of scope: Debian only for now.

## 4. Consequences for the plan

1. Take `lk2nd` from postmarketOS's builds instead of building it: they already carry
   device DTS for mido and santoni.
2. Take kernel fragments and firmware packages as the starting point, as already noted in
   `docs/klipperphones-comparison.md`.
3. Drop sagit from the near-term matrix permanently rather than temporarily: upstream has
   archived it, and the mainline path there needs edk2 UEFI to be useful.
4. Keep the Debian-only decision. Maintaining three backends while the hardware path is
   unverified is how projects end up with three untested images.
