# AGENTS.md: working rules for debiandroid

Read `PRD.md` and `docs/design.md` before touching code. Those documents are the source of truth for scope.

## Language and style

- Responses and documents: English. Keep technical terms in English.
- Expand every abbreviation on first use, e.g. "UFS (Universal Flash Storage)".
- No em dashes. No filler.

## Principles

1. **Safety first.** Every destructive step (flash, format, repartition) requires explicit confirmation and a preflight check.
2. **Test non-destructively first.** Use `fastboot boot` (RAM boot) before writing any partition.
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

- `devices/*.env`: KERNEL_REPO, KERNEL_REF, DEFCONFIG, DTB_NAME, CMDLINE, BOOTIMG_PARAMS, NET_MODE.
- `scripts/build-kernel.sh`: clone the source, cross-compile, output to `out/<codename>/`.
- `scripts/make-bootimg.sh`: assemble `boot.img` from kernel, DTB, and initramfs.
- `scripts/rootfs/*.sh`: build the rootfs per backend.
- `scripts/install.sh`: installation orchestration for the selected `--mode`.
- `scripts/flash.sh`: fastboot boot/flash with confirmation.

## Required verification

```bash
shellcheck scripts/**/*.sh
bats tests/
./scripts/flash.sh mido --dry-run
```

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

- Never claim a boot succeeded without `fastboot boot` evidence plus network/SSH access.
- Never add device support outside scope without an owner decision.
- Never silently switch the default mode (dual-boot) to dedicated.

## Documentation maintenance

- `docs/validation.md` is updated with every release tag: what was checked, how, and what was not.
- Never mark a check as passed without the command output that produced it.
- Update `LICENSES/README.md` when adding a directory or a file with a different license.
- Every source file starts with an SPDX identifier.
