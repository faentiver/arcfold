@testable import Arcfold
import Foundation
import LibretroKit
import Synchronization
import Testing

// Helpers for the tests with melonDS DS and selftest.nds (ADR 0006, section 14).

extension SessionFolder {
    /// The session for `selftest.nds` from the test bundle, or for `game`, with
    /// melonDS DS from the app bundle, configured like the app's `GameSystem.ds`:
    /// core options, a save memory filled with 0xFF and the check for the
    /// core's error screen. Only the clock of the emulated console starts at a
    /// fixed time, so that the pictures do not depend on the time of day.
    ///
    /// - Parameter fillsBlankSaveMemory: False leaves a new save memory as the
    ///   core made it, to show what the fill changes.
    func dsConfiguration(
        pacing: Pacing = .unthrottled, game: URL? = nil, fillsBlankSaveMemory: Bool = true
    ) throws -> SessionConfiguration {
        let system = GameSystem.ds
        var options = system.coreOptions
        options["melonds_start_time_mode"] = "absolute"
        return SessionConfiguration(
            coreName: system.coreName,
            game: try game ?? Fixture.dsSelftest.url(),
            batterySave: batterySave,
            systemDirectory: systemDirectory,
            saveDirectory: url,
            coreOptions: options,
            pacing: pacing,
            blankSaveMemoryByte: fillsBlankSaveMemory ? system.blankSaveMemoryByte : nil,
            requiresSystemMemory: system.requiresSystemMemory
        )
    }
}

