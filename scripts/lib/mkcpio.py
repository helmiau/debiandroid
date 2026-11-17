#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Create a newc (SVR4) cpio archive, optionally gzip-compressed.

Used to build the debiandroid initramfs without requiring cpio(1) on the host,
so the same command works on Windows, macOS and Linux.

Usage: mkcpio.py SOURCE_DIR OUTPUT [--gzip]
       mkcpio.py --list ARCHIVE
"""

from __future__ import annotations

import argparse
import gzip
import os
import stat
import sys

# Character devices the kernel or the init script expect to exist.
DEVICE_NODES = {
    "dev/console": (5, 1, 0o600),
    "dev/null": (1, 3, 0o666),
}

TRAILER = "TRAILER!!!"


def _pad4(data: bytes) -> bytes:
    return data + b"\0" * ((-len(data)) % 4)


def _entry(name: str, mode: int, data: bytes, ino: int, mtime: int,
           rdev_major: int = 0, rdev_minor: int = 0) -> bytes:
    encoded = name.encode()
    fields = [
        ino, mode, 0, 0, 1, mtime, len(data),
        0, 0, rdev_major, rdev_minor, len(encoded) + 1, 0,
    ]
    header = b"070701" + b"".join(b"%08X" % field for field in fields)
    return _pad4(header + encoded + b"\0") + _pad4(data)


def collect(source: str) -> list[tuple[str, int, bytes, int, int]]:
    """Return (name, mode, data, ino, mtime) for every entry, sorted by name."""
    source = os.path.abspath(source)
    if not os.path.isdir(source):
        raise SystemExit(f"mkcpio: source is not a directory: {source}")

    entries: list[tuple[str, int, bytes, int, int]] = []
    ino = 0

    for current, dirs, files in os.walk(source):
        dirs.sort()
        for name in sorted(dirs + files):
            path = os.path.join(current, name)
            rel = os.path.relpath(path, source).replace(os.sep, "/")
            st = os.lstat(path)
            ino += 1
            if stat.S_ISLNK(st.st_mode):
                entries.append((rel, stat.S_IFLNK | 0o777, os.readlink(path).encode(), ino, 0))
            elif stat.S_ISDIR(st.st_mode):
                entries.append((rel, stat.S_IFDIR | stat.S_IMODE(st.st_mode), b"", ino, int(st.st_mtime)))
            elif stat.S_ISREG(st.st_mode):
                with open(path, "rb") as handle:
                    entries.append((rel, stat.S_IFREG | stat.S_IMODE(st.st_mode), handle.read(), ino, int(st.st_mtime)))
            else:
                raise SystemExit(f"mkcpio: unsupported file type: {rel}")

    present = {entry[0] for entry in entries}
    for rel, (major, minor, mode) in DEVICE_NODES.items():
        if rel in present:
            continue
        parent = os.path.dirname(rel)
        if parent and parent not in present:
            ino += 1
            entries.append((parent, stat.S_IFDIR | 0o755, b"", ino, 0))
            present.add(parent)
        ino += 1
        entries.append((rel, stat.S_IFCHR | mode, b"", ino, 0))

    entries.sort(key=lambda entry: entry[0])
    return entries


def build(source: str, modes: dict[str, int] | None = None) -> bytes:
    out = bytearray()
    entries = collect(source)
    modes = modes or {}
    for name, mode, data, ino, mtime in entries:
        major, minor = DEVICE_NODES.get(name, (0, 0))[:2]
        if name in modes:
            mode = (mode & 0o170000) | modes[name]
        out += _entry(name, mode, data, ino, mtime, major, minor)
    out += _entry(TRAILER, 0, b"", len(entries) + 1, 0)
    out += b"\0" * ((-len(out)) % 512)
    return bytes(out)


def read(archive: bytes) -> list[tuple[str, int, bytes]]:
    """Parse a newc archive into (name, mode, data). Used by the tests."""
    offset = 0
    result: list[tuple[str, int, bytes]] = []
    while offset + 110 <= len(archive):
        header = archive[offset:offset + 110]
        if header[:6] != b"070701":
            raise ValueError(f"bad cpio magic at offset {offset}")
        values = [int(header[6 + 8 * i: 14 + 8 * i], 16) for i in range(13)]
        mode, filesize, namesize = values[1], values[6], values[11]
        offset += 110
        name = archive[offset:offset + namesize - 1].decode()
        offset += namesize
        offset += (-offset) % 4
        data = archive[offset:offset + filesize]
        offset += filesize
        offset += (-offset) % 4
        if name == TRAILER:
            break
        result.append((name, mode, data))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?")
    parser.add_argument("output", nargs="?")
    parser.add_argument("--gzip", action="store_true", help="gzip the archive (-9)")
    parser.add_argument("--list", metavar="ARCHIVE", help="list entries and exit")
    parser.add_argument("--chmod", action="append", default=[], metavar="NAME:MODE",
                        help="force permissions of an entry (octal), repeatable")
    args = parser.parse_args()

    if args.list:
        with open(args.list, "rb") as handle:
            payload = handle.read()
        if payload[:2] == b"\x1f\x8b":
            payload = gzip.decompress(payload)
        for name, mode, data in read(payload):
            kind = "d" if stat.S_ISDIR(mode) else ("c" if stat.S_ISCHR(mode) else "-")
            print(f"{kind} {mode & 0o7777:04o} {len(data):8d} {name}")
        return 0

    if not args.source or not args.output:
        parser.error("SOURCE and OUTPUT are required unless --list is used")

    modes: dict[str, int] = {}
    for spec in args.chmod:
        name, _, value = spec.rpartition(":")
        if not name or not value:
            parser.error(f"--chmod expects NAME:MODE, got {spec!r}")
        modes[name.strip("/")] = int(value, 8)

    archive = build(args.source, modes)
    payload = gzip.compress(archive, compresslevel=9, mtime=0) if args.gzip else archive
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as handle:
        handle.write(payload)
    print(f"mkcpio: {args.output} {len(payload)} bytes ({len(archive)} raw)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
