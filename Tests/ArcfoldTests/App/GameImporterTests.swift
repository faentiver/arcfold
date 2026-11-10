@testable import Arcfold
import CryptoKit
import Foundation
import Testing
import UniformTypeIdentifiers

/// Importing files into a library in a temporary folder (ADR 0005, section 9).
struct GameImporterTests {
    /// A library root of its own for every test.
    static func temporaryLocation() throws -> LibraryLocation {
        let root = FileManager.default.temporaryDirectory.appending(path: "ArcfoldTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return LibraryLocation(root: root)
    }

    /// Writes `bytes` to a file in a folder outside the library.
    static func file(named name: String, bytes: [UInt8]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ArcfoldInput-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try Data(bytes).write(to: url)
        return url
    }

    /// The header fields mGBA checks, nothing else: not a game, but enough to pass.
    static func headerOnly(size: Int = 192) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        bytes[3] = 0xEA
        bytes[0xB2] = 0x96
        return bytes
    }

    @Test func importsTheSelftestFixture() async throws {
        let location = try Self.temporaryLocation()
        let source = try Fixture.gbaSelftest.url()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let outcome = try await GameImporter.importGame(from: source, system: .gba, into: location, now: now)

        #expect(!outcome.wasAlreadyInLibrary)
        let game = outcome.game
        #expect(game.id == Fixture.gbaSelftest.sha256)
        #expect(game.name == "selftest")
        #expect(game.system == "gba")
        #expect(game.originalFileName == "selftest.gba")
        #expect(game.size == 864)
        #expect(game.importedAt == now)

        let files = location.files(for: game)
        #expect(files.game.path(percentEncoded: false).hasSuffix("Games/\(Fixture.gbaSelftest.sha256)/game.gba"))
        #expect(try Data(contentsOf: files.game) == Data(contentsOf: source))
        #expect(try GameImporter.readRecord(at: files.record) == game)
        #expect(!FileManager.default.fileExists(atPath: files.batterySave.path(percentEncoded: false)),
                "The import creates no battery save")
    }

    @Test func aSecondImportOfTheSameFileKeepsTheFirstRecord() async throws {
        let location = try Self.temporaryLocation()
        let first = try Self.file(named: "Demo.gba", bytes: Self.headerOnly())
        let renamed = try Self.file(named: "Renamed.gba", bytes: Self.headerOnly())

        let original = try await GameImporter.importGame(from: first, system: .gba, into: location)
        let again = try await GameImporter.importGame(from: renamed, system: .gba, into: location)

        #expect(again.wasAlreadyInLibrary)
        #expect(again.game == original.game, "Same content, same game, same name")
        let folders = try FileManager.default.contentsOfDirectory(atPath: location.games.path(percentEncoded: false))
        #expect(folders == [original.game.id])
    }

    @Test func refusesAFileThatIsTooSmall() async throws {
        let location = try Self.temporaryLocation()
        let url = try Self.file(named: "tiny.gba", bytes: [UInt8](repeating: 0, count: 100))
        await #expect(throws: ImportError.tooSmall(fileName: "tiny.gba", system: "GBA")) {
            try await GameImporter.importGame(from: url, system: .gba, into: location)
        }
        #expect(!FileManager.default.fileExists(atPath: location.games.path(percentEncoded: false)))
    }

    @Test func refusesAFileWithoutTheBranchAtByteThree() async throws {
        let location = try Self.temporaryLocation()
        var bytes = Self.headerOnly(size: 1024)
        bytes[3] = 0x00
        let url = try Self.file(named: "notes.gba", bytes: bytes)
        await #expect(throws: ImportError.notAGame(fileName: "notes.gba", system: "GBA")) {
            try await GameImporter.importGame(from: url, system: .gba, into: location)
        }
    }

    @Test func refusesAFileWithoutTheFixedHeaderValue() async throws {
        let location = try Self.temporaryLocation()
        var bytes = Self.headerOnly(size: 1024)
        bytes[0xB2] = 0x00
        let url = try Self.file(named: "image.gba", bytes: bytes)
        await #expect(throws: ImportError.notAGame(fileName: "image.gba", system: "GBA")) {
            try await GameImporter.importGame(from: url, system: .gba, into: location)
        }
    }

    /// Arcfold's own type comes first; a type another app exports for `.gba`
    /// may follow. Every offered type is data with the extension of the system.
    @Test func thePickerOffersArcfoldsTypeAndTheSystemsTypeForTheExtension() {
        let types = GameSystem.gba.importTypes
        #expect(types.first == GameSystem.gba.contentType)
        #expect((1...2).contains(types.count))
        #expect(types.allSatisfy { $0.conforms(to: .data) })
        #expect(types.allSatisfy { $0.tags[.filenameExtension]?.contains("gba") == true })
    }

    @Test func checksTheUpperSizeLimit() throws {
        var bytes = [UInt8](repeating: 0, count: GBAHeader.maximumSize + 1)
        bytes[3] = 0xEA
        bytes[0xB2] = 0x96
        #expect(throws: ImportError.tooLarge(fileName: "big.gba", system: "GBA")) {
            try GameImporter.check(Data(bytes), system: .gba, fileName: "big.gba")
        }
        bytes.removeLast()
        try GameImporter.check(Data(bytes), system: .gba, fileName: "big.gba")
        #expect(GameImporter.maximumSize(of: .gba) == GBAHeader.maximumSize)
        #expect(GameImporter.maximumSize(of: .ds) == NDSHeader.maximumSize)
    }

    /// The DS test program passes the checks of melonDS DS (ADR 0006). The
    /// rules themselves are tested in NDSHeaderTests.
    @Test func importsTheDSSelftestFixture() async throws {
        let location = try Self.temporaryLocation()
        let outcome = try await GameImporter.importGame(from: try Fixture.dsSelftest.url(), system: .ds, into: location)
        #expect(outcome.game.system == "ds")
        #expect(outcome.game.id == Fixture.dsSelftest.sha256)
        #expect(location.files(for: outcome.game).game.lastPathComponent == "game.nds")
    }

    @Test func theExtensionPicksTheSystem() {
        #expect(GameSystem.system(forFileExtension: "gba") == .gba)
        #expect(GameSystem.system(forFileExtension: "NDS") == .ds)
        #expect(GameSystem.system(forFileExtension: "zip") == nil)
        #expect(GameSystem.all.map(\.id) == ["gba", "ds"])
    }

    @Test func everyErrorHasAMessageWithTheFileName() {
        let errors: [ImportError] = [
            .unreadable(fileName: "a.gba", reason: "gone"), .unknownType(fileName: "a.gba"),
            .tooSmall(fileName: "a.gba", system: "GBA"), .tooLarge(fileName: "a.gba", system: "GBA"),
            .notAGame(fileName: "a.gba", system: "GBA"), .encryptedGame(fileName: "a.gba"),
            .needsDSi(fileName: "a.gba"), .writeFailed(fileName: "a.gba", reason: "full"),
        ]
        for error in errors {
            #expect(error.message.contains("a.gba"))
            #expect(error.fileName == "a.gba")
        }
    }
}
