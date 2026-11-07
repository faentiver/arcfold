# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Fatih (faentiver)
"""Writes selftest.gba, a tiny GBA test program for Arcfold.

The program needs no SDK and no BIOS. It runs in ARM state, uses no BIOS
calls, no interrupts and no stack, and waits for the vertical blank by
polling VCOUNT. Every frame it

- picture: draws in mode 3 (240x160, 15-bit colour) on a background of
  0x2084. An 8-pixel white bar (0x7FFF) in rows 0-111 moves one pixel to
  the right per frame and wraps at x = 232. Three rows of 8x8 blocks show
  numbers, most significant bit on the left, lit blocks in colour, unlit
  blocks in 0x18C6:
    y = 116: boot counter, 8 bits, block i (bit i) at x = 8 + (7 - i) * 16,
             lit colour 0x021F
    y = 128: frame counter, 16 bits, bit i at x = 8 + (15 - i) * 14,
             lit colour 0x03FF
    y = 140: pressed keys as in KEYINPUT (bit 0 = A, 1 = B, 2 = Select,
             3 = Start, 4 = Right, 5 = Left, 6 = Up, 7 = Down, 8 = R, 9 = L),
             10 bits, bit i at x = 8 + (9 - i) * 16, lit colour 0x03E0
  Colours are GBA BGR555 values: bits 0-4 red, 5-9 green, 10-14 blue.
- sound: plays a square wave with 50 % duty on PSG channel 2 at envelope
  volume 10, 131072 / 298 = 439.8 Hz, and 131072 / 149 = 879.7 Hz while A
  is held. The frequency changes without restarting the channel.
- battery save: uses SRAM. The first access is a byte read at 0x0E000000,
  which makes emulators that detect the save type on first use pick SRAM.
  Bytes 0-3 hold the magic "ARCF". At boot the program increments the boot
  counter in byte 4 (1 when the magic is missing, wrapping after 255) and
  clears byte 5. Afterwards byte 5 is a heartbeat: every 64 frames it is
  set to (frame counter / 64) mod 256. Nothing else in SRAM is written.

The header carries no logo; the logo area is zeroed. mGBA recognises the
file by the branch at offset 0 (byte 3 = 0xEA) and the fixed byte 0x96 at
0xB2, and starts it with its built-in BIOS replacement. The game code is
"ZARC" (codes beginning with "F" make mGBA apply special overrides), and
the string "SRAM_V113" tells emulators that scan the ROM which save type to
expect.

Usage: python3 -I make_gba_selftest.py <output.gba>
The output is deterministic; its SHA-256 is listed in Tests/Fixtures/LICENSES.md.
"""

import struct
import sys

ROM_BASE = 0x08000000
CODE_START = 0xC0

COND = {"eq": 0x0, "ne": 0x1, "hs": 0x2, "lo": 0x3, "mi": 0x4, "pl": 0x5,
        "hi": 0x8, "ls": 0x9, "ge": 0xA, "lt": 0xB, "gt": 0xC, "le": 0xD, "al": 0xE}
OPS = {"and": 0x0, "eor": 0x1, "sub": 0x2, "rsb": 0x3, "add": 0x4, "tst": 0x8,
       "cmp": 0xA, "orr": 0xC, "mov": 0xD, "bic": 0xE, "mvn": 0xF}
SHIFT = {"lsl": 0, "lsr": 1, "asr": 2, "ror": 3}
SP, LR, PC = 13, 14, 15


def encode_immediate(value):
    """ARM operand-2 immediate: an 8-bit value rotated right by an even amount."""
    value &= 0xFFFFFFFF
    for rotate in range(16):
        unrotated = ((value << (2 * rotate)) | (value >> (32 - 2 * rotate))) & 0xFFFFFFFF
        if unrotated <= 0xFF:
            return (rotate << 8) | unrotated
    raise ValueError(f"0x{value:08X} is not an ARM immediate")


