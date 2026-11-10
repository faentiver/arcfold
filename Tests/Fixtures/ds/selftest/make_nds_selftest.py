# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Fatih (faentiver)
"""Writes selftest.nds, a small Nintendo DS test program for Arcfold.

The program needs no SDK and no BIOS. Both CPUs run in ARM state, use no
BIOS calls, no interrupts and no stack, and wait for the vertical blank by
polling VCOUNT. The header has no logo, so the file only starts in emulators
that boot the binaries directly (melonDS with its built-in BIOS replacement).

ARM9 (picture), every frame:
- Engine A shows the top screen, engine B the bottom screen (POWCNT1 bit 15).
  Both draw BG3 as a 256x256 direct-colour bitmap: VRAM A at 0x06000000
  (top), VRAM C at 0x06200000 (bottom). Colours are BGR555 with bit 15 set.
- top screen, background 0x2884: rows of 8x8 blocks, one block per bit, most
  significant bit on the left, bit i of an n-bit row at x = 8 + (n-1-i)*10,
  lit blocks in the row colour, unlit blocks in 0x18C6:
    y =   8  frame counter of the ARM9, 24 bits, 0x03FF
    y =  20  keys, 14 bits: bit 0-9 as KEYINPUT (A, B, Select, Start,
             Right, Left, Up, Down, R, L), 10 = X, 11 = Y, 12 = pen down,
             13 = lid closed; 0x03E0
    y =  32  last touch x in pixels, 8 bits, 0x001F
    y =  44  last touch y in pixels, 8 bits, 0x001F
    y =  56  last raw ADC x, 12 bits, 0x7C1F
    y =  68  last raw ADC y, 12 bits, 0x7C1F
    y =  80  touch counter (pen-down events), 8 bits, 0x021F
    y =  92  boot counter from the save memory, 8 bits, 0x7FE0
    y = 104  status, 8 bits, 0x6318: bit 0 save magic found at boot,
             bit 1 boot record written and read back, bit 2 heartbeat
             written and read back, bit 3 ARM7 running
    y = 116  frame counter of the ARM7, 16 bits, 0x7E10
    y = 128  heartbeat byte last written, 8 bits, 0x5E1F
  and an 8-pixel white bar (0x7FFF) in rows 144-191 that moves one pixel to
  the right per frame and wraps at x = 248.
- bottom screen, background 0x0920: after the first touch, a crosshair at
  the last touched position: row y and column x in white (0x7FFF), the
  crossing pixel (x, y) itself in red (0x001F). The crosshair stays when the
  pen is lifted and moves with the next touch.

ARM7 (input, sound, save), every frame:
- reads EXTKEYIN for X, Y, pen down and the lid; while the pen is down it
  reads the touch controller over SPI (commands 0xD0 for x and 0x90 for y,
  12-bit results) and converts with pixel = raw >> 4, which matches the
  calibration of melonDS's generated firmware (adc = pixel << 4);
- plays a square wave (50 % duty) on PSG channel 8 with timer 0x10000-4761,
  16756991 / 4761 / 8 = 439.95 Hz, and with timer 0x10000-2380,
  16756991 / 2380 / 8 = 880.09 Hz while A is held;
- save memory: the program reads the first six bytes over AUXSPI with the
  EEPROM command 0x03 and two address bytes. Bytes 0-3 hold "ARCF", byte 4
  the boot counter, byte 5 the heartbeat. At boot it increments the boot
  counter (1 when the magic is missing, wrapping after 255), clears the
  heartbeat and writes all six bytes back (WREN 0x06, WRITE 0x02), waits
  for RDSR bit 0 (at most 4096 polls, a card without save memory answers
  0xFF) and reads them back. Every 64 frames of the ARM7 it writes
  (frame / 64) mod 256 to byte 5 and reads it back. Nothing else is written.
- ARM7 to ARM9: words in main RAM at 0x02200000: +0 "A7OK" once the ARM7
  runs, +4 ARM7 frames, +8 EXTKEYIN, +12 touch (x | y << 8 | count << 16 |
  pen << 24 | valid << 25), +16 raw (x | y << 16), +20 save (boot |
  status << 8 | heartbeat << 16).

Header: game code "ZARC" (not in melonDS's ROM list) and the ARM9 binary at
0x4000, so emulators treat the file as a retail card (melonDS: EEPROM with
64 kbit = 8 KiB and two address bytes for unknown codes) and not as
homebrew, which would get no save memory and use DLDI instead. Like a
decrypted dump, the ARM9 binary starts with two words 0xE7FFDEFF (the
secure-area marker); the code follows at +0x10. The logo area is zeroed;
the logo checksum field holds 0xCF56, which melonDS DS requires for
non-homebrew files. ARM9 code loads to 0x02000000 (entry 0x02000010), ARM7
code to 0x03800000.

Usage, from the repository root:
    python3 -I Tests/Fixtures/ds/selftest/make_nds_selftest.py Tests/Fixtures/ds/selftest.nds
The output is deterministic; Tests/Fixtures/LICENSES.md records its SHA-256.
"""

