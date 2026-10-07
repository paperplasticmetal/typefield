#!/usr/bin/env python3
"""Independently check Typefield's two-master glyf variation binary.

Run after `TYPEFIELD_VARIABLE_TEST_OUTPUT=/tmp/typefield-variable.ttf
dist/Typefield.app/Contents/MacOS/Typefield --self-test`.
Uses only the Python standard library; the native suite also checks CoreText
rendering and advance interpolation at 400, 550 and 700.
"""

import argparse
import struct
from pathlib import Path


def u16(data, offset):
    return struct.unpack_from(">H", data, offset)[0]


def i16(data, offset):
    return struct.unpack_from(">h", data, offset)[0]


def u32(data, offset):
    return struct.unpack_from(">I", data, offset)[0]


def checksum(data):
    padded = data + b"\0" * ((-len(data)) % 4)
    return sum(struct.unpack(f">{len(padded) // 4}I", padded)) & 0xFFFFFFFF


def tables(font):
    assert u32(font, 0) == 0x00010000
    result = {}
    for index in range(u16(font, 4)):
        record = 12 + 16 * index
        tag = font[record : record + 4].decode("ascii")
        declared_sum, offset, length = struct.unpack_from(">III", font, record + 4)
        assert tag not in result and offset + length <= len(font), tag
        data = font[offset : offset + length]
        checked = data[:8] + b"\0\0\0\0" + data[12:] if tag == "head" else data
        assert checksum(checked) == declared_sum, f"{tag} checksum"
        result[tag] = data
    assert checksum(font) == 0xB1B0AFBA, "whole font checksum"
    return result


def mapped_gid(cmap, scalar):
    for index in range(u16(cmap, 2)):
        record = 4 + 8 * index
        platform, encoding, offset = struct.unpack_from(">HHI", cmap, record)
        if (platform, encoding) != (3, 10) or u16(cmap, offset) != 12:
            continue
        for group in range(u32(cmap, offset + 12)):
            start, end, first_gid = struct.unpack_from(">III", cmap, offset + 16 + 12 * group)
            if start <= scalar <= end:
                return first_gid + scalar - start
    raise AssertionError(f"U+{scalar:04X} missing from format-12 cmap")


def deltas(data, offset, count):
    values = []
    while len(values) < count:
        control = data[offset]
        offset += 1
        run = (control & 0x3F) + 1
        assert len(values) + run <= count
        if control & 0x80:
            assert not control & 0x40
            values.extend([0] * run)
        elif control & 0x40:
            values.extend(struct.unpack_from(f">{run}h", data, offset))
            offset += 2 * run
        else:
            values.extend(struct.unpack_from(f">{run}b", data, offset))
            offset += run
    return values, offset


def point_count(glyf, loca, gid):
    start, end = u32(loca, gid * 4), u32(loca, (gid + 1) * 4)
    if start == end:
        return 0
    contours = i16(glyf, start)
    assert contours >= 0, "Typefield should emit only simple glyphs"
    return u16(glyf, start + 10 + 2 * (contours - 1)) + 1 if contours else 0


def glyph_variation(gvar, gid, point_total):
    count = u16(gvar, 12)
    assert gid < count
    array_offset = u32(gvar, 16)
    start = array_offset + u32(gvar, 20 + 4 * gid)
    end = array_offset + u32(gvar, 24 + 4 * gid)
    if start == end:
        return None
    assert 0 <= start < end <= len(gvar)
    assert u16(gvar, start) == 1, "one tuple at the upper endpoint"
    data_offset = u16(gvar, start + 2)
    data_size = u16(gvar, start + 4)
    assert u16(gvar, start + 6) == 0xA000, "embedded peak + private points"
    assert i16(gvar, start + 8) == 0x4000, "normalized peak +1"
    pos = start + data_offset
    assert gvar[pos] == 0, "zero packed-point count means all points"
    pos += 1
    x, pos = deltas(gvar, pos, point_total + 4)
    y, pos = deltas(gvar, pos, point_total + 4)
    assert pos == start + data_offset + data_size, "tuple payload size"
    assert pos <= end
    return x, y


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("font", type=Path)
    args = parser.parse_args()
    font = args.font.read_bytes()
    table = tables(font)
    assert {"fvar", "STAT", "gvar", "glyf", "loca", "hmtx", "cmap", "head", "maxp", "name"} <= table.keys()
    assert u16(table["head"], 16) & 2, "variable LSB must equal glyf xMin"

    fvar, stat, gvar = table["fvar"], table["STAT"], table["gvar"]
    assert (u16(fvar, 0), u16(fvar, 2), u16(fvar, 4), u16(fvar, 8), u16(fvar, 12)) == (1, 0, 16, 1, 2)
    assert fvar[16:20] == b"wght"
    assert [u32(fvar, 20 + 4 * index) >> 16 for index in range(3)] == [400, 400, 700]
    assert (u16(fvar, 34), u16(fvar, 36), u16(fvar, 44)) == (256, 257, 258)
    assert (u16(stat, 0), u16(stat, 2), u16(stat, 6), u16(stat, 12)) == (1, 2, 1, 2)
    assert stat[20:24] == b"wght" and u16(stat, 24) == 256
    assert (u16(gvar, 0), u16(gvar, 2), u16(gvar, 4), u16(gvar, 12)) == (1, 0, 1, u16(table["maxp"], 4))
    assert u16(gvar, 14) == 1, "long gvar offsets"

    a = mapped_gid(table["cmap"], ord("A"))
    o = mapped_gid(table["cmap"], ord("O"))
    a_x, a_y = glyph_variation(gvar, a, point_count(table["glyf"], table["loca"], a))
    o_x, o_y = glyph_variation(gvar, o, point_count(table["glyf"], table["loca"], o))
    assert any(a_x[:-4]) and any(o_x[:-4]), "both glyph outlines must vary"
    assert a_x[-4:] == [0, 70, 0, 0] and a_y[-4:] == [0, 0, 0, 0], "A advance phantom delta"
    assert o_x[-4:] == [0, 0, 0, 0] and o_y[-4:] == [0, 0, 0, 0], "O metrics stay fixed"
    print(f"PASS: sfnt checksums, fvar/STAT/gvar alignment, A/O contours and A +70-unit advance; {len(font)} bytes")


if __name__ == "__main__":
    main()
