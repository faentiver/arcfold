import Foundation

/// The header checks of a DS game file: whether melonDS DS 1.4.0 starts it
/// with melonDS's built-in BIOS, that is without BIOS files, in DS mode
/// (ADR 0006).
///
/// The rules follow melonDS DS and melonDS in the order the core applies
/// them: the refusal of DSi titles in DS mode (`CreateConsole`,
/// `RequiresDSi`, `IsRetailDSiTitle` in `src/libretro/config/console.cpp`),
/// the entry point and the logo checksum (`LoadNdsCart`), the position of
/// both binaries (`ValidateROM` in melonDS) and the check for encrypted
/// games. Given an encrypted game or a retail DSi title, melonDS DS does not
/// fail but shows an English error screen; the import refuses such files
/// with an explanation instead. Confirmed against the core with variants of
/// the test program (`CoreSessionTests.DS.ImportRules`).
///
/// The checks say whether the core loads a file, not whether its program
/// works: on a direct boot melonDS overwrites the first 2 KiB of an ARM9
/// binary at 0x4000-0x7FFF that lacks the marker of a decrypted dump, so a
/// program laid out like that runs only if its code starts behind them.
nonisolated enum NDSHeader {
    /// The header melonDS reads, 4 KiB including the DSi part.
    static let minimumSize = 0x1000
    /// The largest DS game card, 4 Gbit.
    static let maximumSize = 512 * 1024 * 1024
    /// Neither binary may start inside the 512-byte header.
    static let firstBinaryOffset: UInt32 = 0x200
    /// The range melonDS DS accepts for the entry point of the ARM9.
    static let arm9EntryRange: ClosedRange<UInt32> = 0x0200_0000...0x023B_FE00
    /// The checksum of the logo area that every game card carries. melonDS DS
    /// checks this field, not the logo, for every game that is not homebrew.
    static let logoChecksum: UInt16 = 0xCF56
    /// The first word of a decrypted secure area, and not the word 16 bytes
    /// later (melonDS DS: `romDecrypted`).
    static let decryptedMarker: UInt32 = 0xE7FF_DEFF
    /// The upper half of the title ID of DSiWare.
    static let dsiWareTitleIDHigh: UInt32 = 0x0003_0004
    /// Bit 1 of the DSi crypto flags: modcrypt applied, which retail DSi
    /// titles have and homebrew does not.
    static let modcryptApplied: UInt8 = 0x02

    /// What the header says, for the checks and for tests.
    nonisolated struct Fields: Sendable, Hashable {
        var gameCode: String
        var unitCode: UInt8
        var dsiCryptoFlags: UInt8
        var arm9Offset: UInt32
        var arm9Entry: UInt32
        var arm9Size: UInt32
        var arm7Offset: UInt32
        var arm7Size: UInt32
        var logoChecksum: UInt16
        var dsiTitleIDHigh: UInt32

        /// melonDS: the ARM9 binary below 0x4000 or the game code "####".
        var isHomebrew: Bool {
            arm9Offset < 0x4000 || gameCode == "####"
        }

        /// melonDS DS: homebrew, or a game code that is not four capital
        /// letters or digits as on every released game.
        var looksLikeHomebrew: Bool {
            let isGameCode = gameCode.utf8.count == 4
                && gameCode.utf8.allSatisfy { (0x41...0x5A).contains($0) || (0x30...0x39).contains($0) }
            return isHomebrew || !isGameCode
        }

        /// melonDS DS: modcrypt applied and not homebrew.
        var isRetailDSiTitle: Bool {
            dsiCryptoFlags & NDSHeader.modcryptApplied != 0 && !looksLikeHomebrew
        }

        /// melonDS: a DSi unit code with the DSiWare title ID.
        var isDSiWare: Bool {
            unitCode & 0x02 != 0 && dsiTitleIDHigh == NDSHeader.dsiWareTitleIDHigh
        }

        /// A retail title that needs a DSi: unit code 3 (DSi only) or
        /// DSiWare. melonDS DS refuses these in DS mode with its error screen;
        /// DSi homebrew it runs on the DS as far as it goes, and so does
        /// Arcfold. Unit code 2 alone, DSi-enhanced, runs on a DS.
        var needsDSi: Bool {
            (unitCode == 0x03 || isDSiWare) && isRetailDSiTitle
        }
    }

    /// Reads the fields; nil if the data is shorter than the header.
    static func fields(of data: Data) -> Fields? {
        guard data.count >= minimumSize else { return nil }
        return Fields(
            gameCode: String(decoding: bytes(data, at: 0x0C, count: 4), as: UTF8.self),
            unitCode: bytes(data, at: 0x12, count: 1)[0],
            dsiCryptoFlags: bytes(data, at: 0x1C, count: 1)[0],
            arm9Offset: word(data, at: 0x20),
            arm9Entry: word(data, at: 0x24),
            arm9Size: word(data, at: 0x2C),
            arm7Offset: word(data, at: 0x30),
            arm7Size: word(data, at: 0x3C),
            logoChecksum: UInt16(truncatingIfNeeded: word(data, at: 0x15C)),
            dsiTitleIDHigh: word(data, at: 0x234)
        )
    }

    /// Accepts the file if melonDS DS starts it without BIOS files in DS mode.
    static func check(_ data: Data, fileName: String) throws(ImportError) {
        let system = GameSystem.ds.name
        guard data.count <= maximumSize else { throw .tooLarge(fileName: fileName, system: system) }
        guard let header = fields(of: data) else { throw .tooSmall(fileName: fileName, system: system) }
        // melonDS DS decides on the console before it looks at the game.
        guard !header.needsDSi else { throw .needsDSi(fileName: fileName) }
        // melonDS pads the file with zeros to the next power of two; both
        // binaries lie behind the header and inside that image. Summed in 64
        // bits, so that offset and size cannot wrap around as in melonDS's
        // 32-bit check.
        let image = paddedSize(of: data.count)
        guard arm9EntryRange.contains(header.arm9Entry),
              header.isHomebrew || header.logoChecksum == logoChecksum,
              header.arm9Offset >= firstBinaryOffset,
              UInt64(header.arm9Offset) + UInt64(header.arm9Size) <= image,
              header.arm7Offset >= firstBinaryOffset,
              UInt64(header.arm7Offset) + UInt64(header.arm7Size) <= image
        else {
            throw .notAGame(fileName: fileName, system: system)
        }
        if !header.isHomebrew {
            // melonDS DS reads both words from the padded image.
            guard UInt64(header.arm9Offset) + 0x14 <= image else {
                throw .notAGame(fileName: fileName, system: system)
            }
            let first = paddedWord(data, at: Int(header.arm9Offset))
            let later = paddedWord(data, at: Int(header.arm9Offset) + 0x10)
            guard first == decryptedMarker, later != decryptedMarker else {
                throw .encryptedGame(fileName: fileName)
            }
        }
    }

    /// The size melonDS pads a game of `count` bytes to: the next power of two.
    static func paddedSize(of count: Int) -> UInt64 {
        var size: UInt64 = 1
        while size < UInt64(count) {
            size <<= 1
        }
        return size
    }

    private static func bytes(_ data: Data, at offset: Int, count: Int) -> [UInt8] {
        let start = data.startIndex + offset
        return Array(data[start..<start + count])
    }

    /// A little-endian 32-bit word.
    private static func word(_ data: Data, at offset: Int) -> UInt32 {
        bytes(data, at: offset, count: 4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// A little-endian 32-bit word of the padded image: bytes behind the end
    /// of the file are zero.
    private static func paddedWord(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reversed().reduce(0) { value, index in
            let position = offset + index
            let byte = position < data.count ? data[data.startIndex + position] : 0
            return value << 8 | UInt32(byte)
        }
    }
}
