import UniformTypeIdentifiers

/// A system Arcfold emulates and everything the app needs to run its games
/// (ADR 0005, section 9). M1 has the GBA only.
nonisolated struct GameSystem: Sendable, Hashable, Identifiable {
    /// A short, stable key, stored in `game.json`.
    let id: String
    /// The name shown in the library.
    let name: String
    /// The framework name of the libretro core.
    let coreName: String
    /// The extension of the copy in the game's folder.
    let fileExtension: String
    /// Arcfold's type for the system's games, declared in App/Info.plist.
    let contentType: UTType
    /// Replaces the core's defaults for `RETRO_ENVIRONMENT_GET_VARIABLE`.
    let coreOptions: [String: String]

    /// mGBA, with its built-in replacement for the BIOS: Arcfold ships no BIOS
    /// files (hard rules in CLAUDE.md).
    static let gba = GameSystem(
        id: "gba",
        name: "GBA",
        coreName: "mgba_libretro",
        fileExtension: "gba",
        contentType: UTType(importedAs: "com.faentiver.arcfold.gba-rom", conformingTo: .data),
        coreOptions: ["mgba_use_bios": "OFF"]
    )

    static let all = [gba]

    /// The types `.fileImporter` offers: Arcfold's own and the type the system
    /// maps the extension to right now. Arcfold only imports its type; if
    /// another installed app exports one for the same extension, the system
    /// prefers that, and without it the picker would grey out the games. The
    /// import checks the header either way.
    var importTypes: [UTType] {
        guard let preferred = UTType(filenameExtension: fileExtension, conformingTo: .data),
              preferred != contentType
        else { return [contentType] }
        return [contentType, preferred]
    }

    static func system(id: String) -> GameSystem? {
        all.first { $0.id == id }
    }
}
