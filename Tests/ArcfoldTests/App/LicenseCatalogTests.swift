@testable import Arcfold
import Foundation
import LibretroKit
import Testing

/// The Licenses screen lists exactly the texts in the app bundle.
struct LicenseCatalogTests {
    @Test func listsArcfoldTheCoresAndEveryPartBuiltIntoThem() {
        let expected: [(name: String, license: String)] = [
            ("Arcfold", "GPL-3.0-or-later"), ("mGBA", "MPL-2.0"), ("blip_buf", "LGPL-2.1-or-later"),
            ("inih", "BSD-3-Clause"), ("libretro.h", "MIT"),
            ("melonDS DS", "GPL-3.0-or-later"), ("melonDS", "GPL-3.0-or-later"), ("FreeBIOS", "BSD-2-Clause"),
            ("FatFs", "BSD-1-Clause"), ("teakra", "MIT"), ("Tiny AES in C", "Unlicense"), ("xxHash", "BSD-2-Clause"),
            ("libretro-common", "MIT"), ("libslirp", "BSD-3-Clause"), ("libslirp, parts from 4.4BSD", "BSD-3-Clause"),
            ("libslirp, MIT parts", "MIT"),
            ("{fmt}", "MIT"), ("OpenGL Mathematics (GLM)", "MIT"), ("pntr", "Zlib"), ("yamc", "MIT"),
            ("span lite", "BSL-1.0"), ("date", "MIT"), ("zlib", "Zlib"), ("Open Sans", "OFL-1.1"),
        ]
        #expect(LicenseCatalog.components.map(\.name) == expected.map(\.name))
        #expect(LicenseCatalog.components.map(\.license) == expected.map(\.license))
        #expect(Set(LicenseCatalog.components.map(\.id)).count == LicenseCatalog.components.count)
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

    @Test func sectionsComeFromTheNoticesOfMelonDSDS() throws {
        let fonts = try #require(LicenseCatalog.components.first { $0.name == "Open Sans" }?.text())
        #expect(fonts.hasPrefix("Copyright 2020 The Open Sans Project Authors"))
        #expect(fonts.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(!fonts.contains("# pcap"))
        let common = try #require(LicenseCatalog.components.first { $0.name == "libretro-common" }?.text())
        #expect(common.hasPrefix("Copyright  (C) 2010-2023 The RetroArch team"))
        #expect(!common.contains("#"))
    }

    /// Clause 2 of the BSD license and the MIT license ask for every copyright
    /// line of the files built into Arcfold (lizenzkoepfe.py of the review of
    /// M2 lists them).
    @Test func everyCopyrightHolderOfLibslirpAndDateIsNamed() throws {
        let bsd = try #require(LicenseCatalog.components.first { $0.name == "libslirp" })
        let bsdText = (bsd.note ?? "") + (bsd.text() ?? "")
        for holder in ["Danny Gasparovski", "Guillaume Subiron, Yann Bordenave, Serigne Modou Wagne",
                       "Thomas Huth, Red Hat Inc.", "Gavin Shan, IBM Corporation 2016", "2016-2018 IBM Corp."] {
            #expect(bsdText.contains(holder), "libslirp: \(holder)")
        }
        let berkeley = try #require(LicenseCatalog.components.first { $0.name == "libslirp, parts from 4.4BSD" })
        let berkeleyText = try #require(berkeley.text())
        #expect(berkeleyText.contains("The Regents of the University of California"))
        #expect(berkeleyText.contains("Neither the name of the University"))
        #expect(berkeley.note?.contains("1982, 1986, 1988, 1990, 1992, 1993, 1994") == true)
        #expect(!berkeleyText.contains("#ifndef"))
        let mit = try #require(LicenseCatalog.components.first { $0.name == "libslirp, MIT parts" })
        let mitText = (mit.note ?? "") + (mit.text() ?? "")
        for holder in ["Fabrice Bellard", "Red Hat, Inc.", "AdaCore", "Klaus Stengel", "Magnus Damm"] {
            #expect(mitText.contains(holder), "libslirp MIT: \(holder)")
        }
        let date = try #require(LicenseCatalog.components.first { $0.name == "date" }?.text())
        #expect(date.hasPrefix("The MIT License (MIT)"))
        for author in ["Howard Hinnant", "Adrian Colomitchi", "Florian Dang", "Paul Thompson", "Tomasz Kamiński", "Jiangang Zhuang"] {
            #expect(date.contains(author), "date: \(author)")
        }
        #expect(!date.contains("//") && !date.contains("# Dolphin"))
    }

    @Test func sectionsWrittenAsLineCommentsLoseTheMarkers() {
        let source = "# A ###\n\n// Line one\n//\n//   indented\n\n# B ###\n"
        #expect(LicenseComponent.section(of: source, heading: "# A ", nextHeading: "# B ") == "Line one\n\n  indented")
        let mixed = "# A ###\nhttp://example.org\n// not all lines\n# B ###\n"
        #expect(LicenseComponent.section(of: mixed, heading: "# A ", nextHeading: "# B ") == "http://example.org\n// not all lines")
    }

    @Test func leadingCommentsSkipASPDXTag() throws {
        let slirp = try #require(LicenseCatalog.components.first { $0.name == "libslirp, MIT parts" }?.text())
        #expect(slirp.hasPrefix("Copyright (c) 2003-2008 Fabrice Bellard"))
        #expect(slirp.contains("Permission is hereby granted, free of charge"))
        #expect(!slirp.contains("SPDX"))
        #expect(LicenseComponent.leadingComment(of: "/* SPDX-License-Identifier: MIT */\n/*\n * Notice.\n */") == "Notice.")
    }

    @Test func sectionNeedsBothHeadings() {
        let source = "# A ###\nfirst\n\n# B ###\nsecond\n"
        #expect(LicenseComponent.section(of: source, heading: "# A ", nextHeading: "# B ") == "first")
        #expect(LicenseComponent.section(of: source, heading: "# B ", nextHeading: "# C ") == nil)
    }

    @Test func theMelonDSDSEntryNamesTheSourceOfTheEmbeddedVersion() throws {
        let entry = try #require(LicenseCatalog.components.first { $0.folder == "melonDS-DS" })
        let core = try LibretroCore(named: "melondsds_libretro")
        #expect(entry.version == core.systemInfo().libraryVersion)
        #expect(entry.note?.contains("github.com/JesseTG/melonds-ds") == true)
        #expect(entry.note?.contains("v\(core.systemInfo().libraryVersion)") == true)
    }

    /// GPL-3.0 asks for a copyright notice and, with the object code, for
    /// directions to the Corresponding Source, which for the cores includes
    /// Arcfold's recipes (sections 5 and 6).
    @Test func theArcfoldEntryNamesTheAuthorAndWhereTheSourceIs() throws {
        let note = try #require(LicenseCatalog.components.first { $0.name == "Arcfold" }?.note)
        #expect(note.hasPrefix("Copyright 2026 Fatih (faentiver). "))
        #expect(note.contains("Source code: https://github.com/faentiver/arcfold."))
        #expect(note.contains("Scripts/"))
    }

    /// GPL-3.0, section 5 a: a changed work says so and gives a date. Arcfold's
    /// recipe changes melonDS DS and melonDS (ADR 0006).
    @Test func melonDSDSAndMelonDSNameArcfoldsChangesWithTheirDate() throws {
        let melonDSDS = try #require(LicenseCatalog.components.first { $0.name == "melonDS DS" }?.note)
        for phrase in ["without JIT", "without libpcap", "DownloadTmd", "CacheTmd", "the DSi's key material from melonDS",
                       "7 November 2026", "Scripts/cores/melondsds.sh"] {
            #expect(melonDSDS.contains(phrase), "melonDS DS: \(phrase)")
        }
        let melonDS = try #require(LicenseCatalog.components.first { $0.name == "melonDS" }?.note)
        for phrase in ["github.com/melonDS-emu/melonDS, commit 906e9eb", "Steve Reid", "the DSi's key material",
                       "boot2", "modcrypt", "the key slots", "eMMC", "key scrambler constant", "7 November 2026",
                       "Scripts/cores/melondsds.sh"] {
            #expect(melonDS.contains(phrase), "melonDS: \(phrase)")
        }
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
