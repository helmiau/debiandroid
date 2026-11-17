#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Repackage an Android boot image (header v0) with a different ramdisk.

This is the safe path used by a51-server-os: keep the vendor kernel and device
tree byte-for-byte and replace only the initramfs. No cross-compiler, no device
tree risk, and no new code running in the bootloader's trust path.

Only header version 0 is handled. Version 1/2 images carry a recovery_dtbo or
an extra dtb section, and Samsung/AVB images carry a signed footer whose
offsets would be invalidated by a ramdisk of a different size; use the vendor
image's own tooling for those.

Usage:
  bootimg_v0.py info IMAGE
  bootimg_v0.py repack IMAGE --ramdisk FILE --out FILE [--keep-id]
  bootimg_v0.py selfcheck

Exit codes: 0 ok, 2 invalid input or layout mismatch.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys

MAGIC = b"ANDROID!"
PAGE_SIZES = (2048, 4096, 8192, 16384)
V0_HEADER_LEN = 1632  # magic .. extra_cmdline

# field: (offset, format)
U32 = [
    ("kernel_size", 8), ("kernel_addr", 12),
    ("ramdisk_size", 16), ("ramdisk_addr", 20),
    ("second_size", 24), ("second_addr", 28),
    ("tags_addr", 32), ("page_size", 36),
    ("header_version", 40), ("os_version", 44),
]
HEADER_NAME_OFFSET = 48
HEADER_CMDLINE_OFFSET = 64
HEADER_ID_OFFSET = 576
HEADER_EXTRA_CMDLINE_OFFSET = 608


