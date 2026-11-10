@testable import Arcfold
import Foundation
import Testing

/// Sorting and searching the library as view logic, without `GameLibrary`.
struct LibraryArrangementTests {
    static func game(_ name: String, id: String, daysAgo: Double) -> Game {
        Game(id: id, name: name, system: "gba", originalFileName: "\(name).gba", size: 1024,
             importedAt: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400))
    }

    static let games = [
        game("Zelda-like Demo", id: "1", daysAgo: 3),
        game("äpfel", id: "2", daysAgo: 1),
        game("Game 10", id: "3", daysAgo: 2),
        game("Game 9", id: "4", daysAgo: 2),
        game("Apfelbaum", id: "5", daysAgo: 5),
    ]

    @Test func byNameSortsLikeTheFinder() {
        let names = LibraryArrangement.arranged(Self.games, sort: .name, query: "").map(\.name)
        // Numbers in names count as numbers; umlauts sort with their base letter.
        #expect(names == ["äpfel", "Apfelbaum", "Game 9", "Game 10", "Zelda-like Demo"])
    }

    @Test func recentlyAddedPutsTheNewestFirstAndBreaksTiesByName() {
        let names = LibraryArrangement.arranged(Self.games, sort: .recentlyAdded, query: "").map(\.name)
        #expect(names == ["äpfel", "Game 9", "Game 10", "Zelda-like Demo", "Apfelbaum"])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        let names = LibraryArrangement.arranged(Self.games, sort: .name, query: "APFEL").map(\.name)
        #expect(names == ["äpfel", "Apfelbaum"])
        #expect(LibraryArrangement.arranged(Self.games, sort: .name, query: "demo").map(\.id) == ["1"])
    }

    @Test func anEmptyOrBlankQueryKeepsEveryGame() {
        #expect(LibraryArrangement.arranged(Self.games, sort: .name, query: "").count == Self.games.count)
        #expect(LibraryArrangement.arranged(Self.games, sort: .name, query: "  ").count == Self.games.count)
    }

    @Test func noMatchGivesNoGames() {
        #expect(LibraryArrangement.arranged(Self.games, sort: .name, query: "selftest").isEmpty)
    }

    @Test func theStoredValuesStay() {
        #expect(LibrarySort(rawValue: "name") == .name)
        #expect(LibrarySort(rawValue: "recentlyAdded") == .recentlyAdded)
    }
}