/// Variants of `selftest.nds` with single header fields changed, made at
/// run time and never kept as files in the repository. `NDSHeaderTests` and
/// the tests with the core use the same variants, so that the import check
/// and melonDS DS judge identical files.
enum DSVariant: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// The test program unchanged.
    case selftest
    /// The secure area no longer starts with the marker of a decrypted dump.
    case encrypted
    /// Encrypted dumps repeat the marker 16 bytes later.
    case markerRepeated = "marker-repeated"
    /// Game code "####", no logo checksum, no marker. The ARM9 binary stays at
    /// 0x4000 with its entry 16 bytes in.
    case homebrew
    /// Game code "####" and no logo checksum; the marker stays.
    case homebrewWithMarker = "homebrew-with-marker"
    /// The ARM9 binary copied to 0x200, right behind the header, without the
    /// marker; game code and everything else unchanged, no logo checksum.
    case homebrewBelow0x4000 = "homebrew-below-0x4000"
    case withoutLogoChecksum = "without-logo-checksum"
    /// ARM9 entry 0x023BFE04, just above the range melonDS DS accepts.
    case arm9EntryTooHigh = "arm9-entry-too-high"
    /// The ARM9 binary at 1 MiB, far behind the end of the file.
    case arm9BehindTheFile = "arm9-behind-the-file"
    /// An ARM9 binary of 1 MiB at 0x4000: larger than the file, even padded
    /// to the next power of two as melonDS pads it.
    case arm9LargerThanTheFile = "arm9-larger-than-the-file"
    /// The ARM7 binary at 0x7000, in the zeros melonDS pads the 19 456-byte
    /// file with up to 32 KiB.
    case arm7InThePadding = "arm7-in-the-padding"
    /// Unit code 3 (DSi only) without the modcrypt flag of retail DSi titles.
    case dsiOnlyHomebrew = "dsi-only-homebrew"
    /// Unit code 3 with the modcrypt flag (bit 1 at 0x1C) and a real game code.
    case dsiOnlyRetail = "dsi-only-retail"
    /// A DSi unit code with the DSiWare title ID, without the modcrypt flag.
    case dsiWareHomebrew = "dsiware-homebrew"
    /// A DSi unit code, the DSiWare title ID and the modcrypt flag.
    case dsiWareRetail = "dsiware-retail"
    /// Unit code 2: DSi-enhanced, runs on a DS.
    case dsiEnhanced = "dsi-enhanced"
    /// One byte shorter than the 4 KiB header.
    case tooShort = "too-short"

    var testDescription: String { rawValue }

    /// `selftest.nds` changed this way.
    func apply(to data: Data) -> Data {
        switch self {
        case .selftest:
            data
        case .encrypted:
            Self.patched(data, [(0x4000, [0, 0, 0, 0])])
        case .markerRepeated:
            Self.patched(data, [(0x4010, Self.word(0xE7FF_DEFF))])
        case .homebrew:
            Self.patched(data, [(0x0C, Array("####".utf8)), (0x15C, [0, 0]), (0x4000, [0, 0, 0, 0])])
        case .homebrewWithMarker:
            Self.patched(data, [(0x0C, Array("####".utf8)), (0x15C, [0, 0])])
        case .homebrewBelow0x4000:
            Self.patched(data, [(0x20, Self.word(0x200)), (0x15C, [0, 0]), (0x200, Self.arm9WithoutMarker(of: data))])
        case .withoutLogoChecksum:
            Self.patched(data, [(0x15C, [0, 0])])
        case .arm9EntryTooHigh:
            Self.patched(data, [(0x24, Self.word(0x023B_FE04))])
        case .arm9BehindTheFile:
            Self.patched(data, [(0x20, Self.word(0x10_0000))])
        case .arm9LargerThanTheFile:
            Self.patched(data, [(0x2C, Self.word(0x10_0000))])
        case .arm7InThePadding:
            Self.patched(data, [(0x30, Self.word(0x7000))])
        case .dsiOnlyHomebrew:
            Self.patched(data, [(0x12, [0x03])])
        case .dsiOnlyRetail:
            Self.patched(data, [(0x12, [0x03]), (0x1C, [0x02])])
        case .dsiWareHomebrew:
            Self.patched(data, [(0x12, [0x02]), (0x234, Self.word(0x0003_0004))])
        case .dsiWareRetail:
            Self.patched(data, [(0x12, [0x02]), (0x234, Self.word(0x0003_0004)), (0x1C, [0x02])])
        case .dsiEnhanced:
            Self.patched(data, [(0x12, [0x02])])
        case .tooShort:
            data.prefix(0x0FFF)
        }
    }

    /// The variant as a file in `folder`, named after the variant.
    func file(in folder: SessionFolder) throws -> URL {
        let file = folder.url.appending(path: rawValue + ".nds")
        try apply(to: Data(contentsOf: Fixture.dsSelftest.url())).write(to: file)
        return file
    }

    private static func patched(_ data: Data, _ patches: [(offset: Int, bytes: [UInt8])]) -> Data {
        var data = data
        for patch in patches {
            let start = data.startIndex + patch.offset
            data.replaceSubrange(start ..< start + patch.bytes.count, with: patch.bytes)
        }
        return data
    }

    /// The ARM9 binary of the test program, 0x800 bytes at 0x4000, with the
    /// two marker words zeroed. Behind the header there are zeros up to 0x4000.
    private static func arm9WithoutMarker(of data: Data) -> [UInt8] {
        let start = data.startIndex
        return [UInt8](repeating: 0, count: 8) + data[start + 0x4008 ..< start + 0x4800]
    }

    /// A little-endian 32-bit word.
    private static func word(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }
}

/// Keeps the visible pixels of the newest picture, so that a test can look at
/// the screen after every step without keeping every frame.
final class LatestPicture: VideoSink {
    private struct State {
        var pixels: [UInt8] = []
        var width = 0
        var height = 0
    }

    private let state = Mutex(State())

    /// The newest picture of `selftest.nds`; nil before the first one.
    var picture: DSSelftestPicture? {
        state.withLock { state in
            state.pixels.isEmpty ? nil : DSSelftestPicture(width: state.width, height: state.height, pixels: state.pixels)
        }
    }