import struct
import sys

COND = {"eq": 0x0, "ne": 0x1, "hs": 0x2, "lo": 0x3, "mi": 0x4, "pl": 0x5,
        "hi": 0x8, "ls": 0x9, "ge": 0xA, "lt": 0xB, "gt": 0xC, "le": 0xD, "al": 0xE}
OPS = {"and": 0x0, "eor": 0x1, "sub": 0x2, "rsb": 0x3, "add": 0x4, "tst": 0x8,
       "teq": 0x9, "cmp": 0xA, "orr": 0xC, "mov": 0xD, "bic": 0xE, "mvn": 0xF}
SHIFT = {"lsl": 0, "lsr": 1, "asr": 2, "ror": 3}
SP, LR, PC = 13, 14, 15
r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = range(13)


def encode_immediate(value):
    """ARM operand-2 immediate: an 8-bit value rotated right by an even amount."""
    value &= 0xFFFFFFFF
    for rotate in range(16):
        unrotated = ((value << (2 * rotate)) | (value >> (32 - 2 * rotate))) & 0xFFFFFFFF
        if unrotated <= 0xFF:
            return (rotate << 8) | unrotated
    raise ValueError(f"0x{value:08X} is not an ARM immediate")


class Assembler:
    """Just enough of an ARMv4T (ARM state) assembler for this program.
    ARMv4T code also runs on the ARMv5TE ARM9."""

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
        if op in ("tst", "teq", "cmp"):
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
    def add(self, rd, rn, operand, cond="al"): self.dp("add", rd, rn, operand, False, cond)
    def sub(self, rd, rn, operand, cond="al"): self.dp("sub", rd, rn, operand, False, cond)
    def subs(self, rd, rn, operand): self.dp("sub", rd, rn, operand, True)
    def rsb(self, rd, rn, operand): self.dp("rsb", rd, rn, operand)
    def and_(self, rd, rn, operand): self.dp("and", rd, rn, operand)
    def orr(self, rd, rn, operand, cond="al"): self.dp("orr", rd, rn, operand, False, cond)
    def eor(self, rd, rn, operand): self.dp("eor", rd, rn, operand)
    def bic(self, rd, rn, operand, cond="al"): self.dp("bic", rd, rn, operand, False, cond)
    def cmp(self, rn, operand, cond="al"): self.dp("cmp", 0, rn, operand, True, cond)
    def tst(self, rn, operand): self.dp("tst", 0, rn, operand)

    def mul(self, rd, rm, rs):
        assert rd != rm, "ARMv4 needs Rd != Rm"
        self.emit((COND["al"] << 28) | (rd << 16) | (rs << 8) | 0x90 | rm)

    def _single(self, load, byte, rd, rn, offset, cond="al"):
        up = 1 if offset >= 0 else 0
        offset = abs(offset)
        assert offset < 4096
        self.emit((COND[cond] << 28) | (1 << 26) | (1 << 24) | (up << 23) | (int(byte) << 22)
                  | (int(load) << 20) | (rn << 16) | (rd << 12) | offset)

    def ldr(self, rd, rn, offset=0, cond="al"): self._single(True, False, rd, rn, offset, cond)
    def str_(self, rd, rn, offset=0, cond="al"): self._single(False, False, rd, rn, offset, cond)
    def ldrb(self, rd, rn, offset=0): self._single(True, True, rd, rn, offset)
    def strb(self, rd, rn, offset=0): self._single(False, True, rd, rn, offset)

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

    def bl(self, label, cond="al"): self.b(label, cond, link=True)
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
            assert 0 <= offset < 4096, "literal out of range"
            self.words[index] |= offset | (1 << 23)
        return b"".join(struct.pack("<I", word) for word in self.words)


IO = 0x04000000
VRAM_TOP, VRAM_BOTTOM = 0x06000000, 0x06200000
SHARED = 0x02200000
VARS9 = 0x02300000
SAVEBUF = 0x0380E000
ARM9_RAM, ARM7_RAM = 0x02000000, 0x03800000
# A decrypted retail dump starts its secure area with two words 0xE7FFDEFF;
# melonDS DS checks for them when it boots without the console's BIOS. The
# ARM9 binary carries them in front of the code, which starts at +0x10.
SECURE_MARKER = struct.pack("<IIII", 0xE7FFDEFF, 0xE7FFDEFF, 0, 0)
ARM9_ENTRY = ARM9_RAM + len(SECURE_MARKER)
ARM9_OFFSET = 0x4000

