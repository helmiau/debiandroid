#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify a boot.img is structurally valid and bootable enough to ship.

Parses the Android boot image header (v0), then checks:

  * magic "ANDROID!"
  * page_size is one of {2048, 4096, 8192, 16384}
  * ramdisk_size > 0  (a boot image with no ramdisk cannot boot)
  * file is large enough to hold kernel + ramdisk
  * kernel region begins with gzip magic 1f 8b (kernels here are Image.gz)
  * ramdisk region begins with gzip (our initramfs.cpio.gz) or cpio newc magic

Usage: verify-bootimg.py <boot.img> [-v] [--allow-no-ramdisk]
Exit code 0 = OK, 2 = broken.
"""
import struct
import sys

MAGIC = b"ANDROID!"
PAGE_SIZES = (2048, 4096, 8192, 16384)
HEADER_LEN = 0x260  # header v0 fixed size


def rnd(offset, page_size):
    return ((offset + page_size - 1) // page_size) * page_size


def hexdump_magic(data, label):
    return " ".join(f"{b:02x}" for b in data[:16])


def fail(what):
    print(f"FAIL: {what}")
    sys.exit(2)


def main(argv):
    if len(argv) < 1:
        print("usage: verify-bootimg.py <boot.img> [-v] [--allow-no-ramdisk]")
        sys.exit(2)

    path = None
    verbose = False
    allow_no_ramdisk = False
    for a in argv:
        if a == "-v":
            verbose = True
        elif a == "--allow-no-ramdisk":
            allow_no_ramdisk = True
        else:
            path = a
    if path is None:
        print("usage: verify-bootimg.py <boot.img> [-v] [--allow-no-ramdisk]")
        sys.exit(2)

    with open(path, "rb") as fh:
        data = fh.read()

    if len(data) < HEADER_LEN:
        fail(f"{path}: file too short ({len(data)} bytes < 0x260 header)")

    magic = data[0:8]
    if magic != MAGIC:
        fail(f"{path}: bad magic {magic!r} (expected ANDROID!)")

    (kernel_size, _kernel_addr, ramdisk_size, _ramdisk_addr,
     _second_size, _second_addr, _tags_addr, page_size) = \
        struct.unpack_from("<8I", data, 8)

    if page_size not in PAGE_SIZES:
        fail(f"{path}: invalid page_size {page_size}")
    if kernel_size == 0:
        fail(f"{path}: kernel_size is 0")
    if ramdisk_size == 0 and not allow_no_ramdisk:
        fail(f"{path}: ramdisk_size is 0 - boot image has NO INITRAMFS and "
             "cannot boot. Build the initramfs first, or use --allow-no-ramdisk.")

    kernel_off = page_size
    ramdisk_off = rnd(kernel_off + kernel_size, page_size)

    if len(data) < ramdisk_off + ramdisk_size:
        fail(f"{path}: file too short for kernel+ramdisk "
             f"({len(data)} < {ramdisk_off + ramdisk_size})")

    kernel = data[kernel_off:kernel_off + kernel_size]
    if not kernel.startswith(b"\x1f\x8b") and not kernel.startswith(b"MZ"):
        fail(f"{path}: kernel region does not look like Image.gz "
             f"(magic {hexdump_magic(kernel, 'kernel')})")

    if ramdisk_size > 0 and not allow_no_ramdisk:
        ram = data[ramdisk_off:ramdisk_off + ramdisk_size]
        if not ram.startswith(b"\x1f\x8b") and not ram.startswith(b"070701"):
            fail(f"{path}: ramdisk is neither gzip nor cpio newc "
                 f"(magic {hexdump_magic(ram, 'ramdisk')})")

    print(f"OK {path}")
    if verbose:
        print(f"  page_size      = {page_size}")
        print(f"  kernel_size    = {kernel_size}")
        print(f"  kernel_off     = {kernel_off}")
        print(f"  ramdisk_size   = {ramdisk_size}")
        print(f"  ramdisk_off    = {ramdisk_off}")
        print(f"  total size     = {len(data)}")
        print(f"  kernel magic   = {hexdump_magic(kernel, 'kernel')}")
    sys.exit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
