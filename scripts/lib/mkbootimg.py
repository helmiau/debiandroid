#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Minimal Android boot image v0 writer (arm64).

Only what debiandroid needs: kernel, optional ramdisk, cmdline, board,
page size, base and offsets. Header v0 is 1632 bytes, padded to page size.
Reference: system/tools/mkbootimg/include/bootimg/bootimg.h
"""
import argparse
import hashlib
import struct
import sys

BOOT_MAGIC = b"ANDROID!"
HEADER_V0_SIZE = 1632


def pad(data: bytes, page: int) -> bytes:
    rem = len(data) % page
    return data if rem == 0 else data + b"\0" * (page - rem)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kernel", required=True)
    p.add_argument("--ramdisk")
    p.add_argument("--second")
    p.add_argument("--dtb")
    p.add_argument("--cmdline", default="")
    p.add_argument("--board", default="")
    p.add_argument("--pagesize", type=int, default=2048)
    p.add_argument("--base", type=lambda s: int(s, 0), default=0x80000000)
    p.add_argument("--kernel_offset", type=lambda s: int(s, 0), default=0x00008000)
    p.add_argument("--ramdisk_offset", type=lambda s: int(s, 0), default=0x01000000)
    p.add_argument("--second_offset", type=lambda s: int(s, 0), default=0x00F00000)
    p.add_argument("--tags_offset", type=lambda s: int(s, 0), default=0x00000100)
    p.add_argument("--output", required=True)
    a = p.parse_args(argv)

    if a.pagesize not in (2048, 4096, 16384, 65536):
        print(f"unsupported page size {a.pagesize}", file=sys.stderr)
        return 2
    if len(a.cmdline) > 511:
        print("cmdline exceeds 511 bytes for header v0", file=sys.stderr)
        return 2

    kernel = open(a.kernel, "rb").read()
    ramdisk = open(a.ramdisk, "rb").read() if a.ramdisk else b""
    second = open(a.second, "rb").read() if a.second else b""
    dtb = open(a.dtb, "rb").read() if a.dtb else b""

    def fields(n):
        return struct.pack(
            "<10I", n, a.base + a.kernel_offset, a.base + a.ramdisk_offset,
            a.base + a.second_offset, a.base + a.tags_offset,
            a.pagesize, 0, 0, 0, 0)

    header = BOOT_MAGIC + struct.pack(
        "<10I", len(kernel), a.base + a.kernel_offset, len(ramdisk),
        a.base + a.ramdisk_offset, len(second), a.base + a.second_offset,
        a.base + a.tags_offset, a.pagesize, 0, 0)
    header += struct.pack("<16s", b"")            # name
    header += struct.pack("<512s", a.cmdline.encode()[:511])
    header += struct.pack("<32s", b"")            # id
    header += struct.pack("<1024s", a.board.encode()[:1023])
    if len(header) != HEADER_V0_SIZE:
        print(f"header size {len(header)} != {HEADER_V0_SIZE}", file=sys.stderr)
        return 2

    body = pad(header, a.pagesize) + pad(kernel, a.pagesize) + pad(ramdisk, a.pagesize)
    if second:
        body += pad(second, a.pagesize)
    if dtb:
        body += pad(dtb, a.pagesize)

    open(a.output, "wb").write(body)
    print(f"{a.output}: {len(body)} bytes "
          f"(kernel {len(kernel)}, ramdisk {len(ramdisk)}, dtb {len(dtb)})")
    print("sha256 " + hashlib.sha256(body).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
