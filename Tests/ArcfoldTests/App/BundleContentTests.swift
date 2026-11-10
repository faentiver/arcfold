import Foundation
import Testing

/// What the app bundle carries: the license texts for the Licenses screen, and
/// no games, BIOS files or test programs (CLAUDE.md, hard rules). While tests
/// run, the test bundles sit in `PlugIns`; they are not part of a shipped app.
struct BundleContentTests {
    @Test func appContainsNoGamesOrTestPrograms() throws {
        let app = Bundle.main.bundleURL.standardizedFileURL
        let forbidden: Set<String> = ["gba", "gb", "gbc", "nds", "iso", "cso", "chd", "pbp", "elf", "bin", "sav"]
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))

        var found: [String] = []
        for case let url as URL in files {
            let path = String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(app.path(percentEncoded: false).count))
            if path.hasPrefix("PlugIns") || path.hasPrefix("/PlugIns") {
                files.skipDescendants()
            } else if forbidden.contains(url.pathExtension.lowercased()) {
                found.append(path)
            }
        }

        #expect(found.isEmpty, "Files that must not ship in the app: \(found)")
    }

    @Test func licenseTextsAreBundled() throws {
        // Folder in Arcfold.app/Licenses, file, a phrase from the text.
        let texts = [
            ("Arcfold", "LICENSE", "GNU GENERAL PUBLIC LICENSE"),
            ("mGBA", "LICENSE", "Mozilla Public License Version 2.0"),
            ("blip_buf", "license.txt", "GNU LESSER GENERAL PUBLIC LICENSE"),
            ("inih", "LICENSE.txt", "Copyright (c) 2009, Ben Hoyt"),
            ("libretro.h", "libretro.h", "Permission is hereby granted, free of charge"),
            // melonDS DS and its parts (ADR 0006).
            ("melonDS-DS", "LICENSE", "GNU GENERAL PUBLIC LICENSE"),
            ("melonDS-DS-notices", "melondsds-LICENSE.txt.in", "SIL OPEN FONT LICENSE Version 1.1"),
            ("melonDS", "LICENSE", "GNU GENERAL PUBLIC LICENSE"),
            ("FreeBIOS", "drastic_bios_readme.txt", "Copyright (c) 2013, Gilead Kutnick"),
            ("FatFs", "LICENSE.txt", "FatFs License"),
            ("teakra", "LICENSE", "Copyright (c) 2018 Weiyi Wang"),
            ("tiny-AES-c", "unlicense.txt", "This is free and unencumbered software"),
            ("xxHash", "xxhash.h", "BSD 2-Clause License"),
            ("libslirp", "COPYRIGHT", "Danny Gasparovski"),
            ("libslirp-BSD", "tcp_var.h", "The Regents of the University of California"),
            ("libslirp-MIT", "util.h", "Copyright (c) 2003-2008 Fabrice Bellard"),
            ("fmt", "LICENSE", "Victor Zverovich"),
            ("GLM", "copying.txt", "OpenGL Mathematics (GLM)"),
            ("pntr", "LICENSE.md", "Zlib License"),
            ("yamc", "LICENSE", "Copyright (c) 2017-2019 yohhoy"),
            ("span-lite", "LICENSE.txt", "Boost Software License - Version 1.0"),
            // date's notice with its authors is a section of the collected notices.
            ("melonDS-DS-notices", "melondsds-LICENSE.txt.in", "Copyright (c) 2019 Jiangang Zhuang"),
            ("zlib", "LICENSE", "Jean-loup Gailly and Mark Adler"),
        ]
        for (folder, file, phrase) in texts {
            let url = try #require(
                Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "Licenses/\(folder)"),
                "Licenses/\(folder)/\(file) is missing in the app bundle"
            )
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains(phrase), "Licenses/\(folder)/\(file) does not contain \"\(phrase)\"")
        }
    }
}
