@testable import Arcfold
import Foundation
import Testing

/// The import checks for DS game files (ADR 0006): what melonDS DS 1.4.0
/// starts without BIOS files in DS mode. The variants are the DS test program
/// with single header fields changed (`DSVariant`); the same files run
/// through the real core in `CoreSessionTests.DS.ImportRules`.
struct NDSHeaderTests {
    private func selftest() throws -> Data {
        try Data(contentsOf: Fixture.dsSelftest.url())
    }

    private func check(_ variant: DSVariant) throws(ImportError) {
        let data: Data
        do {
            data = variant.apply(to: try selftest())
        } catch {
            Issue.record(error)
            return
        }
        try NDSHeader.check(data, fileName: "a.nds")
    }

    private func patched(_ data: Data, at offset: Int, _ bytes: [UInt8]) -> Data {
        var data = data
        data.replaceSubrange(offset..<offset + bytes.count, with: bytes)
        return data
    }

    @Test func theTestProgramLooksLikeADecryptedGameCard() throws {
        let data = try selftest()
        let header = try #require(NDSHeader.fields(of: data))
        #expect(header.gameCode == "ZARC")
        #expect(header.arm9Offset == 0x4000)
        #expect(header.arm9Entry == 0x0200_0010)
        #expect(header.arm9Size == 0x800)
        #expect(header.arm7Offset == 0x4800)
        #expect(header.arm7Size == 0x400)
        #expect(header.logoChecksum == NDSHeader.logoChecksum)
        #expect(header.dsiCryptoFlags == 0)
        #expect(!header.isHomebrew)
        #expect(!header.looksLikeHomebrew)
        #expect(!header.needsDSi)
        try NDSHeader.check(data, fileName: "selftest.nds")
    }

    @Test func anEncryptedSecureAreaIsRefused() throws {
        #expect(throws: ImportError.encryptedGame(fileName: "a.nds")) {
            try check(.encrypted)
        }
        // Encrypted dumps repeat the marker 16 bytes later.
        #expect(throws: ImportError.encryptedGame(fileName: "a.nds")) {
            try check(.markerRepeated)
        }
    }

    @Test(arguments: [DSVariant.homebrew, .homebrewWithMarker, .homebrewBelow0x4000])
    func homebrewNeedsNeitherMarkerNorLogoChecksum(_ variant: DSVariant) throws {
        let header = try #require(NDSHeader.fields(of: variant.apply(to: selftest())))
        #expect(header.isHomebrew)
        #expect(header.looksLikeHomebrew)
        try check(variant)
    }

    @Test func aGameCardWithoutTheLogoChecksumIsNotAGame() throws {
        #expect(throws: ImportError.notAGame(fileName: "a.nds", system: "DS")) {
            try check(.withoutLogoChecksum)
        }
    }

    @Test func theARM9EntryMustLieWhereMelonDSDSAcceptsIt() throws {
        #expect(throws: ImportError.notAGame(fileName: "a.nds", system: "DS")) {
            try check(.arm9EntryTooHigh)
        }
    }

    @Test func bothBinariesLieInsideTheImageMelonDSPadsTheFileTo() throws {
        #expect(NDSHeader.paddedSize(of: 19_456) == 32_768)
        #expect(NDSHeader.paddedSize(of: 32_768) == 32_768)
        #expect(NDSHeader.paddedSize(of: NDSHeader.minimumSize) == 4096)
        #expect(throws: ImportError.notAGame(fileName: "a.nds", system: "DS")) {
            try check(.arm9BehindTheFile)
        }
        #expect(throws: ImportError.notAGame(fileName: "a.nds", system: "DS")) {
            try check(.arm9LargerThanTheFile)
        }
        // Behind the end of the file, but inside the zeros up to 32 KiB.
        try check(.arm7InThePadding)
        // Inside the header.
        let inHeader = patched(try selftest(), at: 0x30, [0x00, 0x01, 0x00, 0x00])
        #expect(throws: ImportError.notAGame(fileName: "a.nds", system: "DS")) {
            try NDSHeader.check(inHeader, fileName: "a.nds")
        }
        // Offset plus size beyond 4 GiB does not wrap around.
        let wrapping = patched(try selftest(), at: 0x3C, [0x00, 0xC0, 0xFF, 0xFF])
        #expect(throws: ImportError.notAGame(fileName: "a.nds", system: "DS")) {
            try NDSHeader.check(wrapping, fileName: "a.nds")
        }
    }

    @Test func retailTitlesForTheDSiAreRefusedDSiHomebrewIsNot() throws {
        #expect(throws: ImportError.needsDSi(fileName: "a.nds")) {
            try check(.dsiOnlyRetail)
        }
        #expect(throws: ImportError.needsDSi(fileName: "a.nds")) {
            try check(.dsiWareRetail)
        }
        // Without the modcrypt flag, or with a game code no released game
        // has, melonDS DS runs the file on the DS.
        try check(.dsiOnlyHomebrew)
        try check(.dsiWareHomebrew)
        let lowercaseCode = patched(DSVariant.dsiOnlyRetail.apply(to: try selftest()), at: 0x0C, Array("zarc".utf8))
        try NDSHeader.check(lowercaseCode, fileName: "a.nds")
        // DSi-enhanced game cards run on the DS.
        try check(.dsiEnhanced)
    }

    @Test func aRetailDSiTitleIsRefusedBeforeItsOtherFieldsCount() throws {
        // melonDS DS decides on the console first, as the import does.
        let data = patched(DSVariant.dsiOnlyRetail.apply(to: try selftest()), at: 0x15C, [0, 0])
        #expect(throws: ImportError.needsDSi(fileName: "a.nds")) {
            try NDSHeader.check(data, fileName: "a.nds")
        }
    }

    @Test func checksTheSizeLimits() throws {
        #expect(throws: ImportError.tooSmall(fileName: "a.nds", system: "DS")) {
            try check(.tooShort)
        }
        #expect(NDSHeader.maximumSize == 512 * 1024 * 1024)
    }
}
