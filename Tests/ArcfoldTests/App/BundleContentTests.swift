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
