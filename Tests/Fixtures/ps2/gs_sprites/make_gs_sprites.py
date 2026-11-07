# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Fatih (faentiver)
"""Writes gs_sprites.elf, a tiny PS2 test program for Arcfold.

The program needs no SDK and no BIOS. It switches the display to NTSC
640x448, then draws five sprites (a background, three squares and a bar)
through the GIF on every vertical blank and loops forever. Play! presents a frame only when the GS registers changed since
the last vertical blank, so the redraw keeps frames coming for frame-rate
measurements.

Usage: python3 -I make_gs_sprites.py <output.elf>
The output is deterministic; its SHA-256 is listed in Tests/Fixtures/LICENSES.md.
"""

import struct
import sys

LOAD_ADDRESS = 0x00100000
PACKET_ADDRESS = 0x00100400  # GIF packet, 16-byte aligned

ZERO, V1, A0, A1, A2 = 0, 3, 4, 5, 6
T0, T1, T2, T3, T4, T5 = 8, 9, 10, 11, 12, 13


class Assembler:
    """Just enough of a MIPS assembler for straight-line code and loops."""

    def __init__(self, origin):
        self.origin = origin
        self.words = []
        self.labels = {}
        self.fixups = []

    @property
    def here(self):
        return self.origin + 4 * len(self.words)

    def label(self, name):
        self.labels[name] = self.here

    def _i(self, opcode, rs, rt, immediate):
        self.words.append((opcode << 26) | (rs << 21) | (rt << 16) | (immediate & 0xFFFF))

    def addiu(self, rt, rs, value): self._i(0x09, rs, rt, value)
    def andi(self, rt, rs, value): self._i(0x0C, rs, rt, value)
    def ori(self, rt, rs, value): self._i(0x0D, rs, rt, value)
    def lui(self, rt, value): self._i(0x0F, 0, rt, value)
    def lw(self, rt, offset, base): self._i(0x23, base, rt, offset)
    def sw(self, rt, offset, base): self._i(0x2B, base, rt, offset)
    def nop(self): self.words.append(0)
    def syscall(self): self.words.append(0x0000000C)

    def li(self, rt, value):
        upper, lower = (value >> 16) & 0xFFFF, value & 0xFFFF
        if upper:
            self.lui(rt, upper)
            if lower:
                self.ori(rt, rt, lower)
        else:
            self.ori(rt, ZERO, lower)

    def beq(self, rs, rt, label):
        self.fixups.append((len(self.words), "branch", label))
        self._i(0x04, rs, rt, 0)

    def bne(self, rs, rt, label):
        self.fixups.append((len(self.words), "branch", label))
        self._i(0x05, rs, rt, 0)

    def j(self, label):
        self.fixups.append((len(self.words), "jump", label))
        self.words.append(0x02 << 26)

    def assemble(self):
        for index, kind, label in self.fixups:
            target = self.labels[label]
            if kind == "branch":
                offset = (target - (self.origin + 4 * index + 4)) >> 2
                self.words[index] |= offset & 0xFFFF
            else:
                self.words[index] |= (target >> 2) & 0x03FFFFFF
        return struct.pack("<%dI" % len(self.words), *self.words)


def gif_packet():
    """A GIFtag in PACKED mode followed by A+D register writes."""
    def rgbaq(red, green, blue):
        return red | (green << 8) | (blue << 16) | (0x80 << 24) | (0x3F800000 << 32)

    def xyz2(x, y):
        return (x << 4) | ((y << 4) << 16)

    writes = [
        (0x4C, 10 << 16),                    # FRAME_1: FBP 0, FBW 640/64, PSMCT32
        (0x4E, 0x8C | (1 << 32)),            # ZBUF_1: behind the frame buffer, no Z writes
        (0x47, (1 << 16) | (1 << 17)),       # TEST_1: depth test on, ALWAYS
        (0x40, (639 << 16) | (447 << 48)),   # SCISSOR_1: 640x448
        (0x18, 0),                           # XYOFFSET_1
        (0x1A, 1),                           # PRMODECONT: attributes from PRIM
        (0x00, 6),                           # PRIM: sprite
    ]
    sprites = [
        ((0x10, 0x18, 0x40), (0, 0), (640, 448)),     # dark blue background
        ((0xE0, 0x30, 0x30), (64, 64), (224, 224)),   # red square
        ((0x30, 0xC0, 0x50), (240, 64), (400, 224)),  # green square
        ((0x40, 0x70, 0xF0), (416, 64), (576, 224)),  # blue square
        ((0xF0, 0xD0, 0x30), (64, 288), (576, 384)),  # yellow bar
    ]
    for color, top_left, bottom_right in sprites:
        writes.append((0x01, rgbaq(*color)))
        writes.append((0x05, xyz2(*top_left)))
        writes.append((0x05, xyz2(*bottom_right)))

    tag_low = len(writes) | (1 << 15) | (1 << 60)  # NLOOP, EOP, NREG = 1, PACKED
    tag_high = 0xE                                   # REGS[0] = A+D
    packet = struct.pack("<QQ", tag_low, tag_high)
    for register, data in writes:
        packet += struct.pack("<QQ", data, register)
    return packet