S_STATE, S_FRAMES, S_KEYS, S_TOUCH, S_RAW, S_SAVE = 0, 4, 8, 12, 16, 20
A7OK = 0x4B4F3741   # "A7OK"

OPAQUE = 0x8000
TOP_BG, BOTTOM_BG = 0x2884, 0x0920
BIT_OFF, BAR = 0x18C6, 0x7FFF
LINE, CENTER = 0x7FFF, 0x001F
BAR_Y, BAR_H, BAR_W = 144, 48, 8

# (y, bits, colour) of the rows on the top screen, in drawing order
ROW_FRAME = (8, 24, 0x03FF)
ROW_KEYS = (20, 14, 0x03E0)
ROW_TOUCH_X = (32, 8, 0x001F)
ROW_TOUCH_Y = (44, 8, 0x001F)
ROW_RAW_X = (56, 12, 0x7C1F)
ROW_RAW_Y = (68, 12, 0x7C1F)
ROW_TOUCHES = (80, 8, 0x021F)
ROW_BOOT = (92, 8, 0x7FE0)
ROW_STATUS = (104, 8, 0x6318)
ROW_A7FRAMES = (116, 16, 0x7E10)
ROW_HEART = (128, 8, 0x5E1F)

TONE_LOW, TONE_HIGH = 0x10000 - 4761, 0x10000 - 2380


