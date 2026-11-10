import LibretroKit
import Testing

/// Loads the real cores through LibretroKit from the Frameworks folder of the
/// host app, the same way the app does.
struct EmbeddedCoreTests {
    @Test func appEmbedsMGBAAndMelonDSDS() {
        let names = LibretroCore.embeddedCoreNames()
        #expect(names.contains("mgba_libretro"))
        #expect(names.contains("melondsds_libretro"))
    }

    @Test func melonDSDSReportsItsLibraryInfo() throws {
        let core = try LibretroCore(named: "melondsds_libretro")
        let apiVersion = core.apiVersion()
        let info = core.systemInfo()

        #expect(info.libraryName == "melonDS DS")
        #expect(apiVersion == LibretroCore.hostAPIVersion)
        // Cores/melonds-ds is pinned to tag v1.4.0. Update this together with the submodule.
        #expect(info.libraryVersion == "1.4.0")
        // The core reads the game from memory, so the app can pass its mapped copy.
        #expect(!info.needsFullPath)
        #expect(info.validExtensions.contains("nds"))
    }

    @Test func mgbaReportsItsLibraryInfo() throws {
        let core = try LibretroCore(named: "mgba_libretro")
        let apiVersion = core.apiVersion()
        let info = core.systemInfo()

        #expect(info.libraryName == "mGBA")
        // hostAPIVersion is RETRO_API_VERSION from libretro.h.
        #expect(apiVersion == LibretroCore.hostAPIVersion)
        // Cores/mgba is pinned to tag 0.10.5. Update this together with the submodule.
        #expect(info.libraryVersion == "0.10.5")
        // Scripts/cores/mgba.sh builds without Game Boy support.
        #expect(info.validExtensions == ["gba"])
    }
}