    func submit(pixels: RawSpan, width: Int, height: Int, bytesPerRow: Int, format: PixelFormat, stamp: FrameStamp) {
        let rowBytes = width * format.bytesPerPixel
        state.withLock { state in
            if state.pixels.count != rowBytes * height {
                state.pixels = [UInt8](repeating: 0, count: rowBytes * height)
            }
            pixels.withUnsafeBytes { source in
                state.pixels.withUnsafeMutableBytes { destination in
                    for row in 0..<height {
                        let from = UnsafeRawBufferPointer(rebasing: source[row * bytesPerRow ..< row * bytesPerRow + rowBytes])
                        UnsafeMutableRawBufferPointer(rebasing: destination[row * rowBytes ..< (row + 1) * rowBytes])
                            .copyMemory(from: from)
                    }
                }
            }
            state.width = width
            state.height = height
        }
    }
}

/// A pixel position on one DS screen.
struct DSPixel: Hashable, CustomStringConvertible {
    var x: Int
    var y: Int

    var description: String { "(\(x), \(y))" }

    /// The libretro pointer aimed at the centre of this pixel of the touch
    /// screen, which is the lower half of melonDS DS's 256 × 384 picture.
    var pointerOnTouchScreen: PointerPosition {
        PointerPosition(
            pixelX: x, pixelY: DSSelftestPicture.screenHeight + y,
            frameWidth: DSSelftestPicture.width, frameHeight: DSSelftestPicture.height
        )
    }
}

/// A picture of `selftest.nds` as melonDS DS delivers it: 256 × 384 pixels
/// XRGB8888 without row padding, bytes blue, green, red, unused; the top
/// screen in rows 0–191, the touch screen in rows 192–383. The layout is
/// described in `Tests/Fixtures/ds/selftest/make_nds_selftest.py`.
struct DSSelftestPicture: Sendable {
    static let width = 256
    static let height = 384
    static let screenHeight = 192

    /// An 8-bit colour as the picture holds it.
    struct Color: Hashable, CustomStringConvertible {
        var red: UInt8
        var green: UInt8
        var blue: UInt8

        /// A DS colour, BGR555 with red in the low bits, the way melonDS DS
        /// shows it: melonDS widens each channel to 6 bits (c · 2), melonDS DS
        /// to 8 bits (4 · c6 + c6 / 16). 31 becomes 251, not 255.
        init(bgr555: UInt16) {
            func channel(_ value: UInt16) -> UInt8 {
                let six = (value & 31) * 2
                return UInt8(4 * six + six / 16)
            }
            red = channel(bgr555)
            green = channel(bgr555 >> 5)
            blue = channel(bgr555 >> 10)
        }

        init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var description: String { "(\(red), \(green), \(blue))" }

        /// A block whose bit is 0.
        static let unlit = Color(bgr555: 0x18C6)
        /// Row and column of the crosshair, white.
        static let crosshairLine = Color(bgr555: 0x7FFF)
        /// The crossing point of the crosshair, red.
        static let crosshairCentre = Color(bgr555: 0x001F)
    }

    let width: Int
    let height: Int
    /// The visible pixels row by row.
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(_ picture: SelftestPicture) {
        self.init(width: picture.width, height: picture.height, pixels: picture.pixels)
    }

    /// Whether the picture has the size of both screens one above the other.
    var hasBothScreens: Bool {
        width == Self.width && height == Self.height && pixels.count == width * height * 4
    }

    /// The colour at (x, y) of the whole picture.
    func color(x: Int, y: Int) -> Color {
        let index = (y * width + x) * 4
        return Color(red: pixels[index + 2], green: pixels[index + 1], blue: pixels[index])
    }

    // The rows of 8 × 8 blocks on the top screen.