def arm9_program():
    a = Assembler(ARM9_ENTRY)

    a.mov(r12, IO)
    a.mov(r0, 0)
    a.str_(r0, r12, 0x208)                  # IME off
    a.add(r1, r12, 0x300)
    a.ldr_const(r0, 0x8203)                 # POWCNT1: LCDs, engines A and B, A on top
    a.strh(r0, r1, 0x04)
    a.add(r1, r12, 0x200)
    a.ldrh(r0, r1, 0x04)
    a.orr(r0, r0, 0x0800)
    a.strh(r0, r1, 0x04)                    # EXMEMCNT: NDS slot (save memory) to the ARM7
    a.mov(r0, 0x81)
    a.strb(r0, r1, 0x40)                    # VRAMCNT_A: main BG at 0x06000000
    a.mov(r0, 0x84)
    a.strb(r0, r1, 0x42)                    # VRAMCNT_C: sub BG at 0x06200000
    for base in (0x0000, 0x1000):           # engine A, then engine B
        a.add(r1, r12, base) if base else a.mov(r1, ("r", r12))
        a.ldr_const(r0, 0x00010805)         # DISPCNT: graphics, mode 5, BG3 on
        a.str_(r0, r1, 0x00)
        a.ldr_const(r0, 0x4084)             # BG3CNT: 256x256 direct-colour bitmap
        a.strh(r0, r1, 0x0E)
        a.mov(r0, 0x100)
        a.strh(r0, r1, 0x30)                # BG3PA = 1.0
        a.strh(r0, r1, 0x36)                # BG3PD = 1.0
        a.mov(r0, 0)
        a.strh(r0, r1, 0x32)                # BG3PB
        a.strh(r0, r1, 0x34)                # BG3PC
        a.str_(r0, r1, 0x38)                # BG3X
        a.str_(r0, r1, 0x3C)                # BG3Y

    # Clear both screens
    a.mov(r11, VRAM_TOP)
    a.mov(r0, 0)
    a.mov(r1, 0)
    a.ldr_const(r2, TOP_BG | OPAQUE)
    a.mov(r3, 256)
    a.mov(r5, 192)
    a.bl("rect")
    a.ldr_const(r11, VRAM_BOTTOM)
    a.mov(r0, 0)
    a.mov(r1, 0)
    a.ldr_const(r2, BOTTOM_BG | OPAQUE)
    a.mov(r3, 256)
    a.mov(r5, 192)
    a.bl("rect")

    a.ldr_const(r0, VARS9)
    a.mov(r1, 0)
    a.str_(r1, r0, 0)                       # no crosshair drawn yet
    a.mov(r10, 0)                           # frame counter
    a.mov(SP, 0)                            # bar x; no stack is used, so SP serves as a register

    a.label("frame")
    a.label("wait_out")                     # leave a running vertical blank
    a.ldrh(r0, r12, 0x06)
    a.cmp(r0, 192)
    a.b("wait_out", "hs")
    a.label("wait_in")                      # then wait for the next one to begin
    a.ldrh(r0, r12, 0x06)
    a.cmp(r0, 192)
    a.b("wait_in", "lo")

    a.add(r10, r10, 1)
    a.bic(r10, r10, 0xFF000000)             # the frame counter has 24 bits

    # Crosshair on the bottom screen
    a.ldr_const(r11, VRAM_BOTTOM)
    a.ldr_const(r0, SHARED)
    a.ldr(r9, r0, S_TOUCH)
    a.tst(r9, 1 << 25)
    a.b("cross_done", "eq")                 # never touched
    a.ldr_const(r0, VARS9)
    a.ldr(r8, r0, 0)                        # old crosshair: x | y << 8 | drawn << 16
    a.ldr_const(r0, 0xFFFF)
    a.and_(r1, r9, ("r", r0))
    a.orr(r1, r1, 0x10000)                  # new crosshair in the same form
    a.cmp(r8, ("r", r1))
    a.b("cross_done", "eq")                 # unchanged
    a.tst(r8, 0x10000)
    a.b("cross_draw", "eq")                 # nothing to erase
    a.ldr_const(r2, BOTTOM_BG | OPAQUE)     # erase: row and column of the old position
    a.mov(r0, 0)
    a.mov(r1, ("r", r8, "lsr", 8))
    a.and_(r1, r1, 0xFF)
    a.mov(r3, 256)
    a.mov(r5, 1)
    a.bl("rect")
    a.and_(r0, r8, 0xFF)
    a.mov(r1, 0)
    a.mov(r3, 1)
    a.mov(r5, 192)
    a.bl("rect")
    a.label("cross_draw")
    a.ldr_const(r2, LINE | OPAQUE)
    a.mov(r0, 0)
    a.mov(r1, ("r", r9, "lsr", 8))
    a.and_(r1, r1, 0xFF)
    a.mov(r3, 256)
    a.mov(r5, 1)
    a.bl("rect")
    a.and_(r0, r9, 0xFF)
    a.mov(r1, 0)
    a.mov(r3, 1)
    a.mov(r5, 192)
    a.bl("rect")
    a.and_(r0, r9, 0xFF)
    a.mov(r1, ("r", r9, "lsr", 8))
    a.and_(r1, r1, 0xFF)
    a.ldr_const(r2, CENTER | OPAQUE)
    a.mov(r3, 1)
    a.mov(r5, 1)
    a.bl("rect")
    a.ldr_const(r0, 0xFFFF)
    a.and_(r1, r9, ("r", r0))
    a.orr(r1, r1, 0x10000)
    a.ldr_const(r0, VARS9)
    a.str_(r1, r0, 0)
    a.label("cross_done")

    # Top screen
    a.mov(r11, VRAM_TOP)

    # Bar: erase at the old position, move one pixel, draw
    a.mov(r0, ("r", SP))
    a.mov(r1, BAR_Y)
    a.ldr_const(r2, TOP_BG | OPAQUE)
    a.mov(r3, BAR_W)
    a.mov(r5, BAR_H)
    a.bl("rect")
    a.add(SP, SP, 1)
    a.cmp(SP, 256 - BAR_W)
    a.mov(SP, 0, cond="hs")
    a.mov(r0, ("r", SP))
    a.mov(r1, BAR_Y)
    a.ldr_const(r2, BAR | OPAQUE)
    a.mov(r3, BAR_W)
    a.mov(r5, BAR_H)
    a.bl("rect")

    counter = [0]

    def bit_row(row, value):
        # Bit i is drawn at x = 8 + (bits - 1 - i) * 10, most significant bit on the left.
        # value: register; r8 is used for it, r7 counts bits.
        y, bits, on = row
        name = f"row{counter[0]}"
        counter[0] += 1
        if value != r8:
            a.mov(r8, ("r", value))
        a.mov(r7, 0)
        a.label(name)
        a.mov(r0, ("rs", r8, "lsr", r7))
        a.tst(r0, 1)
        a.ldr_const(r2, on | OPAQUE, "ne")
        a.ldr_const(r2, BIT_OFF | OPAQUE, "eq")
        a.mov(r4, 10)
        a.mul(r0, r7, r4)
        a.rsb(r0, r0, 8 + (bits - 1) * 10)
        a.mov(r1, y)
        a.mov(r3, 8)
        a.mov(r5, 8)
        a.bl("rect")
        a.add(r7, r7, 1)
        a.cmp(r7, bits)
        a.b(name, "lo")

    bit_row(ROW_FRAME, r10)

    # Keys: KEYINPUT bits 0-9, EXTKEYIN X, Y, pen, lid; all active low except the lid
    a.ldr_const(r0, SHARED)
    a.ldr(r6, r0, S_KEYS)                   # EXTKEYIN as the ARM7 saw it
    a.add(r1, r12, 0x100)
    a.ldrh(r9, r1, 0x30)                    # KEYINPUT
    a.ldr_const(r1, 0x3FF)
    a.and_(r9, r9, ("r", r1))
    a.eor(r9, r9, ("r", r1))                # pressed = 1
    a.and_(r0, r6, 0x03)                    # X, Y (active low)
    a.eor(r0, r0, 0x03)
    a.orr(r9, r9, ("r", r0, "lsl", 10))
    a.tst(r6, 0x40)                         # pen: 0 = down
    a.orr(r9, r9, 1 << 12, cond="eq")
    a.tst(r6, 0x80)                         # lid: 1 = closed
    a.orr(r9, r9, 1 << 13, cond="ne")
    bit_row(ROW_KEYS, r9)

    # rect clobbers r4-r6, so every row reloads its shared word
    def shared(reg, offset):
        a.ldr_const(r0, SHARED)
        a.ldr(reg, r0, offset)

    shared(r9, S_TOUCH)
    a.and_(r8, r9, 0xFF)
    bit_row(ROW_TOUCH_X, r8)
    shared(r9, S_TOUCH)
    a.mov(r8, ("r", r9, "lsr", 8))
    a.and_(r8, r8, 0xFF)
    bit_row(ROW_TOUCH_Y, r8)
    shared(r9, S_RAW)
    a.ldr_const(r0, 0xFFF)
    a.and_(r8, r9, ("r", r0))
    bit_row(ROW_RAW_X, r8)
    shared(r9, S_RAW)
    a.mov(r8, ("r", r9, "lsr", 16))
    a.ldr_const(r0, 0xFFF)
    a.and_(r8, r8, ("r", r0))
    bit_row(ROW_RAW_Y, r8)
    shared(r9, S_TOUCH)
    a.mov(r8, ("r", r9, "lsr", 16))
    a.and_(r8, r8, 0xFF)
    bit_row(ROW_TOUCHES, r8)
    shared(r9, S_SAVE)
    a.and_(r8, r9, 0xFF)
    bit_row(ROW_BOOT, r8)
    shared(r9, S_SAVE)
    a.mov(r8, ("r", r9, "lsr", 8))
    a.and_(r8, r8, 0x07)
    shared(r9, S_STATE)
    a.ldr_const(r1, A7OK)
    a.cmp(r9, ("r", r1))
    a.orr(r8, r8, 0x08, cond="eq")
    bit_row(ROW_STATUS, r8)
    shared(r9, S_FRAMES)
    a.ldr_const(r0, 0xFFFF)
    a.and_(r8, r9, ("r", r0))
    bit_row(ROW_A7FRAMES, r8)
    shared(r9, S_SAVE)
    a.mov(r8, ("r", r9, "lsr", 16))
    a.and_(r8, r8, 0xFF)
    bit_row(ROW_HEART, r8)
    a.b("frame")

    # rect: r0 = x, r1 = y, r2 = colour, r3 = width, r5 = height, r11 = bitmap.
    # Keeps r1-r3, clobbers r0 and r4-r6.
    a.label("rect")
    a.mov(r4, 512)
    a.mul(r6, r1, r4)
    a.add(r6, r6, ("r", r0, "lsl", 1))
    a.add(r6, r6, ("r", r11))
    a.rsb(r4, r3, 256)
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


