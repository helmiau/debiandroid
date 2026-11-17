# Cross-project analysis: docker-on-android

Compared against [SoraDimichi/docker-on-android](https://github.com/SoraDimichi/docker-on-android)
(clone at `b051f0c`, 2026-11-16, 2.9 MB, one squashed commit).

It is not a distribution project like the other two. It is a single-device guide: Xiaomi
Mi 9T Pro (`raphael`), VoltageOS 6.2 (Android 17), a custom kernel, Magisk, Kali
NetHunter, and Docker running inside the Kali chroot. Its value here is that it names,
one by one, the kernel features a container runtime needs and the workarounds Android
forces when those features are half-present.

## 1. Their kernel requirement list

`kernel-build/docker.config` (verbatim categories):

| Group | Options |
|---|---|
| Namespaces | `NAMESPACES`, `NET_NS`, `PID_NS`, `IPC_NS`, `UTS_NS`, `USER_NS` |
| cgroups | `CGROUPS`, `CGROUP_PIDS`, `CGROUP_DEVICE`, `CGROUP_FREEZER`, `CGROUP_SCHED`, `CPUSETS`, `MEMCG` |
| Storage | `OVERLAY_FS` |
| Networking | `VETH`, `BRIDGE`, `NETFILTER`, `NETFILTER_ADVANCED`, `NF_NAT`, `IP_NF_NAT`, `IP_NF_TARGET_MASQUERADE`, `NETFILTER_XT_MARK`, `NETFILTER_XT_MATCH_ADDRTYPE`, `NETFILTER_XT_MATCH_IPVS` |
| Misc | `KEYS`, `POSIX_MQUEUE` |

Their stock kernel lacked `CONFIG_CGROUP_DEVICE` and `CONFIG_CGROUP_PIDS`, and
`dockerd` refused to start. That is the whole reason the repo builds a kernel at all.

## 2. Android-specific workarounds (not applicable to us)

| Symptom | Their fix | Why we do not need it |
|---|---|---|
| `pivot_root` fails under Android's shared `/data` mount | `unshare -m` with `mount --make-rprivate /` | No Android userspace is running; our init owns the mount tree |
| `cpuset` mounted `noprefix` by Android, kernel keeps it for every later mount | skip cpuset | We mount cgroups ourselves |
| Kernel refuses a second `memory` cgroup mount | skip memory | Same |
| overlayfs fails | `--storage-driver=vfs` (copies each image, slow) | `CONFIG_OVERLAY_FS=y` on f2fs/ext4 is enough |
| Docker would rewrite Android's iptables | `--iptables=false`, manual `ip rule` for `172.17.0.0/16`, `FORWARD DROP` on `docker0` | We own iptables; NAT works normally |
| Go's resolver fails | `GODEBUG=netdns=cgo` | glibc Debian resolves normally |
| Bridge containers have no internet | use `--network=host` | Not needed once NAT is on |

The general lesson: every one of those bugs is a *host-environment* problem, not a
kernel-capability problem. On a phone where Debian replaced Android, the same kernel
options give a normal Docker.

## 3. The gap this exposed in debiandroid

Our per-device fragments enabled only `CONFIG_NETFILTER` and `CONFIG_BRIDGE`. Checked
with `grep` over `kernel/config/`: no namespaces, no cgroups, no `VETH`, no
`OVERLAY_FS`, no NAT. Docker on our current mainline flavor would fail exactly the way
their stock kernel did, and we would discover it on the device after a full build.

Fixed in this repository:

- `kernel/config/containers.config`: the prerequisite set above, plus `CGROUP_CPUACCT`,
  `BLK_CGROUP`, `IP_NF_FILTER`, `FHANDLE`, and f2fs/ext4 xattr support for overlay2.
- `KCONFIG_FRAGMENT_EXTRA` in `devices/*.env`: merges shared fragments after the
  per-device one.
- `scripts/lib/kconfig-check.sh`: after the merge, prove every requested option survived.
  Kconfig silently drops a symbol that does not exist in the tree or whose dependencies
  are unmet; `merge_config.sh` only warns and `build-kernel.sh` discarded the output.
  Their build does the same check with a two-symbol `grep`; this generalizes it and
  fails at configure time instead of after a 40-minute compile.

## 4. What is still missing for containers on debiandroid

- `stock-repack` cannot run Docker. It keeps the vendor kernel, and vendor kernels for
  msm8937/msm8953 lack the cgroup controllers. Containers require the `mainline` flavor.
- systemd inside the rootfs expects `CONFIG_FHANDLE` (present) and cgroup v2 (kernel 5.0+,
  present in 6.x). Debian 12 uses the unified hierarchy; `MEMCG` is what makes
  `--memory` work, and it is in the fragment.
- No verification yet on hardware. The fragment is checked for presence, not for
  runtime behaviour: `docker run --rm hello-world` on the phone is the acceptance test.
- Resource limits on a phone are real: `CGROUP_PIDS` and `MEMCG` work, but thermal
  throttling under sustained container load is unavoidable.

## 5. Where the three references leave debiandroid

| Reference | Contributes |
|---|---|
| a51-server-os | Safety: dead-man timer, rescue console, read-back verification, stock backup |
| KlipperPhonesLinux | Boot path: lk2nd for msm8953/msm8940, working per-SoC kernel configs |
| docker-on-android | Kernel feature list for containers, and the proof that the remaining problems are Android's, not the kernel's |

Sequencing that follows: stock-repack first (boots), lk2nd + mainline second (modern
kernel), `containers.config` in that same mainline build (so Docker works on the first
boot rather than after another 40-minute build), and `docker run hello-world` as the
acceptance test for the mainline milestone.
