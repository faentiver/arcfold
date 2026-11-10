import CryptoKit
import Foundation

/// Copies a picked file into the library (ADR 0005, section 9): checks that it
/// looks like a game of the system, names it by its SHA-256 and copies it
/// atomically. Runs off the main actor.
nonisolated enum GameImporter {
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

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumSize(of: system) {
            throw .tooLarge(fileName: fileName, system: system.name)
        }
        let data: Data
        do {
            data = try readCoordinated(url)
        } catch {
            throw .unreadable(fileName: fileName, reason: error.localizedDescription)
        }
        try check(data, system: system, fileName: fileName)

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

    /// Reads the whole file under a file coordinator, so that a file provider
    /// such as iCloud Drive can download it first and nothing writes it while
    /// it is read. Blocks the calling thread until then, which is why the
    /// import runs off the main actor.
    private static func readCoordinated(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, error: &coordinationError) { readableURL in
            // Not mapped: the copy must not change once the coordination ends.
            result = Result { try Data(contentsOf: readableURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        return try result.get()
    }

    /// Whether `data` looks like a game of `system`.
    static func check(_ data: Data, system: GameSystem, fileName: String) throws(ImportError) {
        switch system.header {
        case .gba: try GBAHeader.check(data, fileName: fileName)
        case .nds: try NDSHeader.check(data, fileName: fileName)
        }
    }

    /// The largest file the import reads for `system`.
    static func maximumSize(of system: GameSystem) -> Int {
        switch system.header {
        case .gba: GBAHeader.maximumSize
        case .nds: NDSHeader.maximumSize
        }
    }

    static func readRecord(at url: URL) throws -> Game {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Game.self, from: Data(contentsOf: url))
    }
}

/// The header checks of a GBA game file, as in mGBA's GBAIsROM.
nonisolated enum GBAHeader {
    /// At least the header, at most the 32 MiB cartridge space.
    static let minimumSize = 192
    static let maximumSize = 32 * 1024 * 1024

    /// Byte 3 is 0xEA (the branch over the header), byte 0xB2 is 0x96 (the
    /// fixed value of the header).
    static func check(_ data: Data, fileName: String) throws(ImportError) {
        let system = GameSystem.gba.name
        guard data.count >= minimumSize else { throw .tooSmall(fileName: fileName, system: system) }
        guard data.count <= maximumSize else { throw .tooLarge(fileName: fileName, system: system) }
        let start = data.startIndex
        guard data[start + 3] == 0xEA, data[start + 0xB2] == 0x96 else {
            throw .notAGame(fileName: fileName, system: system)
        }
    }
}

nonisolated struct ImportOutcome: Sendable, Hashable {
    let game: Game
    /// The same file was imported before; nothing was copied.
    let wasAlreadyInLibrary: Bool
}

/// Why a file could not be imported. `system` is the name of the system the
/// file was taken for, as the library shows it.
nonisolated enum ImportError: Error, Sendable, Hashable {
    case unreadable(fileName: String, reason: String)
    /// The extension belongs to no system Arcfold runs.
    case unknownType(fileName: String)
    case tooSmall(fileName: String, system: String)
    case tooLarge(fileName: String, system: String)
    case notAGame(fileName: String, system: String)
    /// A DS game whose secure area is still encrypted. melonDS DS starts such
    /// games only with the console's own BIOS files, which Arcfold does not
    /// include (ADR 0006).
    case encryptedGame(fileName: String)
    /// A retail title for the DSi only or retail DSiWare (modcrypt flag and a
    /// game code of capital letters and digits), as melonDS DS rejects it in
    /// DS mode; DSi homebrew starts on the DS (ADR 0006). Arcfold runs the DS.
    case needsDSi(fileName: String)
    case writeFailed(fileName: String, reason: String)

    var fileName: String {
        switch self {
        case let .unreadable(fileName, _), let .unknownType(fileName), let .tooSmall(fileName, _),
             let .tooLarge(fileName, _), let .notAGame(fileName, _), let .encryptedGame(fileName),
             let .needsDSi(fileName), let .writeFailed(fileName, _):
            fileName
        }
    }

    /// A sentence for the library's alert.
    var message: String {
        switch self {
        case let .unreadable(fileName, reason):
            String(localized: "\(fileName) could not be read: \(reason)",
                   comment: "Import error. The first value is a file name, the second the system's reason.")
        case let .unknownType(fileName):
            String(localized: "\(fileName) is not a game file Arcfold can open.",
                   comment: "Import error for a file whose extension belongs to no system. The value is a file name.")
        case let .tooSmall(fileName, system):
            String(localized: "\(fileName) is too small to be a \(system) game.",
                   comment: "Import error. The first value is a file name, the second a system such as GBA or DS.")
        case let .tooLarge(fileName, system):
            String(localized: "\(fileName) is too large to be a \(system) game.",
                   comment: "Import error. The first value is a file name, the second a system such as GBA or DS.")
        case let .notAGame(fileName, system):
            String(localized: "\(fileName) does not look like a \(system) game.",
                   comment: "Import error when the file header does not match. The first value is a file name, the second a system such as GBA or DS.")
        case let .encryptedGame(fileName):
            String(localized: "\(fileName) is an encrypted DS game file. Arcfold cannot start encrypted DS games.",
                   comment: "Import error for a DS game file whose start is encrypted. The value is a file name.")
        case let .needsDSi(fileName):
            String(localized: "\(fileName) needs a DSi. Arcfold runs DS games only.",
                   comment: "Import error for a game made for the DSi only. The value is a file name.")
        case let .writeFailed(fileName, reason):
            String(localized: "\(fileName) could not be copied into the library: \(reason)",
                   comment: "Import error. The first value is a file name, the second the system's reason.")
        }
    }
}