def program(quadword_count):
    asm = Assembler(LOAD_ADDRESS)
    # GsSetCrt(interlaced, NTSC, field mode): syscall 2, number in v1.
    asm.addiu(A0, ZERO, 1)
    asm.addiu(A1, ZERO, 2)
    asm.addiu(A2, ZERO, 0)
    asm.addiu(V1, ZERO, 2)
    asm.syscall()
    asm.nop()

    # GS privileged registers at 0x12000000; 64-bit registers take the low
    # word first, the high word commits the value.
    asm.lui(T0, 0x1200)
    asm.li(T1, 0x0000FF25)       # PMODE: read circuit 1, ALP 0xFF
    asm.sw(T1, 0x0000, T0)
    asm.sw(ZERO, 0x0004, T0)
    asm.li(T1, 10 << 9)          # DISPFB1: FBP 0, FBW 640/64, PSMCT32
    asm.sw(T1, 0x0070, T0)
    asm.sw(ZERO, 0x0074, T0)
    asm.li(T1, 636 | (50 << 12) | (3 << 23))  # DISPLAY1: DX, DY, MAGH 3
    asm.sw(T1, 0x0080, T0)
    asm.li(T1, 2559 | (447 << 12))            # DISPLAY1: DW 2559, DH 447
    asm.sw(T1, 0x0084, T0)

    # DMA registers live at 0x1000xxxx; base 0x10010000 keeps the 16-bit
    # signed offsets in range.
    asm.lui(T3, 0x1001)
    asm.li(T1, 1)
    asm.sw(T1, 0xE000 - 0x10000, T3)         # D_CTRL: DMA enable

    asm.label("frame")
    asm.li(T1, 0x0008)
    asm.sw(T1, 0x1000, T0)                   # CSR: clear the VSYNC flag
    asm.li(T4, PACKET_ADDRESS)
    asm.sw(T4, 0xA010 - 0x10000, T3)         # D2_MADR
    asm.li(T5, quadword_count)
    asm.sw(T5, 0xA020 - 0x10000, T3)         # D2_QWC
    asm.li(T5, 0x0101)
    asm.sw(T5, 0xA000 - 0x10000, T3)         # D2_CHCR: from memory, start
    asm.label("wait_dma")
    asm.lw(T5, 0xA000 - 0x10000, T3)
    asm.andi(T5, T5, 0x0100)
    asm.bne(T5, ZERO, "wait_dma")
    asm.nop()
    asm.label("wait_vsync")
    asm.lw(T5, 0x1000, T0)
    asm.andi(T5, T5, 0x0008)
    asm.beq(T5, ZERO, "wait_vsync")
    asm.nop()
    asm.j("frame")
    asm.nop()
    return asm.assemble()


def elf(code, packet):
    segment = bytearray(code)
    segment += bytes(PACKET_ADDRESS - LOAD_ADDRESS - len(segment))
    segment += packet
    header_size, program_header_size = 52, 32
    offset = 0x80
    ident = b"\x7fELF" + bytes([1, 1, 1]) + bytes(9)  # 32-bit, little endian, version 1
    header = ident + struct.pack(
        "<HHIIIIIHHHHHH",
        2,                  # ET_EXEC
        8,                  # EM_MIPS
        1,                  # EV_CURRENT
        LOAD_ADDRESS,       # entry point
        header_size,        # program header offset
        0,                  # no section headers
        0,                  # flags
        header_size,
        program_header_size,
        1,
        40,
        0,
        0,
    )
    program_header = struct.pack(
        "<IIIIIIII",
        1,                  # PT_LOAD
        offset,
        LOAD_ADDRESS,
        LOAD_ADDRESS,
        len(segment),
        len(segment),
        7,                  # read, write, execute
        16,
    )
    image = header + program_header
    image += bytes(offset - len(image))
    return image + bytes(segment)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    packet = gif_packet()
    image = elf(program(len(packet) // 16), packet)
    with open(sys.argv[1], "wb") as output:
        output.write(image)


if __name__ == "__main__":
    main()
