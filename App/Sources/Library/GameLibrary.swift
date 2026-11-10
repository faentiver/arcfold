import Foundation
import Observation

/// The imported games, read from the folders in Application Support.
@Observable
final class GameLibrary {
    private(set) var games: [Game] = []
    /// False until the first `reload()` finished, so the list does not flash
    /// its empty state at launch.
    private(set) var hasLoaded = false

    let location: LibraryLocation
    private let isPreview: Bool

    init(location: LibraryLocation = .standard) {
        self.location = location
        isPreview = false
    }

    /// For previews: a library that shows `games` and never touches the disk.
    init(previewing games: [Game]) {
        location = LibraryLocation(root: URL(filePath: "/dev/null"))
        self.games = games
        hasLoaded = true
        isPreview = true
    }

    /// Reads every complete game folder again.
    func reload() async {
        guard !isPreview else { return }
        games = await Self.scan(location)
        hasLoaded = true
    }

    /// Imports the files one after another, then reloads. Returns one result
    /// per file, in order. Without a system, each file's extension picks it.
    @discardableResult
    func importGames(from urls: [URL], system: GameSystem? = nil) async -> [Result<ImportOutcome, ImportError>] {
        var results: [Result<ImportOutcome, ImportError>] = []
        for url in urls {
            guard let system = system ?? GameSystem.system(forFileExtension: url.pathExtension) else {
                results.append(.failure(.unknownType(fileName: url.lastPathComponent)))
                continue
            }
            do throws(ImportError) {
                results.append(.success(try await GameImporter.importGame(from: url, system: system, into: location)))
            } catch {
                results.append(.failure(error))
            }
        }
        await reload()
        return results
    }

    func files(for game: Game) -> GameFiles {
        location.files(for: game)
    }

    /// A game folder counts once its record and its copy both exist; a folder
    /// left behind by an interrupted import is ignored.
    @concurrent
    private static func scan(_ location: LibraryLocation) async -> [Game] {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: location.games, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else {
            return []
        }
        var games: [Game] = []
        for folder in folders {
            let record = folder.appending(path: GameFiles.recordName, directoryHint: .notDirectory)
            guard let game = try? GameImporter.readRecord(at: record), game.id == folder.lastPathComponent,
                  manager.fileExists(atPath: location.files(for: game).game.path(percentEncoded: false))
            else {
                continue
            }
            games.append(game)
        }
        return games.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
