#!/usr/bin/env python3
"""Prints the sort experiment's result string from Flash's SharedObject file (hwa_sorttest.sol).

Looks in the default Wine prefix, or pass the .sol path as an argument."""
import glob
import os
import struct
import sys

if len(sys.argv) > 1:
    path = sys.argv[1]
else:
    hits = glob.glob(os.path.expanduser(
        "~/.wine/drive_c/users/*/AppData/Roaming/Macromedia/Flash Player/#SharedObjects/*/**/hwa_sorttest.sol"),
        recursive=True)
    if not hits:
        sys.exit("hwa_sorttest.sol not found; run game/sorttest.exe first, or pass the path")
    path = hits[0]

data = open(path, "rb").read()
i = data.index(b"result") + len(b"result")
if data[i] == 2:  # AMF0 string
    n = struct.unpack(">H", data[i + 1:i + 3])[0]
    s = data[i + 3:i + 3 + n]
else:  # AMF0 long string
    n = struct.unpack(">I", data[i + 1:i + 5])[0]
    s = data[i + 5:i + 5 + n]
sys.stdout.write(s.decode("ascii"))
