# Licensing map

Different parts of this repository have different licenses. Follow the map below.

| Path | License | Rationale |
|---|---|---|
| `scripts/` | MIT | Tooling and shell scripts |
| `installer/` | MIT | TWRP payload scripts |
| `tests/` | MIT | Test harness |
| `tools/` | MIT | Helper utilities |
| `kernel/patches/`, `kernel/config/`, `kernel/devicetree/` | GPL-2.0-only | Kernel-derived work |
| `docs/`, `PRD.md`, `README.md`, `AGENTS.md` | CC-BY-4.0 | Prose documentation |
| `LICENSES/*` | Verbatim | License texts are not modified |

Rules:

1. Any file derived from Linux kernel headers or copied from kernel sources carries GPL-2.0-only.
2. Rootfs artifacts built by this tooling keep the licenses of their upstream distributions; this repository does not relicense them.
3. Never copy code between `scripts/` and kernel-derived paths without updating this map and the file header.
4. Every source file states its license with an SPDX identifier in the first lines.