    /// Frames of the ARM9 since it started; frame number − 7 in melonDS DS.
    var arm9Frames: Int? { number(row: 8, bits: 24, lit: 0x03FF) }
    /// Bits 0–9 as KEYINPUT (A, B, Select, Start, Right, Left, Up, Down, R,
    /// L), 10 X, 11 Y, 12 pen down, 13 lid closed.
    var keys: Int? { number(row: 20, bits: 14, lit: 0x03E0) }
    /// The last touched pixel, as the program computed it from the raw values.
    var touchX: Int? { number(row: 32, bits: 8, lit: 0x001F) }
    var touchY: Int? { number(row: 44, bits: 8, lit: 0x001F) }
    /// The last 12-bit values of the touch controller; pixel · 16 with the
    /// calibration of melonDS's generated firmware.
    var rawX: Int? { number(row: 56, bits: 12, lit: 0x7C1F) }
    var rawY: Int? { number(row: 68, bits: 12, lit: 0x7C1F) }
    /// Pen-down events, modulo 256.
    var touchCount: Int? { number(row: 80, bits: 8, lit: 0x021F) }
    /// The boot counter from the save memory: 1 after the first start.
    var bootCounter: Int? { number(row: 92, bits: 8, lit: 0x7FE0) }
    /// Bit 0 save magic found at boot, bit 1 boot record written and read
    /// back, bit 2 heartbeat written and read back, bit 3 ARM7 running.
    var status: Int? { number(row: 104, bits: 8, lit: 0x6318) }
    /// Frames of the ARM7; frame number − 1 in melonDS DS.
    var arm7Frames: Int? { number(row: 116, bits: 16, lit: 0x7E10) }
    /// The heartbeat byte last written to the save memory.
    var heartbeat: Int? { number(row: 128, bits: 8, lit: 0x5E1F) }

    /// What the blocks and the crosshair show about the last touch, for messages.
    var touchSummary: String {
        func text(_ value: Int?) -> String { value.map(String.init) ?? "?" }
        return "touch (\(text(touchX)), \(text(touchY))), raw (\(text(rawX)), \(text(rawY))), "
            + "count \(text(touchCount)), crosshair \(crosshair?.description ?? "none")"
    }

    /// Reads a row of 8 × 8 blocks at `y` from the centre of each block: bit i
    /// of an n-bit number at x = 8 + (n − 1 − i) · 10, most significant bit on
    /// the left. Nil unless every block is exactly lit or unlit.
    private func number(row y: Int, bits: Int, lit: UInt16) -> Int? {
        let on = Color(bgr555: lit)
        var value = 0
        for bit in 0..<bits {
            let x = 8 + (bits - 1 - bit) * 10
            switch color(x: x + 4, y: y + 4) {
            case on: value |= 1 << bit
            case .unlit: break
            default: return nil
            }
        }
        return value
    }

    /// The crosshair on the touch screen: the only red pixel, whose row and
    /// column are white everywhere else. Nil if there is no red pixel, more
    /// than one, or a line is incomplete.
    var crosshair: DSPixel? {
        let red = Self.word(Color.crosshairCentre)
        let white = Self.word(Color.crosshairLine)
        return pixels.withUnsafeBytes { raw -> DSPixel? in
            func word(_ x: Int, _ y: Int) -> UInt32 {
                raw.loadUnaligned(fromByteOffset: ((Self.screenHeight + y) * width + x) * 4, as: UInt32.self) & 0x00FF_FFFF
            }
            var found: DSPixel?
            for y in 0..<Self.screenHeight {
                for x in 0..<width where word(x, y) == red {
                    guard found == nil else { return nil }
                    found = DSPixel(x: x, y: y)
                }
            }
            guard let found else { return nil }
            for x in 0..<width where x != found.x && word(x, found.y) != white {
                return nil
            }
            for y in 0..<Self.screenHeight where y != found.y && word(found.x, y) != white {
                return nil
            }
            return found
        }
    }

    /// A colour as the low three bytes of a little-endian pixel word.
    private static func word(_ color: Color) -> UInt32 {
        UInt32(color.blue) | UInt32(color.green) << 8 | UInt32(color.red) << 16
    }
}