def arm7_program():
    a = Assembler(ARM7_RAM)

    a.mov(r12, IO)
    a.mov(r0, 0)
    a.str_(r0, r12, 0x208)                  # IME off
    a.add(r11, r12, 0x100)                  # r11: 0x04000100 for KEYINPUT, SPI and AUXSPI

    # Sound: speakers on, master on, bias, channel 8 as PSG square wave
    a.add(r1, r12, 0x300)
    a.mov(r0, 1)
    a.strh(r0, r1, 0x04)                    # POWCNT2: speakers
    a.add(r1, r12, 0x500)
    a.ldr_const(r0, 0x807F)
    a.strh(r0, r1, 0x00)                    # SOUNDCNT: master enable, volume 127
    a.mov(r0, 0x200)
    a.strh(r0, r1, 0x04)                    # SOUNDBIAS
    a.add(r1, r12, 0x400)
    a.ldr_const(r0, TONE_LOW)
    a.strh(r0, r1, 0x88)                    # SOUND8TMR
    a.ldr_const(r0, 0xE3400040)             # start, PSG, duty 4/8, centre, volume 64
    a.str_(r0, r1, 0x80)                    # SOUND8CNT

    # Shared words start at zero
    a.ldr_const(r10, SHARED)
    a.mov(r0, 0)
    for offset in (S_STATE, S_FRAMES, S_KEYS, S_TOUCH, S_RAW, S_SAVE):
        a.str_(r0, r10, offset)

    # Save memory: read bytes 0-5, update the boot record, write, read back
    a.ldr_const(r9, SAVEBUF)
    a.bl("save_read6")
    a.mov(r8, 0)                            # status bits
    for position, char in enumerate(b"ARCF"):
        a.ldrb(r0, r9, position)
        a.cmp(r0, char)
        a.b("fresh", "ne")
    a.orr(r8, r8, 0x01)                     # magic found
    a.ldrb(r7, r9, 4)
    a.add(r7, r7, 1)
    a.and_(r7, r7, 0xFF)
    a.b("store")
    a.label("fresh")
    a.mov(r7, 1)
    a.label("store")
    for position, char in enumerate(b"ARCF"):
        a.mov(r0, char)
        a.strb(r0, r9, 8 + position)        # what to write: SAVEBUF + 8
    a.strb(r7, r9, 12)
    a.mov(r0, 0)
    a.strb(r0, r9, 13)
    a.bl("save_write6")
    a.bl("save_read6")
    a.mov(r6, 0)                            # compare SAVEBUF + 0..5 with + 8..13
    a.label("verify_boot")
    a.add(r1, r9, ("r", r6))
    a.ldrb(r0, r1, 0)
    a.ldrb(r2, r1, 8)
    a.cmp(r0, ("r", r2))
    a.b("verify_boot_done", "ne")
    a.add(r6, r6, 1)
    a.cmp(r6, 6)
    a.b("verify_boot", "lo")
    a.orr(r8, r8, 0x02)                     # boot record verified
    a.label("verify_boot_done")
    a.orr(r0, r7, ("r", r8, "lsl", 8))      # boot | status << 8, heartbeat 0
    a.str_(r0, r10, S_SAVE)
    a.ldr_const(r0, A7OK)
    a.str_(r0, r10, S_STATE)

    a.mov(SP, 0)                            # ARM7 frame counter (SP serves as a register)
    a.mov(r5, 0)                            # touch: x | y << 8 | count << 16 | pen << 24 | valid << 25
    a.mov(r4, 0)                            # 1 while A was held last frame

    a.label("frame")
    a.label("wait_out")
    a.ldrh(r0, r12, 0x06)
    a.cmp(r0, 192)
    a.b("wait_out", "hs")
    a.label("wait_in")
    a.ldrh(r0, r12, 0x06)
    a.cmp(r0, 192)
    a.b("wait_in", "lo")

    a.add(SP, SP, 1)
    a.str_(SP, r10, S_FRAMES)

    # Tone: high while A is held, frequency only, no restart
    a.ldrh(r0, r11, 0x30)                   # KEYINPUT
    a.and_(r0, r0, 1)
    a.eor(r0, r0, 1)                        # 1 = A held
    a.cmp(r0, ("r", r4))
    a.b("tone_done", "eq")
    a.mov(r4, ("r", r0))
    a.add(r1, r12, 0x400)
    a.cmp(r4, 0)
    a.ldr_const(r0, TONE_LOW, "eq")
    a.ldr_const(r0, TONE_HIGH, "ne")
    a.strh(r0, r1, 0x88)
    a.label("tone_done")

    # Keys and touch
    a.ldrh(r6, r11, 0x36)                   # EXTKEYIN
    a.str_(r6, r10, S_KEYS)
    a.tst(r6, 0x40)
    a.b("pen_up", "ne")
    a.mov(r0, 0xD0)                         # x, 12 bit, differential
    a.bl("tsc_read")
    a.mov(r7, ("r", r0))
    a.mov(r0, 0x90)                         # y
    a.bl("tsc_read")
    a.orr(r1, r7, ("r", r0, "lsl", 16))
    a.str_(r1, r10, S_RAW)
    a.tst(r5, 1 << 24)                      # pen was up: count a new touch
    a.add(r5, r5, 1 << 16, cond="eq")
    a.ldr_const(r1, 0x00FF0000)
    a.and_(r5, r5, ("r", r1))               # keep the count, set x, y, pen, valid
    a.mov(r1, ("r", r7, "lsr", 4))
    a.orr(r5, r5, ("r", r1))
    a.mov(r1, ("r", r0, "lsr", 4))
    a.orr(r5, r5, ("r", r1, "lsl", 8))
    a.orr(r5, r5, 3 << 24)
    a.b("touch_done")
    a.label("pen_up")
    a.bic(r5, r5, 1 << 24)
    a.label("touch_done")
    a.str_(r5, r10, S_TOUCH)

    # Heartbeat every 64 frames: byte 5 = (frames / 64) mod 256
    a.tst(SP, 63)
    a.b("frame", "ne")
    a.mov(r7, ("r", SP, "lsr", 6))
    a.and_(r7, r7, 0xFF)
    a.bl("save_write_heart")
    a.bl("save_read6")
    a.ldr(r1, r10, S_SAVE)
    a.ldrb(r0, r9, 5)
    a.cmp(r0, ("r", r7))
    a.orr(r1, r1, 0x0400, cond="eq")        # status bit 2: heartbeat verified
    a.bic(r1, r1, 0x0400, cond="ne")
    a.bic(r1, r1, 0x00FF0000)
    a.orr(r1, r1, ("r", r7, "lsl", 16))
    a.str_(r1, r10, S_SAVE)
    a.b("frame")

    # tsc_read: r0 = command; returns the 12-bit result in r0. Clobbers r1-r3.
    a.label("tsc_read")
    a.ldr_const(r1, 0x8A01)                 # enable, 2 MHz, touch screen, hold
    a.strh(r1, r11, 0xC0)
    a.strh(r0, r11, 0xC2)
    a.label("tsc_wait1")
    a.ldrh(r3, r11, 0xC0)
    a.tst(r3, 0x80)
    a.b("tsc_wait1", "ne")
    a.mov(r0, 0)
    a.strh(r0, r11, 0xC2)
    a.label("tsc_wait2")
    a.ldrh(r3, r11, 0xC0)
    a.tst(r3, 0x80)
    a.b("tsc_wait2", "ne")
    a.ldrh(r2, r11, 0xC2)                   # bits 11-5
    a.ldr_const(r1, 0x8201)                 # last byte: release afterwards
    a.strh(r1, r11, 0xC0)
    a.strh(r0, r11, 0xC2)
    a.label("tsc_wait3")
    a.ldrh(r3, r11, 0xC0)
    a.tst(r3, 0x80)
    a.b("tsc_wait3", "ne")
    a.ldrh(r3, r11, 0xC2)                   # bits 4-0 in bits 7-3
    a.and_(r2, r2, 0x7F)
    a.and_(r3, r3, 0xFF)
    a.mov(r3, ("r", r3, "lsr", 3))
    a.orr(r0, r3, ("r", r2, "lsl", 5))
    a.ret()

    # spi: r0 = byte to send, r1 = AUXSPICNT (0xA040 holds the chip select,
    # 0xA000 releases it after this byte); returns the received byte in r0.
    # Clobbers r3.
    a.label("spi")
    a.strh(r1, r11, 0xA0)
    a.strb(r0, r11, 0xA2)
    a.label("spi_wait")
    a.ldrh(r3, r11, 0xA0)
    a.tst(r3, 0x80)
    a.b("spi_wait", "ne")
    a.ldrb(r0, r11, 0xA2)
    a.ret()

    # The routines below call "spi"; they keep their return address in r2.

    # save_read6: reads bytes 0-5 into SAVEBUF + 0..5. Clobbers r0-r3, r6.
    a.label("save_read6")
    a.mov(r2, ("r", LR))
    a.ldr_const(r1, 0xA040)
    a.mov(r0, 0x03)                         # READ
    a.bl("spi")
    a.mov(r0, 0)
    a.bl("spi")                             # address, high byte
    a.mov(r0, 0)
    a.bl("spi")                             # address, low byte
    a.mov(r6, 0)
    a.label("save_read_loop")
    a.cmp(r6, 5)
    a.ldr_const(r1, 0xA000, "eq")           # last byte releases the chip select
    a.mov(r0, 0)
    a.bl("spi")
    a.add(r3, r9, ("r", r6))
    a.strb(r0, r3, 0)
    a.add(r6, r6, 1)
    a.cmp(r6, 6)
    a.b("save_read_loop", "lo")
    a.mov(PC, ("r", r2))

    # save_wait: polls RDSR until the write-in-progress bit clears, at most
    # 4096 times (a card without save memory answers 0xFF). Clobbers r0-r3.
    a.label("save_wait")
    a.mov(r12, ("r", LR))                   # r12 is restored to IO below
    a.mov(r2, 0x1000)
    a.label("save_wait_loop")
    a.ldr_const(r1, 0xA040)
    a.mov(r0, 0x05)                         # RDSR
    a.bl("spi")
    a.ldr_const(r1, 0xA000)
    a.mov(r0, 0)
    a.bl("spi")
    a.subs(r2, r2, 1)
    a.b("save_wait_done", "eq")
    a.tst(r0, 0x01)
    a.b("save_wait_loop", "ne")
    a.label("save_wait_done")
    a.mov(r0, ("r", r12))
    a.mov(r12, IO)
    a.mov(PC, ("r", r0))

    # save_write6: writes SAVEBUF + 8..13 to bytes 0-5. Clobbers r0-r3, r6.
    a.label("save_write6")
    a.mov(r2, ("r", LR))
    a.ldr_const(r1, 0xA000)
    a.mov(r0, 0x06)                         # WREN
    a.bl("spi")
    a.ldr_const(r1, 0xA040)
    a.mov(r0, 0x02)                         # WRITE
    a.bl("spi")
    a.mov(r0, 0)
    a.bl("spi")
    a.mov(r0, 0)
    a.bl("spi")
    a.mov(r6, 0)
    a.label("save_write_loop")
    a.cmp(r6, 5)
    a.ldr_const(r1, 0xA000, "eq")
    a.add(r3, r9, ("r", r6))
    a.ldrb(r0, r3, 8)
    a.bl("spi")
    a.add(r6, r6, 1)
    a.cmp(r6, 6)
    a.b("save_write_loop", "lo")
    a.mov(r6, ("r", r2))
    a.bl("save_wait")
    a.mov(PC, ("r", r6))

    # save_write_heart: writes r7 to byte 5. Clobbers r0-r3, r6.
    a.label("save_write_heart")
    a.mov(r2, ("r", LR))
    a.ldr_const(r1, 0xA000)
    a.mov(r0, 0x06)                         # WREN
    a.bl("spi")
    a.ldr_const(r1, 0xA040)
    a.mov(r0, 0x02)                         # WRITE
    a.bl("spi")
    a.mov(r0, 0)
    a.bl("spi")
    a.mov(r0, 5)
    a.bl("spi")
    a.ldr_const(r1, 0xA000)
    a.mov(r0, ("r", r7))
    a.bl("spi")
    a.mov(r6, ("r", r2))
    a.bl("save_wait")
    a.mov(PC, ("r", r6))
    return a.assemble()


