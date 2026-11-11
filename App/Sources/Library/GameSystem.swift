import FoldLayout
import UniformTypeIdentifiers

/// A system Arcfold emulates and everything the app needs to run its games
/// (ADR 0005, section 9; ADR 0006).
nonisolated struct GameSystem: Sendable, Hashable, Identifiable {
    /// How the import recognises a game file of the system.
    nonisolated enum Header: Sendable, Hashable {
        /// `GBAHeader`: the checks of mGBA.
        case gba
        /// `NDSHeader`: the checks of melonDS DS, without BIOS files.
        case nds
    }

    /// A short, stable key, stored in `game.json`.
    let id: String
    /// The name shown in the library.
    let name: String
    /// The framework name of the libretro core.
    let coreName: String
    /// The extension of the copy in the game's folder and of the files the
    /// import accepts for the system.
    let fileExtension: String
    /// Arcfold's type for the system's games, declared in App/Info.plist.
    let contentType: UTType
    let header: Header
    /// Replaces the core's defaults for `RETRO_ENVIRONMENT_GET_VARIABLE`.
    let coreOptions: [String: String]
    /// The screens in one frame of the core, for FoldLayout.
    let screens: SystemScreens
    /// `SessionConfiguration.blankSaveMemoryByte`: what a new save memory holds.
    let blankSaveMemoryByte: UInt8?
    /// `SessionConfiguration.requiresSystemMemory`: the core shows an error
    /// screen instead of failing when it cannot run a game.
    let requiresSystemMemory: Bool
    /// The screens of this system are one step larger on the outer display
    /// beside the vertical system bar than below it: the two of the DS 4
    /// instead of 3 times. The case then has no rim, so the system keeps
    /// the bar only for whoever prefers larger screens
    /// (`ConsoleSkin.prefersLargerScreens`).
    let growsBesideVerticalBar: Bool
    /// The console has X and Y; the touch controls show them only then.
    let hasXYButtons: Bool

    /// The game view of this system hides the vertical system bar of the
    /// outer display (`.toolbarVerticalBehavior(.disabled)`), for the whole
    /// game, so that the choice stays stable as Apple asks. The status area
    /// then lies at the top, and the console stands in the middle of the
    /// display with the same margins left and right; beside the bar it
    /// could not. The GBA picture also grows from 4 to 5 times there. A
    /// system whose screens grow beside the bar keeps it for whoever
    /// prefers larger screens (ADR 0006, ADR 0007).
    var disablesVerticalBar: Bool {
        !(growsBesideVerticalBar && ConsoleSkin.prefersLargerScreens)
    }

    /// mGBA, with its built-in replacement for the BIOS: Arcfold ships no BIOS
    /// files (hard rules in CLAUDE.md).
    static let gba = GameSystem(
        id: "gba",
        name: "GBA",
        coreName: "mgba_libretro",
        fileExtension: "gba",
        contentType: UTType(importedAs: "com.faentiver.arcfold.gba-rom", conformingTo: .data),
        header: .gba,
        coreOptions: ["mgba_use_bios": "OFF"],
        screens: .gba,
        blankSaveMemoryByte: nil,
        requiresSystemMemory: false,
        growsBesideVerticalBar: false,
        hasXYButtons: false
    )

    /// melonDS DS in DS mode with melonDS's built-in BIOS and firmware, both
    /// screens as one 256 × 384 frame without a gap, touch through the pointer
    /// only and the network switched off (ADR 0006).
    static let ds = GameSystem(
        id: "ds",
        name: "DS",
        coreName: "melondsds_libretro",
        fileExtension: "nds",
        contentType: UTType(importedAs: "com.faentiver.arcfold.nds-rom", conformingTo: .data),
        header: .nds,
        coreOptions: dsCoreOptions,
        screens: .ds,
        blankSaveMemoryByte: 0xFF,
        requiresSystemMemory: true,
        growsBesideVerticalBar: true,
        hasXYButtons: true
    )

    /// The options of melonDS DS 1.4.0 that differ from its defaults or that
    /// the layout relies on (ADR 0006). Tests replace
    /// `melonds_start_time_mode` with `absolute`, so that the clock of the
    /// emulated console does not depend on the time of day.
    static let dsCoreOptions: [String: String] = [
        // The DSi needs real BIOS and NAND files; the DS runs without files.
        "melonds_console_mode": "ds",
        "melonds_sysfile_mode": "builtin",
        "melonds_boot_mode": "direct",
        // One layout, both screens unchanged one above the other, no gap: the
        // app places them itself. With two layouts R3 would switch to a second.
        "melonds_number_of_screen_layouts": "1",
        "melonds_screen_layout1": "top-bottom",
        "melonds_screen_gap": "0",
        // No cursor drawn into the picture, touch through the pointer only.
        "melonds_show_cursor": "disabled",
        "melonds_touch_mode": "touch",
        "melonds_network_mode": "disabled",
        // No DNS server in the Wi-Fi settings of the generated firmware
        // ("Force Default DNS"). By default melonDS DS writes a replacement
        // server for the discontinued online service there, and "default"
        // would keep one that an earlier session left in
        // System/melonDS DS/wfcsettings.bin.
        "melonds_firmware_wfc_dns": "0.0.0.0",
        "melonds_mic_input": "silence",
        "melonds_homebrew_sdcard": "disabled",
        "melonds_dsi_sdcard": "disabled",
        // The app shows its own messages.
        "melonds_show_unsupported_features": "disabled",
        "melonds_show_bios_warnings": "disabled",
        "melonds_show_current_layout": "disabled",
        "melonds_show_mic_state": "disabled",
        "melonds_show_camera_state": "disabled",
        "melonds_show_lid_state": "disabled",
        "melonds_show_sensor_reading": "disabled",
        "melonds_threaded_renderer": "enabled",
        "melonds_start_time_mode": "real",
    ]

    static let all = [gba, ds]

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

    /// The system whose games have this file extension, in any case.
    static func system(forFileExtension fileExtension: String) -> GameSystem? {
        let fileExtension = fileExtension.lowercased()
        return all.first { $0.fileExtension == fileExtension }
    }
}
