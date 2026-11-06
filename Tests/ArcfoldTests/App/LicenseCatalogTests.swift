@testable import Arcfold
import Foundation
import LibretroKit
import Testing

/// The Licenses screen lists exactly the texts in the app bundle.
struct LicenseCatalogTests {
    @Test func listsTheFiveComponentsOfM1() {
        #expect(LicenseCatalog.components.map(\.name) == ["Arcfold", "mGBA", "blip_buf", "inih", "libretro.h"])
        #expect(LicenseCatalog.components.map(\.license) == ["GPL-3.0", "MPL-2.0", "LGPL-2.1-or-later", "BSD-3-Clause", "MIT"])
    }

    @Test(arguments: LicenseCatalog.components)
    func everyTextIsInTheAppBundle(_ component: LicenseComponent) throws {
        let text = try #require(component.text(), "Licenses/\(component.folder)/\(component.file) is missing")
        #expect(text.count > 200)
    }

    @Test func libretroHShowsOnlyItsHeaderComment() throws {
        let libretro = try #require(LicenseCatalog.components.first { $0.folder == "libretro.h" })
        let text = try #require(libretro.text())
        #expect(text.contains("Permission is hereby granted, free of charge"))
        #expect(text.contains("Copyright (C) 2010-2024 The RetroArch team"))
        #expect(!text.contains("#ifndef LIBRETRO_H__"))
        #expect(!text.contains("*/"))
    }

    @Test func theMGBAEntryNamesTheSourceOfTheEmbeddedVersion() throws {
        let mgba = try #require(LicenseCatalog.components.first { $0.folder == "mGBA" })
        let core = try LibretroCore(named: "mgba_libretro")
        #expect(mgba.version == core.systemInfo().libraryVersion)
        #expect(mgba.note?.contains("github.com/mgba-emu/mgba") == true)
        #expect(mgba.note?.contains(core.systemInfo().libraryVersion) == true)
    }

    @Test func leadingCommentDropsTheMarkers() {
        let source = """
        /*!
         * First line.
         *
         *   Indented line.
         */
        int code;
        """
        #expect(LicenseComponent.leadingComment(of: source) == "First line.\n\n  Indented line.")
    }
}
