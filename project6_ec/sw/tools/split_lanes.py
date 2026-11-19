#!/usr/bin/env python3
"""Split a flat binary image into four byte-lane .mem files for dbus.v.

dbus.v's data memory is four separate 1024x8 arrays, one per byte lane of
the 32-bit word (lane 0 = bits [7:0] ... lane 3 = bits [31:24]), instead of
one word-wide array with byte-enable writes -- see the storage section in
rtl/ip/dbus.v for why: Quartus 25.1 (Cyclone V) does not infer M10K for a
single array that combines byte-enable writes with $readmemh
initialization, confirmed by standalone quartus_map/quartus_fit synthesis.
Each lane therefore needs its own $readmemh source. This splits the same
padded binary that produces program.mem, byte for byte, little-endian.

Usage: split_lanes.py <input.bin> <output-prefix>
Writes <output-prefix>.lane0.mem .. lane3.mem, one hex byte per line.
"""
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: split_lanes.py <input.bin> <output-prefix>\n")
        sys.exit(1)

    in_path, out_prefix = sys.argv[1], sys.argv[2]

    with open(in_path, "rb") as f:
        data = f.read()

    if len(data) % 4 != 0:
        sys.stderr.write(
            f"split_lanes.py: {in_path} is {len(data)} bytes, not a multiple of 4\n"
        )
        sys.exit(1)

    lanes = [[], [], [], []]
    for word_start in range(0, len(data), 4):
        for lane in range(4):
            lanes[lane].append(data[word_start + lane])

    for lane in range(4):
        with open(f"{out_prefix}.lane{lane}.mem", "w") as f:
            for byte in lanes[lane]:
                f.write(f"{byte:02x}\n")


if __name__ == "__main__":
    main()