class Assembler:
    """Just enough of an ARMv4T (ARM state) assembler for this program."""

    def __init__(self, origin):
        self.origin = origin
        self.words = []
        self.labels = {}
        self.fixups = []      # (index, label) of branches
        self.literals = []    # (index, value) of literal loads

    @property
    def here(self):
        return self.origin + 4 * len(self.words)

    def label(self, name):
        assert name not in self.labels, name
        self.labels[name] = self.here

    def emit(self, word):
        self.words.append(word & 0xFFFFFFFF)

    # Data processing. `operand` is an int (immediate) or a register tuple:
    # ("r", rm) / ("r", rm, "lsl", amount) / ("rs", rm, "lsr", rs).
    def dp(self, op, rd, rn, operand, s=False, cond="al"):
        if op in ("tst", "cmp"):
            s, rd = True, 0
        if op in ("mov", "mvn"):
            rn = 0
        word = (COND[cond] << 28) | (OPS[op] << 21) | (int(s) << 20) | (rn << 16) | (rd << 12)
        if isinstance(operand, int):
            word |= (1 << 25) | encode_immediate(operand)
        elif operand[0] == "r":
            word |= operand[1]
            if len(operand) == 4:
                word |= (operand[3] << 7) | (SHIFT[operand[2]] << 5)
        elif operand[0] == "rs":
            word |= (operand[3] << 8) | (SHIFT[operand[2]] << 5) | (1 << 4) | operand[1]
        self.emit(word)

    def mov(self, rd, operand, cond="al"): self.dp("mov", rd, 0, operand, False, cond)
    def add(self, rd, rn, operand): self.dp("add", rd, rn, operand)
    def subs(self, rd, rn, operand): self.dp("sub", rd, rn, operand, True)
    def rsb(self, rd, rn, operand): self.dp("rsb", rd, rn, operand)
    def and_(self, rd, rn, operand): self.dp("and", rd, rn, operand)
    def eor(self, rd, rn, operand): self.dp("eor", rd, rn, operand)
    def cmp(self, rn, operand): self.dp("cmp", 0, rn, operand)
    def tst(self, rn, operand): self.dp("tst", 0, rn, operand)

    def mul(self, rd, rm, rs):
        assert rd != rm, "ARMv4 needs Rd != Rm"
        self.emit((COND["al"] << 28) | (rd << 16) | (rs << 8) | 0x90 | rm)

    def _byte(self, load, rd, rn, offset):
        assert 0 <= offset < 4096
        self.emit((COND["al"] << 28) | (1 << 26) | (1 << 24) | (1 << 23) | (1 << 22)
                  | (int(load) << 20) | (rn << 16) | (rd << 12) | offset)

    def ldrb(self, rd, rn, offset=0): self._byte(True, rd, rn, offset)
    def strb(self, rd, rn, offset=0): self._byte(False, rd, rn, offset)

    def _half(self, load, rd, rn, offset, post=False):
        assert 0 <= offset <= 0xFF
        pre = 0 if post else 1
        self.emit((COND["al"] << 28) | (pre << 24) | (1 << 23) | (1 << 22) | (int(load) << 20)
                  | (rn << 16) | (rd << 12) | ((offset >> 4) << 8) | 0xB0 | (offset & 0xF))

    def ldrh(self, rd, rn, offset=0): self._half(True, rd, rn, offset)
    def strh(self, rd, rn, offset=0): self._half(False, rd, rn, offset)
    def strh_post(self, rd, rn, step): self._half(False, rd, rn, step, post=True)

    def ldr_const(self, rd, value, cond="al"):
        """ldr rd, =value from the literal pool behind the code."""
        self.literals.append((len(self.words), value & 0xFFFFFFFF))
        self.emit((COND[cond] << 28) | (1 << 26) | (1 << 24) | (1 << 20) | (PC << 16) | (rd << 12))

    def b(self, label, cond="al", link=False):
        self.fixups.append((len(self.words), label))
        self.emit((COND[cond] << 28) | (0b101 << 25) | (int(link) << 24))

    def bl(self, label): self.b(label, link=True)
    def ret(self): self.mov(PC, ("r", LR))

    def assemble(self):
        for index, label in self.fixups:
            offset = (self.labels[label] - (self.origin + 4 * index + 8)) >> 2
            self.words[index] |= offset & 0xFFFFFF
        pool = {}
        for index, value in self.literals:
            if value not in pool:
                pool[value] = len(self.words)
                self.words.append(value)
            offset = (pool[value] - index - 2) * 4
            assert 0 <= offset < 4096
            self.words[index] |= offset | (1 << 23)
        return b"".join(struct.pack("<I", word) for word in self.words)