def crc16(data):
    """CRC-16 as the DS uses it (polynomial 0xA001 reflected, start 0xFFFF)."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def build():
    arm9 = SECURE_MARKER + arm9_program()
    arm7 = arm7_program()
    # melonDS encrypts and decrypts the first 0x800 bytes of the ARM9 binary
    # (secure area); the ARM7 binary must lie behind them.
    arm9 += b"\x00" * max(0x800 - len(arm9), -len(arm9) % 0x200)
    arm7 += b"\x00" * (-len(arm7) % 0x200)
    arm9_offset = ARM9_OFFSET
    arm7_offset = arm9_offset + len(arm9)
    total = arm7_offset + len(arm7)

    header = bytearray(0x200)
    header[0x000:0x00C] = b"ARCFOLDTEST\x00"
    header[0x00C:0x010] = b"ZARC"
    header[0x010:0x012] = b"00"
    capacity = 0
    while (0x20000 << capacity) < total:
        capacity += 1
    header[0x014] = capacity                                    # 128 KiB << n
    struct.pack_into("<IIII", header, 0x020, arm9_offset, ARM9_ENTRY, ARM9_RAM, len(arm9))
    struct.pack_into("<IIII", header, 0x030, arm7_offset, ARM7_RAM, ARM7_RAM, len(arm7))
    struct.pack_into("<II", header, 0x060, 0x00586000, 0x001808F8)  # usual ROMCTRL settings
    struct.pack_into("<I", header, 0x080, total)                # used ROM size
    struct.pack_into("<I", header, 0x084, 0x4000)               # header size
    # 0x0C0-0x15B: logo area, left zeroed on purpose. The logo checksum field
    # holds the value cards carry (0xCF56) because melonDS DS refuses
    # non-homebrew files without it (console.cpp, LoadNdsCart); it checks the
    # field, not the logo.
    struct.pack_into("<H", header, 0x15C, 0xCF56)
    struct.pack_into("<H", header, 0x15E, crc16(header[0x000:0x15E]))

    rom = bytearray(header) + b"\x00" * (arm9_offset - len(header)) + arm9 + arm7
    assert len(rom) == total
    return bytes(rom)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], "wb") as file:
        file.write(build())


if __name__ == "__main__":
    main()
