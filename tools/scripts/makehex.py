#!/usr/bin/env python3
#
# Copied verbatim from the PicoRV32 v1.0 distribution
# (picorv32-1.0/firmware/makehex.py) -- converts a raw binary firmware
# image into a $readmemh-compatible hex file (one 32-bit little-endian
# word per line, hex-encoded, zero-padded out to the requested word
# count) for RTL simulation / BRAM initialization.
#
# This is free and unencumbered software released into the public domain.

from sys import argv

binfile = argv[1]
nwords = int(argv[2])

with open(binfile, "rb") as f:
    bindata = f.read()

assert len(bindata) < 4 * nwords
assert len(bindata) % 4 == 0

for i in range(nwords):
    if i < len(bindata) // 4:
        w = bindata[4*i : 4*i+4]
        print("%02x%02x%02x%02x" % (w[3], w[2], w[1], w[0]))
    else:
        print("0")
