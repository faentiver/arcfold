import CryptoKit
import Foundation

/// Copies a picked file into the library (ADR 0005, section 9): checks that it
/// looks like a game of the system, names it by its SHA-256 and copies it
/// atomically. Runs off the main actor.
nonisolated enum GameImporter {
    /// GBA ROMs: at least the header, at most the 32 MiB cartridge space.
    static let minimumSize = 192
    static let maximumSize = 32 * 1024 * 1024

    /// Imports one file. A file that is already in the library is not copied
    /// again; its record and battery save stay as they are.
    ///
    /// - Parameter url: A URL from `.fileImporter` (security-scoped) or a plain file URL.
    @concurrent
    static func importGame(
        from url: URL, system: GameSystem, into location: LibraryLocation, now: Date = .now
    ) async throws(ImportError) -> ImportOutcome {
        let fileName = url.lastPathComponent
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumSize {
            throw .tooLarge(fileName: fileName)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw .unreadable(fileName: fileName, reason: error.localizedDescription)
        }
        try check(data, fileName: fileName)

        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let record = Game(
            id: id,
            name: url.deletingPathExtension().lastPathComponent,
            system: system.id,
            originalFileName: fileName,
            size: data.count,
            // Whole seconds, as game.json stores them, so that the returned
            // record equals the one on disk.
            importedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        )
        let files = location.files(for: record)
        let manager = FileManager.default
        if let existing = try? readRecord(at: files.record), manager.fileExists(atPath: files.game.path(percentEncoded: false)) {
            return ImportOutcome(game: existing, wasAlreadyInLibrary: true)
        }

        do {
            try manager.createDirectory(at: files.folder, withIntermediateDirectories: true)
            // .atomic writes a temporary file and renames it, so a half
            // written copy never carries the final name. The record comes
            // last: only folders with a record count as games.
            try data.write(to: files.game, options: .atomic)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: files.record, options: .atomic)
        } catch {
            throw .writeFailed(fileName: fileName, reason: error.localizedDescription)
        }
        return ImportOutcome(game: record, wasAlreadyInLibrary: false)
    }

    /// The checks of mGBA's GBAIsROM: byte 3 is 0xEA (the branch over the
    /// header), byte 0xB2 is 0x96 (the fixed value of the header).
    static func check(_ data: Data, fileName: String) throws(ImportError) {
        guard data.count >= minimumSize else { throw .tooSmall(fileName: fileName) }
        guard data.count <= maximumSize else { throw .tooLarge(fileName: fileName) }
        let start = data.startIndex
        guard data[start + 3] == 0xEA, data[start + 0xB2] == 0x96 else {
            throw .notAGame(fileName: fileName)
        }
    }

    static func readRecord(at url: URL) throws -> Game {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Game.self, from: Data(contentsOf: url))
    }
}

nonisolated struct ImportOutcome: Sendable, Hashable {
    let game: Game
    /// The same file was imported before; nothing was copied.
    let wasAlreadyInLibrary: Bool
}

/// Why a file could not be imported.
nonisolated enum ImportError: Error, Sendable, Hashable {
    case unreadable(fileName: String, reason: String)
    case tooSmall(fileName: String)
    case tooLarge(fileName: String)
    case notAGame(fileName: String)
    case writeFailed(fileName: String, reason: String)

    var fileName: String {
        switch self {
        case let .unreadable(fileName, _), let .tooSmall(fileName), let .tooLarge(fileName),
             let .notAGame(fileName), let .writeFailed(fileName, _):
            fileName
        }
    }

    /// A sentence for the library's alert.
    var message: String {
        switch self {
        case let .unreadable(fileName, reason):
            String(localized: "\(fileName) could not be read: \(reason)",
                   comment: "Import error. The first value is a file name, the second the system's reason.")
        case let .tooSmall(fileName):
            String(localized: "\(fileName) is too small to be a GBA game.",
                   comment: "Import error. The value is a file name.")
        case let .tooLarge(fileName):
            String(localized: "\(fileName) is larger than 32 MB and cannot be a GBA game.",
                   comment: "Import error. The value is a file name.")
        case let .notAGame(fileName):
            String(localized: "\(fileName) does not look like a GBA game.",
                   comment: "Import error when the file header does not match. The value is a file name.")
        case let .writeFailed(fileName, reason):
            String(localized: "\(fileName) could not be copied into the library: \(reason)",
                   comment: "Import error. The first value is a file name, the second the system's reason.")
        }
    }
}
