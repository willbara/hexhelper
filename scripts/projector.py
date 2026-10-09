#!/usr/bin/env python3
"""Split a Flash projector .exe into the Flash Player stub and the game SWF, or join them back together.

A Flash "projector" is the standalone Flash Player with the game's SWF appended, followed by an 8-byte
trailer: the magic number 0xFA123456 and the SWF's length (both little-endian 32-bit).

  projector.py split GAME.exe STUB_OUT.exe SWF_OUT.swf
  projector.py join  STUB.exe GAME.swf OUT.exe
"""
import struct
import sys

MAGIC = 0xFA123456


def split(exe, stub_out, swf_out):
    data = open(exe, "rb").read()
    magic, length = struct.unpack("<II", data[-8:])
    if magic != MAGIC:
        sys.exit(f"{exe} is not a Flash projector (trailer magic {magic:#x})")
    start = len(data) - 8 - length
    swf = data[start:start + length]
    if swf[:3] not in (b"FWS", b"CWS", b"ZWS"):
        sys.exit("embedded data does not look like a SWF")
    open(stub_out, "wb").write(data[:start])
    open(swf_out, "wb").write(swf)
    print(f"SWF version {swf[3]}, {length} bytes -> {swf_out}")


def join(stub, swf, out):
    s = open(stub, "rb").read()
    w = open(swf, "rb").read()
    open(out, "wb").write(s + w + struct.pack("<II", MAGIC, len(w)))
    print(f"wrote {out}")


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "split":
        split(*sys.argv[2:])
    elif len(sys.argv) == 5 and sys.argv[1] == "join":
        join(*sys.argv[2:])
    else:
        sys.exit(__doc__)
