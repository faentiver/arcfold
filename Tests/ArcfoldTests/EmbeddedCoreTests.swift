import LibretroKit
import Testing

/// Loads the real mGBA core through LibretroKit from the Frameworks folder of the
/// host app, the same way the app does.
struct EmbeddedCoreTests {
    @Test func appEmbedsMGBA() {
        #expect(LibretroCore.embeddedCoreNames().contains("mgba_libretro"))
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