def _round_up(value: int, page_size: int) -> int:
    return ((value + page_size - 1) // page_size) * page_size


def parse(path: str) -> dict:
    with open(path, "rb") as handle:
        data = handle.read()
    if len(data) < V0_HEADER_LEN:
        raise SystemExit(f"FAIL: {path} is {len(data)} bytes, shorter than a v0 header")
    if data[:8] != MAGIC:
        raise SystemExit(f"FAIL: {path} does not start with ANDROID!")

    fields = {"raw": data, "path": path}
    for name, offset in U32:
        fields[name] = struct.unpack_from("<I", data, offset)[0]

    if fields["page_size"] not in PAGE_SIZES:
        raise SystemExit(f"FAIL: unsupported page_size {fields['page_size']}")
    if fields["header_version"] != 0:
        raise SystemExit(
            f"FAIL: header version {fields['header_version']} is not supported by this tool; "
            "v1/v2 images carry extra sections and possibly a signed footer"
        )

    page = fields["page_size"]
    fields["name"] = data[HEADER_NAME_OFFSET:HEADER_NAME_OFFSET + 16].split(b"\0")[0].decode("ascii", "replace")
    fields["cmdline"] = data[HEADER_CMDLINE_OFFSET:HEADER_CMDLINE_OFFSET + 512].split(b"\0")[0].decode("ascii", "replace")
    fields["extra_cmdline"] = data[HEADER_EXTRA_CMDLINE_OFFSET:HEADER_EXTRA_CMDLINE_OFFSET + 1024].split(b"\0")[0].decode("ascii", "replace")
    fields["id"] = data[HEADER_ID_OFFSET:HEADER_ID_OFFSET + 32]

    offset = _round_up(V0_HEADER_LEN, page)
    fields["kernel_off"] = offset
    offset += _round_up(fields["kernel_size"], page)
    fields["ramdisk_off"] = offset
    offset += _round_up(fields["ramdisk_size"], page)
    fields["second_off"] = offset
    offset += _round_up(fields["second_size"], page)
    fields["tail_off"] = offset

    if offset > len(data):
        raise SystemExit(
            f"FAIL: header describes {offset} bytes but the file has {len(data)}"
        )

    # Everything after the known regions (if any) must be preserved verbatim.
    fields["tail"] = data[fields["tail_off"]:]
    fields["kernel"] = data[fields["kernel_off"]:fields["kernel_off"] + fields["kernel_size"]]
    fields["ramdisk"] = data[fields["ramdisk_off"]:fields["ramdisk_off"] + fields["ramdisk_size"]]
    fields["second"] = data[fields["second_off"]:fields["second_off"] + fields["second_size"]]
    fields["total_size"] = len(data)
    return fields


def compute_id(kernel: bytes, ramdisk: bytes, second: bytes) -> bytes:
    digest = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        digest.update(blob)
        digest.update(struct.pack("<I", len(blob)))
    return digest.digest()


def build(image: dict, ramdisk: bytes, keep_id: bool = False) -> bytes:
    page = image["page_size"]
    pad = lambda blob: blob + b"\0" * (_round_up(len(blob), page) - len(blob))

    header = bytearray(image["raw"][:V0_HEADER_LEN])
    struct.pack_into("<I", header, 16, len(ramdisk))
    if not keep_id:
        header[HEADER_ID_OFFSET:HEADER_ID_OFFSET + 32] = compute_id(
            image["kernel"], ramdisk, image["second"]
        )

    out = pad(bytes(header)) + pad(image["kernel"]) + pad(ramdisk) + pad(image["second"]) + image["tail"]
    if len(out) > image["total_size"]:
        raise SystemExit(
            f"FAIL: repacked image is {len(out)} bytes, larger than the original "
            f"{image['total_size']}; shrink the initramfs"
        )
    return out


def cmd_info(args: argparse.Namespace) -> int:
    image = parse(args.image)
    gib = image["total_size"] / (1024 * 1024)
    print(f"file            {image['path']} ({image['total_size']} bytes, {gib:.2f} MiB)")
    print(f"page_size       {image['page_size']}")
    print(f"header_version  {image['header_version']}")
    print(f"kernel          {image['kernel_size']} bytes @ {image['kernel_off']} "
          f"addr 0x{image['kernel_addr']:08x}")
    print(f"ramdisk         {image['ramdisk_size']} bytes @ {image['ramdisk_off']} "
          f"addr 0x{image['ramdisk_addr']:08x}")
    print(f"second          {image['second_size']} bytes @ {image['second_off']}")
    print(f"tail            {len(image['tail'])} bytes @ {image['tail_off']}")
    print(f"name            {image['name']!r}")
    print(f"cmdline         {image['cmdline']}")
    if image["extra_cmdline"]:
        print(f"extra_cmdline   {image['extra_cmdline']}")
    return 0


def cmd_repack(args: argparse.Namespace) -> int:
    image = parse(args.image)
    with open(args.ramdisk, "rb") as handle:
        ramdisk = handle.read()
    if not ramdisk:
        raise SystemExit("FAIL: the new ramdisk is empty")
    if ramdisk[:2] != b"\x1f\x8b" and ramdisk[:6] not in (b"070701", b"070702"):
        raise SystemExit("FAIL: the new ramdisk is neither gzip nor cpio newc")

    out = build(image, ramdisk, keep_id=args.keep_id)
    with open(args.out, "wb") as handle:
        handle.write(out)
    print(f"repack: {args.out} {len(out)} bytes; kernel {image['kernel_size']} (unchanged), "
          f"ramdisk {image['ramdisk_size']} -> {len(ramdisk)}, tail {len(image['tail'])} (unchanged)")
    return 0


def cmd_selfcheck(_: argparse.Namespace) -> int:
    """Build a synthetic v0 image, repack it, and prove the layout round-trips."""
    page = 2048
    kernel = b"\x1f\x8b" + b"K" * 5000
    ramdisk = b"\x1f\x8b" + b"R" * 3000
    second = b"S" * 10

    header = bytearray(V0_HEADER_LEN)
    header[0:8] = MAGIC
    struct.pack_into("<I", header, 8, len(kernel))
    struct.pack_into("<I", header, 12, 0x80008000)
    struct.pack_into("<I", header, 16, len(ramdisk))
    struct.pack_into("<I", header, 20, 0x81000000)
    struct.pack_into("<I", header, 24, len(second))
    struct.pack_into("<I", header, 28, 0x80F00000)
    struct.pack_into("<I", header, 32, 0x80000100)
    struct.pack_into("<I", header, 36, page)
    struct.pack_into("<I", header, 40, 0)
    header[48:48 + 8] = b"santoni\0"
    header[64:64 + 12] = b"console=tty0"
    header[576:608] = compute_id(kernel, ramdisk, second)

    pad = lambda blob: blob + b"\0" * (_round_up(len(blob), page) - len(blob))
    original = pad(bytes(header)) + pad(kernel) + pad(ramdisk) + pad(second)

    path = "_selfcheck_boot.img"
    with open(path, "wb") as handle:
        handle.write(original)
    try:
        image = parse(path)
        assert image["kernel_size"] == len(kernel), image["kernel_size"]
        assert image["ramdisk_size"] == len(ramdisk)
        assert image["second_size"] == len(second)
        assert image["tail"] == b"", f"unexpected tail: {len(image['tail'])} bytes"

        # Same ramdisk must reproduce the file byte for byte.
        rebuilt = build(image, ramdisk)
        assert rebuilt == original, "round-trip with the original ramdisk is not byte-identical"

        # A smaller ramdisk keeps kernel, second and tail intact.
        smaller = b"\x1f\x8b" + b"r" * 1000
        rebuilt = build(image, smaller)
        check = parse_bytes(rebuilt)
        assert check["kernel"] == kernel, "kernel changed"
        assert check["second"] == second, "second stage changed"
        assert check["ramdisk"] == smaller, "ramdisk not replaced"
        assert check["cmdline"] == "console=tty0", "cmdline changed"
        print("selfcheck: OK (layout, byte-identical round trip, ramdisk replacement)")
        return 0
    finally:
        import os
        os.unlink(path)


def parse_bytes(data: bytes) -> dict:
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".img", delete=False) as handle:
        handle.write(data)
        tmp = handle.name
    try:
        return parse(tmp)
    finally:
        import os
        os.unlink(tmp)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    info = sub.add_parser("info", help="print the header fields")
    info.add_argument("image")
    info.set_defaults(func=cmd_info)

    repack = sub.add_parser("repack", help="replace the ramdisk")
    repack.add_argument("image")
    repack.add_argument("--ramdisk", required=True)
    repack.add_argument("--out", required=True)
    repack.add_argument("--keep-id", action="store_true",
                        help="keep the original SHA-1 id instead of recomputing it")
    repack.set_defaults(func=cmd_repack)

    selfcheck = sub.add_parser("selfcheck", help="verify the layout logic on a synthetic image")
    selfcheck.set_defaults(func=cmd_selfcheck)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