IO, VRAM, SRAM = 0x04000000, 0x06000000, 0x0E000000
BACKGROUND, BAR = 0x2084, 0x7FFF
BIT_OFF, FRAME_ON, BOOT_ON, KEY_ON = 0x18C6, 0x03FF, 0x021F, 0x03E0
TONE_LOW, TONE_HIGH = 2048 - 298, 2048 - 149   # 131072 / 298 = 439.8 Hz, / 149 = 879.7 Hz
PLAYFIELD_HEIGHT, BAR_WIDTH = 112, 8


def program():
    a = Assembler(ROM_BASE + CODE_START)
    r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = range(13)

    a.mov(r12, IO)
    a.mov(r11, VRAM)
    a.ldr_const(r0, 0x0403)                 # DISPCNT: mode 3, BG2 on
    a.strh(r0, r12, 0x00)

    # Sound: master on first, then mixer, bias and channel 2
    a.mov(r0, 0x80)
    a.strh(r0, r12, 0x84)                   # SOUNDCNT_X: master enable
    a.ldr_const(r0, 0x2277)
    a.strh(r0, r12, 0x80)                   # SOUNDCNT_L: ch2 left and right, volume 7/7
    a.mov(r0, 0x02)
    a.strh(r0, r12, 0x82)                   # SOUNDCNT_H: PSG at 100 %
    a.mov(r0, 0x200)
    a.strh(r0, r12, 0x88)                   # SOUNDBIAS: the level the BIOS leaves
    a.ldr_const(r0, 0xA080)
    a.strh(r0, r12, 0x68)                   # SOUND2CNT_L: volume 10, no envelope, 50 % duty
    a.ldr_const(r0, 0x8000 | TONE_LOW)
    a.strh(r0, r12, 0x6C)                   # SOUND2CNT_H: restart at 440 Hz

    # Boot counter in SRAM. The first access is a byte read at 0x0E000000.
    a.mov(r1, SRAM)
    for position, char in enumerate(b"ARCF"):
        a.ldrb(r0, r1, position)
        a.cmp(r0, char)
        a.b("fresh", "ne")
    a.ldrb(r9, r1, 4)
    a.add(r9, r9, 1)
    a.and_(r9, r9, 0xFF)
    a.b("store")
    a.label("fresh")
    for position, char in enumerate(b"ARCF"):
        a.mov(r0, char)
        a.strb(r0, r1, position)
    a.mov(r9, 1)
    a.label("store")
    a.strb(r9, r1, 4)
    a.mov(r0, 0)
    a.strb(r0, r1, 5)                       # heartbeat starts at 0

    # Clear the screen
    a.mov(r0, 0)
    a.mov(r1, 0)
    a.ldr_const(r2, BACKGROUND)
    a.mov(r3, 240)
    a.mov(r5, 160)
    a.bl("rect")

    a.mov(r10, 0)                           # frame counter
    a.mov(SP, 0)                            # bar x; no stack is used, so SP serves as a register
    a.mov(r8, 0)                            # pressed keys

    a.label("frame")
    a.label("wait_out")                     # leave a running vertical blank
    a.ldrh(r0, r12, 0x06)
    a.cmp(r0, 160)
    a.b("wait_out", "hs")
    a.label("wait_in")                      # then wait for the next one to begin
    a.ldrh(r0, r12, 0x06)
    a.cmp(r0, 160)
    a.b("wait_in", "lo")

    a.add(r10, r10, 1)
    a.ldr_const(r0, 0xFFFF)
    a.and_(r10, r10, ("r", r0))             # the frame counter has 16 bits

    # Heartbeat: every 64 frames, byte 5 = frame counter / 64
    a.tst(r10, 63)
    a.b("heartbeat_done", "ne")
    a.mov(r0, ("r", r10, "lsr", 6))
    a.mov(r1, SRAM)
    a.strb(r0, r1, 5)
    a.label("heartbeat_done")

    a.add(r1, r12, 0x100)
    a.ldrh(r0, r1, 0x30)                    # KEYINPUT at 0x04000130, active low
    a.ldr_const(r1, 0x3FF)
    a.and_(r0, r0, ("r", r1))
    a.eor(r8, r0, ("r", r1))                # r8: pressed keys, bit 0 = A

    a.tst(r8, 1)
    a.ldr_const(r0, TONE_LOW, "eq")
    a.ldr_const(r0, TONE_HIGH, "ne")
    a.strh(r0, r12, 0x6C)                   # frequency only, no restart

    # Bar: erase at the old position, move one pixel, draw
    a.mov(r0, ("r", SP))
    a.mov(r1, 0)
    a.ldr_const(r2, BACKGROUND)
    a.mov(r3, BAR_WIDTH)
    a.mov(r5, PLAYFIELD_HEIGHT)
    a.bl("rect")
    a.add(SP, SP, 1)
    a.cmp(SP, 240 - BAR_WIDTH)
    a.mov(SP, 0, cond="hs")
    a.mov(r0, ("r", SP))
    a.mov(r1, 0)
    a.ldr_const(r2, BAR)
    a.mov(r3, BAR_WIDTH)
    a.mov(r5, PLAYFIELD_HEIGHT)
    a.bl("rect")

    def bit_row(value, bits, y, dx, on, name):
        # Bit i is drawn at x = 8 + (bits - 1 - i) * dx, most significant bit on the left.
        a.mov(r7, 0)
        a.label(name)
        a.mov(r0, ("rs", value, "lsr", r7))
        a.tst(r0, 1)
        a.ldr_const(r2, on, "ne")
        a.ldr_const(r2, BIT_OFF, "eq")
        a.mov(r4, dx)
        a.mul(r0, r7, r4)
        a.rsb(r0, r0, 8 + (bits - 1) * dx)
        a.mov(r1, y)
        a.mov(r3, 8)
        a.mov(r5, 8)
        a.bl("rect")
        a.add(r7, r7, 1)
        a.cmp(r7, bits)
        a.b(name, "lo")

    bit_row(r9, 8, 116, 16, BOOT_ON, "boot_bits")
    bit_row(r10, 16, 128, 14, FRAME_ON, "frame_bits")
    bit_row(r8, 10, 140, 16, KEY_ON, "key_bits")
    a.b("frame")

    # rect: r0 = x, r1 = y, r2 = colour, r3 = width, r5 = height.
    # Keeps r1-r3, clobbers r0 and r4-r6.
    a.label("rect")
    a.mov(r4, 480)
    a.mul(r6, r1, r4)
    a.add(r6, r6, ("r", r0, "lsl", 1))
    a.add(r6, r6, ("r", r11))
    a.rsb(r4, r3, 240)
    a.mov(r4, ("r", r4, "lsl", 1))
    a.label("rect_row")
    a.mov(r0, ("r", r3))
    a.label("rect_column")
    a.strh_post(r2, r6, 2)
    a.subs(r0, r0, 1)
    a.b("rect_column", "ne")
    a.add(r6, r6, ("r", r4))
    a.subs(r5, r5, 1)
    a.b("rect_row", "ne")
    a.ret()
    return a.assemble()


def header():
    data = bytearray(CODE_START)
    data[0:4] = struct.pack("<I", 0xEA000000 | ((CODE_START - 8) >> 2))   # b 0x080000C0
    # 0x04-0x9F: logo area, left zeroed on purpose
    data[0xA0:0xAC] = b"ARCFOLDTEST\x00"
    data[0xAC:0xB0] = b"ZARC"
    data[0xB0:0xB2] = b"00"
    data[0xB2] = 0x96
    data[0xBD] = (-sum(data[0xA0:0xBD]) - 0x19) & 0xFF                  # header checksum
    return bytes(data)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rom = header() + program() + b"SRAM_V113\x00\x00\x00"
    rom += b"\x00" * (-len(rom) % 16)
    with open(sys.argv[1], "wb") as file:
        file.write(rom)


if __name__ == "__main__":
    main()
