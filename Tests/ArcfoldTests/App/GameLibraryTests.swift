@testable import Arcfold
import Foundation
import Testing

/// The library is the set of complete game folders (ADR 0005, section 9).
@MainActor
struct GameLibraryTests {
    @Test func reloadListsCompleteFoldersSortedByName() async throws {
        let location = try GameImporterTests.temporaryLocation()
        let library = GameLibrary(location: location)
        #expect(!library.hasLoaded)

        var zebra = GameImporterTests.headerOnly()
        zebra[0x40] = 1
        let results = await library.importGames(from: [
            try GameImporterTests.file(named: "zebra.gba", bytes: zebra),
            try Fixture.gbaSelftest.url(),
            try GameImporterTests.file(named: "Alpha.gba", bytes: GameImporterTests.headerOnly()),
        ])
        #expect(results.allSatisfy { (try? $0.get()) != nil })
        #expect(library.hasLoaded)
        #expect(library.games.map(\.name) == ["Alpha", "selftest", "zebra"])

        let fresh = GameLibrary(location: location)
        await fresh.reload()
        #expect(fresh.games == library.games, "The disk is the only source")
    }

    @Test func ignoresFoldersWithoutRecordOrCopy() async throws {
        let location = try GameImporterTests.temporaryLocation()
        let library = GameLibrary(location: location)
        await library.importGames(from: [try Fixture.gbaSelftest.url()])
        let game = try #require(library.games.first)
        let manager = FileManager.default

        // A folder an interrupted import left behind: a copy, no record.
        let stray = location.folder(for: String(repeating: "0", count: 64))
        try manager.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: stray.appending(path: "game.gba"))
        await library.reload()
        #expect(library.games == [game])

        // The copy went missing.
        try manager.removeItem(at: location.files(for: game).game)
        await library.reload()
        #expect(library.games.isEmpty)
    }

    @Test func reportsEachFailedFile() async throws {
        let location = try GameImporterTests.temporaryLocation()
        let library = GameLibrary(location: location)
        let results = await library.importGames(from: [
            try GameImporterTests.file(named: "short.gba", bytes: [1, 2, 3]),
            try Fixture.gbaSelftest.url(),
        ])
        #expect(results.count == 2)
        if case let .failure(error) = results[0] {
            #expect(error == .tooSmall(fileName: "short.gba", system: "GBA"))
        } else {
            Issue.record("short.gba was imported")
        }
        #expect(library.games.map(\.name) == ["selftest"])
    }
}
