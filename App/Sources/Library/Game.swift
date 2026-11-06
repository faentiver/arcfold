import Foundation

/// One imported game, stored as `game.json` next to its copy (ADR 0005,
/// section 9). The file system is the only source of the library.
nonisolated struct Game: Codable, Hashable, Identifiable, Sendable {
    /// SHA-256 of the file, lowercase hex. Importing the same file again finds
    /// the same game, and a renamed file keeps its battery save.
    let id: String
    /// The name shown in the library: the file name without its extension.
    var name: String
    /// `GameSystem.id`.
    let system: String
    /// The name of the file the person picked.
    let originalFileName: String
    /// Bytes of the file.
    let size: Int
    let importedAt: Date
}

/// Where Arcfold keeps its files, inside Application Support:
///
///     Games/<SHA-256>/game.gba     the copy of the imported file
///     Games/<SHA-256>/game.json    the Game record
///     Games/<SHA-256>/battery.sav  the battery save
///     System/                      the system folder of the cores, empty
///
/// The container already has a folder named Library, hence Games.
nonisolated struct LibraryLocation: Sendable, Hashable {
    /// Application Support, or a temporary folder in tests.
    let root: URL

    var games: URL { root.appending(path: "Games", directoryHint: .isDirectory) }
    var system: URL { root.appending(path: "System", directoryHint: .isDirectory) }

    func folder(for id: String) -> URL {
        games.appending(path: id, directoryHint: .isDirectory)
    }

    func files(for game: Game) -> GameFiles {
        let folder = folder(for: game.id)
        let fileExtension = GameSystem.system(id: game.system)?.fileExtension ?? "bin"
        return GameFiles(
            folder: folder,
            game: folder.appending(path: "game.\(fileExtension)", directoryHint: .notDirectory),
            record: folder.appending(path: GameFiles.recordName, directoryHint: .notDirectory),
            batterySave: folder.appending(path: "battery.sav", directoryHint: .notDirectory)
        )
    }

    /// Application Support of this app.
    static let standard = LibraryLocation(root: .applicationSupportDirectory)
}

/// The files of one game.
nonisolated struct GameFiles: Sendable, Hashable {
    let folder: URL
    let game: URL
    let record: URL
    let batterySave: URL

    static let recordName = "game.json"
}
