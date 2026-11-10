import Foundation

/// How the library orders its games. Stored with `@AppStorage`, so the raw
/// values must not change.
nonisolated enum LibrarySort: String, CaseIterable, Sendable {
    case name
    case recentlyAdded
}

/// Sorting and searching as view logic only: `GameLibrary` keeps its order,
/// the library screen shows the games through this function.
nonisolated enum LibraryArrangement {
    /// The games whose name contains `query` (ignoring case and diacritics, as
    /// the Finder does), by name or newest import first. An empty query keeps
    /// every game.
    static func arranged(_ games: [Game], sort: LibrarySort, query: String) -> [Game] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? games : games.filter { $0.name.localizedStandardContains(query) }
        return matching.sorted { first, second in
            switch sort {
            case .name:
                return byName(first, second)
            case .recentlyAdded:
                if first.importedAt != second.importedAt {
                    return first.importedAt > second.importedAt
                }
                return byName(first, second)
            }
        }
    }

    private static func byName(_ first: Game, _ second: Game) -> Bool {
        switch first.name.localizedStandardCompare(second.name) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: first.id < second.id
        }
    }
}
